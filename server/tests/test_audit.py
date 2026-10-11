"""Audit bodies: written after the outcome is known, expired by retention."""

from __future__ import annotations

import tests  # noqa: F401  # isolates the data directories before app imports

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
