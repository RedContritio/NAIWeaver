"""The one-off upgrade of a production-shaped (version 0) database, and the
startup rules around schema versions."""

from __future__ import annotations

import tests  # noqa: F401  # isolates the data directories before app imports

from contextlib import closing
import hashlib
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest import mock

from app import config, db as gwdb, db_upgrade

FIXTURE = Path(__file__).parent / "fixtures" / "prod_schema_v0.sql"
NOW = "2026-01-01T00:00:00+00:00"


def user(db, username: str, **values) -> int:
    columns = {"username": username, "password_hash": "x", "created_at": NOW, **values}
    cursor = db.execute(
        f"INSERT INTO users({', '.join(columns)}) VALUES ({', '.join('?' for _ in columns)})",
        tuple(columns.values()),
    )
    return int(cursor.lastrowid)


def task(db, task_id: str, user_id: int, status: str, mode: str, reserved: int, batch: str, **values) -> None:
    columns = {
        "id": task_id, "user_id": user_id, "status": status, "mode": mode,
        "prompt": "p", "width": 832, "height": 1216, "steps": 28, "scale": 5.0,
        "sampler": "k_euler", "seed": 1, "request_json": "{}", "created_at": NOW,
        "reserved_points": reserved, "batch_id": batch, "cost": reserved,
        "reserved_green_points": reserved if mode == "free" else 0,
        "reserved_red_points": reserved if mode == "paid" else 0,
        "anlas_before": 100, "anlas_after": 90, **values,
    }
    db.execute(
        f"INSERT INTO generation_tasks({', '.join(columns)}) "
        f"VALUES ({', '.join('?' for _ in columns)})",
        tuple(columns.values()),
    )


def build_production_database(path: Path) -> None:
    """A version-0 database in production shape with representative rows."""
    with closing(sqlite3.connect(path)) as db:
        db.executescript(FIXTURE.read_text())
        alice = user(db, "alice", green_point_limit=4000, green_point_used=120,
                     green_points_reserved=28)  # stale: only 14 is really held
        bob = user(db, "bob", can_generate_paid=1, red_points=1000, red_points_used=100,
                   green_points_reserved=5, red_points_reserved=66)  # 5 leaked
        user(db, "carol", is_admin=1, green_point_discount=100, red_points=5000)
        task(db, "a-done", alice, "success", "free", 14, "b1", consumed_green_points=14,
             image_path="2026/a.png")
        task(db, "a-queued", alice, "queued", "free", 14, "b2")
        task(db, "b-queued", bob, "queued", "paid", 33, "b3")
        task(db, "b-running", bob, "running", "paid", 33, "b3")
        # Older paid success: the charge only lives in paid_points_charged.
        task(db, "b-done", bob, "success", "paid", 33, "b4", paid_points_charged=30)
        task(db, "b-failed", bob, "failed", "paid", 33, "b5", released_red_points=33,
             error_message="boom")
        db.executemany(
            "INSERT INTO generation_submission_tasks"
            "(id, user_id, type, status, item_count, reserved_points, consumed_points, "
            " created_at, client_request_id, request_hash) VALUES (?,?,?,?,?,?,?,?,?,?)",
            [
                ("b1", alice, "single", "success", 1, 14, 14, NOW, "req-a1", "hash-a1"),
                ("b2", alice, "single", "queued", 1, 14, 0, NOW, "req-a2", "hash-a2"),
                ("b3", bob, "batch", "running", 2, 66, 0, NOW, "req-b1", "hash-b1"),
                ("b4", bob, "single", "success", 1, 33, 30, NOW, None, None),
                ("b5", bob, "single", "failed", 1, 33, 0, NOW, "req-b2", "hash-b2"),
            ],
        )
        db.executemany(
            "INSERT INTO history_hidden(user_id, task_id, hidden_at) VALUES (?,?,?)",
            [(alice, "a-done", NOW), (bob, "b-done", NOW)],
        )
        db.executemany(
            "INSERT INTO request_audit_logs(id, user_id, service, path, method, status_code, "
            "request_json, created_at) VALUES (?,?,?,?,?,?,?,?)",
            [("au1", alice, "image", "ai/upscale", "POST", 200, "{}", NOW),
             ("au2", bob, "text", "ai/generate", "POST", 429, "{}", NOW)],
        )
        db.execute(
            "INSERT INTO client_feedback_reports(id, user_id, description, client_context_json, "
            "diagnostics_json, event_count, created_at) VALUES ('fb1', ?, 'it broke', '{}', '[]', 3, ?)",
            (alice, NOW),
        )
        db.execute(
            "INSERT INTO sessions(id, user_id, expires_at, created_at) VALUES ('s1', ?, ?, ?)",
            (alice, "2999-01-01T00:00:00+00:00", NOW),
        )
        db.execute("INSERT INTO quota_usage VALUES (?, '2026-01-01', 'free', 2)", (alice,))
        db.execute("INSERT INTO schema_migrations VALUES ('old', ?)", (NOW,))
        db.commit()


def file_hash(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def logical_dump(path: Path) -> str:
    with closing(sqlite3.connect(path)) as db:
        return "\n".join(db.iterdump())


class UpgradeTestCase(unittest.TestCase):
    def setUp(self) -> None:
        directory = tempfile.TemporaryDirectory(prefix="naiweaver-upgrade-")
        self.addCleanup(directory.cleanup)
        self.dir = Path(directory.name)
        self.path = self.dir / "gateway.sqlite3"
        build_production_database(self.path)
        self.logs: list[str] = []

    def run_upgrade(self, **overrides) -> None:
        options = {"apply": False, "backup_verified": False, "backup_to": None,
                   "log": self.logs.append, **overrides}
        db_upgrade.run(self.path, **options)

    def rows(self, sql: str, params=()) -> list[tuple]:
        with closing(sqlite3.connect(self.path)) as db:
            return [tuple(row) for row in db.execute(sql, params)]


class UpgradeTests(UpgradeTestCase):
    def test_dry_run_changes_nothing_and_reports_the_steps(self) -> None:
        before = file_hash(self.path)
        self.run_upgrade()
        self.assertEqual(file_hash(self.path), before)
        self.assertEqual(self.rows("PRAGMA user_version"), [(0,)])
        text = "\n".join(self.logs)
        for expected in ("DRY RUN", "request_body_expired_at", "tool_reservations",
                         "rebuild generation_tasks: copy 6 rows", "anlas_before",
                         "drop table webauthn_credentials", "drop table quota_usage (1 rows",
                         "user 1: green 28 -> 14", "user 2: green 5 -> 0", "checks passed"):
            self.assertIn(expected, text)

    def test_apply_needs_exactly_one_backup_option(self) -> None:
        before = file_hash(self.path)
        for options in ({}, {"backup_verified": True, "backup_to": self.dir / "b.sqlite3"}):
            with self.subTest(options), self.assertRaises(db_upgrade.UpgradeError):
                self.run_upgrade(apply=True, **options)
        self.assertEqual(file_hash(self.path), before)
        self.assertFalse((self.dir / "b.sqlite3").exists())

    def test_apply_reaches_the_final_schema_and_keeps_the_data(self) -> None:
        backup = self.dir / "backup.sqlite3"
        old_schema = self.rows("SELECT name, sql FROM sqlite_master ORDER BY name")
        self.run_upgrade(apply=True, backup_to=backup)

        with closing(sqlite3.connect(self.path)) as db, closing(sqlite3.connect(":memory:")) as fresh:
            fresh.executescript(gwdb.SCHEMA)
            self.assertEqual(db.execute("PRAGMA user_version").fetchone()[0], gwdb.SCHEMA_VERSION)
            self.assertEqual(gwdb.normalized_schema(db), gwdb.normalized_schema(fresh))
            self.assertEqual(db.execute("PRAGMA foreign_key_check").fetchall(), [])
            self.assertEqual(db.execute("PRAGMA integrity_check").fetchone()[0], "ok")

        # Users: totals untouched; reserved counters rebuilt from the items.
        self.assertEqual(
            self.rows("SELECT username, green_point_limit, green_point_used, green_point_discount, "
                      "red_points, red_points_used, green_points_reserved, red_points_reserved "
                      "FROM users ORDER BY id"),
            [("alice", 4000, 120, 0, 3000, 0, 14, 0),
             ("bob", 4000, 0, 0, 1000, 100, 0, 66),
             ("carol", 4000, 0, 100, 5000, 0, 0, 0)],
        )
        with closing(sqlite3.connect(self.path)) as db:
            stored = db.execute("SELECT id, green_points_reserved, red_points_reserved FROM users").fetchall()
            gwdb.recompute_reserved_points(db)
            self.assertEqual(db.execute(
                "SELECT id, green_points_reserved, red_points_reserved FROM users").fetchall(), stored)
        # Items: reservation, charge, status and ids survive; an older paid
        # charge is carried into consumed_red_points.
        self.assertEqual(
            self.rows("SELECT id, user_id, status, mode, reserved_points, consumed_green_points, "
                      "consumed_red_points, batch_id, image_path, error_message "
                      "FROM generation_tasks ORDER BY id"),
            [("a-done", 1, "success", "free", 14, 14, 0, "b1", "2026/a.png", None),
             ("a-queued", 1, "queued", "free", 14, 0, 0, "b2", None, None),
             ("b-done", 2, "success", "paid", 33, 0, 30, "b4", None, None),
             ("b-failed", 2, "failed", "paid", 33, 0, 0, "b5", None, "boom"),
             ("b-queued", 2, "queued", "paid", 33, 0, 0, "b3", None, None),
             ("b-running", 2, "running", "paid", 33, 0, 0, "b3", None, None)],
        )
        # Idempotency keys, hidden history, audit, feedback, sessions.
        self.assertEqual(
            self.rows("SELECT id, user_id, type, status, item_count, client_request_id, request_hash "
                      "FROM generation_submission_tasks ORDER BY id"),
            [("b1", 1, "single", "success", 1, "req-a1", "hash-a1"),
             ("b2", 1, "single", "queued", 1, "req-a2", "hash-a2"),
             ("b3", 2, "batch", "running", 2, "req-b1", "hash-b1"),
             ("b4", 2, "single", "success", 1, None, None),
             ("b5", 2, "single", "failed", 1, "req-b2", "hash-b2")],
        )
        with closing(sqlite3.connect(self.path)) as db, self.assertRaises(sqlite3.IntegrityError):
            db.execute("INSERT INTO generation_submission_tasks(id, user_id, type, status, created_at, "
                       "client_request_id) VALUES ('dup', 1, 'single', 'queued', ?, 'req-a1')", (NOW,))
        self.assertEqual(self.rows("SELECT user_id, task_id FROM history_hidden ORDER BY user_id"),
                         [(1, "a-done"), (2, "b-done")])
        self.assertEqual(self.rows("SELECT id, user_id, status_code, request_body_expired_at "
                                   "FROM request_audit_logs ORDER BY id"),
                         [("au1", 1, 200, None), ("au2", 2, 429, None)])
        self.assertEqual(self.rows("SELECT id, description, event_count FROM client_feedback_reports"),
                         [("fb1", "it broke", 3)])
        self.assertEqual(self.rows("SELECT id FROM sessions"), [("s1",)])
        # Retired tables are gone.
        tables = {row[0] for row in self.rows("SELECT name FROM sqlite_master WHERE type = 'table'")}
        self.assertFalse(tables & set(db_upgrade.OBSOLETE_TABLES))
        # The verified backup is the untouched version-0 database.
        with closing(sqlite3.connect(backup)) as copy:
            self.assertEqual(copy.execute("PRAGMA user_version").fetchone()[0], 0)
            self.assertEqual(
                copy.execute("SELECT name, sql FROM sqlite_master ORDER BY name").fetchall(),
                [tuple(row) for row in old_schema],
            )
            self.assertEqual(copy.execute("SELECT COUNT(*) FROM generation_tasks").fetchone()[0], 6)

    def test_a_second_run_is_refused(self) -> None:
        self.run_upgrade(apply=True, backup_verified=True)
        before = file_hash(self.path)
        with self.assertRaises(db_upgrade.UpgradeError):
            self.run_upgrade(apply=True, backup_verified=True)
        self.assertEqual(file_hash(self.path), before)

    def test_unexpected_structure_stops_before_any_change(self) -> None:
        with closing(sqlite3.connect(self.path)) as db:
            db.execute("ALTER TABLE users ADD COLUMN surprise TEXT")
            db.commit()
        before = file_hash(self.path)
        for apply in (False, True):
            with self.subTest(apply=apply), self.assertRaisesRegex(db_upgrade.UpgradeError, "surprise"):
                self.run_upgrade(apply=apply, backup_verified=True)
        self.assertEqual(file_hash(self.path), before)

    def test_missing_table_stops_before_any_change(self) -> None:
        with closing(sqlite3.connect(self.path)) as db:
            db.execute("DROP TABLE client_feedback_reports")
            db.commit()
        before = file_hash(self.path)
        with self.assertRaisesRegex(db_upgrade.UpgradeError, "client_feedback_reports"):
            self.run_upgrade(apply=True, backup_verified=True)
        self.assertEqual(file_hash(self.path), before)

    def test_failure_halfway_rolls_everything_back(self) -> None:
        before = logical_dump(self.path)

        def fail(step: str) -> None:
            if step == "rebuild_generation_tasks":
                raise RuntimeError("injected failure")

        with self.assertRaisesRegex(RuntimeError, "injected"):
            self.run_upgrade(apply=True, backup_verified=True, after_step=fail)
        self.assertEqual(logical_dump(self.path), before)
        self.assertEqual(self.rows("PRAGMA user_version"), [(0,)])

    def test_a_failed_check_rolls_everything_back(self) -> None:
        with closing(sqlite3.connect(self.path)) as db:
            # A dangling reference the rebuild must not paper over.
            db.execute("PRAGMA foreign_keys = OFF")
            db.execute("INSERT INTO history_hidden VALUES (1, 'no-such-task', ?)", (NOW,))
            db.commit()
        before = logical_dump(self.path)
        with self.assertRaisesRegex(db_upgrade.UpgradeError, "foreign_key_check"):
            self.run_upgrade(apply=True, backup_verified=True)
        self.assertEqual(logical_dump(self.path), before)


class StartupTests(unittest.TestCase):
    def use_database(self) -> Path:
        directory = tempfile.TemporaryDirectory(prefix="naiweaver-startup-")
        self.addCleanup(directory.cleanup)
        root = Path(directory.name)
        for name, value in (("DATA_DIR", root), ("DB_PATH", root / "gateway.sqlite3"),
                            ("IMAGE_DIR", root / "images"), ("THUMBNAIL_DIR", root / "thumbs"),
                            ("AUDIT_DIR", root / "audit")):
            patcher = mock.patch.object(config, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        return root / "gateway.sqlite3"

    def test_a_new_database_gets_the_final_schema(self) -> None:
        path = self.use_database()
        gwdb.init_db()
        with closing(sqlite3.connect(path)) as db, closing(sqlite3.connect(":memory:")) as fresh:
            fresh.executescript(gwdb.SCHEMA)
            self.assertEqual(db.execute("PRAGMA user_version").fetchone()[0], gwdb.SCHEMA_VERSION)
            self.assertEqual(gwdb.normalized_schema(db), gwdb.normalized_schema(fresh))
        gwdb.init_db()  # the current version starts normally

    def test_other_versions_refuse_to_start_and_point_at_the_upgrade(self) -> None:
        path = self.use_database()
        build_production_database(path)  # user_version 0, not empty
        with self.assertRaisesRegex(gwdb.SchemaVersionError, "db upgrade"):
            gwdb.init_db()
        with closing(sqlite3.connect(path)) as db:
            self.assertEqual(db.execute("PRAGMA user_version").fetchone()[0], 0)
            self.assertIn("quota_usage", gwdb.normalized_schema(db))  # untouched
            db.execute(f"PRAGMA user_version = {gwdb.SCHEMA_VERSION + 1}")
        with self.assertRaisesRegex(gwdb.SchemaVersionError, "needs version"):
            gwdb.init_db()


if __name__ == "__main__":
    unittest.main()
