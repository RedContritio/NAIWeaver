from __future__ import annotations

import asyncio
import base64
from collections import OrderedDict
from collections.abc import Callable
import hashlib
import json
import math
import os
from pathlib import Path
import posixpath
import re
import secrets
import sqlite3
import time
from urllib.parse import quote, unquote, urlencode, urlsplit
import weakref

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
from fastapi import HTTPException, Request
from fastapi.responses import RedirectResponse
import httpx


def b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def unb64(value: str) -> bytes:
    return base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))


FLOW_TTL = 300
MAX_RETURN_TO = 2048

SESSION_TABLE = """
CREATE TABLE IF NOT EXISTS only_webauth_sessions (
  id TEXT PRIMARY KEY,
  subject TEXT NOT NULL,
  user_id INTEGER NOT NULL,
  refresh_token TEXT NOT NULL,
  access_expires REAL NOT NULL,
  expires REAL NOT NULL
)
"""


def auth_error(status_code: int, code: str, message: str) -> HTTPException:
    return HTTPException(status_code, {"code": code, "message": message})


def not_authenticated() -> HTTPException:
    return auth_error(401, "not_authenticated", "Not authenticated")


def auth_unavailable() -> HTTPException:
    return auth_error(503, "auth_unavailable", "认证服务暂时不可用，请稍后重试。")


def login_failed() -> HTTPException:
    return auth_error(403, "login_failed", "认证未完成，请从 NAIWeaver 重新发起登录。")


def is_transient(exc: Exception) -> bool:
    """An outage or throttling at the identity provider, not a rejection."""
    if isinstance(exc, httpx.HTTPStatusError):
        return exc.response.status_code == 429 or exc.response.status_code >= 500
    return isinstance(exc, httpx.TransportError)


def safe_return_to(value: str | None) -> str:
    """Keep only same-origin relative paths; anything else returns to the root."""
    if (
        not value
        or len(value) > MAX_RETURN_TO
        or not value.startswith("/")
        or value.startswith("//")
        or any(not "!" <= char <= "~" or char == "\\" for char in value)
    ):
        return "/"
    # Returning into /auth/ would only start another login.
    path = posixpath.normpath(unquote(urlsplit(value).path))
    return "/" if path.lstrip("/").startswith("auth/") else value


def redirect(location: str) -> RedirectResponse:
    response = RedirectResponse(location, status_code=302)
    response.headers["Cache-Control"] = "no-store"
    return response


class OnlyWebAuth:
    cookie = "__Host-naiweaver_session"
    flow_cookie = "__Host-naiweaver_flow"
    max_flows = 1024
    max_browser_flows = 16

    def __init__(self, public_url: str, session_ttl: int,
                 connect: Callable[[], sqlite3.Connection] | None = None):
        self.issuer = os.getenv("NAIWEAVER_AUTH_ISSUER", "").rstrip("/")
        self.enabled = bool(self.issuer)
        self.client_id = os.getenv("NAIWEAVER_AUTH_CLIENT_ID", "naiweaver")
        self.redirect_uri = public_url + "/auth/callback"
        self.session_ttl = session_ttl
        self.subject_map = json.loads(os.getenv("NAIWEAVER_AUTH_SUBJECT_MAP", "{}"))
        self.key_ttl = int(os.getenv("NAIWEAVER_AUTH_KEY_CACHE_MINUTES", "10080")) * 60
        self.secret = ""
        if self.enabled:
            for url in (self.issuer, public_url):
                parsed = urlsplit(url)
                if parsed.scheme != "https" or not parsed.netloc or parsed.path or parsed.query or parsed.fragment or parsed.username:
                    raise ValueError("Authentication URLs must be HTTPS origins")
            self.secret = Path(os.environ["NAIWEAVER_AUTH_CLIENT_SECRET_FILE"]).read_text().strip()
            if not self.secret or self.key_ttl <= 0:
                raise ValueError("Authentication secret and positive key cache lifetime are required")
            if not isinstance(self.subject_map, dict) or any(not isinstance(v, int) or v < 1 for v in self.subject_map.values()):
                raise ValueError("Subject map must map only WebAuth user IDs to local integer user IDs")
        self.http = httpx.AsyncClient(timeout=10)
        self.discovery = None
        self.keys = {}
        self.keys_expire = 0
        self.key_lock = asyncio.Lock()
        # Pending logins by state, oldest first; they only live for FLOW_TTL.
        self.flows = OrderedDict()
        # Sessions are kept in SQLite so they survive a restart. The factory is
        # called once; without one they live in a private in-memory database.
        self.connect = connect or (lambda: sqlite3.connect(":memory:"))
        self._db = None
        self.refresh_locks = weakref.WeakValueDictionary()

    @property
    def db(self) -> sqlite3.Connection:
        # A single connection is enough: every caller runs on the event loop.
        if self._db is None:
            db = self.connect()
            db.row_factory = sqlite3.Row
            db.execute(SESSION_TABLE)
            db.commit()
            self._db = db
        return self._db

    async def aclose(self):
        await self.http.aclose()
        if self._db is not None:
            self._db.close()

    async def metadata(self):
        if self.discovery is None:
            response = await self.http.get(self.issuer + "/.well-known/openid-configuration")
            response.raise_for_status()
            data = response.json()
            if data.get("issuer") != self.issuer:
                raise ValueError("Issuer mismatch")
            for name in ("authorization_endpoint", "token_endpoint", "jwks_uri", "revocation_endpoint"):
                if not data[name].startswith(self.issuer + "/"):
                    raise ValueError("Unexpected authentication endpoint")
            self.discovery = data
        return self.discovery

    async def signing_key(self, kid):
        async with self.key_lock:
            if time.time() >= self.keys_expire or kid not in self.keys:
                metadata = await self.metadata()
                response = await self.http.get(metadata["jwks_uri"])
                response.raise_for_status()
                self.keys = {
                    key["kid"]: Ed25519PublicKey.from_public_bytes(unb64(key["x"]))
                    for key in response.json()["keys"]
                    if key.get("kty") == "OKP" and key.get("crv") == "Ed25519"
                    and key.get("alg", "EdDSA") == "EdDSA" and key.get("use", "sig") == "sig"
                }
                match = re.search(r"(?:^|,)\s*max-age=(\d+)", response.headers.get("cache-control", ""))
                ttl = min(self.key_ttl, int(match[1])) if match else self.key_ttl
                self.keys_expire = time.time() + ttl
            return self.keys[kid]

    async def verify(self, token: str, token_use: str, nonce=None):
        header, payload, signature = token.split(".")
        head = json.loads(unb64(header))
        if head.get("alg") != "EdDSA":
            raise ValueError("Unexpected signing algorithm")
        key = await self.signing_key(head["kid"])
        key.verify(unb64(signature), (header + "." + payload).encode())
        claims = json.loads(unb64(payload))
        audience = claims.get("aud")
        audience = audience if isinstance(audience, list) else [audience]
        if claims.get("iss") != self.issuer or self.client_id not in audience:
            raise ValueError("Invalid token audience or issuer")
        if len(audience) > 1 and claims.get("azp") != self.client_id:
            raise ValueError("Invalid authorized party")
        now = time.time()
        for name in ("exp", "iat"):
            if not isinstance(claims.get(name), (int, float)) or not math.isfinite(claims[name]):
                raise ValueError("Invalid token time")
        if claims["exp"] <= now or claims["iat"] > now + 60 or claims.get("nbf", 0) > now + 60:
            raise ValueError("Expired or premature token")
        if claims.get("token_use") != token_use or not isinstance(claims.get("sub"), str) or not claims["sub"]:
            raise ValueError("Invalid token identity")
        if nonce is not None and claims.get("nonce") != nonce:
            raise ValueError("Invalid nonce")
        return claims

    async def token_request(self, form):
        metadata = await self.metadata()
        response = await self.http.post(metadata["token_endpoint"], data=form,
                                        auth=(self.client_id, self.secret))
        response.raise_for_status()
        tokens = response.json()
        if not tokens.get("refresh_token"):
            # RFC 6749 section 6: a refresh may keep the current refresh token.
            tokens["refresh_token"] = form.get("refresh_token")
        if tokens.get("token_type", "").lower() != "bearer" or not tokens.get("refresh_token"):
            raise ValueError("Incomplete token response")
        claims = await self.verify(tokens["access_token"], "access")
        return tokens, claims

    def prune(self):
        now = time.monotonic()
        while self.flows and next(iter(self.flows.values()))["expires"] <= now:
            self.flows.popitem(last=False)
        with self.db:
            self.db.execute("DELETE FROM only_webauth_sessions WHERE expires <= ?", (time.time(),))

    def flow_cookie_name(self, state: str) -> str:
        # One cookie per pending login, so tabs logging in at the same time
        # never overwrite each other's state.
        return f"{self.flow_cookie}_{hashlib.sha256(state.encode()).hexdigest()[:16]}"

    def surplus_flow_cookies(self, request: Request) -> list[str]:
        """This browser's oldest flow cookies beyond room for one more login."""
        prefix = self.flow_cookie + "_"
        pending = sorted(
            (name for name in request.cookies if name.startswith(prefix)),
            key=lambda name: self.flows.get(request.cookies[name], {}).get("expires", 0),
        )
        return pending[:max(0, len(pending) - self.max_browser_flows + 1)]

    @staticmethod
    def login_location(request: Request) -> str:
        """The login URL that brings this page load back to where it started."""
        target = quote(request.url.path) + (f"?{request.url.query}" if request.url.query else "")
        return "/auth/login?" + urlencode({"return_to": target})

    async def login(self, request: Request | None = None):
        # The request supplies return_to and this browser's pending flow cookies.
        if not self.enabled:
            raise auth_error(503, "auth_unavailable", "only WebAuth is not configured")
        self.prune()
        try:
            metadata = await self.metadata()
        except Exception as exc:
            raise auth_unavailable() from exc
        state, nonce, verifier = (secrets.token_urlsafe(32) for _ in range(3))
        self.flows[state] = {
            "nonce": nonce, "verifier": verifier, "expires": time.monotonic() + FLOW_TTL,
            "return_to": safe_return_to(request.query_params.get("return_to")) if request else "/",
        }
        while len(self.flows) > self.max_flows:
            self.flows.popitem(last=False)
        query = urlencode({
            "client_id": self.client_id, "redirect_uri": self.redirect_uri,
            "response_type": "code", "scope": "openid profile offline_access",
            "state": state, "nonce": nonce, "code_challenge_method": "S256",
            "code_challenge": b64(hashlib.sha256(verifier.encode()).digest()),
        })
        response = redirect(metadata["authorization_endpoint"] + "?" + query)
        response.set_cookie(self.flow_cookie_name(state), state, secure=True, httponly=True,
                            samesite="lax", max_age=FLOW_TTL)
        for name in self.surplus_flow_cookies(request) if request else ():
            response.delete_cookie(name, secure=True, httponly=True, samesite="lax")
        return response

    async def callback(self, request: Request, db):
        self.prune()
        state = request.query_params.get("state", "")
        flow = self.flows.pop(state, None)
        flow_cookie = self.flow_cookie_name(state)
        browser_state = request.cookies.get(flow_cookie, "")
        if not flow or not secrets.compare_digest(browser_state.encode(), state.encode()):
            # Expired, evicted, lost in a restart or not started by this
            # browser: start over instead of failing the page.
            response = redirect("/")
            response.delete_cookie(flow_cookie, secure=True, httponly=True, samesite="lax")
            return response
        error = request.query_params.get("error")
        if error in ("temporarily_unavailable", "server_error"):
            raise auth_unavailable()
        if error:
            raise login_failed()
        try:
            tokens, claims = await self.token_request({
                "grant_type": "authorization_code", "code": request.query_params.get("code", ""),
                "redirect_uri": self.redirect_uri, "code_verifier": flow["verifier"],
            })
            identity = await self.verify(tokens["id_token"], "id", flow["nonce"])
        except Exception as exc:
            raise (auth_unavailable() if is_transient(exc) else login_failed()) from exc
        if identity["sub"] != claims["sub"]:
            raise login_failed()
        local_id = self.subject_map.get(claims["sub"])
        user = db.execute("SELECT * FROM users WHERE id = ?", (local_id,)).fetchone()
        if not user or user["disabled"]:
            raise auth_error(403, "account_not_linked", "此认证身份尚未绑定 NAIWeaver 账户，请联系管理员。")
        session_id = secrets.token_urlsafe(32)
        with self.db:
            self.db.execute("DELETE FROM only_webauth_sessions WHERE id = ?",
                            (self.session_key(request.cookies.get(self.cookie, "")),))
            self.db.execute(
                "INSERT INTO only_webauth_sessions VALUES (?, ?, ?, ?, ?, ?)",
                (self.session_key(session_id), claims["sub"], local_id, tokens["refresh_token"],
                 claims["exp"], time.time() + self.session_ttl),
            )
        response = redirect(flow["return_to"])
        response.set_cookie(self.cookie, session_id, secure=True, httponly=True,
                            samesite="lax", max_age=self.session_ttl)
        response.delete_cookie(flow_cookie, secure=True, httponly=True, samesite="lax")
        response.delete_cookie("access_token")
        return response

    @staticmethod
    def session_key(session_id: str) -> str:
        # Only a digest is stored, so a copy of the database cannot be replayed as cookies.
        return hashlib.sha256(session_id.encode()).hexdigest()

    def session(self, key: str) -> sqlite3.Row:
        session = self.db.execute("SELECT * FROM only_webauth_sessions WHERE id = ?", (key,)).fetchone()
        # Sessions outlive restarts, so a subject unmapped since login loses access now.
        if (not session or session["expires"] <= time.time()
                or self.subject_map.get(session["subject"]) != session["user_id"]):
            raise not_authenticated()
        return session

    def drop_session(self, key: str):
        with self.db:
            self.db.execute("DELETE FROM only_webauth_sessions WHERE id = ?", (key,))

    async def user_id(self, request: Request):
        key = self.session_key(request.cookies.get(self.cookie, ""))
        session = self.session(key)
        if session["access_expires"] <= time.time() + 15:
            async with self.refresh_locks.setdefault(key, asyncio.Lock()):
                # Another request may have refreshed or ended it while this one waited.
                session = self.session(key)
                if session["access_expires"] <= time.time() + 15:
                    await self.refresh(key, session)
        return session["user_id"]

    async def refresh(self, key: str, session: sqlite3.Row):
        try:
            tokens, claims = await self.token_request({
                "grant_type": "refresh_token", "refresh_token": session["refresh_token"],
            })
            if claims["sub"] != session["subject"]:
                raise ValueError("Identity changed")
        except Exception as exc:
            # An unreachable or overloaded provider says nothing about the
            # session; only a definite rejection ends it.
            if is_transient(exc):
                raise auth_unavailable() from exc
            self.drop_session(key)
            raise not_authenticated() from exc
        with self.db:
            self.db.execute(
                "UPDATE only_webauth_sessions SET refresh_token = ?, access_expires = ? WHERE id = ?",
                (tokens["refresh_token"], claims["exp"], key),
            )

    async def logout(self, request: Request):
        key = self.session_key(request.cookies.get(self.cookie, ""))
        session = self.db.execute(
            "SELECT refresh_token FROM only_webauth_sessions WHERE id = ?", (key,)
        ).fetchone()
        if session:
            self.drop_session(key)
            try:
                metadata = await self.metadata()
                await self.http.post(metadata["revocation_endpoint"],
                                     data={"token": session["refresh_token"]},
                                     auth=(self.client_id, self.secret))
            except httpx.HTTPError:
                pass
