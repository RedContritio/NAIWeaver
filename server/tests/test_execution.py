from __future__ import annotations

import tests  # noqa: F401  # isolates the data directories before app imports

import asyncio
from datetime import datetime, timedelta, timezone
import json
import unittest

from fastapi import HTTPException

from app import admin as admin_routes, billing, config, db as gwdb, generation, proxy, state, users
from tests import support


class ExecutionTestCase(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.db = support.temporary_database(self)
        support.reset_queue_state()
        self.fake = support.FakeNovelAI(self)
        self.worker: asyncio.Task | None = None

    async def asyncTearDown(self) -> None:
        await self.stop_worker()
        support.reset_queue_state()

    def start_worker(self) -> None:
        self.worker = asyncio.create_task(generation.queue_worker())

    async def stop_worker(self) -> None:
        if self.worker is not None:
            self.worker.cancel()
            await asyncio.gather(self.worker, return_exceptions=True)
            self.worker = None

    def account(self, user) -> dict:
        row = self.db.execute(
            "SELECT green_point_used, green_points_reserved, red_points_used, "
            "red_points_reserved FROM users WHERE id = ?",
            (user["id"],),
        ).fetchone()
        return dict(row)

    def anomalies(self) -> list[dict]:
        return [
            dict(row)
            for row in self.db.execute(
                "SELECT kind, user_id, task_id, tool, mode, quoted, measured "
                "FROM billing_anomalies ORDER BY id"
            ).fetchall()
        ]

    async def run_until_final(self, *task_ids: str) -> None:
        if self.worker is None:
            self.start_worker()
        await support.wait_until(
            lambda: all(support.items_final(self.db, task_id) for task_id in task_ids)
        )

    async def call_tool(self, user, path: str, body: bytes, *, key: str, expected: int | None = None):
        tool = config.PAID_TOOL_PATHS[path]
        headers = {"Idempotency-Key": key}
        headers["X-NAIWeaver-Expected-Points"] = str(
            billing.TOOL_CAPS[tool] if expected is None else expected
        )
        return await proxy.novelai_proxy(
            service="image",
            path=path,
            request=support.make_request(f"/api/nai/image/{path}", body, headers=headers),
            user=user,
            db=self.db,
        )


class GenerationSettlementTests(ExecutionTestCase):
    async def test_paid_generation_is_charged_the_measured_delta_up_to_its_quote(self) -> None:
        # quote = 33 red points (832x1216, 50 steps)
        cases = [
            ("below_quote", 25, True, 25, False),
            ("delta_unavailable", 25, False, 33, False),
            ("negative_delta", -5, True, 33, False),
            ("above_quote", 40, True, 33, True),
        ]
        for index, (name, cost, balance_available, charged, anomaly) in enumerate(cases):
            with self.subTest(name):
                user = support.create_user(self.db, f"paid-{name}", "paid")
                self.fake.costs["ai/generate-image"] = cost
                self.fake.balance_available = balance_available
                submitted = await support.submit(
                    self.db, user, support.generation_request(steps=50), [100 + index]
                )
                self.assertEqual(self.account(user)["red_points_reserved"], 33)

                await self.run_until_final(submitted["task_id"])

                item = support.item_rows(self.db, submitted["task_id"])[0]
                self.assertEqual(item["status"], "success")
                self.assertEqual(item["consumed_red_points"], charged)
                self.assertEqual(
                    self.account(user),
                    {
                        "green_point_used": 0,
                        "green_points_reserved": 0,
                        "red_points_used": charged,
                        "red_points_reserved": 0,
                    },
                )
                user_anomalies = [a for a in self.anomalies() if a["user_id"] == user["id"]]
                if anomaly:
                    self.assertEqual(
                        user_anomalies,
                        [
                            {
                                "kind": "measured_above_quote",
                                "user_id": user["id"],
                                "task_id": item["id"],
                                "tool": None,
                                "mode": "paid",
                                "quoted": 33,
                                "measured": 40,
                            }
                        ],
                    )
                else:
                    self.assertEqual(user_anomalies, [])
        self.assertEqual(self.fake.max_in_flight, 1)

    async def test_free_generation_is_charged_its_green_quote(self) -> None:
        user = support.create_user(self.db, "free-user", green_point_discount=30)
        submitted = await support.submit(
            self.db, user, support.generation_request(), [1, 2]
        )
        await self.run_until_final(submitted["task_id"])

        self.assertEqual(
            [row["status"] for row in support.item_rows(self.db, submitted["task_id"])],
            ["success", "success"],
        )
        self.assertEqual(self.account(user)["green_point_used"], 28)
        self.assertEqual(self.account(user)["green_points_reserved"], 0)
        self.assertEqual(self.anomalies(), [])

    async def test_upstream_failure_releases_the_whole_reservation(self) -> None:
        user = support.create_user(self.db, "paid-user", "paid")
        self.fake.statuses["ai/generate-image"] = 429
        self.fake.costs["ai/generate-image"] = 33
        submitted = await support.submit(
            self.db, user, support.generation_request(steps=50), [1, 2]
        )
        self.assertEqual(self.account(user)["red_points_reserved"], 66)

        await self.run_until_final(submitted["task_id"])

        items = support.item_rows(self.db, submitted["task_id"])
        self.assertEqual(
            [(row["status"], row["error_code"]) for row in items],
            [("failed", "upstream_error")] * 2,
        )
        self.assertEqual(self.account(user)["red_points_reserved"], 0)
        self.assertEqual(self.account(user)["red_points_used"], 0)
        task = self.db.execute(
            "SELECT status FROM generation_submission_tasks WHERE id = ?",
            (submitted["task_id"],),
        ).fetchone()
        self.assertEqual(task["status"], "failed")


class UpstreamLaneTests(ExecutionTestCase):
    async def test_red_tool_overtakes_free_work_already_waiting_for_the_lane(self) -> None:
        free = support.create_user(self.db, "free-user")
        paid = support.create_user(self.db, "paid-user", "paid")
        self.fake.gate = asyncio.Event()
        first_tool = asyncio.create_task(
            self.call_tool(paid, "ai/upscale", b'{"image":"a"}', key="upscale-key-1")
        )
        await support.wait_until(lambda: self.fake.in_flight == 1)

        submitted = await support.submit(
            self.db, free, support.generation_request(), [1, 2]
        )
        self.start_worker()
        await support.wait_until(lambda: state.upstream_lane.waiting == 1)
        later_tool = asyncio.create_task(
            self.call_tool(paid, "ai/encode-vibe", b'{"image":"b"}', key="vibe-key-001")
        )
        await support.wait_until(lambda: state.upstream_lane.waiting == 2)

        self.fake.gate.set()
        await asyncio.gather(first_tool, later_tool)
        await self.run_until_final(submitted["task_id"])

        # The worker asked for the lane first, but red work goes first.
        self.assertEqual(
            self.fake.calls,
            ["ai/upscale", "ai/encode-vibe", "ai/generate-image", "ai/generate-image"],
        )
        self.assertEqual(self.fake.max_in_flight, 1)

    async def test_red_tool_waits_for_the_running_image_then_goes_next(self) -> None:
        free = support.create_user(self.db, "free-user")
        paid = support.create_user(self.db, "paid-user", "paid")
        self.fake.gate = asyncio.Event()
        submitted = await support.submit(
            self.db, free, support.generation_request(), [1, 2]
        )
        self.start_worker()
        await support.wait_until(lambda: self.fake.in_flight == 1)
        self.assertEqual(self.fake.calls, ["ai/generate-image"])

        tool = asyncio.create_task(
            self.call_tool(paid, "ai/upscale", b'{"image":"x"}', key="upscale-key-1")
        )
        await support.wait_until(lambda: state.upstream_lane.waiting >= 1)
        self.assertEqual(self.fake.calls, ["ai/generate-image"])

        self.fake.gate.set()
        response = await tool
        await self.run_until_final(submitted["task_id"])

        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            self.fake.calls,
            ["ai/generate-image", "ai/upscale", "ai/generate-image"],
        )
        self.assertEqual(self.fake.max_in_flight, 1)

    async def test_paid_generation_overtakes_queued_free_generation(self) -> None:
        free = support.create_user(self.db, "free-user")
        paid = support.create_user(self.db, "paid-user", "paid")
        free_task = await support.submit(
            self.db, free, support.generation_request(), [1, 2]
        )
        paid_task = await support.submit(
            self.db, paid, support.generation_request(steps=50), [3]
        )

        await self.run_until_final(free_task["task_id"], paid_task["task_id"])

        seeds = [json.loads(body)["parameters"]["seed"] for body in self.fake.bodies]
        self.assertEqual(seeds, [3, 1, 2])


class PaidToolTests(ExecutionTestCase):
    async def asyncSetUp(self) -> None:
        await super().asyncSetUp()
        self.user = support.create_user(self.db, "tool-user", "paid")

    async def test_same_key_calls_upstream_once_and_replays_the_response(self) -> None:
        self.fake.costs["ai/encode-vibe"] = 2
        first = await self.call_tool(self.user, "ai/encode-vibe", b'{"image":"a"}', key="vibe-key-01")
        second = await self.call_tool(self.user, "ai/encode-vibe", b'{"image":"a"}', key="vibe-key-01")

        self.assertEqual(self.fake.calls, ["ai/encode-vibe"])
        self.assertEqual(second.body, first.body)
        self.assertEqual(self.account(self.user)["red_points_used"], 2)

        with self.assertRaises(HTTPException) as raised:
            await self.call_tool(self.user, "ai/encode-vibe", b'{"image":"b"}', key="vibe-key-01")
        self.assertEqual(raised.exception.status_code, 409)
        self.assertEqual(support.error_detail(raised)["code"], "duplicate_request")
        self.assertEqual(self.fake.calls, ["ai/encode-vibe"])

    async def test_concurrent_retries_share_one_upstream_call(self) -> None:
        self.fake.gate = asyncio.Event()
        calls = [
            asyncio.create_task(
                self.call_tool(self.user, "ai/upscale", b'{"image":"a"}', key="shared-key-1")
            )
            for _ in range(2)
        ]
        await support.wait_until(lambda: self.fake.in_flight == 1)
        self.fake.gate.set()
        responses = await asyncio.gather(*calls)

        self.assertEqual(self.fake.calls, ["ai/upscale"])
        self.assertEqual(responses[0].body, responses[1].body)

    async def test_headers_are_required_and_the_price_must_match_the_cap(self) -> None:
        with self.assertRaises(HTTPException) as raised:
            await proxy.novelai_proxy(
                service="image",
                path="ai/upscale",
                request=support.make_request(
                    "/api/nai/image/ai/upscale",
                    b"{}",
                    headers={"X-NAIWeaver-Expected-Points": "10"},
                ),
                user=self.user,
                db=self.db,
            )
        self.assertEqual(support.error_detail(raised)["field"], "Idempotency-Key")

        with self.assertRaises(HTTPException) as raised:
            await self.call_tool(self.user, "ai/augment-image", b"{}", key="augment-key-1", expected=10)
        detail = support.error_detail(raised)
        self.assertEqual(detail["code"], "quote_changed")
        self.assertEqual((detail["quote"]["mode"], detail["quote"]["points"]), ("paid", 80))
        self.assertEqual(self.fake.calls, [])

    async def test_tool_charge_is_measured_and_capped(self) -> None:
        self.fake.costs.update({"ai/upscale": 4, "ai/augment-image": 120})
        await self.call_tool(self.user, "ai/upscale", b'{"image":"a"}', key="upscale-key-1")
        self.assertEqual(self.account(self.user)["red_points_used"], 4)

        self.fake.balance_available = False
        await self.call_tool(self.user, "ai/upscale", b'{"image":"b"}', key="upscale-key-2")
        self.assertEqual(self.account(self.user)["red_points_used"], 14)

        self.fake.balance_available = True
        await self.call_tool(self.user, "ai/augment-image", b'{"image":"c"}', key="augment-key-1")
        self.assertEqual(self.account(self.user)["red_points_used"], 94)
        self.assertEqual(self.account(self.user)["red_points_reserved"], 0)
        self.assertEqual(
            self.anomalies(),
            [
                {
                    "kind": "measured_above_quote",
                    "user_id": self.user["id"],
                    "task_id": None,
                    "tool": "augment",
                    "mode": "paid",
                    "quoted": 80,
                    "measured": 120,
                }
            ],
        )

    async def test_tool_failure_releases_and_insufficient_points_never_call_upstream(self) -> None:
        self.fake.statuses["ai/upscale"] = 401
        with self.assertRaises(HTTPException) as raised:
            await self.call_tool(self.user, "ai/upscale", b'{"image":"a"}', key="failing-key-1")
        self.assertEqual(raised.exception.status_code, 502)
        detail = support.error_detail(raised)
        self.assertEqual((detail["code"], detail["upstream_status"]), ("upstream_error", 401))
        self.assertEqual(self.account(self.user)["red_points_used"], 0)
        self.assertEqual(self.account(self.user)["red_points_reserved"], 0)

        self.db.execute(
            "UPDATE users SET red_points_used = red_points - 9 WHERE id = ?",
            (self.user["id"],),
        )
        self.db.commit()
        calls_before = list(self.fake.calls)
        with self.assertRaises(HTTPException) as raised:
            await self.call_tool(self.user, "ai/upscale", b'{"image":"b"}', key="poor-key-01")
        detail = support.error_detail(raised)
        self.assertEqual(
            (detail["code"], detail["point_kind"], detail["required"], detail["remaining"]),
            ("points_insufficient", "red", 10, 9),
        )
        self.assertEqual(self.fake.calls, calls_before)


class FreeAllowanceExhaustionTests(ExecutionTestCase):
    async def test_measured_cost_on_free_work_pauses_free_generation(self) -> None:
        free = support.create_user(self.db, "free-user")
        self.fake.costs["ai/generate-image"] = 20
        self.fake.gate = asyncio.Event()
        submitted = await support.submit(
            self.db, free, support.generation_request(), [1, 2, 3]
        )
        self.start_worker()
        await support.wait_until(lambda: self.fake.in_flight == 1)
        self.assertEqual(self.account(free)["green_points_reserved"], 60)
        self.fake.gate.set()
        await self.run_until_final(submitted["task_id"])

        items = support.item_rows(self.db, submitted["task_id"])
        self.assertEqual(
            [(row["status"], row["error_code"]) for row in items],
            [
                ("success", None),
                ("failed", "free_allowance_exhausted"),
                ("failed", "free_allowance_exhausted"),
            ],
        )
        # The item that ran is still charged in green; the rest are released.
        self.assertEqual(
            self.account(free),
            {
                "green_point_used": 20,
                "green_points_reserved": 0,
                "red_points_used": 0,
                "red_points_reserved": 0,
            },
        )
        self.assertEqual(self.fake.calls, ["ai/generate-image"])
        self.assertEqual(
            [(a["kind"], a["mode"], a["measured"]) for a in self.anomalies()],
            [("free_allowance_exhausted", "free", 20)],
        )

        rules = users.image_rules_for_user(self.db, free)
        self.assertTrue(rules["free_allowance_exhausted"])
        quote = support.quote_for(self.db, free, support.generation_request(), 1)
        self.assertEqual((quote.mode, quote.reasons), ("paid", ("allowance_exhausted",)))

        admin = support.create_user(self.db, "admin-user", "admin")
        state = admin_routes.admin_config(admin, self.db)["free_allowance"]
        self.assertTrue(state["exhausted"])
        until = datetime.fromisoformat(state["exhausted_until"])
        self.assertAlmostEqual(
            (until - datetime.now(timezone.utc)).total_seconds(), 1800, delta=60
        )

    async def test_queued_free_work_restored_during_cooldown_never_runs(self) -> None:
        free = support.create_user(self.db, "free-user")
        submitted = await support.submit(
            self.db, free, support.generation_request(), [1]
        )
        billing.record_billing_anomaly(
            self.db,
            kind=billing.ANOMALY_FREE_ALLOWANCE_EXHAUSTED,
            user_id=free["id"],
            mode="free",
            quoted=20,
            measured=20,
            note="test",
            created_at=datetime.now(timezone.utc) - timedelta(minutes=1),
        )
        self.db.commit()

        await self.run_until_final(submitted["task_id"])

        item = support.item_rows(self.db, submitted["task_id"])[0]
        self.assertEqual((item["status"], item["error_code"]), ("failed", "free_allowance_exhausted"))
        self.assertEqual(self.account(free)["green_points_reserved"], 0)
        self.assertEqual(self.fake.calls, [])


class InterruptionTests(ExecutionTestCase):
    async def test_restart_fails_running_items_and_restores_only_queued_ones(self) -> None:
        user = support.create_user(self.db, "paid-user", "paid")
        submitted = await support.submit(
            self.db, user, support.generation_request(steps=50), [1, 2]
        )
        running_id, queued_id = (item["id"] for item in submitted["items"])
        self.db.execute(
            "UPDATE generation_tasks SET status = 'running', started_at = ? WHERE id = ?",
            (gwdb.now_iso(), running_id),
        )
        self.db.commit()
        support.reset_queue_state()  # the previous process is gone

        await generation.restore_generation_queue()

        rows = {row["id"]: row for row in support.item_rows(self.db, submitted["task_id"])}
        self.assertEqual(
            (rows[running_id]["status"], rows[running_id]["error_code"]),
            ("failed", "interrupted"),
        )
        self.assertEqual(rows[queued_id]["status"], "queued")
        self.assertEqual([job.task_id for job in state.pending_jobs], [queued_id])
        self.assertEqual(self.account(user)["red_points_reserved"], 33)

        await self.run_until_final(submitted["task_id"])
        self.assertEqual(len(self.fake.calls), 1)
        self.assertEqual(support.item_rows(self.db, submitted["task_id"])[1]["status"], "success")

    async def test_shutdown_never_leaves_an_item_running(self) -> None:
        user = support.create_user(self.db, "paid-user", "paid")
        self.fake.gate = asyncio.Event()
        submitted = await support.submit(
            self.db, user, support.generation_request(steps=50), [1]
        )
        self.start_worker()
        await support.wait_until(lambda: self.fake.in_flight == 1)

        await self.stop_worker()

        item = support.item_rows(self.db, submitted["task_id"])[0]
        self.assertEqual((item["status"], item["error_code"]), ("failed", "interrupted"))
        self.assertEqual(self.account(user)["red_points_reserved"], 0)
        self.assertEqual(self.account(user)["red_points_used"], 0)
        self.assertFalse(state.upstream_lane.held)


class CancelQueuedTests(ExecutionTestCase):
    async def cancel(self, user, task_id: str) -> dict:
        return await generation.cancel_generation_task(
            task_id=task_id, user=user, db=self.db
        )

    async def test_cancelling_releases_the_reservation_and_the_worker_skips_it(
        self,
    ) -> None:
        user = support.create_user(self.db, "free-user")
        submitted = await support.submit(
            self.db, user, support.generation_request(), [1, 2]
        )
        self.assertGreater(self.account(user)["green_points_reserved"], 0)

        payload = await self.cancel(user, submitted["task_id"])

        self.assertEqual(payload["status"], "cancelled")
        self.assertEqual(
            [item["status"] for item in payload["items"]], ["cancelled", "cancelled"]
        )
        self.assertEqual(self.account(user)["green_points_reserved"], 0)
        self.assertEqual(self.account(user)["green_point_used"], 0)
        self.assertEqual(state.pending_jobs, [])

        self.start_worker()
        await asyncio.sleep(0.05)
        self.assertEqual(self.fake.calls, [])

        # Cancelling again changes nothing.
        again = await self.cancel(user, submitted["task_id"])
        self.assertEqual(again["status"], "cancelled")
        self.assertEqual(self.account(user)["green_points_reserved"], 0)

    async def test_paid_reservations_are_released_in_red_points(self) -> None:
        user = support.create_user(self.db, "paid-user", "paid")
        submitted = await support.submit(
            self.db, user, support.generation_request(steps=50), [1]
        )
        self.assertEqual(self.account(user)["red_points_reserved"], 33)

        await self.cancel(user, submitted["task_id"])

        self.assertEqual(self.account(user)["red_points_reserved"], 0)

    async def test_another_users_task_cannot_be_cancelled(self) -> None:
        owner = support.create_user(self.db, "owner")
        other = support.create_user(self.db, "other")
        admin = support.create_user(self.db, "root", "admin")
        submitted = await support.submit(
            self.db, owner, support.generation_request(), [1]
        )
        reserved = self.account(owner)["green_points_reserved"]

        for caller in (other, admin):
            with self.assertRaises(HTTPException) as raised:
                await self.cancel(caller, submitted["task_id"])
            self.assertEqual(support.error_detail(raised)["code"], "not_found")

        self.assertEqual(
            [row["status"] for row in support.item_rows(self.db, submitted["task_id"])],
            ["queued"],
        )
        self.assertEqual(self.account(owner)["green_points_reserved"], reserved)

    async def test_a_running_item_is_not_cancelled(self) -> None:
        user = support.create_user(self.db, "free-user")
        self.fake.gate = asyncio.Event()
        submitted = await support.submit(
            self.db, user, support.generation_request(), [1, 2]
        )
        self.start_worker()
        await support.wait_until(lambda: self.fake.in_flight == 1)

        payload = await self.cancel(user, submitted["task_id"])

        self.assertEqual(
            [item["status"] for item in payload["items"]], ["running", "cancelled"]
        )
        # Only the running item's share stays reserved.
        per_image = support.quote_for(
            self.db, user, support.generation_request(), 1
        ).points
        self.assertEqual(self.account(user)["green_points_reserved"], per_image)

        self.fake.gate.set()
        await self.run_until_final(submitted["task_id"])

        statuses = [row["status"] for row in support.item_rows(self.db, submitted["task_id"])]
        self.assertEqual(statuses, ["success", "cancelled"])
        self.assertEqual(len(self.fake.calls), 1)
        self.assertEqual(self.account(user)["green_points_reserved"], 0)


if __name__ == "__main__":
    unittest.main()
