from __future__ import annotations

import tests  # noqa: F401  # isolates the data directories before app imports

import copy
import json
import sqlite3
import unittest

from fastapi import HTTPException, status
from starlette.requests import Request

from app import billing, config, db as gwdb, generation, history, state, storage
from app.db import generation_request_fingerprint
from app.generation import submission_request_hash
from tests import support


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

    def test_submission_hash_ignores_the_key_but_keeps_seed_order(self) -> None:
        envelope = {
            "client_request_id": "request-1",
            "request": self.request,
            "seeds": [1, 2],
            "expected_quote": {"mode": "free", "points": 40},
        }
        same_body_new_key = {**envelope, "client_request_id": "request-2"}
        swapped_seeds = {**envelope, "seeds": [2, 1]}
        self.assertEqual(
            submission_request_hash(envelope),
            submission_request_hash(same_body_new_key),
        )
        self.assertNotEqual(
            submission_request_hash(envelope),
            submission_request_hash(swapped_seeds),
        )

    def test_public_task_payload_keeps_model_but_omits_binary_inputs(self) -> None:
        request = copy.deepcopy(self.request)
        request["parameters"]["image"] = "large-base64-image"
        request["parameters"]["director_reference_images"] = ["a", "b"]
        restored = json.loads(generation.public_request_json(json.dumps(request)))

        self.assertEqual(restored["model"], self.request["model"])
        self.assertNotIn("image", restored["parameters"])
        self.assertNotIn("director_reference_images", restored["parameters"])
        self.assertEqual(
            restored["parameters"]["director_reference_images_count"], 2
        )


class GenerationModelNormalizationTests(unittest.TestCase):
    rules = billing.build_image_rules(
        is_admin=False,
        can_generate_paid=True,
        green_point_discount=0,
        allowance_exhausted=False,
    )

    def request(self, *, model: str, action: str = "generate") -> dict:
        return {
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

    def test_old_full_client_is_normalized_to_v5(self) -> None:
        parsed, _ = billing.classify_and_quote(
            self.request(model="nai-diffusion-4-5-full"), self.rules
        )

        self.assertEqual(parsed["model"], billing.NAI_V5_FULL_MODEL)
        self.assertEqual(parsed["parameters"]["params_version"], 4)
        self.assertEqual(parsed["parameters"]["n_samples"], 1)

    def test_curated_generation_and_inpainting_match_official_routing(self) -> None:
        generated, _ = billing.classify_and_quote(
            self.request(model="nai-diffusion-4-5-curated"), self.rules
        )
        inpainted, _ = billing.classify_and_quote(
            self.request(model="nai-diffusion-5-curated-inpainting", action="infill"),
            self.rules,
        )
        full_inpainted, _ = billing.classify_and_quote(
            self.request(model="nai-diffusion-4-5-full-inpainting", action="infill"),
            self.rules,
        )

        self.assertEqual(generated["model"], billing.NAI_V5_CURATED_MODEL)
        self.assertEqual(
            inpainted["model"], billing.NAI_V4_5_CURATED_INPAINTING_MODEL
        )
        self.assertEqual(
            full_inpainted["model"], billing.NAI_V5_FULL_INPAINTING_MODEL
        )


class GenerationFailureLoggingTests(unittest.TestCase):
    def job(self) -> state.ProxyJob:
        return state.ProxyJob(
            virtual_finish=1.0,
            negative_weight=-100,
            created_at="2026-08-30T00:00:00+00:00",
            user_id=7,
            task_id="item-logging-test",
            service="image",
            path="ai/generate-image",
            body=json.dumps(
                {
                    "input": "prompt that must stay private",
                    "model": "nai-diffusion-5-full",
                    "action": "generate",
                    "parameters": {
                        "width": 832,
                        "height": 1216,
                        "steps": 28,
                        "sampler": "k_euler_ancestral",
                        "seed": 123,
                        "uc": "negative prompt that must stay private",
                    },
                }
            ).encode(),
            quota_mode="free",
        )

    def test_upstream_http_failure_logs_diagnostics_without_request_secrets(self) -> None:
        response = json.dumps(
            {
                "error": {
                    "code": "generation_rejected",
                    "message": "rejected prompt that must stay private",
                    "input": "prompt that must stay private",
                },
                "token": "pst-test-secret",
            }
        ).encode()

        with self.assertLogs(config.logger, level="ERROR") as captured:
            generation.log_generation_upstream_failure(
                self.job(),
                batch_id="batch-logging-test",
                status_code=503,
                headers={
                    "content-type": "application/json",
                    "x-request-id": "upstream-request-1",
                    "retry-after": "2",
                },
                content=response,
                elapsed_ms=5012,
            )

        rendered = "\n".join(captured.output)
        self.assertIn("kind=upstream_http", rendered)
        self.assertIn("task_id=item-logging-test", rendered)
        self.assertIn("batch_id=batch-logging-test", rendered)
        self.assertIn("status_code=503", rendered)
        self.assertIn("upstream_request_id=upstream-request-1", rendered)
        self.assertIn("generation_rejected", rendered)
        self.assertIn("<redacted", rendered)
        self.assertNotIn("prompt that must stay private", rendered)
        self.assertNotIn("pst-test-secret", rendered)

    def test_invalid_upstream_archive_logs_the_decode_traceback(self) -> None:
        with self.assertLogs(config.logger, level="ERROR") as captured:
            image = storage.decode_zip_image(b"not-a-zip-archive")

        self.assertIsNone(image)
        rendered = "\n".join(captured.output)
        self.assertIn("novelai_image_archive_decode_failed", rendered)
        self.assertIn("exception_type=BadZipFile", rendered)
        self.assertIn("response_bytes=17", rendered)
        self.assertIn("Traceback", rendered)


class AtomicGenerationBatchTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.db = support.temporary_database(self)
        self.user = support.create_user(self.db, "batch-test", green_point_discount=100)
        support.reset_queue_state()

    async def asyncTearDown(self) -> None:
        support.reset_queue_state()

    async def test_replay_is_idempotent_and_model_change_is_distinct(self) -> None:
        request = support.generation_request()
        first = await support.submit(
            self.db, self.user, request, [123, 124], client_request_id="request-123"
        )
        self.assertEqual(len(state.pending_jobs), 2)

        replay = await support.submit(
            self.db, self.user, request, [123, 124], client_request_id="request-123"
        )
        self.assertEqual(replay["task_id"], first["task_id"])
        self.assertEqual(
            [item["id"] for item in replay["items"]],
            [item["id"] for item in first["items"]],
        )
        self.assertEqual(len(state.pending_jobs), 2)

        with self.assertRaises(HTTPException) as duplicate:
            await support.submit(
                self.db, self.user, request, [123], client_request_id="request-new-action"
            )
        self.assertEqual(support.error_detail(duplicate)["code"], "duplicate_generation")
        self.assertEqual(len(state.pending_jobs), 2)

        curated = support.generation_request()
        curated["model"] = "nai-diffusion-4-5-curated"
        changed = await support.submit(
            self.db, self.user, curated, [123], client_request_id="request-model-change"
        )
        self.assertEqual(len(changed["items"]), 1)
        self.assertEqual(len(state.pending_jobs), 3)

    async def test_duplicate_batch_is_rejected_before_any_item_is_added(self) -> None:
        with self.assertRaises(HTTPException) as raised:
            await support.submit(
                self.db, self.user, support.generation_request(), [999, 999]
            )

        self.assertEqual(raised.exception.status_code, 409)
        self.assertEqual(support.error_detail(raised)["code"], "duplicate_within_batch")
        self.assertEqual(len(state.pending_jobs), 0)
        count = self.db.execute("SELECT COUNT(*) FROM generation_tasks").fetchone()[0]
        self.assertEqual(count, 0)

    async def test_batch_requires_the_full_aggregate_balance(self) -> None:
        self.db.execute(
            "UPDATE users SET green_point_discount = 0, green_point_limit = 39 "
            "WHERE id = ?",
            (self.user["id"],),
        )
        self.db.commit()
        self.user = support.fetch_user(self.db, "batch-test")

        with self.assertRaises(HTTPException) as raised:
            await support.submit(
                self.db, self.user, support.generation_request(), [401, 402]
            )

        detail = support.error_detail(raised)
        self.assertEqual(detail["code"], "points_insufficient")
        self.assertEqual(detail["point_kind"], "green")
        self.assertEqual((detail["required"], detail["remaining"]), (40, 39))
        self.assertEqual(len(state.pending_jobs), 0)
        account = self.db.execute(
            "SELECT green_points_reserved FROM users WHERE id = ?",
            (self.user["id"],),
        ).fetchone()
        self.assertEqual(account["green_points_reserved"], 0)

    async def test_single_image_is_a_one_seed_batch(self) -> None:
        submitted = await support.submit(
            self.db, self.user, support.generation_request(), [777]
        )

        item = self.db.execute(
            "SELECT status, batch_id, seed FROM generation_tasks WHERE id = ?",
            (submitted["item_id"],),
        ).fetchone()
        self.assertEqual(item["status"], "queued")
        self.assertEqual(item["batch_id"], submitted["task_id"])
        self.assertEqual(item["seed"], 777)
        task = self.db.execute(
            "SELECT type, item_count FROM generation_submission_tasks WHERE id = ?",
            (submitted["task_id"],),
        ).fetchone()
        self.assertEqual((task["type"], task["item_count"]), ("single", 1))

    async def test_generation_task_http_handler_returns_202_and_persists_item(self) -> None:
        body = json.dumps(
            {
                "client_request_id": "handler-request",
                "request": support.generation_request(),
                "seeds": [778],
                "expected_quote": {"mode": "free", "points": 0},
            }
        ).encode()
        request = Request(
            {
                "type": "http",
                "method": "POST",
                "path": "/api/generation-tasks",
                "headers": [(b"content-type", b"application/json")],
                "client": ("127.0.0.1", 12345),
            },
            support.make_request("/api/generation-tasks", body).receive,
        )

        response = await generation.submit_generation_task(
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


class HistoryPaginationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.db = sqlite3.connect(":memory:")
        self.db.row_factory = sqlite3.Row
        self.db.executescript(gwdb.SCHEMA)
        self.db.execute(
            "INSERT INTO users(username, password_hash, created_at) VALUES ('history', 'x', ?)",
            (gwdb.now_iso(),),
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

        page = history.history(
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
            (gwdb.now_iso(),),
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

        own_page = history.history(request, user=self.user, db=self.db)
        all_page = history.history(
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

        result = history.delete_history_batch(
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
            history.delete_history_batch("active-batch", user=self.user, db=self.db)

        self.assertEqual(raised.exception.status_code, status.HTTP_409_CONFLICT)
        hidden = self.db.execute("SELECT COUNT(*) AS count FROM history_hidden").fetchone()
        self.assertEqual(hidden["count"], 0)


if __name__ == "__main__":
    unittest.main()
