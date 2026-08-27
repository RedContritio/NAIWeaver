from __future__ import annotations

import sqlite3
import unittest

from fastapi import HTTPException

from app import main


class ClientFeedbackTests(unittest.TestCase):
    def setUp(self) -> None:
        self.db = sqlite3.connect(":memory:")
        self.db.row_factory = sqlite3.Row
        self.db.executescript(main.SCHEMA)
        main.migrate_db(self.db)
        self.db.execute(
            "INSERT INTO users(username, password_hash, is_admin, created_at) "
            "VALUES ('reporter', 'unused', 0, ?), ('admin', 'unused', 1, ?)",
            (main.now_iso(), main.now_iso()),
        )
        self.user = self.db.execute(
            "SELECT * FROM users WHERE username = 'reporter'"
        ).fetchone()
        self.admin = self.db.execute(
            "SELECT * FROM users WHERE username = 'admin'"
        ).fetchone()

    def tearDown(self) -> None:
        self.db.close()

    def payload(self) -> main.ClientFeedbackCreateRequest:
        return main.ClientFeedbackCreateRequest(
            description="Keyboard closed after focus",
            client_context={
                "app_version": "0.9.2",
                "platform": "iPhone",
                "web": True,
                "viewport_width": 390,
                "viewport_height": 700,
            },
            diagnostics=[
                {
                    "timestamp": "2026-08-25T12:00:00Z",
                    "sequence": 17,
                    "elapsed_ms": 1200,
                    "event": "native_textarea_dom_blur",
                    "details": {"view_insets_bottom": 301.0},
                }
            ],
        )

    def test_authenticated_user_can_create_report_and_admin_can_read_it(self) -> None:
        created = main.create_client_feedback(self.payload(), self.user, self.db)
        self.assertTrue(created["id"].startswith("fb_"))

        stored = main.admin_feedback_report(created["id"], self.admin, self.db)
        self.assertEqual(stored["username"], "reporter")
        self.assertEqual(stored["event_count"], 1)
        self.assertEqual(
            stored["diagnostics"][0]["event"], "native_textarea_dom_blur"
        )
        self.assertEqual(stored["diagnostics"][0]["sequence"], 17)
        self.assertEqual(stored["diagnostics"][0]["elapsed_ms"], 1200)
        self.assertEqual(stored["client_context"]["platform"], "iPhone")

    def test_feedback_is_rate_limited_per_user(self) -> None:
        for _ in range(10):
            main.create_client_feedback(self.payload(), self.user, self.db)

        with self.assertRaises(HTTPException) as raised:
            main.create_client_feedback(self.payload(), self.user, self.db)
        self.assertEqual(raised.exception.status_code, 429)


if __name__ == "__main__":
    unittest.main()
