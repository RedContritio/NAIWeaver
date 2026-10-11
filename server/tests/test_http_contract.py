from __future__ import annotations

import tests  # noqa: F401  # isolates the data directories before app imports

import asyncio
import json
import unittest
from unittest import mock

import httpx

from app import auth, config, main, proxy, state
from tests import support


CONTRACT_ITEM_FIELDS = {
    "id",
    "user_id",
    "username",
    "batch_id",
    "batch_index",
    "batch_size",
    "status",
    "error_code",
    "error_message",
    "mode",
    "points_charged",
    "prompt",
    "negative_prompt",
    "width",
    "height",
    "steps",
    "scale",
    "sampler",
    "seed",
    "request_json",
    "has_image",
    "created_at",
    "completed_at",
}
FEEDBACK = {
    "description": "chunked upload",
    "client_context": {"app_version": "test"},
    "diagnostics": [],
}


class HttpContractTestCase(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.db = support.temporary_database(self)
        support.reset_queue_state()
        state.text_queue_condition = asyncio.Condition()
        self.user = support.create_user(self.db, "http-user")
        self.client = httpx.AsyncClient(
            transport=httpx.ASGITransport(app=main.app),
            base_url="http://testserver",
            cookies=support.session_cookies(self.db, self.user),
        )

    async def asyncTearDown(self) -> None:
        await self.client.aclose()
        support.reset_queue_state()

    def assertError(self, response: httpx.Response, status_code: int, code: str) -> dict:
        self.assertEqual(response.status_code, status_code, response.text)
        detail = response.json()["detail"]
        self.assertEqual(detail["code"], code)
        self.assertIsInstance(detail["message"], str)
        return detail


class RequestLimitTests(HttpContractTestCase):
    async def test_chunked_upload_is_counted_on_the_stream(self) -> None:
        limit = config.MAX_REQUEST_BODY_BYTES
        chunk = b" " * (1024 * 1024)

        async def oversized():
            yield b'{"description": "'
            for _ in range(limit // len(chunk) + 1):
                yield chunk

        response = await self.client.post(
            "/api/feedback",
            content=oversized(),
            headers={"content-type": "application/json"},
        )

        self.assertNotIn("content-length", response.request.headers)
        detail = self.assertError(response, 413, "request_too_large")
        self.assertEqual(detail["limit"], limit)
        count = self.db.execute("SELECT COUNT(*) FROM client_feedback_reports").fetchone()[0]
        self.assertEqual(count, 0)

    async def test_chunked_upload_within_the_limit_is_accepted(self) -> None:
        payload = json.dumps(FEEDBACK).encode()

        async def chunks():
            for start in range(0, len(payload), 7):
                yield payload[start:start + 7]

        response = await self.client.post(
            "/api/feedback",
            content=chunks(),
            headers={"content-type": "application/json"},
        )
        self.assertNotIn("content-length", response.request.headers)
        self.assertEqual(response.status_code, 201, response.text)

    async def test_declared_length_over_the_limit_is_rejected_before_reading(self) -> None:
        response = await self.client.post(
            "/api/feedback",
            content=b"{}",
            headers={"content-length": str(config.MAX_REQUEST_BODY_BYTES + 1)},
        )
        self.assertError(response, 413, "request_too_large")


class ErrorFormatTests(HttpContractTestCase):
    async def test_unknown_api_paths_are_json_404_even_with_web_auth(self) -> None:
        with mock.patch.object(auth.only_auth, "enabled", True):
            api = await self.client.get("/api/does-not-exist")
            page = await self.client.get("/history")
        self.assertError(api, 404, "not_found")
        self.assertEqual(page.status_code, 302)
        self.assertEqual(page.headers["location"], "/auth/login?return_to=%2Fhistory")

    async def test_missing_session_is_not_authenticated(self) -> None:
        self.client.cookies.clear()
        for path in ("/api/me", "/api/quota", "/api/history"):
            with self.subTest(path):
                self.assertError(await self.client.get(path), 401, "not_authenticated")

    async def test_upstream_401_is_reported_as_upstream_error(self) -> None:
        async def unauthorized(service, path, *, method, body=b"", stream=False):
            return 401, {"content-type": "application/json"}, b'{"message":"bad token"}'

        with mock.patch.object(proxy, "forward_to_novelai", unauthorized):
            response = await self.client.post("/api/nai/text/ai/generate", json={"input": "x"})

        detail = self.assertError(response, 502, "upstream_error")
        self.assertEqual(detail["upstream_status"], 401)

    async def test_direct_generation_proxy_is_rejected(self) -> None:
        response = await self.client.post(
            "/api/nai/image/ai/generate-image", json=support.generation_request()
        )
        detail = self.assertError(response, 400, "invalid_parameters")
        self.assertEqual(detail["field"], "path")

    async def test_paid_tool_without_permission_is_permission_denied(self) -> None:
        response = await self.client.post(
            "/api/nai/image/ai/upscale",
            json={"image": "x"},
            headers={"Idempotency-Key": "tool-key-0001", "X-NAIWeaver-Expected-Points": "10"},
        )
        detail = self.assertError(response, 403, "permission_denied")
        self.assertEqual(detail["permission"], "image.upscale")

    async def test_body_validation_errors_are_invalid_parameters(self) -> None:
        response = await self.client.post(
            "/api/feedback", json={**FEEDBACK, "diagnostics": "not-a-list"}
        )
        detail = self.assertError(response, 400, "invalid_parameters")
        self.assertEqual(detail["field"], "diagnostics")

    async def test_submission_errors_use_contract_codes(self) -> None:
        response = await self.client.post(
            "/api/generation-tasks",
            json={
                "client_request_id": "http-request-1",
                "request": support.generation_request(),
                "seeds": [1],
                "expected_quote": {"mode": "free", "points": 5},
            },
        )
        detail = self.assertError(response, 409, "quote_changed")
        self.assertEqual(detail["quote"]["points"], 20)


class ProfileRulesTests(HttpContractTestCase):
    async def test_me_serves_rules_resolved_for_the_user(self) -> None:
        response = await self.client.get("/api/me")
        self.assertEqual(response.status_code, 200)
        rules = response.json()["rules"]["image"]
        self.assertEqual(
            set(rules),
            {
                "free_sizes",
                "free_max_steps",
                "max_steps",
                "max_dimension",
                "allowed_samplers",
                "batch_limit",
                "green_point_discount",
                "free_allowance_exhausted",
                "pricing",
                "tool_caps",
            },
        )
        self.assertEqual((rules["batch_limit"], rules["max_steps"]), (4, 28))
        self.assertEqual(rules["tool_caps"], {"upscale": 10, "augment": 80, "encode_vibe": 2})
        self.assertFalse(rules["free_allowance_exhausted"])


class HistoryDtoTests(HttpContractTestCase):
    def insert_submission(self, task_id: str, created_at: str, items: list[dict]) -> None:
        self.db.execute(
            "INSERT INTO generation_submission_tasks(id, user_id, type, status, item_count, created_at) "
            "VALUES (?, ?, ?, 'success', ?, ?)",
            (task_id, self.user["id"], "batch" if len(items) > 1 else "single", len(items), created_at),
        )
        for index, item in enumerate(items):
            self.db.execute(
                """
                INSERT INTO generation_tasks(
                  id, user_id, mode, status, prompt, negative_prompt, width, height,
                  steps, scale, sampler, seed, image_path, error_message,
                  reserved_points, consumed_green_points,
                  batch_id, batch_index, request_fingerprint, request_json, created_at
                ) VALUES (?, ?, 'free', ?, 'p', 'n', 832, 1216, 28, 5, 'k_euler', ?, ?,
                          ?, 14, ?, ?, ?, 'fingerprint', ?, ?)
                """,
                (
                    item["id"],
                    self.user["id"],
                    item["status"],
                    index,
                    item.get("image_path"),
                    item.get("error_message"),
                    14 if item["status"] == "success" else 0,
                    task_id,
                    index,
                    json.dumps({"parameters": {"image": "secret-base64", "seed": index}}),
                    created_at,
                ),
            )
            if item.get("error_code"):
                self.db.execute(
                    "INSERT INTO generation_item_errors(item_id, error_code, created_at) VALUES (?, ?, ?)",
                    (item["id"], item["error_code"], created_at),
                )
        self.db.commit()

    async def asyncSetUp(self) -> None:
        await super().asyncSetUp()
        self.insert_submission(
            "older-batch",
            "2026-01-01T00:00:00+00:00",
            [
                {"id": "ok-item", "status": "success", "image_path": "2026-01-01/ok-item.png"},
                {
                    "id": "failed-item",
                    "status": "failed",
                    "error_message": "NovelAI HTTP 429",
                    "error_code": "upstream_error",
                },
            ],
        )
        self.insert_submission(
            "newer-single",
            "2026-01-02T00:00:00+00:00",
            [{"id": "single-item", "status": "success", "image_path": "2026-01-02/single.png"}],
        )

    async def test_history_items_expose_exactly_the_contract_fields(self) -> None:
        response = await self.client.get("/api/history")
        self.assertEqual(response.status_code, 200)
        items = {item["id"]: item for item in response.json()["items"]}
        for item in items.values():
            self.assertEqual(set(item), CONTRACT_ITEM_FIELDS)
        self.assertEqual(
            {key: items[key]["batch_size"] for key in items},
            {"ok-item": 2, "failed-item": 2, "single-item": 1},
        )
        self.assertTrue(items["ok-item"]["has_image"])
        self.assertFalse(items["failed-item"]["has_image"])
        self.assertEqual(items["failed-item"]["error_code"], "upstream_error")
        self.assertIsNone(items["ok-item"]["error_code"])
        self.assertEqual(items["ok-item"]["points_charged"], 14)
        self.assertEqual(items["failed-item"]["points_charged"], 0)
        self.assertNotIn("secret-base64", items["ok-item"]["request_json"])

        single = await self.client.get("/api/generation-items/failed-item")
        self.assertEqual(set(single.json()), CONTRACT_ITEM_FIELDS)

    async def test_hidden_items_are_never_returned(self) -> None:
        deleted = await self.client.delete("/api/history/failed-item")
        self.assertEqual(deleted.status_code, 200)

        task = (await self.client.get("/api/generation-tasks/older-batch")).json()
        self.assertEqual([item["id"] for item in task["items"]], ["ok-item"])
        self.assertTrue(all(set(item) == CONTRACT_ITEM_FIELDS for item in task["items"]))
        self.assertError(
            await self.client.get("/api/generation-items/failed-item"), 404, "not_found"
        )
        history = (await self.client.get("/api/history")).json()
        self.assertNotIn("failed-item", [item["id"] for item in history["items"]])

        current = (await self.client.get("/api/current-generation-task")).json()["task"]
        self.assertEqual(current["id"], "newer-single")
        await self.client.delete("/api/history/batches/newer-single")
        current = (await self.client.get("/api/current-generation-task")).json()["task"]
        self.assertEqual(current["id"], "older-batch")
        self.assertEqual([item["id"] for item in current["items"]], ["ok-item"])

        await self.client.delete("/api/history/ok-item")
        self.assertIsNone((await self.client.get("/api/current-generation-task")).json()["task"])
        self.assertError(
            await self.client.get("/api/generation-tasks/older-batch"), 404, "not_found"
        )


if __name__ == "__main__":
    unittest.main()
