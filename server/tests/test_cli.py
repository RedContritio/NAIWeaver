from __future__ import annotations

import os
import tempfile

# Isolate every data path before app.main reads them at import time.
_TEMP = tempfile.TemporaryDirectory(prefix="naiweaver-cli-test-")
os.environ["NAIWEAVER_DATA_DIR"] = _TEMP.name
os.environ["NAIWEAVER_DB_PATH"] = os.path.join(_TEMP.name, "naiweaver.sqlite3")
for _name in ("IMAGE_DIR", "THUMBNAIL_DIR", "AUDIT_DIR"):
    os.environ[f"NAIWEAVER_{_name}"] = os.path.join(_TEMP.name, _name.lower())
os.environ.pop("NAIWEAVER_AUTH_ISSUER", None)

import ast
from contextlib import closing, redirect_stdout
import io
from pathlib import Path
import sqlite3
import unittest
from unittest import mock

from app import cli, main, roles


def tearDownModule() -> None:
    _TEMP.cleanup()


class CliTests(unittest.TestCase):
    def setUp(self) -> None:
        temp = tempfile.TemporaryDirectory(prefix="naiweaver-cli-case-")
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        # Patch the module globals too, in case app.main was imported earlier.
        for name in ("DATA_DIR", "IMAGE_DIR", "THUMBNAIL_DIR", "AUDIT_DIR"):
            patcher = mock.patch.object(main, name, root / name.lower())
            patcher.start()
            self.addCleanup(patcher.stop)
        patcher = mock.patch.object(main, "DB_PATH", root / "naiweaver.sqlite3")
        patcher.start()
        self.addCleanup(patcher.stop)
        self.assertEqual(main.DB_PATH.parent, root)

    def run_cli(self, *argv: str) -> str:
        args = cli.build_parser().parse_args(argv)
        output = io.StringIO()
        with redirect_stdout(output):
            args.func(args)
        return output.getvalue()

    def user(self, username: str) -> sqlite3.Row:
        with closing(main.db_connect()) as db:
            return db.execute("SELECT * FROM users WHERE username = ?", (username,)).fetchone()

    def set_columns(self, username: str, **values: int) -> None:
        assignments = ", ".join(f"{name} = ?" for name in values)
        with closing(main.db_connect()) as db:
            db.execute(
                f"UPDATE users SET {assignments} WHERE username = ?",
                (*values.values(), username),
            )
            db.commit()

    def test_create_applies_role_defaults(self) -> None:
        for role in roles.ROLES:
            with self.subTest(role=role):
                self.run_cli("user", "create", f"{role}_user", "--role", role)
                user = self.user(f"{role}_user")
                for name, value in roles.role_defaults(role).items():
                    self.assertEqual(user[name], value, name)
        self.run_cli("user", "create", "plain")
        self.assertEqual(self.user("plain")["can_generate_paid"], 0)

    def test_grant_adds_to_the_balance_even_if_it_changed_meanwhile(self) -> None:
        self.run_cli("user", "create", "alice", "--role", "paid")
        original = cli.user_row_or_exit

        def grant_elsewhere(db, username):
            row = original(db, username)
            with closing(main.db_connect()) as other:
                other.execute("UPDATE users SET red_points = red_points + 100")
                other.commit()
            return row

        with mock.patch.object(cli, "user_row_or_exit", grant_elsewhere):
            self.run_cli("user", "points", "grant", "alice", "--red", "50")
        self.assertEqual(self.user("alice")["red_points"], 3150)

    def test_cli_commands_keep_in_flight_tool_reservations(self) -> None:
        self.run_cli("user", "create", "alice", "--role", "paid")
        user = self.user("alice")
        with closing(main.db_connect()) as db:
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

    def test_points_show_subtracts_reserved_points(self) -> None:
        self.run_cli("user", "create", "alice", "--role", "paid", "--green-points", "10000")
        self.set_columns("alice", green_point_used=100, red_points=1000, red_points_used=100)
        # init_db() rebuilds the reserved counters from active tasks, so reserve
        # through queued tasks rather than by writing the counters directly.
        with closing(main.db_connect()) as db:
            for task_id, mode, points in (("t-free", "free", 250), ("t-paid", "paid", 300)):
                db.execute(
                    "INSERT INTO generation_tasks(id, user_id, mode, status, prompt, width,"
                    " height, steps, scale, sampler, seed, reserved_points, request_json,"
                    " created_at) VALUES (?, ?, ?, 'queued', '', 832, 1216, 28, 5,"
                    " 'k_euler', 1, ?, '{}', ?)",
                    (task_id, self.user("alice")["id"], mode, points, main.now_iso()),
                )
            db.commit()
        output = self.run_cli("user", "points", "show", "alice")
        self.assertIn("green: 9650 remaining / 10000 total (250 reserved)", output)
        self.assertIn("red: 600 remaining / 1000 total (300 reserved)", output)


class RoleDefaultsTests(unittest.TestCase):
    def test_role_defaults_has_a_single_definition(self) -> None:
        self.assertIs(cli.role_defaults, roles.role_defaults)
        app_dir = Path(roles.__file__).parent
        definers = [
            path.name
            for path in sorted(app_dir.glob("*.py"))
            for node in ast.walk(ast.parse(path.read_text()))
            if isinstance(node, ast.FunctionDef) and node.name == "role_defaults"
        ]
        self.assertEqual(definers, ["roles.py"])

    def test_roles_follow_one_rule_set(self) -> None:
        free, paid, admin = (roles.role_defaults(role) for role in ("free", "paid", "admin"))
        self.assertEqual(free["red_points"], 0)
        self.assertEqual(
            {free[name] for name in ("can_generate_paid", "can_image_upscale",
                                     "can_image_augment", "can_image_encode_vibe")},
            {0},
        )
        self.assertEqual(paid["red_points"], roles.DEFAULT_RED_POINTS)
        self.assertEqual((admin["is_admin"], admin["green_point_discount"]), (1, 100))
        self.assertEqual(admin["red_points"], roles.DEFAULT_ADMIN_RED_POINTS)
        self.assertIsNot(roles.role_defaults("free"), roles.role_defaults("free"))
        with self.assertRaises(ValueError):
            roles.role_defaults("owner")


if __name__ == "__main__":
    unittest.main()
