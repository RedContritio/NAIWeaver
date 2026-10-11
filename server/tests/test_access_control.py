"""Access control of the history files, the audit body and the status endpoints.

Every request goes through the full ASGI stack (routing, middleware, auth
dependency) against a temporary database and temporary image directories.
"""

from __future__ import annotations

import tests  # noqa: F401  # isolates the data directories before app imports

import asyncio
from io import BytesIO
from pathlib import Path
import tempfile
import unittest
from unittest import mock

from fastapi.testclient import TestClient
from PIL import Image

from app import config, db as gwdb, main, state
from tests import support


def png_bytes(color: tuple[int, int, int]) -> bytes:
    buffer = BytesIO()
    Image.new("RGB", (8, 8), color).save(buffer, format="PNG")
    return buffer.getvalue()


class AccessControlTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.db = support.temporary_database(self)
        support.reset_queue_state()
        state.text_queue_condition = asyncio.Condition()
        self.addCleanup(support.reset_queue_state)

        directory = tempfile.TemporaryDirectory(prefix="naiweaver-files-")
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        for name in ("IMAGE_DIR", "THUMBNAIL_DIR", "AUDIT_DIR"):
            patcher = mock.patch.object(config, name, self.root / name.lower())
            patcher.start()
            self.addCleanup(patcher.stop)

        self.owner = support.create_user(self.db, "owner")
        self.other = support.create_user(self.db, "other")
        self.admin = support.create_user(self.db, "root", "admin")

    def client_for(self, user) -> TestClient:
        client = TestClient(main.app, follow_redirects=False)
        self.addCleanup(client.close)
        for name, value in support.session_cookies(self.db, user).items():
            client.cookies.set(name, value)
        return client

    def anonymous(self) -> TestClient:
        client = TestClient(main.app, follow_redirects=False)
        self.addCleanup(client.close)
        return client

    def assert_error(self, response, status_code: int, code: str) -> None:
        self.assertEqual(response.status_code, status_code, response.text)
        self.assertEqual(response.json()["detail"]["code"], code)


class HistoryFileAccessTests(AccessControlTestCase):
    def setUp(self) -> None:
        super().setUp()
        self.image = png_bytes((10, 200, 30))
        image_path = Path("2026-01-01") / "owned.png"
        (config.IMAGE_DIR / image_path.parent).mkdir(parents=True)
        (config.IMAGE_DIR / image_path).write_bytes(self.image)

        self.db.execute(
            "INSERT INTO generation_submission_tasks(id, user_id, type, status, item_count, "
            "created_at) VALUES ('batch-1', ?, 'single', 'success', 1, ?)",
            (self.owner["id"], "2026-01-01T00:00:00+00:00"),
        )
        self.db.execute(
            """
            INSERT INTO generation_tasks(
              id, user_id, mode, status, prompt, negative_prompt, width, height, steps,
              scale, sampler, seed, image_path, anlas_before, anlas_after,
              reserved_points, consumed_green_points, batch_id, batch_index,
              request_fingerprint, request_json, created_at
            ) VALUES ('item-1', ?, 'free', 'success', 'p', 'n', 832, 1216, 28, 5,
                      'k_euler', 1, ?, 100, 100, 14, 14, 'batch-1', 0, 'fp', '{}', ?)
            """,
            (self.owner["id"], str(image_path), "2026-01-01T00:00:00+00:00"),
        )
        self.db.commit()

    def get(self, user, kind: str):
        return self.client_for(user).get(f"/api/history/item-1/{kind}")

    def test_the_owner_gets_the_image_and_a_thumbnail(self) -> None:
        image = self.get(self.owner, "image")
        self.assertEqual(image.status_code, 200)
        self.assertEqual(image.headers["content-type"], "image/png")
        self.assertEqual(image.content, self.image)
        self.assertIn("private", image.headers["cache-control"])

        thumbnail = self.get(self.owner, "thumbnail")
        self.assertEqual(thumbnail.status_code, 200)
        self.assertEqual(thumbnail.headers["content-type"], "image/webp")
        self.assertTrue(thumbnail.content.startswith(b"RIFF"))

    def test_another_user_gets_neither_file(self) -> None:
        for kind in ("image", "thumbnail"):
            with self.subTest(kind=kind):
                response = self.get(self.other, kind)
                self.assert_error(response, 403, "permission_denied")
                self.assertNotEqual(response.content, self.image)

    def test_anonymous_requests_are_not_authenticated(self) -> None:
        for kind in ("image", "thumbnail"):
            with self.subTest(kind=kind):
                response = self.anonymous().get(f"/api/history/item-1/{kind}")
                self.assert_error(response, 401, "not_authenticated")

    def test_an_admin_can_open_a_visible_item_of_someone_else(self) -> None:
        response = self.get(self.admin, "image")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.content, self.image)

    def test_a_hidden_item_is_gone_for_the_owner_and_for_admins(self) -> None:
        deleted = self.client_for(self.owner).delete("/api/history/item-1")
        self.assertEqual(deleted.status_code, 200, deleted.text)

        for user in (self.owner, self.admin):
            for kind in ("image", "thumbnail"):
                with self.subTest(user=user["username"], kind=kind):
                    self.assert_error(self.get(user, kind), 404, "not_found")
        # The file itself is not what protects it: it is still on disk.
        self.assertTrue((config.IMAGE_DIR / "2026-01-01" / "owned.png").exists())

    def test_an_unknown_task_is_not_found(self) -> None:
        response = self.client_for(self.owner).get("/api/history/nope/image")
        self.assert_error(response, 404, "not_found")

    def test_an_item_without_an_image_is_not_found(self) -> None:
        self.db.execute("UPDATE generation_tasks SET image_path = NULL")
        self.db.commit()
        for kind in ("image", "thumbnail"):
            with self.subTest(kind=kind):
                self.assert_error(self.get(self.owner, kind), 404, "not_found")

    def test_a_stored_path_cannot_escape_the_image_directory(self) -> None:
        secret = self.root / "secret.png"
        secret.write_bytes(png_bytes((1, 2, 3)))
        for evil in ("../secret.png", str(secret)):
            self.db.execute("UPDATE generation_tasks SET image_path = ?", (evil,))
            self.db.commit()
            for kind in ("image", "thumbnail"):
                with self.subTest(path=evil, kind=kind):
                    response = self.get(self.owner, kind)
                    self.assertEqual(response.status_code, 404, response.text)
                    self.assertNotEqual(response.content, secret.read_bytes())


class AuditBodyAccessTests(AccessControlTestCase):
    BODY = b'{"prompt": "private request"}'

    def setUp(self) -> None:
        super().setUp()
        config.AUDIT_DIR.mkdir(parents=True)
        (config.AUDIT_DIR / "a1.body").write_bytes(self.BODY)
        (self.root / "outside.body").write_bytes(b"outside")
        for audit_id, relative in (("a1", "a1.body"), ("evil", "../outside.body")):
            self.db.execute(
                "INSERT INTO request_audit_logs(id, user_id, service, path, method, "
                "request_content_type, request_body_path, created_at) "
                "VALUES (?, ?, 'image', '/x', 'POST', 'application/json', ?, ?)",
                (audit_id, self.owner["id"], relative, gwdb.now_iso()),
            )
        self.db.commit()

    def test_an_admin_downloads_the_stored_body(self) -> None:
        response = self.client_for(self.admin).get("/api/admin/audit/a1/body")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.content, self.BODY)
        self.assertEqual(response.headers["content-type"], "application/json")

    def test_the_owner_of_the_request_is_not_an_admin(self) -> None:
        for user in (self.owner, self.other):
            with self.subTest(user=user["username"]):
                response = self.client_for(user).get("/api/admin/audit/a1/body")
                self.assert_error(response, 403, "permission_denied")
                self.assertNotIn(b"private request", response.content)

    def test_anonymous_requests_are_not_authenticated(self) -> None:
        response = self.anonymous().get("/api/admin/audit/a1/body")
        self.assert_error(response, 401, "not_authenticated")

    def test_unknown_ids_and_paths_outside_the_audit_directory_are_404(self) -> None:
        admin = self.client_for(self.admin)
        self.assertEqual(admin.get("/api/admin/audit/missing/body").status_code, 404)
        escaped = admin.get("/api/admin/audit/evil/body")
        self.assertEqual(escaped.status_code, 404)
        self.assertNotEqual(escaped.content, b"outside")


class StatusEndpointTests(AccessControlTestCase):
    PATHS = ("/api/quota", "/api/queue", "/api/current-generation-task")

    def test_all_three_need_a_session(self) -> None:
        for path in self.PATHS:
            with self.subTest(path=path):
                self.assert_error(self.anonymous().get(path), 401, "not_authenticated")

    def test_a_garbage_token_is_rejected_like_a_missing_one(self) -> None:
        client = self.anonymous()
        client.cookies.set("access_token", "not-a-jwt")
        for path in self.PATHS:
            with self.subTest(path=path):
                self.assert_error(client.get(path), 401, "not_authenticated")

    def test_quota_reports_both_point_buckets_for_the_caller(self) -> None:
        paid = support.create_user(
            self.db, "payer", "paid", green_point_limit=500, green_point_used=120
        )
        body = self.client_for(paid).get("/api/quota").json()
        self.assertEqual(set(body), {"free", "paid"})
        self.assertEqual(body["free"]["mode"], "free")
        self.assertEqual(body["free"]["green_point_limit"], 500)
        self.assertEqual(body["free"]["used"], 120)
        self.assertEqual(body["free"]["remaining"], 380)
        self.assertEqual(body["paid"]["mode"], "paid")
        self.assertEqual(body["paid"]["red_points"], 1000)
        self.assertTrue(body["paid"]["enabled"])

        # A different caller sees their own numbers, not the first user's.
        free = self.client_for(self.owner).get("/api/quota").json()
        self.assertEqual(free["free"]["green_point_limit"], 4000)
        self.assertEqual(free["free"]["used"], 0)
        self.assertFalse(free["paid"]["enabled"])

    def test_an_idle_queue_reports_nothing_for_the_caller(self) -> None:
        body = self.client_for(self.owner).get("/api/queue").json()
        self.assertEqual(
            {key: body[key] for key in (
                "queued", "active", "user_active", "user_queued",
                "tasks_ahead", "estimated_wait_seconds", "user_pending_count",
            )},
            {
                "queued": 0, "active": 0, "user_active": False, "user_queued": False,
                "tasks_ahead": None, "estimated_wait_seconds": None,
                "user_pending_count": 0,
            },
        )
        self.assertIn("text_concurrency", body)

    def test_the_queue_position_is_the_callers_own(self) -> None:
        def job(user_id: int):
            return mock.Mock(user_id=user_id)

        state.pending_jobs.extend(
            [job(int(self.other["id"])), job(int(self.owner["id"])),
             job(int(self.owner["id"]))]
        )
        owner = self.client_for(self.owner).get("/api/queue").json()
        self.assertEqual(owner["queued"], 3)
        self.assertTrue(owner["user_queued"])
        self.assertEqual(owner["tasks_ahead"], 1)
        self.assertEqual(owner["user_pending_count"], 2)

        other = self.client_for(self.other).get("/api/queue").json()
        self.assertEqual((other["tasks_ahead"], other["user_pending_count"]), (0, 1))

        admin = self.client_for(self.admin).get("/api/queue").json()
        self.assertFalse(admin["user_queued"])
        self.assertIsNone(admin["tasks_ahead"])
        self.assertEqual(admin["queued"], 3)

    def test_current_generation_task_is_empty_without_history(self) -> None:
        response = self.client_for(self.owner).get("/api/current-generation-task")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"task": None})

    def test_current_generation_task_never_shows_another_users_task(self) -> None:
        self.db.execute(
            "INSERT INTO generation_submission_tasks(id, user_id, type, status, "
            "item_count, created_at) VALUES ('theirs', ?, 'single', 'running', 1, ?)",
            (self.other["id"], gwdb.now_iso()),
        )
        self.db.execute(
            """
            INSERT INTO generation_tasks(
              id, user_id, mode, status, prompt, negative_prompt, width, height, steps,
              scale, sampler, seed, anlas_before, anlas_after, reserved_points,
              consumed_green_points, batch_id, batch_index, request_fingerprint,
              request_json, created_at
            ) VALUES ('theirs-item', ?, 'free', 'running', 'p', 'n', 832, 1216, 28, 5,
                      'k_euler', 1, 100, 100, 14, 0, 'theirs', 0, 'fp', '{}', ?)
            """,
            (self.other["id"], gwdb.now_iso()),
        )
        self.db.commit()

        mine = self.client_for(self.owner).get("/api/current-generation-task").json()
        self.assertEqual(mine, {"task": None})
        theirs = self.client_for(self.other).get("/api/current-generation-task").json()
        self.assertEqual(theirs["task"]["id"], "theirs")
        self.assertEqual(theirs["task"]["status"], "running")


if __name__ == "__main__":
    unittest.main()
