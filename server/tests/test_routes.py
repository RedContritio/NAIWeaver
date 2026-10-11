"""Every router is mounted on the assembled app (smoke test through HTTP)."""

from __future__ import annotations

import tests  # noqa: F401  # isolates the data directories before app imports

import asyncio
import json
import tempfile
from pathlib import Path
import unittest
from unittest import mock

from fastapi.testclient import TestClient

from app import billing, config, main, state
from tests import support


class AssembledAppTests(unittest.TestCase):
    def setUp(self) -> None:
        self.db = support.temporary_database(self)
        support.reset_queue_state()
        state.text_queue_condition = asyncio.Condition()
        self.addCleanup(support.reset_queue_state)
        self.fake = support.FakeNovelAI(self)
        directory = tempfile.TemporaryDirectory(prefix="naiweaver-routes-")
        self.addCleanup(directory.cleanup)
        for name in ("IMAGE_DIR", "THUMBNAIL_DIR", "AUDIT_DIR"):
            patcher = mock.patch.object(config, name, Path(directory.name) / name.lower())
            patcher.start()
            self.addCleanup(patcher.stop)
        self.user = support.create_user(self.db, "member", "paid")
        self.admin = support.create_user(self.db, "root", "admin")

    def client_for(self, user) -> TestClient:
        client = TestClient(main.app, follow_redirects=False)
        self.addCleanup(client.close)
        for name, value in support.session_cookies(self.db, user).items():
            client.cookies.set(name, value)
        return client

    def test_account_routes(self) -> None:
        client = self.client_for(self.user)
        self.assertEqual(client.get("/api/health").json(), {"ok": True})
        me = client.get("/api/me")
        self.assertEqual(me.status_code, 200)
        self.assertEqual(me.json()["user"]["username"], "member")
        self.assertEqual(client.get("/api/quota").status_code, 200)
        self.assertEqual(client.get("/api/queue").status_code, 200)
        self.assertEqual(TestClient(main.app).get("/api/me").status_code, 401)

    def test_generation_submission_status_and_history(self) -> None:
        client = self.client_for(self.user)
        request = support.generation_request()
        quote = support.quote_for(self.db, self.user, request, 1)
        submitted = client.post(
            "/api/generation-tasks",
            content=json.dumps(
                {
                    "client_request_id": "routes-1",
                    "request": request,
                    "seeds": [3],
                    "expected_quote": {"mode": quote.mode, "points": quote.points},
                }
            ),
            headers={"content-type": "application/json"},
        )
        self.assertEqual(submitted.status_code, 202)
        task_id = submitted.json()["task_id"]
        item_id = submitted.json()["item_id"]
        self.assertEqual(client.get(f"/api/generation-tasks/{task_id}").status_code, 200)
        self.assertEqual(client.get(f"/api/generation-items/{item_id}").status_code, 200)
        self.assertEqual(client.get("/api/current-generation-task").status_code, 200)
        history = client.get("/api/history")
        self.assertEqual(history.status_code, 200)
        self.assertEqual(history.json()["total"], 1)
        # No image has been produced yet.
        self.assertEqual(client.get(f"/api/history/{item_id}/image").status_code, 404)
        self.assertEqual(client.get(f"/api/history/{item_id}/thumbnail").status_code, 404)
        # The item is still queued, so it cannot be deleted.
        self.assertEqual(client.delete(f"/api/history/{item_id}").status_code, 409)

    def test_paid_tool_through_the_proxy_router(self) -> None:
        price = billing.tool_quote("upscale").points
        response = self.client_for(self.user).post(
            "/api/nai/image/ai/upscale",
            content=b'{"image":"a"}',
            headers={
                "content-type": "application/json",
                "idempotency-key": "routes-upscale-1",
                "x-naiweaver-expected-points": str(price),
            },
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(self.fake.calls, ["ai/upscale"])

    def test_admin_and_permissions(self) -> None:
        self.assertEqual(self.client_for(self.admin).get("/api/admin/users").status_code, 200)
        self.assertEqual(self.client_for(self.admin).get("/api/admin/config").status_code, 200)
        self.assertEqual(self.client_for(self.admin).get("/api/admin/audit").status_code, 200)
        self.assertEqual(self.client_for(self.user).get("/api/admin/users").status_code, 403)

    def test_web_fallback_and_unknown_api_paths(self) -> None:
        client = TestClient(main.app, follow_redirects=False)
        self.assertEqual(client.get("/api/does-not-exist").status_code, 404)
        self.assertEqual(client.get("/api/does-not-exist").json()["detail"]["code"], "not_found")
        page = client.get("/some/client/route")
        # Either the built UI or the "not built" notice; never an API error.
        self.assertIn(page.status_code, (200, 404))
        self.assertNotIn("application/json", page.headers.get("content-type", ""))
