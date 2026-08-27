from __future__ import annotations

import asyncio
import copy
import json
import sqlite3
import unittest

from fastapi import HTTPException, status
from starlette.requests import Request

from app import main
from app.main import generation_batch_request_hash, generation_request_fingerprint


class GenerationFingerprintTests(unittest.TestCase):
    def setUp(self) -> None:
        self.request = {
            "input": "1girl",
            "model": "nai-diffusion-4-5-full",
            "action": "generate",
            "parameters": {
                "width": 832,
                "height": 1216,
                "steps": 28,
                "sampler": "k_euler_ancestral",
                "seed": 123,
            },
        }

    def test_key_order_does_not_change_fingerprint(self) -> None:
        reordered = {
            "parameters": dict(reversed(self.request["parameters"].items())),
            "action": self.request["action"],
            "model": self.request["model"],
            "input": self.request["input"],
        }
        self.assertEqual(
            generation_request_fingerprint(self.request),
            generation_request_fingerprint(reordered),
        )

    def test_seed_and_model_are_part_of_fingerprint(self) -> None:
        other_seed = copy.deepcopy(self.request)
        other_seed["parameters"]["seed"] = 124
        other_model = copy.deepcopy(self.request)
        other_model["model"] = "nai-diffusion-4-5-curated"

        original = generation_request_fingerprint(self.request)
        self.assertNotEqual(original, generation_request_fingerprint(other_seed))
        self.assertNotEqual(original, generation_request_fingerprint(other_model))

    def test_batch_idempotency_hash_preserves_item_order(self) -> None:
        second = copy.deepcopy(self.request)
        second["parameters"]["seed"] = 124
        self.assertNotEqual(
            generation_batch_request_hash([self.request, second]),
            generation_batch_request_hash([second, self.request]),
        )

    def test_public_task_payload_keeps_model_but_omits_binary_inputs(self) -> None:
        request = copy.deepcopy(self.request)
        request["parameters"]["image"] = "large-base64-image"
        request["parameters"]["director_reference_images"] = ["a", "b"]
        public = main.public_generation_item(
            {"id": "item", "request_json": json.dumps(request)}
        )
        restored = json.loads(public["request_json"])

        self.assertEqual(restored["model"], self.request["model"])
        self.assertNotIn("image", restored["parameters"])
        self.assertNotIn("director_reference_images", restored["parameters"])
        self.assertEqual(
            restored["parameters"]["director_reference_images_count"], 2
        )


class GenerationModelNormalizationTests(unittest.TestCase):
    user = {
        "can_generate_paid": 1,
        "is_admin": 0,
        "green_point_limit": 0,
        "green_point_used": 0,
        "green_point_discount": 0,
    }

    def request(self, *, model: str, action: str = "generate") -> bytes:
        return json.dumps(
            {
                "input": "1girl",
                "model": model,
                "action": action,
                "parameters": {
                    "params_version": 3,
                    "width": 832,
                    "height": 1216,
                    "steps": 23,
                    "scale": 7.0,
                    "sampler": "k_euler_ancestral",
                    "seed": 123,
                },
            }
        ).encode()

    def test_old_full_client_is_normalized_to_v5(self) -> None:
        _, parsed, _ = main.sanitize_novelai_generate_body(
            self.request(model="nai-diffusion-4-5-full"), self.user
        )

        self.assertEqual(parsed["model"], main.NAI_V5_FULL_MODEL)
        self.assertEqual(parsed["parameters"]["params_version"], 4)
        self.assertEqual(parsed["parameters"]["n_samples"], 1)

    def test_curated_generation_and_inpainting_match_official_routing(self) -> None:
        _, generated, _ = main.sanitize_novelai_generate_body(
            self.request(model="nai-diffusion-4-5-curated"), self.user
        )
        _, inpainted, _ = main.sanitize_novelai_generate_body(
            self.request(
                model="nai-diffusion-5-curated-inpainting", action="infill"
            ),
            self.user,
        )

        self.assertEqual(generated["model"], main.NAI_V5_CURATED_MODEL)
        self.assertEqual(
            inpainted["model"], main.NAI_V4_5_CURATED_INPAINTING_MODEL
        )


class AtomicGenerationBatchTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.db = sqlite3.connect(":memory:", isolation_level=None)
        self.db.row_factory = sqlite3.Row
        self.db.executescript(main.SCHEMA)
        main.migrate_db(self.db)
        self.db.execute(
            "INSERT INTO users(username, password_hash, green_point_discount, created_at) "
            "VALUES ('batch-test', 'unused', 100, ?)",
            (main.now_iso(),),
        )
        self.user = self.db.execute(
            "SELECT * FROM users WHERE username = 'batch-test'"
        ).fetchone()
        main.pending_jobs.clear()
        main.active_user_ids.clear()
        main.queue_condition = asyncio.Condition()
        main.queue_virtual_time = 0.0
        for queue_name in main.queue_last_finish:
            main.queue_last_finish[queue_name] = 0.0

    async def asyncTearDown(self) -> None:
        main.pending_jobs.clear()
        main.active_user_ids.clear()
        self.db.close()

    def item(self, seed: int, *, model: str = "nai-diffusion-4-5-full"):
        request = {
            "input": "1girl",
            "model": model,
            "action": "generate",
            "parameters": {
                "width": 832,
                "height": 1216,
                "steps": 28,
                "scale": 5.0,
                "sampler": "k_euler_ancestral",
                "seed": seed,
                "uc": "",
            },
        }
        return (json.dumps(request).encode(), request, "free")

    async def test_replay_is_idempotent_and_model_change_is_distinct(self) -> None:
        items = [self.item(123), self.item(124)]
        parent_id, item_ids, replayed = await main.enqueue_generation_batch(
            user=self.user,
            client_request_id="request-123",
            items=items,
            db=self.db,
        )
        self.assertFalse(replayed)
        self.assertEqual(len(main.pending_jobs), 2)

        replay_parent, replay_ids, replayed = await main.enqueue_generation_batch(
            user=self.user,
            client_request_id="request-123",
            items=items,
            db=self.db,
        )
        self.assertTrue(replayed)
        self.assertEqual(replay_parent, parent_id)
        self.assertEqual(replay_ids, item_ids)
        self.assertEqual(len(main.pending_jobs), 2)

        with self.assertRaises(HTTPException) as duplicate:
            await main.enqueue_generation_batch(
                user=self.user,
                client_request_id="request-new-action",
                items=[self.item(123)],
                db=self.db,
            )
        self.assertEqual(duplicate.exception.detail["code"], "duplicate_generation")
        self.assertEqual(len(main.pending_jobs), 2)

        _, model_item_ids, _ = await main.enqueue_generation_batch(
            user=self.user,
            client_request_id="request-model-change",
            items=[self.item(123, model="nai-diffusion-4-5-curated")],
            db=self.db,
        )
        self.assertEqual(len(model_item_ids), 1)
        self.assertEqual(len(main.pending_jobs), 3)

    async def test_duplicate_batch_is_rejected_before_any_item_is_added(self) -> None:
        with self.assertRaises(HTTPException) as raised:
            await main.enqueue_generation_batch(
                user=self.user,
                client_request_id="request-duplicate",
                items=[self.item(999), self.item(999)],
                db=self.db,
            )

        self.assertEqual(raised.exception.status_code, 409)
        self.assertEqual(raised.exception.detail["code"], "duplicate_within_batch")
        self.assertEqual(len(main.pending_jobs), 0)
        count = self.db.execute("SELECT COUNT(*) FROM generation_tasks").fetchone()[0]
        self.assertEqual(count, 0)

    async def test_batch_requires_the_full_aggregate_balance(self) -> None:
        self.db.execute(
            "UPDATE users SET green_point_discount = 0, green_point_limit = 39 "
            "WHERE id = ?",
            (self.user["id"],),
        )
        self.user = self.db.execute(
            "SELECT * FROM users WHERE id = ?", (self.user["id"],)
        ).fetchone()

        with self.assertRaises(HTTPException) as raised:
            await main.enqueue_generation_batch(
                user=self.user,
                client_request_id="request-insufficient-total",
                items=[self.item(401), self.item(402)],
                db=self.db,
            )

        self.assertEqual(raised.exception.detail["code"], "points_insufficient")
        self.assertEqual(len(main.pending_jobs), 0)
        account = self.db.execute(
            "SELECT green_points_reserved FROM users WHERE id = ?",
            (self.user["id"],),
        ).fetchone()
        self.assertEqual(account["green_points_reserved"], 0)

    async def test_single_enqueue_inserts_all_queue_columns(self) -> None:
        body, request, mode = self.item(777)
        parent_id, item_id = await main.enqueue_generate(
            user=self.user,
            service="image",
            path="ai/generate-image",
            body=body,
            parsed=request,
            quota_mode=mode,
            db=self.db,
        )

        item = self.db.execute(
            "SELECT status, batch_id, seed FROM generation_tasks WHERE id = ?",
            (item_id,),
        ).fetchone()
        self.assertEqual(item["status"], "queued")
        self.assertEqual(item["batch_id"], parent_id)
        self.assertEqual(item["seed"], 777)

    async def test_generation_task_http_handler_returns_202_and_persists_item(self) -> None:
        payload = self.item(778)[1]
        body = json.dumps(payload).encode()

        async def receive():
            return {"type": "http.request", "body": body, "more_body": False}

        request = Request(
            {
                "type": "http",
                "method": "POST",
                "path": "/api/generation-tasks",
                "headers": [(b"content-type", b"application/json")],
                "client": ("127.0.0.1", 12345),
            },
            receive,
        )

        response = await main.submit_generation_task(
            request=request,
            user=self.user,
            db=self.db,
        )

        self.assertEqual(response.status_code, 202)
        response_body = json.loads(response.body)
        item = self.db.execute(
            "SELECT status, seed FROM generation_tasks WHERE id = ?",
            (response_body["item_id"],),
        ).fetchone()
        self.assertEqual(item["status"], "queued")
        self.assertEqual(item["seed"], 778)
        audit = self.db.execute(
            "SELECT status_code, completed_at FROM request_audit_logs ORDER BY created_at DESC LIMIT 1"
        ).fetchone()
        self.assertEqual(audit["status_code"], 202)
        self.assertIsNotNone(audit["completed_at"])


class QuotaMigrationTests(unittest.TestCase):
    def test_legacy_daily_counts_convert_to_current_green_points(self) -> None:
        db = sqlite3.connect(":memory:")
        db.row_factory = sqlite3.Row
        db.executescript(
            """
            CREATE TABLE users (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              username TEXT NOT NULL UNIQUE,
              password_hash TEXT NOT NULL,
              is_admin INTEGER NOT NULL DEFAULT 0,
              disabled INTEGER NOT NULL DEFAULT 0,
              can_generate_free INTEGER NOT NULL DEFAULT 1,
              can_generate_paid INTEGER NOT NULL DEFAULT 0,
              can_text_generate INTEGER NOT NULL DEFAULT 1,
              can_image_upscale INTEGER NOT NULL DEFAULT 1,
              can_image_augment INTEGER NOT NULL DEFAULT 1,
              can_image_encode_vibe INTEGER NOT NULL DEFAULT 1,
              daily_limit INTEGER,
              paid_daily_limit INTEGER,
              paid_point_limit INTEGER NOT NULL DEFAULT 3000,
              paid_point_used INTEGER NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL
            );
            """
        )
        db.executescript(main.SCHEMA)
        created = main.now_iso()
        db.executemany(
            "INSERT INTO users(username, password_hash, is_admin, "
            "can_generate_free, daily_limit, created_at) VALUES (?, 'x', ?, ?, ?, ?)",
            [
                ("admin-old", 1, 1, 10, created),
                ("free-old", 0, 1, 10, created),
                ("disabled-old", 0, 0, 10, created),
            ],
        )
        free_id = db.execute(
            "SELECT id FROM users WHERE username = 'free-old'"
        ).fetchone()["id"]
        db.executemany(
            "INSERT INTO quota_usage(user_id, quota_date, mode, used) "
            "VALUES (?, ?, 'free', ?)",
            [
                (free_id, main.today_key(), 2),
                (free_id, "2000-01-01", 99),
            ],
        )

        main.migrate_db(db)

        migrated = {
            row["username"]: row
            for row in db.execute("SELECT * FROM users").fetchall()
        }
        self.assertEqual(migrated["free-old"]["green_point_limit"], 200)
        self.assertEqual(migrated["free-old"]["green_point_used"], 40)
        self.assertEqual(migrated["free-old"]["green_point_discount"], 0)
        self.assertEqual(migrated["disabled-old"]["green_point_limit"], 0)
        self.assertEqual(migrated["admin-old"]["green_point_discount"], 100)
        db.close()

    def test_interim_point_schema_preserves_ambiguous_user_balances(self) -> None:
        db = sqlite3.connect(":memory:")
        db.row_factory = sqlite3.Row
        db.executescript(main.SCHEMA)
        db.execute(
            "INSERT INTO users(username, password_hash, green_point_used, "
            "green_point_discount, created_at) VALUES ('interim', 'x', 101, 100, ?)",
            (main.now_iso(),),
        )
        user_id = db.execute(
            "SELECT id FROM users WHERE username = 'interim'"
        ).fetchone()["id"]
        db.execute(
            "INSERT INTO quota_usage(user_id, quota_date, mode, used) "
            "VALUES (?, ?, 'free', 2)",
            (user_id, main.today_key()),
        )
        db.execute(
            """
            INSERT INTO generation_tasks(
              id, user_id, mode, status, prompt, width, height, steps, scale,
              sampler, seed, reserved_points, consumed_green_points,
              request_json, created_at
            ) VALUES ('new-point-task', ?, 'free', 'success', 'p', 832, 1216,
                      28, 5, 'k_euler', 1, 7, 7, '{}', ?)
            """,
            (user_id, main.now_iso()),
        )

        main.migrate_db(db)
        preserved = db.execute(
            "SELECT green_point_used, green_point_discount FROM users WHERE id = ?",
            (user_id,),
        ).fetchone()
        self.assertEqual(preserved["green_point_used"], 101)
        self.assertEqual(preserved["green_point_discount"], 100)

        db.execute("UPDATE users SET green_point_used = 55 WHERE id = ?", (user_id,))
        main.migrate_db(db)
        rerun = db.execute(
            "SELECT green_point_used FROM users WHERE id = ?", (user_id,)
        ).fetchone()
        self.assertEqual(rerun["green_point_used"], 55)
        db.close()

    def test_legacy_quota_values_are_snapshotted_before_columns_are_dropped(self) -> None:
        db = sqlite3.connect(":memory:")
        db.row_factory = sqlite3.Row
        db.executescript(
            """
            CREATE TABLE users (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              username TEXT NOT NULL UNIQUE,
              password_hash TEXT NOT NULL,
              is_admin INTEGER NOT NULL DEFAULT 0,
              disabled INTEGER NOT NULL DEFAULT 0,
              can_generate_free INTEGER NOT NULL DEFAULT 1,
              can_generate_paid INTEGER NOT NULL DEFAULT 0,
              daily_limit INTEGER,
              paid_daily_limit INTEGER,
              paid_point_limit INTEGER NOT NULL DEFAULT 3000,
              paid_point_used INTEGER NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL
            );
            """
        )
        db.executescript(main.SCHEMA)
        db.execute(
            "INSERT INTO users(username, password_hash, can_generate_free, "
            "daily_limit, paid_daily_limit, paid_point_limit, paid_point_used, created_at) "
            "VALUES ('legacy', 'secret-hash', 1, 200, 50, 1234, 12, ?)",
            (main.now_iso(),),
        )

        main.migrate_db(db)

        snapshot = db.execute(
            "SELECT values_json FROM legacy_quota_snapshots WHERE user_id = 1"
        ).fetchone()
        values = json.loads(snapshot["values_json"])
        self.assertEqual(values["daily_limit"], 200)
        self.assertEqual(values["paid_point_used"], 12)
        self.assertNotIn("password_hash", values)
        columns = {
            row["name"] for row in db.execute("PRAGMA table_info(users)").fetchall()
        }
        self.assertNotIn("daily_limit", columns)
        db.close()


class HistoryPaginationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.db = sqlite3.connect(":memory:")
        self.db.row_factory = sqlite3.Row
        self.db.executescript(main.SCHEMA)
        main.migrate_db(self.db)
        self.db.execute(
            "INSERT INTO users(username, password_hash, created_at) VALUES ('history', 'x', ?)",
            (main.now_iso(),),
        )
        self.user = self.db.execute(
            "SELECT * FROM users WHERE username = 'history'"
        ).fetchone()

    def tearDown(self) -> None:
        self.db.close()

    def _insert_item(
        self,
        item_id: str,
        batch_id: str,
        index: int,
        created: str,
        *,
        user_id: int | None = None,
    ) -> None:
        self.db.execute(
            """
            INSERT INTO generation_tasks(
              id, user_id, mode, status, prompt, negative_prompt, width,
              height, steps, scale, sampler, seed, batch_id, batch_index,
              request_json, created_at
            ) VALUES (?, ?, 'free', 'success', 'p', '', 832, 1216, 28,
                      5, 'k_euler', ?, ?, ?, '{}', ?)
            """,
            (item_id, user_id or self.user["id"], index, batch_id, index, created),
        )

    def test_page_limit_counts_batches_and_returns_every_batch_item(self) -> None:
        self._insert_item("old-0", "old-batch", 0, "2026-01-01T00:00:00+00:00")
        self._insert_item("old-1", "old-batch", 1, "2026-01-01T00:00:01+00:00")
        self._insert_item("new-0", "new-batch", 0, "2026-01-02T00:00:00+00:00")
        self._insert_item("new-1", "new-batch", 1, "2026-01-02T00:00:01+00:00")
        request = Request({"type": "http", "headers": []})

        page = main.history(
            request,
            limit=1,
            offset=0,
            user_id=None,
            current_batch=False,
            user=self.user,
            db=self.db,
        )

        self.assertEqual(page["total"], 2)
        self.assertEqual([item["id"] for item in page["items"]], ["new-0", "new-1"])

    def test_admin_defaults_to_own_history_and_must_explicitly_request_all(self) -> None:
        self.db.execute(
            "UPDATE users SET is_admin = 1 WHERE id = ?", (self.user["id"],)
        )
        self.user = self.db.execute(
            "SELECT * FROM users WHERE id = ?", (self.user["id"],)
        ).fetchone()
        self.db.execute(
            "INSERT INTO users(username, password_hash, created_at) "
            "VALUES ('other-user', 'x', ?)",
            (main.now_iso(),),
        )
        other_id = self.db.execute(
            "SELECT id FROM users WHERE username = 'other-user'"
        ).fetchone()["id"]
        self._insert_item(
            "admin-item",
            "admin-batch",
            0,
            "2026-01-02T00:00:00+00:00",
        )
        self._insert_item(
            "other-item",
            "other-batch",
            0,
            "2026-01-03T00:00:00+00:00",
            user_id=other_id,
        )
        request = Request({"type": "http", "headers": []})

        own_page = main.history(request, user=self.user, db=self.db)
        all_page = main.history(
            request,
            all_users=True,
            user=self.user,
            db=self.db,
        )

        self.assertEqual([item["id"] for item in own_page["items"]], ["admin-item"])
        self.assertEqual(
            [item["id"] for item in all_page["items"]],
            ["other-item", "admin-item"],
        )

    def test_delete_history_batch_hides_every_item_atomically(self) -> None:
        self._insert_item("batch-0", "batch-to-hide", 0, "2026-01-01T00:00:00+00:00")
        self._insert_item("batch-1", "batch-to-hide", 1, "2026-01-01T00:00:01+00:00")

        result = main.delete_history_batch(
            "batch-to-hide", user=self.user, db=self.db
        )

        self.assertEqual(result, {"ok": True, "hidden": 2})
        hidden = self.db.execute(
            "SELECT task_id FROM history_hidden WHERE user_id = ? ORDER BY task_id",
            (self.user["id"],),
        ).fetchall()
        self.assertEqual([row["task_id"] for row in hidden], ["batch-0", "batch-1"])

    def test_delete_history_batch_rejects_all_when_one_item_is_active(self) -> None:
        self._insert_item("batch-0", "active-batch", 0, "2026-01-01T00:00:00+00:00")
        self._insert_item("batch-1", "active-batch", 1, "2026-01-01T00:00:01+00:00")
        self.db.execute(
            "UPDATE generation_tasks SET status = 'queued' WHERE id = 'batch-1'"
        )

        with self.assertRaises(HTTPException) as raised:
            main.delete_history_batch("active-batch", user=self.user, db=self.db)

        self.assertEqual(raised.exception.status_code, status.HTTP_409_CONFLICT)
        hidden = self.db.execute("SELECT COUNT(*) AS count FROM history_hidden").fetchone()
        self.assertEqual(hidden["count"], 0)


if __name__ == "__main__":
    unittest.main()
