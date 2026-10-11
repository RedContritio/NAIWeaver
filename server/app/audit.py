from __future__ import annotations

import asyncio
import hashlib
from pathlib import Path
import secrets
import sqlite3

from . import config
from .db import now_iso


def audit_request_preview(body: bytes) -> str:
    if not body:
        return ""
    text = body.decode("utf-8", errors="replace")
    if len(text) > config.AUDIT_MAX_STRING_CHARS:
        omitted = len(text) - config.AUDIT_MAX_STRING_CHARS
        return f"{text[:config.AUDIT_MAX_STRING_CHARS]}<truncated {omitted} chars>"
    return text


def write_audit_body_file(
    *,
    audit_id: str,
    user_id: int,
    created_at: str,
    body: bytes,
) -> tuple[str | None, int, str]:
    if not body:
        return None, 0, ""
    day = created_at[:10]
    relative_path = Path(day) / f"user-{user_id}" / f"{audit_id}.body"
    audit_root = config.AUDIT_DIR.resolve()
    body_path = (audit_root / relative_path).resolve()
    if audit_root not in body_path.parents:
        raise RuntimeError("Invalid audit body path")
    body_path.parent.mkdir(parents=True, exist_ok=True)
    body_path.write_bytes(body)
    return relative_path.as_posix(), len(body), hashlib.sha256(body).hexdigest()


def prepare_audit_record(
    *,
    audit_id: str,
    user_id: int,
    created_at: str,
    body: bytes,
    store_body: bool,
) -> tuple[str, str | None, int, str]:
    """Blocking part of an audit record: preview, and optionally the body file.

    Runs in a worker thread because bodies reach 25 MB (write + sha256).
    """
    preview = audit_request_preview(body)
    if store_body:
        body_path, body_bytes, body_sha256 = write_audit_body_file(
            audit_id=audit_id, user_id=user_id, created_at=created_at, body=body
        )
    else:
        # Metadata only: the size is recorded, the content is not kept.
        body_path, body_bytes, body_sha256 = None, len(body), ""
    return preview, body_path, body_bytes, body_sha256


async def create_audit_log(
    db: sqlite3.Connection,
    user: sqlite3.Row,
    *,
    service: str,
    path: str,
    method: str,
    body: bytes,
    content_type: str,
    store_body: bool = True,
) -> str:
    audit_id = secrets.token_urlsafe(18)
    created_at = now_iso()
    preview, body_path, body_bytes, body_sha256 = await asyncio.to_thread(
        prepare_audit_record,
        audit_id=audit_id,
        user_id=int(user["id"]),
        created_at=created_at,
        body=body,
        store_body=store_body,
    )
    db.execute(
        """
        INSERT INTO request_audit_logs(
          id, user_id, service, path, method, request_content_type,
          request_json, request_body_path, request_body_bytes,
          request_body_sha256, created_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            audit_id,
            int(user["id"]),
            service,
            path,
            method,
            content_type,
            preview,
            body_path,
            body_bytes,
            body_sha256,
            created_at,
        ),
    )
    db.commit()
    return audit_id


def complete_audit_log(
    db: sqlite3.Connection,
    audit_id: str | None,
    *,
    status_code: int | None,
    error_message: str | None = None,
) -> None:
    if audit_id is None:
        return
    db.execute(
        """
        UPDATE request_audit_logs
        SET status_code = ?, error_message = ?, completed_at = ?
        WHERE id = ?
        """,
        (status_code, error_message, now_iso(), audit_id),
    )
    db.commit()
