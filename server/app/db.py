from __future__ import annotations

from contextlib import closing, contextmanager
from datetime import date, datetime, timezone
import hashlib
import json
import os
import re
import sqlite3
from typing import Any, Iterator

from . import config
from .roles import POINT_TOTAL_FIELDS, role_defaults
from .security import hash_password

# Bump together with SCHEMA and the `PRAGMA user_version` below. The service
# starts only on exactly this version; an older database is upgraded once by
# `python -m app.cli db upgrade` and is never migrated on startup.
SCHEMA_VERSION = 1

# Shared with the WebAuth session store, which also creates it on demand when
# it runs on a connection of its own (tests).
ONLY_WEBAUTH_SESSIONS_DDL = """
CREATE TABLE IF NOT EXISTS only_webauth_sessions (
  id TEXT PRIMARY KEY,
  subject TEXT NOT NULL,
  user_id INTEGER NOT NULL,
  refresh_token TEXT NOT NULL,
  access_expires REAL NOT NULL,
  expires REAL NOT NULL
)
"""

# The column order of retained tables follows the production database, so the
# upgrade only has to rebuild the two tables that lose columns.
SCHEMA = f"""
CREATE TABLE users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  is_admin INTEGER NOT NULL DEFAULT 0,
  disabled INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  can_generate_paid INTEGER NOT NULL DEFAULT 0,
  can_text_generate INTEGER NOT NULL DEFAULT 1,
  can_image_upscale INTEGER NOT NULL DEFAULT 1,
  can_image_augment INTEGER NOT NULL DEFAULT 1,
  can_image_encode_vibe INTEGER NOT NULL DEFAULT 1,
  green_point_used INTEGER NOT NULL DEFAULT 0,
  green_point_limit INTEGER NOT NULL DEFAULT 4000,
  green_point_discount INTEGER NOT NULL DEFAULT 0,
  red_points INTEGER NOT NULL DEFAULT 3000,
  red_points_used INTEGER NOT NULL DEFAULT 0,
  green_points_reserved INTEGER NOT NULL DEFAULT 0,
  red_points_reserved INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE sessions (
  id TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  expires_at TEXT NOT NULL,
  revoked_at TEXT,
  created_at TEXT NOT NULL
);

{ONLY_WEBAUTH_SESSIONS_DDL};

-- One row per image. reserved_points is the amount held while the item is
-- queued or running, in the point kind of its mode; consumed_* is what it
-- finally charged.
CREATE TABLE generation_tasks (
  id TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status TEXT NOT NULL,
  prompt TEXT NOT NULL,
  negative_prompt TEXT NOT NULL DEFAULT '',
  width INTEGER NOT NULL,
  height INTEGER NOT NULL,
  steps INTEGER NOT NULL,
  scale REAL NOT NULL,
  sampler TEXT NOT NULL,
  seed INTEGER NOT NULL,
  image_path TEXT,
  error_message TEXT,
  request_json TEXT NOT NULL,
  created_at TEXT NOT NULL,
  completed_at TEXT,
  mode TEXT NOT NULL DEFAULT 'free',
  queue_class TEXT,
  queue_weight INTEGER,
  virtual_finish REAL,
  queued_at TEXT,
  started_at TEXT,
  request_fingerprint TEXT,
  reserved_points INTEGER NOT NULL DEFAULT 0,
  batch_id TEXT,
  batch_index INTEGER,
  consumed_green_points INTEGER NOT NULL DEFAULT 0,
  consumed_red_points INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX idx_generation_tasks_user_fingerprint
ON generation_tasks(user_id, request_fingerprint);

-- A submission groups the items (generation_tasks.batch_id) of one request.
CREATE TABLE generation_submission_tasks (
  id TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type TEXT NOT NULL CHECK(type IN ('single', 'batch')),
  status TEXT NOT NULL,
  item_count INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  completed_at TEXT,
  client_request_id TEXT,
  request_hash TEXT
);

CREATE INDEX idx_generation_submission_tasks_user_created
ON generation_submission_tasks(user_id, created_at DESC);

CREATE UNIQUE INDEX idx_generation_submission_tasks_idempotency
ON generation_submission_tasks(user_id, client_request_id)
WHERE client_request_id IS NOT NULL;

-- Machine-readable failure reason of a generation item (contract section 1).
CREATE TABLE generation_item_errors (
  item_id TEXT PRIMARY KEY REFERENCES generation_tasks(id) ON DELETE CASCADE,
  error_code TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE TABLE history_hidden (
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  task_id TEXT NOT NULL REFERENCES generation_tasks(id) ON DELETE CASCADE,
  hidden_at TEXT NOT NULL,
  PRIMARY KEY (user_id, task_id)
);

CREATE INDEX idx_history_hidden_task_id ON history_hidden(task_id);

CREATE TABLE request_audit_logs (
  id TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  service TEXT NOT NULL,
  path TEXT NOT NULL,
  method TEXT NOT NULL,
  status_code INTEGER,
  request_json TEXT NOT NULL DEFAULT '',
  error_message TEXT,
  created_at TEXT NOT NULL,
  completed_at TEXT,
  request_content_type TEXT NOT NULL DEFAULT '',
  request_body_path TEXT,
  request_body_bytes INTEGER NOT NULL DEFAULT 0,
  request_body_sha256 TEXT NOT NULL DEFAULT '',
  request_body_expired_at TEXT
);

CREATE INDEX idx_request_audit_logs_user_id ON request_audit_logs(user_id);
CREATE INDEX idx_request_audit_logs_created_at ON request_audit_logs(created_at);

CREATE TABLE client_feedback_reports (
  id TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  description TEXT NOT NULL DEFAULT '',
  client_context_json TEXT NOT NULL,
  diagnostics_json TEXT NOT NULL,
  event_count INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL
);

CREATE INDEX idx_client_feedback_reports_user_created
ON client_feedback_reports(user_id, created_at DESC);
CREATE INDEX idx_client_feedback_reports_created
ON client_feedback_reports(created_at DESC);

-- Settlements that disagreed with the quote. A 'free_allowance_exhausted'
-- row also starts the free-allowance cooldown (contract section 4).
CREATE TABLE billing_anomalies (
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

CREATE INDEX idx_billing_anomalies_kind_created
ON billing_anomalies(kind, created_at);

-- In-flight paid-tool reservations. Generation reservations live on their
-- items; this makes tool reservations durable too, so that
-- recompute_reserved_points keeps them.
CREATE TABLE tool_reservations (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  mode TEXT NOT NULL,
  points INTEGER NOT NULL,
  tool TEXT NOT NULL,
  created_at TEXT NOT NULL
);

PRAGMA user_version = {SCHEMA_VERSION};
"""


class SchemaVersionError(RuntimeError):
    """The database does not have the schema this code version needs."""


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


def current_schema_version(db: sqlite3.Connection) -> int:
    return int(db.execute("PRAGMA user_version").fetchone()[0])


def normalized_schema(db: sqlite3.Connection) -> dict[str, str]:
    """sqlite_master reduced to a comparable form: name -> canonical SQL.

    Whitespace, case and identifier quotes are dropped, because SQLite
    rewrites the stored text after ALTER TABLE and RENAME.
    """
    rows = db.execute(
        "SELECT name, sql FROM sqlite_master "
        "WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%'"
    ).fetchall()
    return {
        str(row[0]): re.sub(r"\s+", "", str(row[1]).replace('"', "")).lower()
        for row in rows
    }


def init_db() -> None:
    """Create a new database, or check that an existing one is current.

    Never migrates: an older schema stops the service until the operator has
    run the one-off upgrade.
    """
    config.DATA_DIR.mkdir(parents=True, exist_ok=True)
    config.IMAGE_DIR.mkdir(parents=True, exist_ok=True)
    config.THUMBNAIL_DIR.mkdir(parents=True, exist_ok=True)
    config.AUDIT_DIR.mkdir(parents=True, exist_ok=True)
    with closing(db_connect()) as db:
        version = current_schema_version(db)
        empty = db.execute(
            "SELECT COUNT(*) FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'"
        ).fetchone()[0] == 0
        if version == 0 and empty:
            db.executescript(SCHEMA)
        elif version != SCHEMA_VERSION:
            raise SchemaVersionError(
                f"Database {config.DB_PATH} has schema version {version}; this "
                f"gateway needs version {SCHEMA_VERSION}. It does not migrate on "
                "startup. Stop the service, back the database up and run "
                "`python -m app.cli db upgrade` first (see server/README.md)."
            )
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
    """Derive the durable status of a submission from its items."""
    items = db.execute(
        "SELECT status FROM generation_tasks WHERE batch_id = ?", (task_id,)
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
    db.execute(
        """
        UPDATE generation_submission_tasks
        SET status = ?, item_count = ?,
            completed_at = CASE WHEN ? THEN COALESCE(completed_at, ?) ELSE NULL END
        WHERE id = ?
        """,
        (task_status, len(items), not active, now_iso(), task_id),
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
