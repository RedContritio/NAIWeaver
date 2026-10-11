"""One-off upgrade of a version-0 gateway database to the current schema.

The service never migrates on startup. Production predates `PRAGMA
user_version`, so this module takes that database (structure checked against
`EXPECTED_V0`) to `SCHEMA_VERSION` in a single transaction:

* a dry run (the default) performs the identical upgrade on an in-memory copy
  and prints every step and the resulting numbers; the database file is only
  opened read-only;
* `apply` first requires a verified backup, then upgrades the real file; any
  failure rolls everything back.

It uses SQLite only: no NovelAI, no identity provider, no application config.
"""

from __future__ import annotations

from collections.abc import Callable
from contextlib import closing
import os
from pathlib import Path
import re
import sqlite3

from .db import (
    SCHEMA,
    SCHEMA_VERSION,
    normalized_schema,
    recompute_reserved_points,
)


class UpgradeError(RuntimeError):
    """The upgrade cannot or should not proceed; nothing was changed."""


# Exact column signature of every table in a version-0 production database
# ("name TYPE", plus pk / nn flags), captured from the live database.
EXPECTED_V0: dict[str, str] = {
    "users": "id INTEGER pk, username TEXT nn, password_hash TEXT nn, is_admin INTEGER nn, disabled INTEGER nn, created_at TEXT nn, can_generate_paid INTEGER nn, can_text_generate INTEGER nn, can_image_upscale INTEGER nn, can_image_augment INTEGER nn, can_image_encode_vibe INTEGER nn, green_point_used INTEGER nn, green_point_limit INTEGER nn, green_point_discount INTEGER nn, red_points INTEGER nn, red_points_used INTEGER nn, green_points_reserved INTEGER nn, red_points_reserved INTEGER nn",
    "sessions": "id TEXT pk, user_id INTEGER nn, expires_at TEXT nn, revoked_at TEXT, created_at TEXT nn",
    "daily_quotas": "user_id INTEGER pk, quota_date TEXT pk, used INTEGER nn",
    "generation_tasks": "id TEXT pk, user_id INTEGER nn, status TEXT nn, prompt TEXT nn, negative_prompt TEXT nn, width INTEGER nn, height INTEGER nn, steps INTEGER nn, scale REAL nn, sampler TEXT nn, seed INTEGER nn, cost INTEGER nn, image_path TEXT, error_message TEXT, request_json TEXT nn, created_at TEXT nn, completed_at TEXT, mode TEXT nn, queue_class TEXT, queue_weight INTEGER, virtual_finish REAL, queued_at TEXT, started_at TEXT, anlas_before INTEGER, anlas_after INTEGER, paid_points_charged INTEGER nn, request_fingerprint TEXT, reserved_points INTEGER nn, batch_id TEXT, batch_index INTEGER, reserved_green_points INTEGER nn, reserved_red_points INTEGER nn, consumed_green_points INTEGER nn, consumed_red_points INTEGER nn, released_green_points INTEGER nn, released_red_points INTEGER nn",
    "admin_config": "key TEXT pk, value TEXT nn, updated_at TEXT nn",
    "quota_usage": "user_id INTEGER pk, quota_date TEXT pk, mode TEXT pk, used INTEGER nn",
    "history_hidden": "user_id INTEGER pk, task_id TEXT pk, hidden_at TEXT nn",
    "request_audit_logs": "id TEXT pk, user_id INTEGER nn, service TEXT nn, path TEXT nn, method TEXT nn, status_code INTEGER, request_json TEXT nn, error_message TEXT, created_at TEXT nn, completed_at TEXT, request_content_type TEXT nn, request_body_path TEXT, request_body_bytes INTEGER nn, request_body_sha256 TEXT nn",
    "webauthn_credentials": "id INTEGER pk, user_id INTEGER nn, credential_id TEXT nn, public_key TEXT nn, sign_count INTEGER nn, aaguid TEXT nn, device_type TEXT nn, backed_up INTEGER nn, transports TEXT nn, disabled INTEGER nn, created_at TEXT nn, last_used_at TEXT",
    "webauthn_enrollment_tokens": "token_hash TEXT pk, user_id INTEGER nn, expires_at TEXT nn, used_at TEXT, created_at TEXT nn",
    "webauthn_challenges": "id TEXT pk, user_id INTEGER, purpose TEXT nn, challenge TEXT nn, enrollment_token_hash TEXT, expires_at TEXT nn, used_at TEXT, created_at TEXT nn",
    "generation_submission_tasks": "id TEXT pk, user_id INTEGER nn, type TEXT nn, status TEXT nn, item_count INTEGER nn, reserved_points INTEGER nn, consumed_points INTEGER nn, released_points INTEGER nn, reserved_green_points INTEGER nn, reserved_red_points INTEGER nn, consumed_green_points INTEGER nn, consumed_red_points INTEGER nn, released_green_points INTEGER nn, released_red_points INTEGER nn, created_at TEXT nn, completed_at TEXT, client_request_id TEXT, request_hash TEXT",
    "schema_migrations": "migration_key TEXT pk, applied_at TEXT nn",
    "legacy_quota_snapshots": "user_id INTEGER pk, values_json TEXT nn, captured_at TEXT nn",
    "client_feedback_reports": "id TEXT pk, user_id INTEGER nn, description TEXT nn, client_context_json TEXT nn, diagnostics_json TEXT nn, event_count INTEGER nn, created_at TEXT nn",
}
# Left behind if a newer gateway ever ran against the database; harmless.
OPTIONAL_V0 = {"only_webauth_sessions"}

OBSOLETE_TABLES = (
    "daily_quotas",
    "quota_usage",
    "admin_config",
    "schema_migrations",
    "legacy_quota_snapshots",
    "webauthn_credentials",
    "webauthn_enrollment_tokens",
    "webauthn_challenges",
)
NEW_TABLES = (
    "only_webauth_sessions",
    "generation_item_errors",
    "billing_anomalies",
    "tool_reservations",
)
# Rebuilt to drop columns: table -> columns copied across.
REBUILT_COLUMNS = {
    "generation_tasks": (
        "id, user_id, status, prompt, negative_prompt, width, height, steps, scale, "
        "sampler, seed, image_path, error_message, request_json, created_at, "
        "completed_at, mode, queue_class, queue_weight, virtual_finish, queued_at, "
        "started_at, request_fingerprint, reserved_points, batch_id, batch_index, "
        "consumed_green_points"
    ),
    "generation_submission_tasks": (
        "id, user_id, type, status, item_count, created_at, completed_at, "
        "client_request_id, request_hash"
    ),
}
DROPPED_COLUMNS = {
    "generation_tasks": (
        "cost", "anlas_before", "anlas_after", "paid_points_charged",
        "reserved_green_points", "reserved_red_points",
        "released_green_points", "released_red_points",
    ),
    "generation_submission_tasks": (
        "reserved_points", "consumed_points", "released_points",
        "reserved_green_points", "reserved_red_points",
        "consumed_green_points", "consumed_red_points",
        "released_green_points", "released_red_points",
    ),
}
# Tables that must come out with exactly their row count.
COPIED_TABLES = (
    "users", "sessions", "generation_tasks", "generation_submission_tasks",
    "history_hidden", "request_audit_logs", "client_feedback_reports",
)
USER_TOTALS = (
    "green_point_limit", "green_point_used", "green_point_discount",
    "red_points", "red_points_used",
)


Log = Callable[[str], None]


def column_signatures(db: sqlite3.Connection) -> dict[str, str]:
    result: dict[str, str] = {}
    tables = db.execute(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'"
    ).fetchall()
    for (name,) in tables:
        parts = []
        for row in db.execute(f"PRAGMA table_info({name})"):
            flags = (" pk" if row[5] else "") + (" nn" if row[3] and not row[5] else "")
            parts.append(f"{row[1]} {row[2]}{flags}")
        result[str(name)] = ", ".join(parts)
    return result


def check_structure(db: sqlite3.Connection) -> None:
    """Refuse anything that is not exactly the known version-0 structure."""
    version = int(db.execute("PRAGMA user_version").fetchone()[0])
    if version != 0:
        raise UpgradeError(
            f"user_version is {version}, expected 0 (nothing to upgrade)"
            if version == SCHEMA_VERSION
            else f"user_version is {version}, expected 0; refusing to guess"
        )
    actual = column_signatures(db)
    problems: list[str] = []
    for table, expected in EXPECTED_V0.items():
        if table not in actual:
            problems.append(f"missing table {table}")
        elif set(actual[table].split(", ")) != set(expected.split(", ")):
            have, want = set(actual[table].split(", ")), set(expected.split(", "))
            problems.append(
                f"table {table} differs: missing {sorted(want - have)}, "
                f"unexpected {sorted(have - want)}"
            )
    for table in sorted(set(actual) - set(EXPECTED_V0) - OPTIONAL_V0):
        problems.append(f"unexpected table {table}")
    if problems:
        raise UpgradeError(
            "the database does not have the expected version-0 structure:\n  "
            + "\n  ".join(problems)
        )


def final_ddl() -> dict[str, str]:
    """name -> CREATE statement of every object in the final schema."""
    with closing(sqlite3.connect(":memory:")) as fresh:
        fresh.executescript(SCHEMA)
        return {
            str(name): str(sql)
            for name, sql in fresh.execute(
                "SELECT name, sql FROM sqlite_master "
                "WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%'"
            )
        }


def count(db: sqlite3.Connection, table: str) -> int:
    return int(db.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0])


def snapshot(db: sqlite3.Connection) -> dict:
    """Numbers that must survive the upgrade."""
    totals = {
        column: int(db.execute(f"SELECT COALESCE(SUM({column}), 0) FROM users").fetchone()[0])
        for column in USER_TOTALS
    }
    return {
        "rows": {table: count(db, table) for table in COPIED_TABLES},
        "user_totals": totals,
        "consumed_green": int(db.execute(
            "SELECT COALESCE(SUM(consumed_green_points), 0) FROM generation_tasks").fetchone()[0]),
        "idempotency_keys": sorted(
            tuple(row) for row in db.execute(
                "SELECT user_id, client_request_id, request_hash, id "
                "FROM generation_submission_tasks WHERE client_request_id IS NOT NULL"
            )
        ),
        "hidden": sorted(tuple(row) for row in db.execute("SELECT * FROM history_hidden")),
        "feedback": sorted(tuple(row) for row in db.execute(
            "SELECT id, user_id, description, event_count FROM client_feedback_reports")),
        "audit": sorted(tuple(row) for row in db.execute(
            "SELECT id, user_id, path, status_code FROM request_audit_logs")),
    }


def reserved_expectation(db: sqlite3.Connection) -> list[tuple[int, int, int, int, int]]:
    """(user, green stored, red stored, green rebuilt, red rebuilt), from the data."""
    rows = db.execute(
        """
        SELECT u.id, u.green_points_reserved, u.red_points_reserved,
               COALESCE((SELECT SUM(reserved_points) FROM generation_tasks i
                         WHERE i.user_id = u.id AND i.mode = 'free'
                           AND i.status IN ('queued', 'running')), 0),
               COALESCE((SELECT SUM(reserved_points) FROM generation_tasks i
                         WHERE i.user_id = u.id AND i.mode = 'paid'
                           AND i.status IN ('queued', 'running')), 0)
        FROM users u ORDER BY u.id
        """
    ).fetchall()
    return [tuple(int(value) for value in row) for row in rows]


def rename_create(sql: str, table: str, new_name: str) -> str:
    out, n = re.subn(rf"CREATE TABLE {table}\b", f"CREATE TABLE {new_name}", sql, count=1)
    if n != 1:
        raise UpgradeError(f"cannot derive the rebuild statement for {table}")
    return out


def upgrade(
    db: sqlite3.Connection,
    log: Log,
    *,
    after_step: Callable[[str], None] | None = None,
) -> None:
    """Upgrade `db` in one transaction. Commits only if every check passes.

    `db` must be opened with isolation_level=None. `after_step` is called
    after each step (tests use it to inject a failure).
    """
    ddl = final_ddl()
    # Rebuilding tables needs foreign keys off, and the pragma is a no-op
    # inside a transaction.
    db.execute("PRAGMA foreign_keys = OFF")
    # The write lock is taken first, so what is checked is what is upgraded.
    db.execute("BEGIN IMMEDIATE")
    try:
        check_structure(db)
        before = snapshot(db)
        log(f"found a version-0 database: {sum(before['rows'].values())} rows in "
            f"{len(before['rows'])} kept tables")
        def step(name: str) -> None:
            if after_step is not None:
                after_step(name)

        log("step 1: ALTER TABLE request_audit_logs ADD COLUMN request_body_expired_at TEXT")
        db.execute("ALTER TABLE request_audit_logs ADD COLUMN request_body_expired_at TEXT")
        step("add_audit_column")

        for table in NEW_TABLES:
            if table == "only_webauth_sessions" and table in column_signatures(db):
                log(f"step 2: table {table} already exists, kept")
                continue
            log(f"step 2: create table {table} (new, empty)")
            db.execute(ddl[table])
            for name, sql in ddl.items():
                if re.search(rf"\bON {table}\b", sql) and sql.startswith("CREATE"):
                    log(f"        create index {name}")
                    db.execute(sql)
        step("create_tables")

        for table, columns in REBUILT_COLUMNS.items():
            rows = count(db, table)
            log(
                f"step 3: rebuild {table}: copy {rows} rows, drop columns "
                f"{', '.join(DROPPED_COLUMNS[table])}"
            )
            temp = f"{table}__new"
            db.execute(rename_create(ddl[table], table, temp))
            if table == "generation_tasks":
                # consumed_red_points is what the gateway reads; older rows
                # may only carry the amount in paid_points_charged.
                recovered = db.execute(
                    "SELECT COUNT(*) FROM generation_tasks WHERE mode = 'paid' "
                    "AND consumed_red_points = 0 AND paid_points_charged > 0"
                ).fetchone()[0]
                log(f"        consumed_red_points <- paid_points_charged on {recovered} rows")
                db.execute(
                    f"INSERT INTO {temp}({columns}, consumed_red_points) "
                    f"SELECT {columns}, CASE WHEN mode = 'paid' AND consumed_red_points = 0 "
                    "AND paid_points_charged > 0 THEN paid_points_charged "
                    f"ELSE consumed_red_points END FROM {table}"
                )
            else:
                db.execute(f"INSERT INTO {temp}({columns}) SELECT {columns} FROM {table}")
            db.execute(f"DROP TABLE {table}")
            db.execute(f"ALTER TABLE {temp} RENAME TO {table}")
            for name, sql in ddl.items():
                if sql.startswith("CREATE") and re.search(rf"\bON {table}\(", sql):
                    log(f"        recreate index {name}")
                    db.execute(sql)
            step(f"rebuild_{table}")

        for table in OBSOLETE_TABLES:
            log(f"step 4: drop table {table} ({count(db, table)} rows discarded)")
            db.execute(f"DROP TABLE {table}")
        step("drop_tables")

        before_reserved = reserved_expectation(db)
        log("step 5: recompute users.green_points_reserved / red_points_reserved")
        recompute_reserved_points(db)
        changed = [row for row in before_reserved
                   if (row[1], row[2]) != (row[3], row[4])]
        log(f"        {len(changed)} of {len(before_reserved)} users change"
            + "".join(f"\n        user {r[0]}: green {r[1]} -> {r[3]}, red {r[2]} -> {r[4]}"
                      for r in changed))
        step("recompute_reserved")

        log(f"step 6: PRAGMA user_version = {SCHEMA_VERSION}")
        db.execute(f"PRAGMA user_version = {SCHEMA_VERSION}")
        step("set_version")

        # Checks; any failure rolls everything back.
        violations = db.execute("PRAGMA foreign_key_check").fetchall()
        if violations:
            raise UpgradeError(f"foreign_key_check reports {len(violations)} violation(s)")
        expected_schema = fresh_normalized()
        actual_schema = normalized_schema(db)
        if actual_schema != expected_schema:
            diff = sorted(set(actual_schema.items()) ^ set(expected_schema.items()))
            raise UpgradeError(
                "upgraded schema differs from the final schema: "
                + ", ".join(sorted({name for name, _ in diff}))
            )
        after = snapshot(db)
        for key in ("rows", "idempotency_keys", "hidden", "feedback", "audit"):
            if after[key] != before[key]:
                raise UpgradeError(f"{key} changed during the upgrade")
        if after["user_totals"] != before["user_totals"] or (
            after["consumed_green"] != before["consumed_green"]
        ):
            raise UpgradeError("point totals changed during the upgrade")
        stored = [tuple(r[:3]) for r in db.execute(
            "SELECT id, green_points_reserved, red_points_reserved FROM users ORDER BY id")]
        if stored != [(r[0], r[3], r[4]) for r in before_reserved]:
            raise UpgradeError("reserved counters do not match the rebuild")
        log("checks passed: foreign_key_check, final schema, row counts, point totals, "
            "idempotency keys, hidden history, audit, feedback, reserved counters")
        db.execute("COMMIT")
    except BaseException:
        db.execute("ROLLBACK")
        raise


def fresh_normalized() -> dict[str, str]:
    with closing(sqlite3.connect(":memory:")) as fresh:
        fresh.executescript(SCHEMA)
        return normalized_schema(fresh)


def open_readonly_copy(path: Path) -> sqlite3.Connection:
    """An in-memory copy of the database; the file is opened read-only."""
    if not path.exists():
        raise UpgradeError(f"database not found: {path}")
    memory = sqlite3.connect(":memory:", isolation_level=None)
    with closing(sqlite3.connect(f"{path.resolve().as_uri()}?mode=ro", uri=True)) as source:
        source.backup(memory)
    return memory


def table_counts(db: sqlite3.Connection) -> dict[str, int]:
    names = [r[0] for r in db.execute(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'")]
    return {name: count(db, name) for name in sorted(names)}


def make_backup(path: Path, target: Path, log: Log) -> None:
    """Copy the database with SQLite's backup API and prove the copy readable."""
    if target.exists():
        raise UpgradeError(f"backup target already exists: {target}")
    if target.resolve() == path.resolve():
        raise UpgradeError("backup target is the database itself")
    fd = os.open(target, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    os.close(fd)
    with closing(sqlite3.connect(f"{path.resolve().as_uri()}?mode=ro", uri=True)) as source:
        with closing(sqlite3.connect(target)) as copy:
            source.backup(copy)
        expected = table_counts(source)
    with closing(sqlite3.connect(f"{target.resolve().as_uri()}?mode=ro", uri=True)) as copy:
        verdict = copy.execute("PRAGMA integrity_check").fetchone()[0]
        if verdict != "ok":
            raise UpgradeError(f"backup {target} failed integrity_check: {verdict}")
        if table_counts(copy) != expected:
            raise UpgradeError(f"backup {target} does not match the database")
    log(f"backup written and verified: {target}")


def run(
    path: Path,
    *,
    apply: bool,
    backup_verified: bool,
    backup_to: Path | None,
    log: Log = print,
    after_step: Callable[[str], None] | None = None,
) -> None:
    if apply and bool(backup_verified) == bool(backup_to):
        raise UpgradeError(
            "--apply needs exactly one of --backup-verified (you have made and "
            "checked a backup yourself) or --backup-to PATH (back up first, then verify it)"
        )
    if not apply:
        log(f"DRY RUN on an in-memory copy of {path}; the database file is not modified")
        with closing(open_readonly_copy(path)) as copy:
            upgrade(copy, log)
        log("dry run complete: nothing was changed. Re-run with --apply to upgrade.")
        return
    if not path.exists():
        raise UpgradeError(f"database not found: {path}")
    if backup_to is not None:
        make_backup(path, backup_to, log)
    else:
        log("backup acknowledged by --backup-verified")
    with closing(sqlite3.connect(path, isolation_level=None)) as db:
        upgrade(db, log, after_step=after_step)
        verdict = db.execute("PRAGMA integrity_check").fetchone()[0]
        if verdict != "ok":
            raise UpgradeError(f"integrity_check after the upgrade: {verdict}")
    log(f"upgrade committed: {path} is now at schema version {SCHEMA_VERSION}")
