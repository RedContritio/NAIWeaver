"""Audit bodies: written after the outcome is known, expired by retention."""

from __future__ import annotations

import tests  # noqa: F401  # isolates the data directories before app imports

from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

from fastapi.testclient import TestClient

from app import audit, config, db as gwdb, main, state
from tests import support


class AuditTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.db = support.temporary_database(self)
        support.reset_queue_state()
        self.addCleanup(support.reset_queue_state)
        directory = tempfile.TemporaryDirectory(prefix="naiweaver-audit-")
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        patcher = mock.patch.object(config, "AUDIT_DIR", self.root / "audit")
        patcher.start()
        self.addCleanup(patcher.stop)
        self.owner = support.create_user(self.db, "owner")
        self.admin = support.create_user(self.db, "root", "admin")

    def client_for(self, user) -> TestClient:
        client = TestClient(main.app, follow_redirects=False)
        self.addCleanup(client.close)
        for name, value in support.session_cookies(self.db, user).items():
            client.cookies.set(name, value)
        return client

    def audit_rows(self) -> list:
        return self.db.execute(
            "SELECT * FROM request_audit_logs ORDER BY created_at"
        ).fetchall()

    def body_files(self) -> list[Path]:
        if not config.AUDIT_DIR.exists():
            return []
        return [p for p in config.AUDIT_DIR.rglob("*.body")]


class SubmissionAuditTests(AuditTestCase):
    def test_a_rejected_submission_records_metadata_but_no_body(self) -> None:
        body = b'{"client_request_id": "x", "padding": "' + b"p" * 2000 + b'"}'
        response = self.client_for(self.owner).post(
            "/api/generation-tasks",
            content=body,
            headers={"content-type": "application/json"},
        )
        self.assertEqual(response.status_code, 400)
        (row,) = self.audit_rows()
        self.assertEqual(row["status_code"], 400)
        self.assertIsNone(row["request_body_path"])
        self.assertEqual(row["request_body_bytes"], len(body))
        self.assertEqual(self.body_files(), [])

    def test_an_accepted_submission_stores_the_full_body(self) -> None:
        request = support.generation_request()
        quote = support.quote_for(self.db, self.owner, request, 1)
        body = json.dumps(
            {
                "client_request_id": "accepted-1",
                "request": request,
                "seeds": [7],
                "expected_quote": {"mode": quote.mode, "points": quote.points},
            }
        ).encode()
        response = self.client_for(self.owner).post(
            "/api/generation-tasks",
            content=body,
            headers={"content-type": "application/json"},
        )
        self.assertEqual(response.status_code, 202)
        (row,) = self.audit_rows()
        self.assertEqual(row["status_code"], 202)
        stored = config.AUDIT_DIR / row["request_body_path"]
        self.assertEqual(stored.read_bytes(), body)
        self.assertEqual(row["request_body_bytes"], len(body))


class RetentionTests(AuditTestCase):
    def add_audit(self, audit_id: str, age_days: int, body: bytes) -> Path:
        created = datetime.now(timezone.utc) - timedelta(days=age_days)
        relative = Path(created.date().isoformat()) / "user-1" / f"{audit_id}.body"
        target = config.AUDIT_DIR / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(body)
        self.db.execute(
            "INSERT INTO request_audit_logs(id, user_id, service, path, method, "
            "request_content_type, request_body_path, request_body_bytes, created_at) "
            "VALUES (?, ?, 'image', '/x', 'POST', 'application/json', ?, ?, ?)",
            (audit_id, self.owner["id"], relative.as_posix(), len(body), created.isoformat()),
        )
        self.db.commit()
        return target

    def test_expired_bodies_are_deleted_and_recent_ones_kept(self) -> None:
        old = self.add_audit("old", 45, b"old body")
        fresh = self.add_audit("fresh", 5, b"fresh body")
        with mock.patch.object(config, "AUDIT_RETENTION_DAYS", 30):
            self.assertEqual(audit.prune_expired_audit_bodies(), 1)
        self.assertFalse(old.exists())
        self.assertTrue(fresh.exists())
        rows = {r["id"]: r for r in self.audit_rows()}
        self.assertIsNone(rows["old"]["request_body_path"])
        self.assertIsNotNone(rows["old"]["request_body_expired_at"])
        self.assertIsNone(rows["fresh"]["request_body_expired_at"])
        self.assertEqual(
            rows["fresh"]["request_body_path"],
            fresh.relative_to(config.AUDIT_DIR).as_posix(),
        )

    def test_reading_an_expired_body_is_404_and_says_expired(self) -> None:
        self.add_audit("old", 45, b"old body")
        self.add_audit("fresh", 5, b"fresh body")
        with mock.patch.object(config, "AUDIT_RETENTION_DAYS", 30):
            audit.prune_expired_audit_bodies()
        admin = self.client_for(self.admin)
        expired = admin.get("/api/admin/audit/old/body")
        self.assertEqual(expired.status_code, 404)
        self.assertIn("expired", json.dumps(expired.json()).lower())
        fresh = admin.get("/api/admin/audit/fresh/body")
        self.assertEqual(fresh.status_code, 200)
        self.assertEqual(fresh.content, b"fresh body")
        items = {i["id"]: i for i in admin.get("/api/admin/audit").json()["items"]}
        self.assertTrue(items["old"]["request_body_expired"])
        self.assertFalse(items["old"]["request_body_available"])
        self.assertFalse(items["fresh"]["request_body_expired"])
        for leaked in ("request_body_path", "request_body_sha256"):
            self.assertNotIn(leaked, items["fresh"])
        self.assertEqual(items["fresh"]["request_body_url"], "/api/admin/audit/fresh/body")

    def test_zero_days_keeps_everything(self) -> None:
        old = self.add_audit("old", 400, b"old body")
        with mock.patch.object(config, "AUDIT_RETENTION_DAYS", 0):
            self.assertEqual(audit.prune_expired_audit_bodies(), 0)
        self.assertTrue(old.exists())
