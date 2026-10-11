from __future__ import annotations

import json
import sqlite3
from typing import Any, Literal

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import FileResponse
from pydantic import BaseModel, ConfigDict, Field

from . import config
from .auth import require_admin
from .billing import (
    ALLOWED_SAMPLERS,
    FREE_ALLOWANCE_COOLDOWN_SECONDS,
    MAX_DIMENSION,
    MAX_STEPS_ADMIN,
    MAX_STEPS_FREE,
    MAX_STEPS_PAID,
    TOOL_CAPS,
    free_allowance_exhausted_until,
)
from .db import get_db, now_iso
from .errors import invalid_parameters
from .proxy import novelai_token
from .roles import (
    DEFAULT_ADMIN_RED_POINTS,
    DEFAULT_GREEN_POINT_LIMIT,
    DEFAULT_RED_POINTS,
    role_defaults,
)
from .users import user_admin_dict

router = APIRouter()


class UserUpdateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    is_admin: bool | None = None
    disabled: bool | None = None
    green_point_discount: int | None = Field(default=None, ge=0, le=100)
    can_generate_paid: bool | None = None
    can_text_generate: bool | None = None
    can_image_upscale: bool | None = None
    can_image_augment: bool | None = None
    can_image_encode_vibe: bool | None = None
    green_point_limit: int | None = Field(default=None, ge=0)
    green_point_used: int | None = Field(default=None, ge=0)
    red_points: int | None = Field(default=None, ge=0)
    red_points_used: int | None = Field(default=None, ge=0)


class UserCreateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    username: str = Field(min_length=1, max_length=80)
    # The role supplies every default; fields left out take its values.
    role: Literal["free", "paid", "admin"] = "free"
    is_admin: bool | None = None
    disabled: bool = False
    green_point_discount: int | None = Field(default=None, ge=0, le=100)
    can_generate_paid: bool | None = None
    can_text_generate: bool | None = None
    can_image_upscale: bool | None = None
    can_image_augment: bool | None = None
    can_image_encode_vibe: bool | None = None
    green_point_limit: int | None = Field(default=None, ge=0)
    green_point_used: int = Field(default=0, ge=0)
    red_points: int | None = Field(default=None, ge=0)
    red_points_used: int = Field(default=0, ge=0)


@router.get("/api/admin/users")
def admin_users(
    _: sqlite3.Row = Depends(require_admin),
    db: sqlite3.Connection = Depends(get_db),
):
    rows = db.execute("SELECT * FROM users ORDER BY id").fetchall()
    return {"items": [user_admin_dict(row) for row in rows]}


@router.get("/api/admin/feedback")
def admin_feedback_reports(
    limit: int = 100,
    user_id: int | None = None,
    _: sqlite3.Row = Depends(require_admin),
    db: sqlite3.Connection = Depends(get_db),
):
    where: list[str] = []
    params: list[Any] = []
    if user_id is not None:
        where.append("f.user_id = ?")
        params.append(user_id)
    where_sql = f"WHERE {' AND '.join(where)}" if where else ""
    params.append(max(1, min(limit, 500)))
    rows = db.execute(
        f"""
        SELECT f.id, f.user_id, u.username, f.description,
               f.client_context_json, f.event_count, f.created_at
        FROM client_feedback_reports f
        JOIN users u ON u.id = f.user_id
        {where_sql}
        ORDER BY f.created_at DESC
        LIMIT ?
        """,
        params,
    ).fetchall()
    items = []
    for row in rows:
        item = dict(row)
        item["client_context"] = json.loads(item.pop("client_context_json"))
        items.append(item)
    return {"items": items}


@router.get("/api/admin/feedback/{feedback_id}")
def admin_feedback_report(
    feedback_id: str,
    _: sqlite3.Row = Depends(require_admin),
    db: sqlite3.Connection = Depends(get_db),
):
    row = db.execute(
        """
        SELECT f.*, u.username
        FROM client_feedback_reports f
        JOIN users u ON u.id = f.user_id
        WHERE f.id = ?
        """,
        (feedback_id,),
    ).fetchone()
    if not row:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Feedback report not found")
    item = dict(row)
    item["client_context"] = json.loads(item.pop("client_context_json"))
    item["diagnostics"] = json.loads(item.pop("diagnostics_json"))
    return item


@router.get("/api/admin/audit")
def admin_audit_logs(
    limit: int = 100,
    user_id: int | None = None,
    _: sqlite3.Row = Depends(require_admin),
    db: sqlite3.Connection = Depends(get_db),
):
    where: list[str] = []
    params: list[Any] = []
    if user_id is not None:
        where.append("a.user_id = ?")
        params.append(user_id)
    where_sql = f"WHERE {' AND '.join(where)}" if where else ""
    params.append(max(1, min(limit, 500)))
    rows = db.execute(
        f"""
        SELECT a.*, u.username
        FROM request_audit_logs a
        JOIN users u ON u.id = a.user_id
        {where_sql}
        ORDER BY a.created_at DESC
        LIMIT ?
        """,
        params,
    ).fetchall()
    items = []
    for row in rows:
        item = dict(row)
        item["request_body_available"] = bool(item["request_body_path"])
        item["request_body_expired"] = bool(item["request_body_expired_at"])
        item["request_body_url"] = (
            f"/api/admin/audit/{item['id']}/body"
            if item["request_body_path"]
            else None
        )
        items.append(item)
    return {"items": items}


@router.get("/api/admin/audit/{audit_id}/body")
def admin_audit_body(
    audit_id: str,
    _: sqlite3.Row = Depends(require_admin),
    db: sqlite3.Connection = Depends(get_db),
):
    row = db.execute(
        """
        SELECT request_body_path, request_content_type, request_body_expired_at
        FROM request_audit_logs
        WHERE id = ?
        """,
        (audit_id,),
    ).fetchone()
    if row and row["request_body_expired_at"]:
        raise HTTPException(
            status.HTTP_404_NOT_FOUND,
            "Audit body expired: removed by the audit retention policy "
            f"at {row['request_body_expired_at']}",
        )
    if not row or not row["request_body_path"]:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Audit body not found")
    audit_root = config.AUDIT_DIR.resolve()
    body_path = (audit_root / row["request_body_path"]).resolve()
    if audit_root not in body_path.parents or not body_path.exists():
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Audit body not found")
    return FileResponse(
        body_path,
        media_type=row["request_content_type"] or "application/octet-stream",
        filename=f"{audit_id}.body",
    )


@router.post("/api/admin/users")
def admin_create_user(
    payload: UserCreateRequest,
    _: sqlite3.Row = Depends(require_admin),
    db: sqlite3.Connection = Depends(get_db),
):
    if payload.role == "admin" and payload.is_admin is False:
        raise invalid_parameters("is_admin", "role admin contradicts is_admin=false")
    values = role_defaults(payload.role)
    values.update(
        (name, value)
        for name in values
        if (value := getattr(payload, name)) is not None
    )
    if values["is_admin"]:
        values["green_point_discount"] = 100
    columns = {
        "username": payload.username,
        "password_hash": "",  # unused column, see db.SCHEMA
        **{name: int(value) for name, value in values.items()},
        "disabled": int(payload.disabled),
        "green_point_used": payload.green_point_used,
        "red_points_used": payload.red_points_used,
        "created_at": now_iso(),
    }
    try:
        db.execute(
            f"INSERT INTO users({', '.join(columns)}) "
            f"VALUES ({', '.join('?' for _ in columns)})",
            tuple(columns.values()),
        )
        db.commit()
    except sqlite3.IntegrityError:
        raise HTTPException(status.HTTP_409_CONFLICT, "Username already exists")
    user = db.execute("SELECT * FROM users WHERE username = ?", (payload.username,)).fetchone()
    return {"user": user_admin_dict(user)}


@router.patch("/api/admin/users/{user_id}")
def admin_update_user(
    user_id: int,
    payload: UserUpdateRequest,
    _: sqlite3.Row = Depends(require_admin),
    db: sqlite3.Connection = Depends(get_db),
):
    user = db.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
    if not user:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "User not found")

    values: list[Any] = []
    assignments: list[str] = []
    bool_fields = {
        "is_admin",
        "disabled",
        "can_generate_paid",
        "can_text_generate",
        "can_image_upscale",
        "can_image_augment",
        "can_image_encode_vibe",
    }
    int_fields = {
        "green_point_discount",
        "green_point_limit",
        "green_point_used",
        "red_points",
        "red_points_used",
    }
    fields = set(payload.model_fields_set)
    makes_admin = bool(payload.is_admin) and "is_admin" in fields
    if makes_admin:
        # Administrators are always unlimited, as when one is created.
        fields.add("green_point_discount")
    for field in sorted(fields):
        if field in bool_fields:
            assignments.append(f"{field} = ?")
            values.append(int(bool(getattr(payload, field))))
        elif field in int_fields:
            assignments.append(f"{field} = ?")
            values.append(
                100
                if makes_admin and field == "green_point_discount"
                else getattr(payload, field)
            )
    if assignments:
        values.append(user_id)
        db.execute(f"UPDATE users SET {', '.join(assignments)} WHERE id = ?", values)
        db.commit()
    updated = db.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
    return {"user": user_admin_dict(updated)}


@router.get("/api/admin/config")
def admin_config(
    _: sqlite3.Row = Depends(require_admin),
    db: sqlite3.Connection = Depends(get_db),
):
    exhausted_until = free_allowance_exhausted_until(db)
    return {
        "green_point_limit": DEFAULT_GREEN_POINT_LIMIT,
        "red_points": DEFAULT_RED_POINTS,
        "admin_red_points": DEFAULT_ADMIN_RED_POINTS,
        "free_max_steps": MAX_STEPS_FREE,
        "paid_max_steps": MAX_STEPS_PAID,
        "admin_max_steps": MAX_STEPS_ADMIN,
        "max_dimension": MAX_DIMENSION,
        "allowed_samplers": sorted(ALLOWED_SAMPLERS),
        "queue_weights": config.QUEUE_WEIGHTS,
        "text_concurrency": config.TEXT_GLOBAL_CONCURRENCY,
        "fake_novelai": config.FAKE_NOVELAI,
        "has_novelai_token": bool(novelai_token()),
        "tool_caps": dict(TOOL_CAPS),
        "free_allowance": {
            "exhausted": exhausted_until is not None,
            "exhausted_until": exhausted_until.isoformat() if exhausted_until else None,
            "cooldown_seconds": FREE_ALLOWANCE_COOLDOWN_SECONDS,
        },
    }
