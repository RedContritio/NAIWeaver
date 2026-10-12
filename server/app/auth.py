from __future__ import annotations

import sqlite3

from fastapi import APIRouter, Depends, HTTPException, Request, Response, status

from . import config
from .db import db_connect, get_db
from .errors import api_error, permission_denied
from .only_webauth import OnlyWebAuth
from .users import image_rules_for_user, quota_for_user, user_to_dict

router = APIRouter()


only_auth = OnlyWebAuth(config.PUBLIC_BASE_URL, config.SESSION_TTL_SECONDS, lambda: db_connect())


LOOPBACK_HOSTS = frozenset({"127.0.0.1", "::1"})


def validate_runtime_config() -> None:
    if config.PRODUCTION:
        if config.DEV_USER:
            # Behind frp every request looks like it comes from 127.0.0.1, so
            # the loopback check means nothing there.
            raise RuntimeError("NAIWEAVER_DEV_USER must not be set in production")
        if not only_auth.enabled:
            raise RuntimeError("NAIWEAVER_AUTH_ISSUER is required in production")


def dev_user_active(request: Request) -> bool:
    """Development auto login: no production, no OIDC, loopback client only."""
    return bool(
        config.DEV_USER
        and not config.PRODUCTION
        and not only_auth.enabled
        and request.client is not None
        and request.client.host in LOOPBACK_HOSTS
    )


def not_authenticated(message: str) -> HTTPException:
    return api_error(status.HTTP_401_UNAUTHORIZED, "not_authenticated", message)


async def require_user(request: Request, db: sqlite3.Connection = Depends(get_db)) -> sqlite3.Row:
    if only_auth.enabled:
        local_id = await only_auth.user_id(request)
        user = db.execute("SELECT * FROM users WHERE id = ?", (local_id,)).fetchone()
    elif dev_user_active(request):
        user = db.execute("SELECT * FROM users WHERE username = ?", (config.DEV_USER,)).fetchone()
    else:
        raise not_authenticated(
            "Not authenticated"
            if config.PRODUCTION
            else "Not authenticated; set NAIWEAVER_DEV_USER for local development"
        )
    if not user or user["disabled"]:
        raise not_authenticated("User disabled")
    return user


def require_admin(user: sqlite3.Row = Depends(require_user)) -> sqlite3.Row:
    if not user["is_admin"]:
        raise permission_denied("admin", "Admin required")
    return user


@router.post("/api/logout")
async def logout(request: Request, response: Response):
    if only_auth.enabled:
        await only_auth.logout(request)
        response.delete_cookie(only_auth.cookie, secure=True, httponly=True, samesite="lax")
    response.delete_cookie("naiweaver_current_task", path="/")
    return {"ok": True}


@router.get("/api/me")
def me(user: sqlite3.Row = Depends(require_user), db: sqlite3.Connection = Depends(get_db)):
    return {
        "user": user_to_dict(user),
        "quota": quota_for_user(user),
        "rules": {"image": image_rules_for_user(db, user)},
    }


@router.get("/auth/login")
async def only_webauth_login(request: Request):
    return await only_auth.login(request)


@router.get("/auth/callback")
async def only_webauth_callback(request: Request, db: sqlite3.Connection = Depends(get_db)):
    if not only_auth.enabled:
        raise HTTPException(404, "Not found")
    return await only_auth.callback(request, db)


@router.get("/api/quota")
def quota(user: sqlite3.Row = Depends(require_user)):
    return quota_for_user(user)
