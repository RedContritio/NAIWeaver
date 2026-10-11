from __future__ import annotations

import os
import tempfile

# Isolate every data path before app config reads them at import time.
_TEMP = tempfile.TemporaryDirectory(prefix="naiweaver-cli-test-")
os.environ["NAIWEAVER_DATA_DIR"] = _TEMP.name
os.environ["NAIWEAVER_DB_PATH"] = os.path.join(_TEMP.name, "naiweaver.sqlite3")
for _name in ("IMAGE_DIR", "THUMBNAIL_DIR", "AUDIT_DIR"):
    os.environ[f"NAIWEAVER_{_name}"] = os.path.join(_TEMP.name, _name.lower())
os.environ.pop("NAIWEAVER_AUTH_ISSUER", None)

from contextlib import closing, redirect_stdout
import io
from pathlib import Path
import sqlite3
import unittest
from unittest import mock

from app import cli, config, db as gwdb


def tearDownModule() -> None:
    _TEMP.cleanup()


class CliTests(unittest.TestCase):
    def setUp(self) -> None:
        temp = tempfile.TemporaryDirectory(prefix="naiweaver-cli-case-")
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        # Patch the module globals too, in case app.config was imported earlier.
        for name in ("DATA_DIR", "IMAGE_DIR", "THUMBNAIL_DIR", "AUDIT_DIR"):
            patcher = mock.patch.object(config, name, root / name.lower())
            patcher.start()
            self.addCleanup(patcher.stop)
        patcher = mock.patch.object(config, "DB_PATH", root / "naiweaver.sqlite3")
        patcher.start()
        self.addCleanup(patcher.stop)
        self.assertEqual(config.DB_PATH.parent, root)

    def run_cli(self, *argv: str) -> str:
        args = cli.build_parser().parse_args(argv)
        output = io.StringIO()
        with redirect_stdout(output):
            args.func(args)
        return output.getvalue()

    def user(self, username: str) -> sqlite3.Row:
        with closing(gwdb.db_connect()) as db:
            return db.execute("SELECT * FROM users WHERE username = ?", (username,)).fetchone()

    def set_columns(self, username: str, **values: int) -> None:
        assignments = ", ".join(f"{name} = ?" for name in values)
        with closing(gwdb.db_connect()) as db:
            db.execute(
                f"UPDATE users SET {assignments} WHERE username = ?",
                (*values.values(), username),
            )
            db.commit()

    def test_grant_adds_to_the_balance_even_if_it_changed_meanwhile(self) -> None:
        self.run_cli("user", "create", "alice", "--role", "paid")
        original = cli.user_row_or_exit

        def grant_elsewhere(db, username):
            row = original(db, username)
            with closing(gwdb.db_connect()) as other:
                other.execute("UPDATE users SET red_points = red_points + 100")
                other.commit()
            return row

        with mock.patch.object(cli, "user_row_or_exit", grant_elsewhere):
            self.run_cli("user", "points", "grant", "alice", "--red", "50")
        self.assertEqual(self.user("alice")["red_points"], 3150)

    def test_cli_commands_keep_in_flight_tool_reservations(self) -> None:
        self.run_cli("user", "create", "alice", "--role", "paid")
        user = self.user("alice")
        with closing(gwdb.db_connect()) as db:
            db.execute(
                "INSERT INTO tool_reservations(user_id, mode, points, tool, created_at) "
                "VALUES (?, 'paid', 80, 'augment', 'now')",
                (user["id"],),
            )
            db.execute("UPDATE users SET red_points_reserved = 80")
            db.commit()
        self.run_cli("user", "points", "show", "alice")
        self.assertEqual(self.user("alice")["red_points_reserved"], 80)

    def test_update_changes_only_the_options_given(self) -> None:
        self.run_cli("user", "create", "agent_test", "--role", "free", "--green-points", "10000")
        self.run_cli("user", "points", "grant", "agent_test", "--red", "500")
        self.run_cli("user", "disable", "agent_test")

        self.assertIn("unchanged", self.run_cli("user", "create", "agent_test", "--update"))
        self.run_cli("user", "create", "agent_test", "--role", "paid", "--update")
        user = self.user("agent_test")
        self.assertEqual(user["green_point_limit"], 10000)
        self.assertEqual(user["red_points"], 500)
        self.assertEqual(user["can_generate_paid"], 1)
        self.assertEqual(user["disabled"], 1)

        self.run_cli("user", "create", "agent_test", "--green-points", "12000", "--update")
        user = self.user("agent_test")
        self.assertEqual(user["green_point_limit"], 12000)
        self.assertEqual(user["red_points"], 500)
        self.assertEqual(user["can_generate_paid"], 1)

    def test_create_refuses_existing_user_without_update(self) -> None:
        self.run_cli("user", "create", "alice")
        with self.assertRaises(SystemExit):
            self.run_cli("user", "create", "alice", "--role", "admin")
        self.assertEqual(self.user("alice")["is_admin"], 0)


if __name__ == "__main__":
    unittest.main()
