from __future__ import annotations

import tests  # noqa: F401  # isolates the data directories before app imports

import asyncio
from contextlib import closing
import sqlite3
import unittest
from unittest import mock

from app import billing, main
from tests import support
from tests.test_execution import ExecutionTestCase


class ToolReservationTests(ExecutionTestCase):
    async def asyncSetUp(self) -> None:
        await super().asyncSetUp()
        self.user = support.create_user(self.db, "tool-user", "paid")

    async def test_rebuilding_counters_keeps_in_flight_tool_reservations(self) -> None:
        other = support.create_user(self.db, "other-user", "paid")
        self.fake.gate = asyncio.Event()
        call = asyncio.create_task(
            self.call_tool(self.user, "ai/upscale", b'{"image":"a"}', key="inflight-01")
        )
        await support.wait_until(lambda: self.fake.in_flight == 1)
        self.assertEqual(self.account(self.user)["red_points_reserved"], 10)

        # A CLI command running beside the service rebuilds the counters.
        with closing(main.db_connect()) as cli_db:
            main.migrate_db(cli_db)
            cli_db.commit()
        self.assertEqual(self.account(self.user)["red_points_reserved"], 10)
        self.assertEqual(self.account(other)["red_points_reserved"], 0)

        self.fake.gate.set()
        await call
        self.assertEqual(self.account(self.user)["red_points_reserved"], 0)
        self.assertEqual(self.db.execute("SELECT COUNT(*) FROM tool_reservations").fetchone()[0], 0)

    async def test_startup_reclaims_reservations_of_a_dead_process(self) -> None:
        with billing.immediate_transaction(self.db):
            billing.reserve_tool_points(self.db, self.user["id"], 80, "augment")
        self.assertEqual(self.account(self.user)["red_points_reserved"], 80)

        # Another process runs a CLI command: the hold stays.
        main.migrate_db(self.db)
        self.db.commit()
        self.assertEqual(self.account(self.user)["red_points_reserved"], 80)

        # The service restarts: nothing can still be running.
        main.reclaim_tool_reservations(self.db)
        self.db.commit()
        self.assertEqual(self.account(self.user)["red_points_reserved"], 0)
        self.assertEqual(self.db.execute("SELECT COUNT(*) FROM tool_reservations").fetchone()[0], 0)

    async def test_same_key_on_another_tool_is_a_separate_call(self) -> None:
        self.fake.costs.update({"ai/upscale": 4, "ai/augment-image": 30})
        await self.call_tool(self.user, "ai/upscale", b'{"image":"a"}', key="shared-key-1")
        await self.call_tool(self.user, "ai/augment-image", b'{"image":"a"}', key="shared-key-1")

        self.assertEqual(self.fake.calls, ["ai/upscale", "ai/augment-image"])
        self.assertEqual(self.account(self.user)["red_points_used"], 34)


class LockedDatabase:
    """Delegates to a connection but fails BEGIN IMMEDIATE ``failures`` times."""

    def __init__(self, db: sqlite3.Connection, failures: int) -> None:
        self.db = db
        self.failures = failures
        self.begins = 0

    def execute(self, sql, *args):
        if sql == "BEGIN IMMEDIATE":
            self.begins += 1
            if self.failures:
                self.failures -= 1
                raise sqlite3.OperationalError("database is locked")
        return self.db.execute(sql, *args)

    def __getattr__(self, name):
        return getattr(self.db, name)


class SettlementRetryTests(ExecutionTestCase):
    async def test_locked_database_is_retried_until_it_frees_up(self) -> None:
        user = support.create_user(self.db, "retry-user", "paid")
        with mock.patch.object(billing, "SETTLEMENT_BACKOFF_SECONDS", 0):
            locked = LockedDatabase(self.db, failures=3)
            with billing.settlement_transaction(locked):
                billing.reserve_points(self.db, user["id"], "red", 5)
        self.assertEqual(locked.begins, 4)
        self.assertEqual(self.account(user)["red_points_reserved"], 5)

    async def test_persistent_lock_gives_up(self) -> None:
        with mock.patch.object(billing, "SETTLEMENT_BACKOFF_SECONDS", 0):
            locked = LockedDatabase(self.db, failures=99)
            with self.assertRaises(sqlite3.OperationalError):
                with billing.settlement_transaction(locked):
                    pass
        self.assertEqual(locked.begins, billing.SETTLEMENT_ATTEMPTS)

    async def test_failed_release_is_logged_and_left_for_startup(self) -> None:
        user = support.create_user(self.db, "retry-user", "paid")
        self.fake.statuses["ai/upscale"] = 401
        with mock.patch.object(
            main, "release_tool_points", side_effect=sqlite3.OperationalError("locked")
        ), self.assertLogs("uvicorn.error.naiweaver", level="ERROR") as logs:
            with self.assertRaises(Exception) as raised:
                await main.execute_paid_tool(
                    self.db, user["id"], path="ai/upscale", tool="upscale", body=b"{}"
                )
        # The upstream error surfaces, not the release failure.
        self.assertNotIsInstance(raised.exception, sqlite3.Error)
        self.assertTrue(any("tool_reservation_release_failed" in line for line in logs.output))
        self.assertEqual(self.account(user)["red_points_reserved"], 10)
        main.reclaim_tool_reservations(self.db)
        self.db.commit()
        self.assertEqual(self.account(user)["red_points_reserved"], 0)


class DecodeFailureTests(ExecutionTestCase):
    async def test_paid_decode_failure_releases_in_full_and_records_the_cost(self) -> None:
        user = support.create_user(self.db, "paid-user", "paid")
        self.fake.costs["ai/generate-image"] = 20
        self.fake.contents["ai/generate-image"] = b"not a zip"
        submitted = await support.submit(
            self.db, user, support.generation_request(steps=50), [1]
        )
        await self.run_until_final(submitted["task_id"])

        item = support.item_rows(self.db, submitted["task_id"])[0]
        self.assertEqual((item["status"], item["error_code"]), ("failed", "upstream_error"))
        self.assertEqual(self.account(user)["red_points_used"], 0)
        self.assertEqual(self.account(user)["red_points_reserved"], 0)
        self.assertEqual(
            [(a["kind"], a["mode"], a["quoted"], a["measured"]) for a in self.anomalies()],
            [("decode_failed", "paid", 33, 20)],
        )

    async def test_free_decode_failure_with_measured_cost_pauses_free_work(self) -> None:
        user = support.create_user(self.db, "free-user")
        self.fake.costs["ai/generate-image"] = 20
        self.fake.contents["ai/generate-image"] = b"not a zip"
        submitted = await support.submit(self.db, user, support.generation_request(), [1, 2])
        await self.run_until_final(submitted["task_id"])

        self.assertEqual(
            [(r["status"], r["error_code"]) for r in support.item_rows(self.db, submitted["task_id"])],
            [("failed", "upstream_error"), ("failed", "free_allowance_exhausted")],
        )
        self.assertEqual(self.account(user)["green_point_used"], 0)
        self.assertEqual(self.account(user)["green_points_reserved"], 0)
        self.assertEqual(
            [(a["kind"], a["measured"]) for a in self.anomalies()],
            [("free_allowance_exhausted", 20)],
        )
        self.assertEqual(self.fake.calls, ["ai/generate-image"])


class UnmeasuredBalanceTests(ExecutionTestCase):
    async def test_paid_generation_with_unchanged_balance_is_charged_the_quote(self) -> None:
        user = support.create_user(self.db, "paid-user", "paid")
        submitted = await support.submit(
            self.db, user, support.generation_request(steps=50), [1]
        )
        await self.run_until_final(submitted["task_id"])

        self.assertEqual(self.account(user)["red_points_used"], 33)
        self.assertEqual(
            [(a["kind"], a["mode"], a["quoted"], a["measured"]) for a in self.anomalies()],
            [("unmeasured", "paid", 33, 0)],
        )

    async def test_stale_balance_is_read_again_before_believing_zero(self) -> None:
        user = support.create_user(self.db, "paid-user", "paid")
        self.fake.costs["ai/generate-image"] = 25
        # The first "after" read still shows the balance from before the call.
        self.fake.stale_reads = 1
        submitted = await support.submit(
            self.db, user, support.generation_request(steps=50), [1]
        )
        await self.run_until_final(submitted["task_id"])

        self.assertEqual(self.account(user)["red_points_used"], 25)
        self.assertEqual(self.anomalies(), [])

    async def test_tool_with_unchanged_balance_is_charged_zero_and_reported(self) -> None:
        user = support.create_user(self.db, "tool-user", "paid")
        await self.call_tool(user, "ai/upscale", b'{"image":"a"}', key="free-tool-01")

        self.assertEqual(self.account(user)["red_points_used"], 0)
        self.assertEqual(self.account(user)["red_points_reserved"], 0)
        self.assertEqual(
            [(a["kind"], a["tool"], a["quoted"], a["measured"]) for a in self.anomalies()],
            [("unmeasured", "upscale", 10, 0)],
        )

    async def test_free_generation_without_a_balance_reading_is_reported(self) -> None:
        user = support.create_user(self.db, "free-user")
        self.fake.balance_available = False
        submitted = await support.submit(self.db, user, support.generation_request(), [1])
        await self.run_until_final(submitted["task_id"])

        self.assertEqual(
            [(a["kind"], a["mode"], a["measured"]) for a in self.anomalies()],
            [("unmeasured", "free", None)],
        )
        self.assertEqual(self.account(user)["green_point_used"], 20)


if __name__ == "__main__":
    unittest.main()
