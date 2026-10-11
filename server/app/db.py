from __future__ import annotations

from contextlib import closing, contextmanager
from datetime import date, datetime, timezone
import hashlib
import json
import os
import sqlite3
from typing import Any, Iterator

from . import config
from .roles import (
    DEFAULT_GREEN_POINT_LIMIT,
    DEFAULT_RED_POINTS,
    POINT_TOTAL_FIELDS,
    role_defaults,
)
from .security import hash_password

SCHEMA = """
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS schema_migrations (
  migration_key TEXT PRIMARY KEY,
  applied_at TEXT NOT NULL
);

-- Keep the source values for destructive quota-schema migrations. This is
-- intentionally separate from users so a later repair never has to guess
-- what a retired column contained.
CREATE TABLE IF NOT EXISTS legacy_quota_snapshots (
  user_id INTEGER PRIMARY KEY,
  values_json TEXT NOT NULL,
  captured_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  is_admin INTEGER NOT NULL DEFAULT 0,
  disabled INTEGER NOT NULL DEFAULT 0,
  can_generate_paid INTEGER NOT NULL DEFAULT 0,
  can_text_generate INTEGER NOT NULL DEFAULT 1,
  can_image_upscale INTEGER NOT NULL DEFAULT 1,
  can_image_augment INTEGER NOT NULL DEFAULT 1,
  can_image_encode_vibe INTEGER NOT NULL DEFAULT 1,
  green_point_limit INTEGER NOT NULL DEFAULT 4000,
  green_point_used INTEGER NOT NULL DEFAULT 0,
  green_points_reserved INTEGER NOT NULL DEFAULT 0,
  green_point_discount INTEGER NOT NULL DEFAULT 0,
  red_points INTEGER NOT NULL DEFAULT 3000,
  red_points_used INTEGER NOT NULL DEFAULT 0,
  red_points_reserved INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS sessions (
  id TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  expires_at TEXT NOT NULL,
  revoked_at TEXT,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS quota_usage (
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  quota_date TEXT NOT NULL,
  mode TEXT NOT NULL,
  used INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, quota_date, mode)
);

CREATE TABLE IF NOT EXISTS generation_tasks (
  id TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  mode TEXT NOT NULL,
  queue_class TEXT,
  queue_weight INTEGER,
  virtual_finish REAL,
  status TEXT NOT NULL,
  prompt TEXT NOT NULL,
  negative_prompt TEXT NOT NULL DEFAULT '',
  width INTEGER NOT NULL,
  height INTEGER NOT NULL,
  steps INTEGER NOT NULL,
  scale REAL NOT NULL,
  sampler TEXT NOT NULL,
  seed INTEGER NOT NULL,
  cost INTEGER NOT NULL DEFAULT 1,
  image_path TEXT,
  error_message TEXT,
  anlas_before INTEGER,
  anlas_after INTEGER,
  paid_points_charged INTEGER NOT NULL DEFAULT 0,
  reserved_points INTEGER NOT NULL DEFAULT 0,
  reserved_green_points INTEGER NOT NULL DEFAULT 0,
  reserved_red_points INTEGER NOT NULL DEFAULT 0,
  consumed_green_points INTEGER NOT NULL DEFAULT 0,
  consumed_red_points INTEGER NOT NULL DEFAULT 0,
  released_green_points INTEGER NOT NULL DEFAULT 0,
  released_red_points INTEGER NOT NULL DEFAULT 0,
  batch_id TEXT,
  batch_index INTEGER,
  request_fingerprint TEXT,
  request_json TEXT NOT NULL,
  queued_at TEXT,
  started_at TEXT,
  completed_at TEXT,
  created_at TEXT NOT NULL
);

-- A task is one user submission. Existing generation_tasks rows are its
-- image-level items; their batch_id is migrated into this parent record.
CREATE TABLE IF NOT EXISTS generation_submission_tasks (
  id TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  client_request_id TEXT,
  request_hash TEXT,
  type TEXT NOT NULL CHECK(type IN ('single', 'batch')),
  status TEXT NOT NULL,
  item_count INTEGER NOT NULL DEFAULT 0,
  reserved_points INTEGER NOT NULL DEFAULT 0,
  consumed_points INTEGER NOT NULL DEFAULT 0,
  released_points INTEGER NOT NULL DEFAULT 0,
  reserved_green_points INTEGER NOT NULL DEFAULT 0,
  reserved_red_points INTEGER NOT NULL DEFAULT 0,
  consumed_green_points INTEGER NOT NULL DEFAULT 0,
  consumed_red_points INTEGER NOT NULL DEFAULT 0,
  released_green_points INTEGER NOT NULL DEFAULT 0,
  released_red_points INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  completed_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_generation_submission_tasks_user_created
ON generation_submission_tasks(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS history_hidden (
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  task_id TEXT NOT NULL REFERENCES generation_tasks(id) ON DELETE CASCADE,
  hidden_at TEXT NOT NULL,
  PRIMARY KEY (user_id, task_id)
);

CREATE INDEX IF NOT EXISTS idx_history_hidden_task_id ON history_hidden(task_id);

CREATE TABLE IF NOT EXISTS request_audit_logs (
  id TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  service TEXT NOT NULL,
  path TEXT NOT NULL,
  method TEXT NOT NULL,
  status_code INTEGER,
  request_content_type TEXT NOT NULL DEFAULT '',
  request_json TEXT NOT NULL DEFAULT '',
  request_body_path TEXT,
  request_body_bytes INTEGER NOT NULL DEFAULT 0,
  request_body_sha256 TEXT NOT NULL DEFAULT '',
  request_body_expired_at TEXT,
  error_message TEXT,
  created_at TEXT NOT NULL,
  completed_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_request_audit_logs_user_id ON request_audit_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_request_audit_logs_created_at ON request_audit_logs(created_at);

CREATE TABLE IF NOT EXISTS client_feedback_reports (
  id TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  description TEXT NOT NULL DEFAULT '',
  client_context_json TEXT NOT NULL,
  diagnostics_json TEXT NOT NULL,
  event_count INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_client_feedback_reports_user_created
ON client_feedback_reports(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_client_feedback_reports_created
ON client_feedback_reports(created_at DESC);

-- Machine-readable failure reason of a generation item (contract §1 codes).
CREATE TABLE IF NOT EXISTS generation_item_errors (
  item_id TEXT PRIMARY KEY REFERENCES generation_tasks(id) ON DELETE CASCADE,
  error_code TEXT NOT NULL,
  created_at TEXT NOT NULL
);

-- Settlements that disagreed with the quote. A 'free_allowance_exhausted'
-- row also starts the free-allowance cooldown (contract §4).
CREATE TABLE IF NOT EXISTS billing_anomalies (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  kind TEXT NOT NULL,
  user_id INTEGER NOT NULL,
  task_id TEXT,
  tool TEXT,
  mode TEXT NOT NULL,
  quoted INTEGER NOT NULL,
  measured INTEGER,
  note TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_billing_anomalies_kind_created
ON billing_anomalies(kind, created_at);

-- In-flight paid-tool reservations. Generation reservations live on their
-- items; this makes tool reservations durable too, so rebuilding the user
-- counters (migrate_db, run by every CLI command) keeps them.
CREATE TABLE IF NOT EXISTS tool_reservations (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  mode TEXT NOT NULL,
  points INTEGER NOT NULL,
  tool TEXT NOT NULL,
  created_at TEXT NOT NULL
);

"""




def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def today_key() -> str:
    return date.today().isoformat()


def db_connect() -> sqlite3.Connection:
    config.DATA_DIR.mkdir(parents=True, exist_ok=True)
    if not config.DB_PATH.exists():
        # The database holds session secrets: owner-only from the start.
        os.close(os.open(config.DB_PATH, os.O_CREAT | os.O_WRONLY, 0o600))
    conn = sqlite3.connect(config.DB_PATH, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("PRAGMA journal_mode = WAL")
    return conn


def get_db():
    conn = db_connect()
    try:
        yield conn
    finally:
        conn.close()


@contextmanager
def db_session() -> Iterator[sqlite3.Connection]:
    """A short-lived connection for background work; always closed."""
    conn = db_connect()
    try:
        yield conn
    finally:
        conn.close()


def init_db() -> None:
    config.DATA_DIR.mkdir(parents=True, exist_ok=True)
    config.IMAGE_DIR.mkdir(parents=True, exist_ok=True)
    config.THUMBNAIL_DIR.mkdir(parents=True, exist_ok=True)
    config.AUDIT_DIR.mkdir(parents=True, exist_ok=True)
    with closing(db_connect()) as db:
        db.executescript(SCHEMA)
        migrate_db(db)
        db.commit()
    config.DB_PATH.chmod(0o600)


def recompute_reserved_points(db: sqlite3.Connection) -> None:
    """Rebuild the reserved counters from durable reservations.

    The counters are a cache of active item reservations plus in-flight tool
    reservations. This repairs leaked counters while preserving consumed
    point balances.
    """
    db.execute(
        """
        UPDATE users
        SET green_points_reserved = COALESCE((
              SELECT SUM(reserved_points) FROM generation_tasks i
              WHERE i.user_id = users.id AND i.mode = 'free'
                AND i.status IN ('queued', 'running')
            ), 0),
            red_points_reserved = COALESCE((
              SELECT SUM(reserved_points) FROM generation_tasks i
              WHERE i.user_id = users.id AND i.mode = 'paid'
                AND i.status IN ('queued', 'running')
            ), 0) + COALESCE((
              SELECT SUM(points) FROM tool_reservations r
              WHERE r.user_id = users.id AND r.mode = 'paid'
            ), 0)
        """
    )


def reclaim_tool_reservations(db: sqlite3.Connection) -> None:
    """Drop tool reservations left by a previous gateway process.

    Only the service calls this at startup, when no tool call can be in
    flight; the CLI must not, or it would erase a running service's holds.
    """
    db.execute("DELETE FROM tool_reservations")
    recompute_reserved_points(db)


def migrate_db(db: sqlite3.Connection) -> None:
    table_columns = {
        row["name"] for row in db.execute("PRAGMA table_info(users)").fetchall()
    }
    user_columns = {
        "can_text_generate": "INTEGER NOT NULL DEFAULT 1",
        "can_image_upscale": "INTEGER NOT NULL DEFAULT 1",
        "can_image_augment": "INTEGER NOT NULL DEFAULT 1",
        "can_image_encode_vibe": "INTEGER NOT NULL DEFAULT 1",
        "green_point_limit": f"INTEGER NOT NULL DEFAULT {DEFAULT_GREEN_POINT_LIMIT}",
        "green_point_used": "INTEGER NOT NULL DEFAULT 0",
        "green_points_reserved": "INTEGER NOT NULL DEFAULT 0",
        "green_point_discount": "INTEGER NOT NULL DEFAULT 0",
        "red_points": f"INTEGER NOT NULL DEFAULT {DEFAULT_RED_POINTS}",
        "red_points_used": "INTEGER NOT NULL DEFAULT 0",
        "red_points_reserved": "INTEGER NOT NULL DEFAULT 0",
    }
    for name, definition in user_columns.items():
        if name not in table_columns:
            db.execute(f"ALTER TABLE users ADD COLUMN {name} {definition}")
    submission_columns = {
        "client_request_id": "TEXT",
        "request_hash": "TEXT",
        "reserved_green_points": "INTEGER NOT NULL DEFAULT 0",
        "reserved_red_points": "INTEGER NOT NULL DEFAULT 0",
        "consumed_green_points": "INTEGER NOT NULL DEFAULT 0",
        "consumed_red_points": "INTEGER NOT NULL DEFAULT 0",
        "released_green_points": "INTEGER NOT NULL DEFAULT 0",
        "released_red_points": "INTEGER NOT NULL DEFAULT 0",
    }
    existing_submission_columns = {
        row["name"] for row in db.execute("PRAGMA table_info(generation_submission_tasks)").fetchall()
    }
    for name, definition in submission_columns.items():
        if name not in existing_submission_columns:
            db.execute(f"ALTER TABLE generation_submission_tasks ADD COLUMN {name} {definition}")
    db.execute(
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_generation_submission_tasks_idempotency "
        "ON generation_submission_tasks(user_id, client_request_id) "
        "WHERE client_request_id IS NOT NULL"
    )
    legacy_quota_columns = (
        "daily_limit",
        "paid_daily_limit",
        "can_generate_free",
        "paid_point_limit",
        "paid_point_used",
        "red_point_limit",
        "red_point_used",
    )
    present_legacy_columns = [
        name for name in legacy_quota_columns if name in table_columns
    ]
    if present_legacy_columns:
        # Snapshot before ALTER TABLE DROP COLUMN. Do not include credentials or
        # other unrelated user data in the recovery record.
        select_columns = ", ".join(["id", *present_legacy_columns])
        for row in db.execute(f"SELECT {select_columns} FROM users").fetchall():
            values = {name: row[name] for name in present_legacy_columns}
            db.execute(
                "INSERT OR IGNORE INTO legacy_quota_snapshots"
                "(user_id, values_json, captured_at) VALUES (?, ?, ?)",
                (row["id"], json.dumps(values, sort_keys=True), now_iso()),
            )

    # Copy retired quota values once before physically removing their columns.
    if "green_point_limit" not in table_columns and "daily_limit" in table_columns:
        free_permission = (
            "WHEN can_generate_free = 0 THEN 0 "
            if "can_generate_free" in table_columns
            else ""
        )
        db.execute(
            "UPDATE users SET green_point_limit = CASE "
            "WHEN is_admin = 1 THEN ? "
            f"{free_permission}"
            "WHEN daily_limit IS NULL OR daily_limit < 0 THEN ? "
            "ELSE daily_limit * ? END",
            (
                DEFAULT_GREEN_POINT_LIMIT,
                DEFAULT_GREEN_POINT_LIMIT,
                config.STANDARD_GREEN_IMAGE_POINTS,
            ),
        )
    if "green_point_used" not in table_columns:
        db.execute(
            """
            UPDATE users
            SET green_point_used = COALESCE((
              SELECT SUM(used) * ? FROM quota_usage
              WHERE quota_usage.user_id = users.id AND mode = 'free'
                AND quota_date = ?
            ), 0)
            """,
            (config.STANDARD_GREEN_IMAGE_POINTS, today_key()),
        )
    if "green_point_discount" not in table_columns:
        # Only administrators are unlimited. Legacy free-generation access is
        # represented by the migrated green-point limit, not a 100% discount.
        db.execute(
            "UPDATE users SET green_point_discount = CASE "
            "WHEN is_admin = 1 THEN 100 ELSE 0 END"
        )
    if "red_points" not in table_columns:
        if "red_point_limit" in table_columns:
            db.execute("UPDATE users SET red_points = red_point_limit")
        else:
            db.execute("UPDATE users SET red_points = COALESCE(paid_point_limit, 0)")
    if "red_points_used" not in table_columns:
        if "red_point_used" in table_columns:
            db.execute("UPDATE users SET red_points_used = red_point_used")
        else:
            db.execute("UPDATE users SET red_points_used = COALESCE(paid_point_used, 0)")
    # This is a one-time physical schema migration, not a compatibility layer.
    # All values are copied above before the retired quota columns are removed.
    for legacy_column in legacy_quota_columns:
        if legacy_column in table_columns:
            db.execute(f"ALTER TABLE users DROP COLUMN {legacy_column}")
    task_columns = {
        row["name"] for row in db.execute("PRAGMA table_info(generation_tasks)").fetchall()
    }
    generation_task_columns = {
        "queue_class": "TEXT",
        "queue_weight": "INTEGER",
        "virtual_finish": "REAL",
        "anlas_before": "INTEGER",
        "anlas_after": "INTEGER",
        "paid_points_charged": "INTEGER NOT NULL DEFAULT 0",
        "reserved_points": "INTEGER NOT NULL DEFAULT 0",
        "reserved_green_points": "INTEGER NOT NULL DEFAULT 0",
        "reserved_red_points": "INTEGER NOT NULL DEFAULT 0",
        "consumed_green_points": "INTEGER NOT NULL DEFAULT 0",
        "consumed_red_points": "INTEGER NOT NULL DEFAULT 0",
        "released_green_points": "INTEGER NOT NULL DEFAULT 0",
        "released_red_points": "INTEGER NOT NULL DEFAULT 0",
        "batch_id": "TEXT",
        "batch_index": "INTEGER",
        "request_fingerprint": "TEXT",
    }
    for name, definition in generation_task_columns.items():
        if name not in task_columns:
            db.execute(f"ALTER TABLE generation_tasks ADD COLUMN {name} {definition}")
    # Only backfill accounting columns when upgrading a schema that did not
    # have them. Rewriting them on every boot can destroy legitimate manual
    # adjustments and makes an interrupted migration impossible to audit.
    accounting_columns = {
        "reserved_green_points",
        "reserved_red_points",
        "consumed_green_points",
        "consumed_red_points",
        "released_green_points",
        "released_red_points",
    }
    if not accounting_columns.issubset(task_columns):
        db.execute(
            """
            UPDATE generation_tasks
            SET reserved_green_points = CASE WHEN mode = 'free' THEN reserved_points ELSE 0 END,
                reserved_red_points = CASE WHEN mode = 'paid' THEN reserved_points ELSE 0 END,
                consumed_green_points = CASE WHEN mode = 'free' AND status = 'success' THEN reserved_points ELSE 0 END,
                consumed_red_points = CASE WHEN mode = 'paid' AND status = 'success' THEN paid_points_charged ELSE 0 END,
                released_green_points = CASE WHEN mode = 'free' AND status IN ('failed', 'rejected', 'cancelled') THEN reserved_points ELSE 0 END,
                released_red_points = CASE WHEN mode = 'paid' AND status IN ('failed', 'rejected', 'cancelled') THEN reserved_points ELSE 0 END
            """
        )
    fingerprint_rows = db.execute(
        "SELECT id, request_json FROM generation_tasks WHERE request_fingerprint IS NULL"
    ).fetchall()
    for row in fingerprint_rows:
        try:
            parsed_request = json.loads(row["request_json"])
            fingerprint = generation_request_fingerprint(parsed_request)
        except (TypeError, ValueError, json.JSONDecodeError):
            continue
        db.execute(
            "UPDATE generation_tasks SET request_fingerprint = ? WHERE id = ?",
            (fingerprint, row["id"]),
        )
    db.execute(
        "CREATE INDEX IF NOT EXISTS idx_generation_tasks_user_fingerprint "
        "ON generation_tasks(user_id, request_fingerprint)"
    )
    # Backfill the outer task for every historical image item. Explicit batch
    # IDs are authoritative. Rows from before explicit batch IDs are kept as
    # separate submissions; timing proximity is not proof of one batch.
    rows = db.execute(
        "SELECT id, user_id, batch_id, created_at, status, reserved_points "
        "FROM generation_tasks ORDER BY user_id, created_at, id"
    ).fetchall()
    for row in rows:
        explicit = row["batch_id"]
        if explicit:
            parent_id = explicit
        else:
            parent_id = f"legacy-{row['id']}"
        db.execute(
            "INSERT OR IGNORE INTO generation_submission_tasks "
            "(id, user_id, type, status, created_at) VALUES (?, ?, 'single', 'queued', ?)",
            (parent_id, row["user_id"], row["created_at"]),
        )
        db.execute("UPDATE generation_tasks SET batch_id = ? WHERE id = ?", (parent_id, row["id"]))
    db.execute(
        """
        UPDATE generation_submission_tasks
        SET item_count = (SELECT COUNT(*) FROM generation_tasks i WHERE i.batch_id = generation_submission_tasks.id),
            reserved_points = (SELECT COALESCE(SUM(reserved_points), 0) FROM generation_tasks i WHERE i.batch_id = generation_submission_tasks.id),
            type = CASE WHEN (SELECT COUNT(*) FROM generation_tasks i WHERE i.batch_id = generation_submission_tasks.id) > 1 THEN 'batch' ELSE 'single' END
        """
    )
    for row in db.execute("SELECT id FROM generation_submission_tasks").fetchall():
        refresh_submission_task(db, row["id"])
    # A submission without items cannot ever run. Removing stale active shells
    # lets an idempotent client retry instead of replaying an empty task.
    db.execute(
        """
        DELETE FROM generation_submission_tasks
        WHERE status IN ('queued', 'running')
          AND NOT EXISTS (
            SELECT 1 FROM generation_tasks i
            WHERE i.batch_id = generation_submission_tasks.id
          )
        """
    )
    recompute_reserved_points(db)
    db.execute(
        """
        CREATE TABLE IF NOT EXISTS history_hidden (
          user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          task_id TEXT NOT NULL REFERENCES generation_tasks(id) ON DELETE CASCADE,
          hidden_at TEXT NOT NULL,
          PRIMARY KEY (user_id, task_id)
        )
        """
    )
    db.execute(
        "CREATE INDEX IF NOT EXISTS idx_history_hidden_task_id ON history_hidden(task_id)"
    )
    db.execute(
        """
        CREATE TABLE IF NOT EXISTS request_audit_logs (
          id TEXT PRIMARY KEY,
          user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          service TEXT NOT NULL,
          path TEXT NOT NULL,
          method TEXT NOT NULL,
          status_code INTEGER,
          request_content_type TEXT NOT NULL DEFAULT '',
          request_json TEXT NOT NULL DEFAULT '',
          request_body_path TEXT,
          request_body_bytes INTEGER NOT NULL DEFAULT 0,
          request_body_sha256 TEXT NOT NULL DEFAULT '',
          request_body_expired_at TEXT,
          error_message TEXT,
          created_at TEXT NOT NULL,
          completed_at TEXT
        )
        """
    )
    audit_columns = {
        row["name"]
        for row in db.execute("PRAGMA table_info(request_audit_logs)").fetchall()
    }
    audit_log_columns = {
        "request_content_type": "TEXT NOT NULL DEFAULT ''",
        "request_body_path": "TEXT",
        "request_body_bytes": "INTEGER NOT NULL DEFAULT 0",
        "request_body_sha256": "TEXT NOT NULL DEFAULT ''",
        "request_body_expired_at": "TEXT",
    }
    for name, definition in audit_log_columns.items():
        if name not in audit_columns:
            db.execute(f"ALTER TABLE request_audit_logs ADD COLUMN {name} {definition}")
    db.execute(
        "CREATE INDEX IF NOT EXISTS idx_request_audit_logs_user_id ON request_audit_logs(user_id)"
    )
    db.execute(
        "CREATE INDEX IF NOT EXISTS idx_request_audit_logs_created_at ON request_audit_logs(created_at)"
    )
    db.execute(
        """
        CREATE TABLE IF NOT EXISTS client_feedback_reports (
          id TEXT PRIMARY KEY,
          user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          description TEXT NOT NULL DEFAULT '',
          client_context_json TEXT NOT NULL,
          diagnostics_json TEXT NOT NULL,
          event_count INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL
        )
        """
    )
    db.execute(
        "CREATE INDEX IF NOT EXISTS idx_client_feedback_reports_user_created "
        "ON client_feedback_reports(user_id, created_at DESC)"
    )
    db.execute(
        "CREATE INDEX IF NOT EXISTS idx_client_feedback_reports_created "
        "ON client_feedback_reports(created_at DESC)"
    )


def bootstrap_users() -> None:
    if not config.BOOTSTRAP_TEST_USERS:
        return
    admin_password_env = os.environ.get("NAIWEAVER_ADMIN_PASSWORD")
    admin_password = admin_password_env or "local-test-admin"
    samples = [
        ("admin", admin_password, "admin"),
        ("free_user", "free-test-pass", "free"),
        ("paid_user", "paid-test-pass", "paid"),
    ]
    with closing(db_connect()) as db:
        for username, password, role in samples:
            existing = db.execute("SELECT id FROM users WHERE username = ?", (username,)).fetchone()
            if existing:
                if username == "admin" and admin_password_env:
                    # Point totals are balances; only permissions are re-applied.
                    changes = {
                        "password_hash": hash_password(admin_password),
                        "disabled": 0,
                        **{
                            name: value
                            for name, value in role_defaults("admin").items()
                            if name not in POINT_TOTAL_FIELDS
                        },
                    }
                    assignments = ", ".join(f"{name} = ?" for name in changes)
                    db.execute(
                        f"UPDATE users SET {assignments} WHERE id = ?",
                        (*changes.values(), existing["id"]),
                    )
                continue
            columns = {
                "username": username,
                "password_hash": hash_password(password),
                **role_defaults(role),
                "created_at": now_iso(),
            }
            db.execute(
                f"INSERT INTO users({', '.join(columns)}) "
                f"VALUES ({', '.join('?' for _ in columns)})",
                tuple(columns.values()),
            )
        db.commit()


def refresh_submission_task(db: sqlite3.Connection, task_id: str) -> None:
    """Derive durable outer-task status and point totals from its items."""
    items = db.execute(
        "SELECT status, mode, reserved_points, paid_points_charged FROM generation_tasks "
        "WHERE batch_id = ? ORDER BY batch_index, created_at, id",
        (task_id,),
    ).fetchall()
    if not items:
        return
    statuses = [str(item["status"]) for item in items]
    active = any(value in {"queued", "running"} for value in statuses)
    success = sum(value == "success" for value in statuses)
    if active:
        task_status = "running" if ("running" in statuses or success) else "queued"
    elif success == len(items):
        task_status = "success"
    elif success:
        task_status = "partial_failed"
    elif all(value == "cancelled" for value in statuses):
        task_status = "cancelled"
    else:
        task_status = "failed"
    reserved_green = sum(int(item["reserved_points"] or 0) for item in items if item["mode"] == "free")
    reserved_red = sum(int(item["reserved_points"] or 0) for item in items if item["mode"] == "paid")
    consumed_green = sum(int(item["reserved_points"] or 0) for item in items if item["mode"] == "free" and item["status"] == "success")
    consumed_red = sum(int(item["paid_points_charged"] or 0) for item in items if item["mode"] == "paid" and item["status"] == "success")
    released_green = sum(int(item["reserved_points"] or 0) for item in items if item["mode"] == "free" and item["status"] in {"failed", "rejected", "cancelled"})
    released_red = sum(int(item["reserved_points"] or 0) for item in items if item["mode"] == "paid" and item["status"] in {"failed", "rejected", "cancelled"})
    db.execute(
        """
        UPDATE generation_submission_tasks
        SET status = ?, item_count = ?, reserved_points = ?, consumed_points = ?,
            released_points = ?, reserved_green_points = ?, reserved_red_points = ?,
            consumed_green_points = ?, consumed_red_points = ?, released_green_points = ?,
            released_red_points = ?,
            completed_at = CASE WHEN ? THEN COALESCE(completed_at, ?) ELSE NULL END
        WHERE id = ?
        """,
        (task_status, len(items), reserved_green + reserved_red, consumed_green + consumed_red,
         released_green + released_red, reserved_green, reserved_red, consumed_green,
         consumed_red, released_green, released_red, not active, now_iso(), task_id),
    )


def generation_request_fingerprint(parsed: dict[str, Any]) -> str:
    """Hash the normalized, server-validated generation request deterministically."""
    normalized = json.dumps(
        parsed,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    )
    return hashlib.sha256(normalized.encode("utf-8")).hexdigest()
