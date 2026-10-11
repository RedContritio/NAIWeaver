from __future__ import annotations

import tests  # noqa: F401  # isolates the data directories before app imports

import asyncio
from datetime import datetime, timezone
import json
import sqlite3
import threading
import time
import unittest

from fastapi import HTTPException

from app import auth, billing, config, db as gwdb, generation, state, users
from tests import support


class SubmissionContractTests(unittest.IsolatedAsyncioTestCase):
    """POST /api/generation-tasks (contract §4)."""

    async def asyncSetUp(self) -> None:
        self.db = support.temporary_database(self)
        support.reset_queue_state()
        self.free = support.create_user(self.db, "free-user")
        self.paid = support.create_user(self.db, "paid-user", "paid")
        self.admin = support.create_user(self.db, "admin-user", "admin")

    async def asyncTearDown(self) -> None:
        support.reset_queue_state()

    async def post(self, user, envelope: dict) -> dict:
        response = await generation.submit_generation_task(
            request=support.make_request(
                "/api/generation-tasks", json.dumps(envelope).encode()
            ),
            user=user,
            db=self.db,
        )
        self.assertEqual(response.status_code, 202)
        return json.loads(response.body)

    def reserved(self, user) -> tuple[int, int]:
        row = self.db.execute(
            "SELECT green_points_reserved, red_points_reserved FROM users WHERE id = ?",
            (user["id"],),
        ).fetchone()
        return int(row[0]), int(row[1])

    def task_count(self) -> int:
        return self.db.execute("SELECT COUNT(*) FROM generation_tasks").fetchone()[0]

    async def test_expected_quote_is_required(self) -> None:
        with self.assertRaises(HTTPException) as raised:
            await self.post(
                self.paid,
                {
                    "client_request_id": "no-quote-request",
                    "request": support.generation_request(),
                    "seeds": [1],
                },
            )
        self.assertEqual(raised.exception.status_code, 400)
        detail = support.error_detail(raised)
        self.assertEqual((detail["code"], detail["field"]), ("invalid_parameters", "expected_quote"))
        self.assertEqual(self.task_count(), 0)

    async def test_quote_changed_returns_the_server_quote_and_reserves_nothing(self) -> None:
        request = support.generation_request(steps=50)
        with self.assertRaises(HTTPException) as raised:
            await support.submit(
                self.db, self.paid, request, [1, 2], expected={"mode": "paid", "points": 40}
            )
        self.assertEqual(raised.exception.status_code, 409)
        detail = support.error_detail(raised)
        self.assertEqual(detail["code"], "quote_changed")
        self.assertEqual(
            (detail["quote"]["mode"], detail["quote"]["points"], detail["quote"]["per_image"]),
            ("paid", 66, 33),
        )
        self.assertEqual(detail["quote"]["reasons"], ["steps_over_free_limit"])
        self.assertEqual(self.reserved(self.paid), (0, 0))
        self.assertEqual(self.task_count(), 0)

        # The client confirms the server price and resubmits.
        await support.submit(
            self.db, self.paid, request, [1, 2], expected={"mode": "paid", "points": 66}
        )
        self.assertEqual(self.reserved(self.paid), (0, 66))

    async def test_mode_mismatch_is_a_quote_change(self) -> None:
        with self.assertRaises(HTTPException) as raised:
            await support.submit(
                self.db,
                self.paid,
                support.generation_request(),
                [1],
                expected={"mode": "paid", "points": 20},
            )
        self.assertEqual(support.error_detail(raised)["code"], "quote_changed")

    async def test_normalized_request_is_what_gets_forwarded_and_stored(self) -> None:
        request = support.generation_request(
            action="img2img",
            params_version=3,
            n_samples=4,
            image="base64-image",
            strength=0.6,
        )
        submitted = await support.submit(self.db, self.paid, request, [11, 12])

        bodies = {job.task_id: json.loads(job.body) for job in state.pending_jobs}
        for item, seed in zip(submitted["items"], (11, 12)):
            forwarded = bodies[item["id"]]
            stored = json.loads(
                self.db.execute(
                    "SELECT request_json FROM generation_tasks WHERE id = ?", (item["id"],)
                ).fetchone()[0]
            )
            self.assertEqual(forwarded, stored)
            params = forwarded["parameters"]
            self.assertEqual(params["n_samples"], 1)
            self.assertEqual(params["params_version"], 4)
            self.assertEqual(params["seed"], seed)
            self.assertEqual(params["extra_noise_seed"], seed)
            self.assertEqual(forwarded["model"], billing.NAI_V5_FULL_MODEL)

    async def test_strictly_invalid_parameters_are_rejected_before_reserving(self) -> None:
        for field, value in (("width", 832.0), ("steps", "28"), ("height", False)):
            with self.subTest(field=field):
                with self.assertRaises(HTTPException) as raised:
                    await support.submit(
                        self.db,
                        self.paid,
                        support.generation_request(**{field: value}),
                        [1],
                        expected={"mode": "free", "points": 20},
                    )
                detail = support.error_detail(raised)
                self.assertEqual((detail["code"], detail["field"]), ("invalid_parameters", field))
        for seeds in ([], [1.5], [True], [-1], [2**32], "1"):
            with self.subTest(seeds=seeds):
                with self.assertRaises(HTTPException) as raised:
                    await support.submit(
                        self.db,
                        self.paid,
                        support.generation_request(),
                        seeds,
                        expected={"mode": "free", "points": 20},
                    )
                self.assertEqual(support.error_detail(raised)["field"], "seeds")
        self.assertEqual(self.reserved(self.paid), (0, 0))
        self.assertEqual(self.task_count(), 0)

    async def test_same_key_same_body_replays_and_different_body_is_rejected(self) -> None:
        request = support.generation_request()
        first = await support.submit(
            self.db, self.free, request, [5, 6], client_request_id="replay-key-1"
        )
        reserved_after_first = self.reserved(self.free)

        replay = await support.submit(
            self.db, self.free, request, [5, 6], client_request_id="replay-key-1"
        )
        self.assertEqual(replay["task_id"], first["task_id"])
        self.assertEqual(replay["items"], first["items"])
        self.assertEqual(self.reserved(self.free), reserved_after_first)
        self.assertEqual(self.task_count(), 2)

        with self.assertRaises(HTTPException) as raised:
            await support.submit(
                self.db, self.free, request, [5, 7], client_request_id="replay-key-1"
            )
        self.assertEqual(raised.exception.status_code, 409)
        self.assertEqual(support.error_detail(raised)["code"], "duplicate_request")
        self.assertEqual(self.task_count(), 2)

    async def test_batch_limit_is_resolved_per_user_and_enforced(self) -> None:
        cases = ((self.free, 4), (self.paid, 8), (self.admin, 10))
        for user, limit in cases:
            with self.subTest(user=user["username"]):
                rules = auth.me(user=user, db=self.db)["rules"]["image"]
                self.assertEqual(rules["batch_limit"], limit)
                with self.assertRaises(HTTPException) as raised:
                    await support.submit(
                        self.db,
                        user,
                        support.generation_request(),
                        list(range(1000, 1001 + limit)),
                    )
                detail = support.error_detail(raised)
                self.assertEqual((detail["field"], detail["limit"]), ("seeds", limit))
                submitted = await support.submit(
                    self.db,
                    user,
                    support.generation_request(),
                    list(range(user["id"] * 100, user["id"] * 100 + limit)),
                )
                self.assertEqual(len(submitted["items"]), limit)

    async def test_concurrent_submissions_cannot_both_reserve_the_last_points(self) -> None:
        self.db.execute(
            "UPDATE users SET red_points = 40 WHERE id = ?", (self.paid["id"],)
        )
        self.db.commit()
        paid = support.fetch_user(self.db, "paid-user")
        request = support.generation_request(steps=50)  # 33 red points each
        connections = [gwdb.db_connect() for _ in range(2)]
        for connection in connections:
            self.addCleanup(connection.close)

        async def submit_on(connection, seed):
            body = json.dumps(
                {
                    "client_request_id": f"concurrent-{seed}",
                    "request": request,
                    "seeds": [seed],
                    "expected_quote": {"mode": "paid", "points": 33},
                }
            ).encode()
            return await generation.submit_generation_task(
                request=support.make_request("/api/generation-tasks", body),
                user=paid,
                db=connection,
            )

        results = await asyncio.gather(
            submit_on(connections[0], 1), submit_on(connections[1], 2), return_exceptions=True
        )

        accepted = [result for result in results if not isinstance(result, Exception)]
        rejected = [result for result in results if isinstance(result, HTTPException)]
        self.assertEqual(len(accepted), 1)
        self.assertEqual(len(rejected), 1)
        self.assertEqual(rejected[0].detail["code"], "points_insufficient")
        self.assertEqual(
            (rejected[0].detail["point_kind"], rejected[0].detail["required"], rejected[0].detail["remaining"]),
            ("red", 33, 7),
        )
        self.assertEqual(self.reserved(paid), (0, 33))
        self.assertEqual(self.task_count(), 1)

    async def test_exhausted_allowance_needs_a_confirmed_red_quote(self) -> None:
        billing.record_billing_anomaly(
            self.db,
            kind=billing.ANOMALY_FREE_ALLOWANCE_EXHAUSTED,
            user_id=self.free["id"],
            mode="free",
            quoted=20,
            measured=20,
            note="test",
        )
        self.db.commit()
        request = support.generation_request()

        # A free-only account cannot pay for it.
        with self.assertRaises(HTTPException) as raised:
            await support.submit(
                self.db, self.free, request, [1], expected={"mode": "free", "points": 20}
            )
        detail = support.error_detail(raised)
        self.assertEqual(detail["code"], "free_allowance_exhausted")
        self.assertEqual(
            (detail["quote"]["mode"], detail["quote"]["reasons"]), ("paid", ["allowance_exhausted"])
        )

        # A paid account must confirm the red price first.
        with self.assertRaises(HTTPException) as raised:
            await support.submit(
                self.db, self.paid, request, [1], expected={"mode": "free", "points": 20}
            )
        self.assertEqual(support.error_detail(raised)["code"], "free_allowance_exhausted")
        self.assertEqual(self.task_count(), 0)

        await support.submit(
            self.db, self.paid, request, [1], expected={"mode": "paid", "points": 20}
        )
        self.assertEqual(self.reserved(self.paid), (0, 20))


class SlowUserReadConnection(sqlite3.Connection):
    """Widens the window between the balance read and the reservation write."""

    def execute(self, sql, *args):  # type: ignore[override]
        cursor = super().execute(sql, *args)
        if sql.lstrip().upper().startswith("SELECT * FROM USERS"):
            time.sleep(0.05)
        return cursor


class ReservationAtomicityTests(unittest.TestCase):
    def test_parallel_writers_cannot_overspend(self) -> None:
        db = support.temporary_database(self)
        user = support.create_user(db, "racer", "paid", red_points=40)
        barrier = threading.Barrier(4)
        outcomes: list[str] = []
        lock = threading.Lock()

        def reserve() -> None:
            connection = sqlite3.connect(
                config.DB_PATH, timeout=10, factory=SlowUserReadConnection, check_same_thread=False
            )
            connection.row_factory = sqlite3.Row
            try:
                barrier.wait()
                with billing.immediate_transaction(connection):
                    billing.reserve_points(connection, user["id"], "red", 33)
                outcome = "reserved"
            except HTTPException as exc:
                outcome = exc.detail["code"]
            finally:
                connection.close()
            with lock:
                outcomes.append(outcome)

        threads = [threading.Thread(target=reserve) for _ in range(4)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()

        self.assertEqual(sorted(outcomes), ["points_insufficient"] * 3 + ["reserved"])
        reserved = db.execute(
            "SELECT red_points_reserved FROM users WHERE id = ?", (user["id"],)
        ).fetchone()[0]
        self.assertEqual(reserved, 33)


class PermissionConsistencyTests(unittest.IsolatedAsyncioTestCase):
    """One permission rule for /api/me, quota, admin view, submission and the worker."""

    EXPECTED = {
        "admin": {"free": True, "paid": True},
        "paid": {"free": True, "paid": True},
        "free": {"free": True, "paid": False},
        "spent": {"free": False, "paid": False},
        "discounted": {"free": True, "paid": False},
        "disabled": {"free": False, "paid": False},
    }

    async def asyncSetUp(self) -> None:
        self.db = support.temporary_database(self)
        support.reset_queue_state()
        self.users = {
            "admin": support.create_user(self.db, "admin", "admin"),
            "paid": support.create_user(self.db, "paid", "paid"),
            "free": support.create_user(self.db, "free"),
            "spent": support.create_user(
                self.db, "spent", green_point_limit=100, green_point_used=100
            ),
            "discounted": support.create_user(
                self.db, "discounted", green_point_limit=0, green_point_discount=50
            ),
            "disabled": support.create_user(self.db, "disabled", "paid", disabled=1),
        }
        self.fake = support.FakeNovelAI(self)

    async def asyncTearDown(self) -> None:
        support.reset_queue_state()

    def request_for(self, mode: str) -> dict:
        # SMEA makes a request paid without exceeding a free account's steps.
        return support.generation_request(sm=mode == "paid")

    async def test_profile_quota_and_admin_views_agree(self) -> None:
        for name, user in self.users.items():
            profile = users.user_to_dict(user)["permissions"]
            admin_view = users.user_admin_dict(user)["permissions"]
            quota = users.quota_for_user(user)
            for mode, expected in self.EXPECTED[name].items():
                with self.subTest(user=name, mode=mode):
                    self.assertEqual(users.image_generation_allowed(user, mode), expected)
                    self.assertEqual(f"image.generate.{mode}" in profile, expected)
                    self.assertEqual(quota[mode]["enabled"], expected)
            self.assertEqual(admin_view, profile)
            tools_expected = name in {"admin", "paid"}
            self.assertEqual("image.upscale" in profile, tools_expected, name)

    async def test_submission_refuses_exactly_the_denied_modes(self) -> None:
        for name, user in self.users.items():
            for mode, expected in self.EXPECTED[name].items():
                with self.subTest(user=name, mode=mode):
                    seed = 7000 + int(user["id"]) * 10 + (mode == "paid")
                    try:
                        await support.submit(self.db, user, self.request_for(mode), [seed])
                        outcome = "accepted"
                    except HTTPException as exc:
                        outcome = exc.detail["code"]
                        if outcome == "permission_denied":
                            self.assertEqual(
                                exc.detail["permission"], f"image.generate.{mode}"
                            )
                    if expected:
                        # Allowed accounts may still lack points, never permission.
                        self.assertIn(outcome, {"accepted", "points_insufficient"})
                    else:
                        self.assertEqual(outcome, "permission_denied")

    async def test_worker_refuses_queued_work_after_permission_is_revoked(self) -> None:
        paid = self.users["paid"]
        free = self.users["free"]
        paid_task = await support.submit(self.db, paid, self.request_for("paid"), [1])
        free_task = await support.submit(self.db, free, self.request_for("free"), [2])
        self.db.execute("UPDATE users SET can_generate_paid = 0 WHERE id = ?", (paid["id"],))
        self.db.execute("UPDATE users SET disabled = 1 WHERE id = ?", (free["id"],))
        self.db.commit()

        worker = asyncio.create_task(generation.queue_worker())
        try:
            await support.wait_until(
                lambda: support.items_final(self.db, paid_task["task_id"])
                and support.items_final(self.db, free_task["task_id"])
            )
        finally:
            worker.cancel()
            await asyncio.gather(worker, return_exceptions=True)

        for task, user in ((paid_task, paid), (free_task, free)):
            item = support.item_rows(self.db, task["task_id"])[0]
            self.assertEqual((item["status"], item["error_code"]), ("failed", "permission_denied"))
            account = self.db.execute(
                "SELECT green_points_reserved, red_points_reserved, green_point_used, red_points_used "
                "FROM users WHERE id = ?",
                (user["id"],),
            ).fetchone()
            self.assertEqual(tuple(account), (0, 0, 0, 0))
        self.assertEqual(self.fake.calls, [])


class FreeAllowanceStateTests(unittest.TestCase):
    def test_cooldown_starts_at_the_latest_exhaustion_and_expires(self) -> None:
        db = support.temporary_database(self)
        user = support.create_user(db, "anomaly-user")
        self.assertIsNone(billing.free_allowance_exhausted_until(db))
        started = datetime(2026, 1, 1, 12, 0, tzinfo=timezone.utc)
        billing.record_billing_anomaly(
            db,
            kind=billing.ANOMALY_FREE_ALLOWANCE_EXHAUSTED,
            user_id=user["id"],
            mode="free",
            quoted=20,
            measured=20,
            note="test",
            created_at=started,
        )
        cooldown = billing.FREE_ALLOWANCE_COOLDOWN_SECONDS
        during = datetime.fromtimestamp(started.timestamp() + cooldown - 1, timezone.utc)
        after = datetime.fromtimestamp(started.timestamp() + cooldown, timezone.utc)
        self.assertEqual(
            billing.free_allowance_exhausted_until(db, now=during).timestamp(),
            started.timestamp() + 1800,
        )
        self.assertIsNone(billing.free_allowance_exhausted_until(db, now=after))


if __name__ == "__main__":
    unittest.main()
