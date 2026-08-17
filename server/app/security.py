from __future__ import annotations

import base64
from datetime import datetime, timedelta, timezone
import hashlib
import hmac
import json
import secrets
from typing import Any


class TokenError(Exception):
    pass


def _b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def _unb64url(value: str) -> bytes:
    padding = "=" * (-len(value) % 4)
    return base64.urlsafe_b64decode(value + padding)


def hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, 260_000)
    return f"pbkdf2_sha256${_b64url(salt)}${_b64url(digest)}"


def verify_password(password: str, encoded: str) -> bool:
    try:
        alg, salt_b64, digest_b64 = encoded.split("$", 2)
        if alg != "pbkdf2_sha256":
            return False
        salt = _unb64url(salt_b64)
        expected = _unb64url(digest_b64)
        actual = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, 260_000)
        return hmac.compare_digest(actual, expected)
    except Exception:
        return False


def create_jwt(payload: dict[str, Any], secret: str, ttl_seconds: int) -> str:
    now = datetime.now(timezone.utc)
    body = {
        **payload,
        "iat": int(now.timestamp()),
        "exp": int((now + timedelta(seconds=ttl_seconds)).timestamp()),
    }
    header = {"alg": "HS256", "typ": "JWT"}
    signing_input = (
        f"{_b64url(json.dumps(header, separators=(',', ':')).encode())}."
        f"{_b64url(json.dumps(body, separators=(',', ':')).encode())}"
    )
    sig = hmac.new(secret.encode(), signing_input.encode(), hashlib.sha256).digest()
    return f"{signing_input}.{_b64url(sig)}"


def decode_jwt(token: str, secret: str) -> dict[str, Any]:
    try:
        header_b64, body_b64, sig_b64 = token.split(".", 2)
        signing_input = f"{header_b64}.{body_b64}"
        expected = hmac.new(secret.encode(), signing_input.encode(), hashlib.sha256).digest()
        if not hmac.compare_digest(expected, _unb64url(sig_b64)):
            raise TokenError("bad signature")
        body = json.loads(_unb64url(body_b64))
        exp = int(body.get("exp", 0))
        if exp < int(datetime.now(timezone.utc).timestamp()):
            raise TokenError("expired")
        return body
    except TokenError:
        raise
    except Exception as exc:
        raise TokenError("invalid") from exc
