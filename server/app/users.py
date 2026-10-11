from __future__ import annotations

from datetime import datetime, timedelta, timezone
import secrets
import sqlite3
from typing import Any

from fastapi import Response

from . import config
from .billing import (
    build_image_rules,
    free_allowance_exhausted_until,
    green_point_discount_for,
    remaining_points,
)
from .db import now_iso
from .security import create_jwt

def session_response(
    response: Response, db: sqlite3.Connection, user: sqlite3.Row
) -> dict[str, Any]:
    session_id = secrets.token_urlsafe(24)
    expires_at = datetime.now(timezone.utc) + timedelta(seconds=config.SESSION_TTL_SECONDS)
    db.execute(
        "INSERT INTO sessions(id, user_id, expires_at, created_at) VALUES (?, ?, ?, ?)",
        (session_id, user["id"], expires_at.isoformat(), now_iso()),
    )
    db.commit()
    token = create_jwt(
        {"sub": int(user["id"]), "jti": session_id}, config.SECRET_KEY, config.SESSION_TTL_SECONDS
    )
    response.set_cookie(
        "access_token",
        token,
        httponly=True,
        secure=config.COOKIE_SECURE,
        samesite="strict" if config.PRODUCTION else "lax",
        max_age=config.SESSION_TTL_SECONDS,
        path="/",
    )
    return {"user": user_to_dict(user), "quota": quota_for_user(user)}


def image_generation_allowed(user: Any, mode: str) -> bool:
    """The only rule for "may this user generate images in this mode".

    It describes capability, not balance: reservations report missing points
    as ``points_insufficient``. /api/me, quota, submission and the worker all
    call this function.
    """
    if user is None or user["disabled"]:
        return False
    if user["is_admin"]:
        return True
    if mode == "paid":
        return bool(user["can_generate_paid"])
    return (
        int(user["green_point_discount"]) > 0
        or int(user["green_point_limit"]) > int(user["green_point_used"])
    )


def image_tool_allowed(user: Any, tool: str) -> bool:
    if user is None or user["disabled"]:
        return False
    if user["is_admin"]:
        return True
    return bool(user[config.TOOL_PERMISSION_COLUMNS[tool]]) and image_generation_allowed(
        user, "paid"
    )


def generation_permission_name(mode: str) -> str:
    return "image.generate.paid" if mode == "paid" else "image.generate.free"


def tool_permission_name(tool: str) -> str:
    return f"image.{tool}"


def user_to_dict(user: sqlite3.Row) -> dict[str, Any]:
    permissions = {"history.read"}
    for mode in ("free", "paid"):
        if image_generation_allowed(user, mode):
            permissions.add(generation_permission_name(mode))
    if user["can_text_generate"] or user["is_admin"]:
        permissions.add("text.generate")
    for tool in config.TOOL_PERMISSION_COLUMNS:
        if image_tool_allowed(user, tool):
            permissions.add(tool_permission_name(tool))
    if any(
        permission.startswith(("image.", "text."))
        for permission in permissions
    ):
        permissions.add("novelai.proxy")
    if user["is_admin"]:
        permissions.update({"history.all", "admin.users", "admin.config"})
    return {
        "id": user["id"],
        "username": user["username"],
        "is_admin": bool(user["is_admin"]),
        "permissions": sorted(permissions),
    }


def user_admin_dict(user: sqlite3.Row) -> dict[str, Any]:
    return {
        **user_to_dict(user),
        "disabled": bool(user["disabled"]),
        "green_point_discount": user["green_point_discount"],
        "can_generate_paid": bool(user["can_generate_paid"]),
        "can_text_generate": bool(user["can_text_generate"]),
        "can_image_upscale": bool(user["can_image_upscale"]),
        "can_image_augment": bool(user["can_image_augment"]),
        "can_image_encode_vibe": bool(user["can_image_encode_vibe"]),
        "green_point_limit": user["green_point_limit"],
        "green_point_used": user["green_point_used"],
        "red_points": user["red_points"],
        "red_points_used": user["red_points_used"],
        "created_at": user["created_at"],
    }


def image_rules_for_user(db: sqlite3.Connection, user: sqlite3.Row) -> dict[str, Any]:
    """``rules.image`` for this user (contract §2), the input of every quote."""
    return build_image_rules(
        is_admin=bool(user["is_admin"]),
        can_generate_paid=bool(user["can_generate_paid"]),
        green_point_discount=green_point_discount_for(user),
        allowance_exhausted=free_allowance_exhausted_until(db) is not None,
    )


def quota_bucket(user: sqlite3.Row, mode: str) -> dict[str, Any]:
    enabled = image_generation_allowed(user, mode)
    if mode == "paid":
        limit = int(user["red_points"])
        reserved = int(user["red_points_reserved"])
        return {
            "date": None,
            "mode": mode,
            "kind": "points",
            "red_points": limit,
            "point_limit": limit,
            "used": int(user["red_points_used"]) + reserved,
            "reserved": reserved,
            "remaining": remaining_points(user, "red"),
            "unlimited": False,
            "enabled": enabled,
        }
    limit = int(user["green_point_limit"])
    reserved = int(user["green_points_reserved"])
    remaining = remaining_points(user, "green")
    return {
        "date": None,
        "mode": mode,
        "kind": "points",
        "green_point_limit": limit,
        "green_point_discount": green_point_discount_for(user),
        "point_limit": limit,
        "used": int(user["green_point_used"]) + reserved,
        "reserved": reserved,
        "remaining": 0 if remaining is None else max(0, remaining),
        "unlimited": remaining is None,
        "enabled": enabled,
    }


def quota_for_user(user: sqlite3.Row) -> dict[str, Any]:
    return {
        "free": quota_bucket(user, "free"),
        "paid": quota_bucket(user, "paid"),
    }


def mode_for_user(user: sqlite3.Row) -> str:
    if user["is_admin"]:
        return "admin"
    if user["can_generate_paid"]:
        return "paid"
    return "free"
