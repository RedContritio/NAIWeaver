from __future__ import annotations

import asyncio
import base64
import hashlib
import json
import math
import os
from pathlib import Path
import re
import secrets
import time
from urllib.parse import urlencode, urlsplit

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
from fastapi import HTTPException, Request
from fastapi.responses import RedirectResponse
import httpx


def b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def unb64(value: str) -> bytes:
    return base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))


class OnlyWebAuth:
    cookie = "__Host-naiweaver_session"
    flow_cookie = "__Host-naiweaver_flow"

    def __init__(self, public_url: str, session_ttl: int):
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
        self.flows = {}
        self.sessions = {}

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
        if tokens.get("token_type", "").lower() != "bearer" or not tokens.get("refresh_token"):
            raise ValueError("Incomplete token response")
        claims = await self.verify(tokens["access_token"], "access")
        return tokens, claims

    def prune(self):
        now = time.time()
        for collection in (self.flows, self.sessions):
            for key in list(collection):
                if collection[key]["expires"] <= now:
                    collection.pop(key, None)

    async def login(self):
        if not self.enabled:
            raise HTTPException(503, "only WebAuth is not configured")
        self.prune()
        metadata = await self.metadata()
        state, nonce, verifier = (secrets.token_urlsafe(32) for _ in range(3))
        self.flows[state] = {"nonce": nonce, "verifier": verifier, "expires": time.time() + 300}
        query = urlencode({
            "client_id": self.client_id, "redirect_uri": self.redirect_uri,
            "response_type": "code", "scope": "openid profile offline_access",
            "state": state, "nonce": nonce, "code_challenge_method": "S256",
            "code_challenge": b64(hashlib.sha256(verifier.encode()).digest()),
        })
        response = RedirectResponse(metadata["authorization_endpoint"] + "?" + query, status_code=302)
        response.headers["Cache-Control"] = "no-store"
        response.set_cookie(self.flow_cookie, state, secure=True, httponly=True, samesite="lax", max_age=300)
        return response

    async def callback(self, request: Request, db):
        state = request.query_params.get("state", "")
        if not state or not secrets.compare_digest(state, request.cookies.get(self.flow_cookie, "")):
            raise HTTPException(403, "Login state mismatch")
        flow = self.flows.pop(state, None)
        if not flow or flow["expires"] <= time.time() or request.query_params.get("error"):
            raise HTTPException(403, "Login expired or denied")
        tokens, claims = await self.token_request({
            "grant_type": "authorization_code", "code": request.query_params.get("code", ""),
            "redirect_uri": self.redirect_uri, "code_verifier": flow["verifier"],
        })
        identity = await self.verify(tokens["id_token"], "id", flow["nonce"])
        if identity["sub"] != claims["sub"]:
            raise HTTPException(403, "Identity mismatch")
        local_id = self.subject_map.get(claims["sub"])
        user = db.execute("SELECT * FROM users WHERE id = ?", (local_id,)).fetchone()
        if not user or user["disabled"]:
            raise HTTPException(403, "此认证身份尚未绑定 NAIWeaver 账户，请联系管理员。")
        self.sessions.pop(request.cookies.get(self.cookie), None)
        session_id = secrets.token_urlsafe(32)
        self.sessions[session_id] = {
            "subject": claims["sub"], "user_id": local_id, "tokens": tokens,
            "access_exp": claims["exp"], "expires": time.time() + self.session_ttl,
            "lock": asyncio.Lock(),
        }
        response = RedirectResponse("/", status_code=302)
        response.headers["Cache-Control"] = "no-store"
        response.set_cookie(self.cookie, session_id, secure=True, httponly=True,
                            samesite="lax", max_age=self.session_ttl)
        response.delete_cookie(self.flow_cookie, secure=True, httponly=True, samesite="lax")
        response.delete_cookie("access_token")
        return response

    async def user_id(self, request: Request):
        session_id = request.cookies.get(self.cookie)
        session = self.sessions.get(session_id)
        if not session or session["expires"] <= time.time():
            self.sessions.pop(session_id, None)
            raise HTTPException(401, "Not authenticated")
        async with session["lock"]:
            if session["access_exp"] <= time.time() + 15:
                try:
                    tokens, claims = await self.token_request({
                        "grant_type": "refresh_token", "refresh_token": session["tokens"]["refresh_token"],
                    })
                    if claims["sub"] != session["subject"]:
                        raise ValueError("Identity changed")
                    session.update(tokens=tokens, access_exp=claims["exp"])
                except (httpx.TimeoutException, httpx.NetworkError):
                    raise HTTPException(503, "认证服务暂时不可用，请稍后重试。")
                except Exception:
                    self.sessions.pop(session_id, None)
                    raise HTTPException(401, "Session expired")
        if session["access_exp"] <= time.time() or session["expires"] <= time.time():
            self.sessions.pop(session_id, None)
            raise HTTPException(401, "Session expired")
        return session["user_id"]

    async def logout(self, request: Request):
        session = self.sessions.pop(request.cookies.get(self.cookie), None)
        if session:
            try:
                metadata = await self.metadata()
                await self.http.post(metadata["revocation_endpoint"],
                                     data={"token": session["tokens"]["refresh_token"]},
                                     auth=(self.client_id, self.secret))
            except httpx.HTTPError:
                pass
