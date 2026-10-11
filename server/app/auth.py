from __future__ import annotations

from datetime import datetime, timezone
import sqlite3

from fastapi import APIRouter, Depends, HTTPException, Request, Response, status
from pydantic import BaseModel, ConfigDict, Field

from . import config
from .db import db_connect, get_db, now_iso
from .errors import api_error, permission_denied
from .only_webauth import OnlyWebAuth
from .security import TokenError, decode_jwt, verify_password
from .users import image_rules_for_user, quota_for_user, session_response, user_to_dict

router = APIRouter()


only_auth = OnlyWebAuth(config.PUBLIC_BASE_URL, config.SESSION_TTL_SECONDS, lambda: db_connect())


class LoginRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    username: str = Field(min_length=1, max_length=80)
    password: str = Field(min_length=1, max_length=256)


def validate_runtime_config() -> None:
    if not config.SECRET_KEY:
        raise RuntimeError("NAIWEAVER_SECRET_KEY is required in production")
    if config.PRODUCTION:
        if config.SECRET_KEY == "local-dev-change-me" or len(config.SECRET_KEY) < 32:
            raise RuntimeError("NAIWEAVER_SECRET_KEY must be a strong production secret")
        if not config.COOKIE_SECURE:
            raise RuntimeError("NAIWEAVER_COOKIE_SECURE=1 is required in production")
        if config.ALLOW_PASSWORD_LOGIN:
            raise RuntimeError("Password login must stay disabled in production")
        if not only_auth.enabled:
            raise RuntimeError("NAIWEAVER_AUTH_ISSUER is required in production")


def not_authenticated(message: str) -> HTTPException:
    return api_error(status.HTTP_401_UNAUTHORIZED, "not_authenticated", message)


async def require_user(request: Request, db: sqlite3.Connection = Depends(get_db)) -> sqlite3.Row:
    if only_auth.enabled:
        local_id = await only_auth.user_id(request)
        user = db.execute("SELECT * FROM users WHERE id = ?", (local_id,)).fetchone()
        if not user or user["disabled"]:
            raise not_authenticated("User disabled")
        return user
    token = request.cookies.get("access_token")
    auth = request.headers.get("Authorization", "")
    if not token and auth.lower().startswith("bearer "):
        token = auth[7:].strip()
    if not token:
        raise not_authenticated("Not authenticated")
    try:
        payload = decode_jwt(token, config.SECRET_KEY)
    except TokenError:
        raise not_authenticated("Invalid session")
    session_id = payload.get("jti")
    user_id = payload.get("sub")
    if not session_id or not user_id:
        raise not_authenticated("Invalid session")
    try:
        user_id_int = int(user_id)
    except (TypeError, ValueError):
        raise not_authenticated("Invalid session")
    session = db.execute(
        "SELECT * FROM sessions WHERE id = ? AND user_id = ? AND revoked_at IS NULL",
        (session_id, user_id_int),
    ).fetchone()
    if not session:
        raise not_authenticated("Session expired")
    if datetime.fromisoformat(session["expires_at"]) < datetime.now(timezone.utc):
        raise not_authenticated("Session expired")
    user = db.execute("SELECT * FROM users WHERE id = ?", (user_id_int,)).fetchone()
    if not user or user["disabled"]:
        raise not_authenticated("User disabled")
    return user


def require_admin(user: sqlite3.Row = Depends(require_user)) -> sqlite3.Row:
    if not user["is_admin"]:
        raise permission_denied("admin", "Admin required")
    return user


@router.post("/api/login")
def login(payload: LoginRequest, response: Response, db: sqlite3.Connection = Depends(get_db)):
    if only_auth.enabled or not config.ALLOW_PASSWORD_LOGIN:
        raise HTTPException(status.HTTP_410_GONE, "Password login is disabled")
    user = db.execute("SELECT * FROM users WHERE username = ?", (payload.username,)).fetchone()
    if not user or user["disabled"] or not verify_password(payload.password, user["password_hash"]):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid username or password")
    return session_response(response, db, user)


@router.post("/api/logout")
async def logout(request: Request, response: Response, db: sqlite3.Connection = Depends(get_db)):
    if only_auth.enabled:
        await only_auth.logout(request)
        response.delete_cookie(only_auth.cookie, secure=True, httponly=True, samesite="lax")
        response.delete_cookie("access_token", path="/")
        response.delete_cookie("naiweaver_current_task", path="/")
        return {"ok": True}
    token = request.cookies.get("access_token")
    if token:
        try:
            payload = decode_jwt(token, config.SECRET_KEY)
            session_id = payload.get("jti")
            if session_id:
                db.execute(
                    "UPDATE sessions SET revoked_at = ? WHERE id = ?",
                    (now_iso(), session_id),
                )
                db.commit()
        except TokenError:
            pass
    response.delete_cookie("access_token", path="/")
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
