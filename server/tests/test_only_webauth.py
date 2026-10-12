from __future__ import annotations

import os
import tempfile

# Isolate every data path before anything from app is imported.
_TEMP = tempfile.TemporaryDirectory(prefix="naiweaver-auth-test-")
os.environ["NAIWEAVER_DATA_DIR"] = _TEMP.name
os.environ["NAIWEAVER_DB_PATH"] = os.path.join(_TEMP.name, "naiweaver.sqlite3")

import asyncio
import base64
import json
import sqlite3
import time
import unittest
from unittest import mock
from urllib.parse import parse_qs, urlencode, urlsplit

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat
from fastapi import HTTPException
import httpx
from starlette.requests import Request

from app.only_webauth import OnlyWebAuth, safe_return_to


ISSUER = "https://idp.test"
PUBLIC_URL = "https://nai.test"
SUBJECT = "webauth-user-1"
LOCAL_ID = 7


def tearDownModule() -> None:
    _TEMP.cleanup()


def b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


class FakeIdentityProvider:
    """Answers discovery, JWKS, token and revocation requests in-process."""

    def __init__(self) -> None:
        self.key = Ed25519PrivateKey.generate()
        self.token_replies: list = []
        self.token_requests: list[dict[str, str]] = []
        self.revoked: list[str] = []
        self.key_id = "k1"

    def jwt(self, token_use: str, **claims) -> str:
        now = int(time.time())
        body = {
            "iss": ISSUER, "aud": "naiweaver", "sub": SUBJECT,
            "iat": now, "exp": now + 300, "token_use": token_use, **claims,
        }
        header = b64(json.dumps({"alg": "EdDSA", "kid": self.key_id}).encode())
        payload = b64(json.dumps(body).encode())
        signature = self.key.sign(f"{header}.{payload}".encode())
        return f"{header}.{payload}.{b64(signature)}"

    def tokens(self, refresh_token: str | None = "rt-1", nonce: str | None = None) -> httpx.Response:
        body = {"token_type": "Bearer", "access_token": self.jwt("access")}
        if refresh_token:
            body["refresh_token"] = refresh_token
        if nonce:
            body["id_token"] = self.jwt("id", nonce=nonce)
        return httpx.Response(200, json=body)

    async def handler(self, request: httpx.Request) -> httpx.Response:
        # Yield like a real network call so concurrent requests interleave.
        await asyncio.sleep(0)
        path = request.url.path
        if path == "/.well-known/openid-configuration":
            return httpx.Response(200, json={
                "issuer": ISSUER,
                "authorization_endpoint": ISSUER + "/authorize",
                "token_endpoint": ISSUER + "/token",
                "jwks_uri": ISSUER + "/jwks",
                "revocation_endpoint": ISSUER + "/revoke",
            })
        if path == "/jwks":
            raw = self.key.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)
            return httpx.Response(200, json={"keys": [
                {"kty": "OKP", "crv": "Ed25519", "kid": "k1", "x": b64(raw)},
            ]})
        form = {name: values[0] for name, values in parse_qs(request.content.decode()).items()}
        if path == "/revoke":
            self.revoked.append(form["token"])
            return httpx.Response(200)
        self.token_requests.append(form)
        reply = self.token_replies.pop(0)
        if isinstance(reply, Exception):
            raise reply
        return reply


class Browser:
    """A cookie jar shared by every tab of one browser."""

    def __init__(self) -> None:
        self.cookies: dict[str, str] = {}

    def request(self, path: str, query: str = "") -> Request:
        header = "; ".join(f"{name}={value}" for name, value in self.cookies.items())
        return Request({
            "type": "http", "method": "GET", "scheme": "https",
            "server": ("nai.test", 443), "path": path, "raw_path": path.encode(),
            "query_string": query.encode(), "headers": [(b"cookie", header.encode())],
        })

    def receive(self, response):
        for header in response.headers.getlist("set-cookie"):
            name, _, rest = header.partition("=")
            if "max-age=0" in header.lower():
                self.cookies.pop(name, None)
            else:
                self.cookies[name] = rest.split(";", 1)[0]
        return response

    def flow_cookies(self) -> list[str]:
        return [name for name in self.cookies if name.startswith(OnlyWebAuth.flow_cookie + "_")]


class OnlyWebAuthTestCase(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        temp = tempfile.TemporaryDirectory(prefix="naiweaver-auth-case-")
        self.addCleanup(temp.cleanup)
        self.secret_file = os.path.join(temp.name, "client-secret")
        with open(self.secret_file, "w") as handle:
            handle.write("client-secret\n")
        self.session_db = os.path.join(temp.name, "sessions.sqlite3")
        self.users = sqlite3.connect(os.path.join(temp.name, "users.sqlite3"))
        self.users.row_factory = sqlite3.Row
        self.users.execute("CREATE TABLE users (id INTEGER PRIMARY KEY, disabled INTEGER NOT NULL)")
        self.users.execute("INSERT INTO users VALUES (?, 0)", (LOCAL_ID,))
        self.users.commit()
        self.addCleanup(self.users.close)
        self.idp = FakeIdentityProvider()
        self.subject_map = {SUBJECT: LOCAL_ID}

    async def make_auth(self) -> OnlyWebAuth:
        env = {
            "NAIWEAVER_AUTH_ISSUER": ISSUER,
            "NAIWEAVER_AUTH_CLIENT_SECRET_FILE": self.secret_file,
            "NAIWEAVER_AUTH_SUBJECT_MAP": json.dumps(self.subject_map),
        }
        with mock.patch.dict(os.environ, env):
            auth = OnlyWebAuth(PUBLIC_URL, 3600, lambda: sqlite3.connect(self.session_db))
        await auth.http.aclose()
        auth.http = httpx.AsyncClient(transport=httpx.MockTransport(self.idp.handler))
        self.addAsyncCleanup(auth.aclose)
        return auth

    async def start_login(self, auth: OnlyWebAuth, browser: Browser, return_to: str | None = None):
        query = urlencode({"return_to": return_to}) if return_to is not None else ""
        response = browser.receive(await auth.login(browser.request("/auth/login", query)))
        params = parse_qs(urlsplit(response.headers["location"]).query)
        return params["state"][0], params["nonce"][0]

    async def finish_login(self, auth: OnlyWebAuth, browser: Browser, state: str, nonce: str):
        self.idp.token_replies.append(self.idp.tokens(nonce=nonce))
        request = browser.request("/auth/callback", urlencode({"code": "code", "state": state}))
        return browser.receive(await auth.callback(request, self.users))

    async def signed_in(self, auth: OnlyWebAuth) -> Browser:
        browser = Browser()
        response = await self.finish_login(auth, browser, *await self.start_login(auth, browser))
        self.assertIn(OnlyWebAuth.cookie, browser.cookies, response.headers)
        return browser

    def expire_access(self, auth: OnlyWebAuth) -> None:
        with auth.db:
            auth.db.execute("UPDATE only_webauth_sessions SET access_expires = 0")

    def refresh_tokens(self, auth: OnlyWebAuth) -> list[str]:
        """The (decrypted) refresh token of every stored session."""
        rows = auth.db.execute("SELECT refresh_token FROM only_webauth_sessions").fetchall()
        return [auth.unseal(row["refresh_token"]) for row in rows]

    async def assert_auth_error(self, awaitable, status: int, code: str) -> None:
        with self.assertRaises(HTTPException) as raised:
            await awaitable
        self.assertEqual(raised.exception.status_code, status)
        self.assertEqual(raised.exception.detail["code"], code)


class SessionTests(OnlyWebAuthTestCase):
    async def test_provider_outage_keeps_session(self) -> None:
        auth = await self.make_auth()
        browser = await self.signed_in(auth)
        outages = [
            httpx.Response(500), httpx.Response(502), httpx.Response(503), httpx.Response(429),
            httpx.ConnectTimeout("timed out"), httpx.ConnectError("refused"),
            httpx.RemoteProtocolError("disconnected"),
        ]
        for outage in outages:
            with self.subTest(outage=outage):
                self.expire_access(auth)
                self.idp.token_replies.append(outage)
                await self.assert_auth_error(auth.user_id(browser.request("/")), 503, "auth_unavailable")
                self.assertEqual(len(self.refresh_tokens(auth)), 1)

        self.idp.token_replies.append(self.idp.tokens("rt-2"))
        self.assertEqual(await auth.user_id(browser.request("/")), LOCAL_ID)
        self.assertEqual(self.refresh_tokens(auth), ["rt-2"])

    async def test_rejected_refresh_ends_session(self) -> None:
        auth = await self.make_auth()
        browser = await self.signed_in(auth)
        self.expire_access(auth)
        self.idp.token_replies.append(httpx.Response(400, json={"error": "invalid_grant"}))
        await self.assert_auth_error(auth.user_id(browser.request("/")), 401, "not_authenticated")
        self.assertEqual(self.refresh_tokens(auth), [])
        await self.assert_auth_error(auth.user_id(browser.request("/")), 401, "not_authenticated")

    async def test_refresh_without_new_refresh_token_keeps_current_one(self) -> None:
        auth = await self.make_auth()
        browser = await self.signed_in(auth)
        self.expire_access(auth)
        self.idp.token_replies.append(self.idp.tokens(refresh_token=None))
        self.assertEqual(await auth.user_id(browser.request("/")), LOCAL_ID)
        self.assertEqual(self.refresh_tokens(auth), ["rt-1"])

        self.expire_access(auth)
        self.idp.token_replies.append(self.idp.tokens("rt-2"))
        self.assertEqual(await auth.user_id(browser.request("/")), LOCAL_ID)
        self.assertEqual(self.idp.token_requests[-1]["refresh_token"], "rt-1")
        self.assertEqual(self.refresh_tokens(auth), ["rt-2"])

    async def test_concurrent_requests_refresh_once(self) -> None:
        auth = await self.make_auth()
        browser = await self.signed_in(auth)
        self.expire_access(auth)
        self.idp.token_replies.append(self.idp.tokens("rt-2"))
        results = await asyncio.gather(*(auth.user_id(browser.request("/")) for _ in range(3)))
        self.assertEqual(results, [LOCAL_ID] * 3)
        refreshes = [form for form in self.idp.token_requests if form["grant_type"] == "refresh_token"]
        self.assertEqual(len(refreshes), 1)

    async def test_logout_revokes_and_forgets_the_session(self) -> None:
        auth = await self.make_auth()
        browser = await self.signed_in(auth)
        await auth.logout(browser.request("/api/logout"))
        self.assertEqual(self.idp.revoked, ["rt-1"])
        self.assertEqual(self.refresh_tokens(auth), [])
        await self.assert_auth_error(auth.user_id(browser.request("/")), 401, "not_authenticated")


class FlowTests(OnlyWebAuthTestCase):
    async def test_parallel_tabs_each_complete_login(self) -> None:
        auth = await self.make_auth()
        browser = Browser()
        first = await self.start_login(auth, browser)
        second = await self.start_login(auth, browser)
        self.assertEqual(len(browser.flow_cookies()), 2)

        for state, nonce in (second, first):
            response = await self.finish_login(auth, browser, state, nonce)
            self.assertEqual(response.status_code, 302)
            self.assertEqual(response.headers["location"], "/")
            self.assertEqual(await auth.user_id(browser.request("/")), LOCAL_ID)
        self.assertEqual(browser.flow_cookies(), [])
        self.assertEqual(len(self.refresh_tokens(auth)), 1)

    async def test_foreign_or_unknown_state_restarts_login(self) -> None:
        auth = await self.make_auth()
        state, _ = await self.start_login(auth, Browser())
        for query in (f"code=x&state={state}", "code=x&state=unknown", "code=x"):
            with self.subTest(query=query):
                other = Browser()
                response = other.receive(await auth.callback(other.request("/auth/callback", query), self.users))
                self.assertEqual(response.status_code, 302)
                self.assertEqual(response.headers["location"], "/")
                self.assertNotIn(OnlyWebAuth.cookie, other.cookies)
        self.assertEqual(self.idp.token_requests, [])

    async def test_provider_error_does_not_loop(self) -> None:
        auth = await self.make_auth()
        browser = Browser()
        state, _ = await self.start_login(auth, browser)
        request = browser.request("/auth/callback", urlencode({"error": "access_denied", "state": state}))
        await self.assert_auth_error(auth.callback(request, self.users), 403, "login_failed")

    async def test_pending_flows_are_bounded_and_pruned(self) -> None:
        auth = await self.make_auth()
        auth.max_flows = 3
        states = [(await self.start_login(auth, Browser()))[0] for _ in range(5)]
        self.assertEqual(list(auth.flows), states[2:])

        for flow in auth.flows.values():
            flow["expires"] = time.monotonic() - 1
        browser = Browser()
        # Pruning is lazy: not before PRUNE_INTERVAL has passed.
        await auth.callback(browser.request("/auth/callback", "state=unknown"), self.users)
        self.assertEqual(len(auth.flows), 3)
        auth.last_prune -= 61
        await auth.callback(browser.request("/auth/callback", "state=unknown"), self.users)
        self.assertEqual(len(auth.flows), 0)

    async def test_browser_keeps_a_bounded_number_of_flow_cookies(self) -> None:
        auth = await self.make_auth()
        auth.max_browser_flows = 3
        browser = Browser()
        logins = [await self.start_login(auth, browser) for _ in range(5)]
        self.assertEqual(len(browser.flow_cookies()), 3)

        oldest = browser.request("/auth/callback", urlencode({"code": "code", "state": logins[0][0]}))
        response = browser.receive(await auth.callback(oldest, self.users))
        self.assertEqual(response.headers["location"], "/")
        self.assertNotIn(OnlyWebAuth.cookie, browser.cookies)
        self.assertEqual(self.idp.token_requests, [])
        await self.finish_login(auth, browser, *logins[-1])
        self.assertEqual(await auth.user_id(browser.request("/")), LOCAL_ID)


class HardeningTests(OnlyWebAuthTestCase):
    async def test_login_starts_share_a_global_rate_limit(self) -> None:
        auth = await self.make_auth()
        for _ in range(30):
            await self.start_login(auth, Browser())
        await self.assert_auth_error(
            auth.login(Browser().request("/auth/login")), 429, "rate_limited"
        )
        # The budget refills over time.
        auth.login_refilled -= 60
        await self.start_login(auth, Browser())

    async def test_unconfigured_login_is_unavailable_before_the_rate_limit(self) -> None:
        with mock.patch.dict(os.environ, {"NAIWEAVER_AUTH_ISSUER": ""}):
            auth = OnlyWebAuth(PUBLIC_URL, 3600, lambda: sqlite3.connect(self.session_db))
        self.addAsyncCleanup(auth.aclose)
        await self.assert_auth_error(
            auth.login(Browser().request("/auth/login")), 503, "auth_unavailable"
        )

    async def test_expired_flow_is_refused_even_before_pruning(self) -> None:
        auth = await self.make_auth()
        browser = Browser()
        state, nonce = await self.start_login(auth, browser)
        auth.flows[state]["expires"] = time.monotonic() - 1
        response = await self.finish_login(auth, browser, state, nonce)
        self.assertEqual(response.headers["location"], "/")
        self.assertNotIn(OnlyWebAuth.cookie, browser.cookies)

    async def test_unknown_signing_key_keeps_the_session(self) -> None:
        auth = await self.make_auth()
        browser = await self.signed_in(auth)
        self.expire_access(auth)
        self.idp.key_id = "rotated"
        reply = self.idp.tokens("rt-2")
        self.idp.token_replies.append(reply)
        await self.assert_auth_error(auth.user_id(browser.request("/")), 503, "auth_unavailable")
        self.assertEqual(self.refresh_tokens(auth), ["rt-1"])

        self.idp.key_id = "k1"
        self.idp.token_replies.append(self.idp.tokens("rt-2"))
        self.assertEqual(await auth.user_id(browser.request("/")), LOCAL_ID)

    async def test_refresh_token_is_encrypted_and_bound_to_the_client_secret(self) -> None:
        auth = await self.make_auth()
        browser = await self.signed_in(auth)
        stored = auth.db.execute("SELECT refresh_token FROM only_webauth_sessions").fetchone()[0]
        self.assertNotIn("rt-1", stored)
        self.assertEqual(self.refresh_tokens(auth), ["rt-1"])

        with open(self.secret_file, "w") as handle:
            handle.write("another-secret\n")
        changed = await self.make_auth()
        self.expire_access(changed)
        await self.assert_auth_error(changed.user_id(browser.request("/")), 401, "not_authenticated")
        self.assertEqual(changed.db.execute("SELECT COUNT(*) FROM only_webauth_sessions").fetchone()[0], 0)
        self.assertEqual(
            [form["grant_type"] for form in self.idp.token_requests], ["authorization_code"]
        )


class ReturnToTests(OnlyWebAuthTestCase):
    def test_only_same_origin_relative_paths_are_kept(self) -> None:
        kept = ["/", "/?lang=en", "/gallery?lang=ja&tab=2", "/%2Fevil.example", "/a/b#c"]
        for value in kept:
            with self.subTest(value=value):
                self.assertEqual(safe_return_to(value), value)
        rejected = [
            None, "", "gallery", "//evil.example", "///evil.example", "/\\evil.example",
            "\\\\evil.example", "https://evil.example/", "javascript:alert(1)",
            "/\t/evil.example", "/ /evil.example", "/auth/login", "/auth/callback?state=x",
            "/%61uth/login", "/x/../auth/login", "/" + "a" * 3000,
        ]
        for value in rejected:
            with self.subTest(value=value):
                self.assertEqual(safe_return_to(value), "/")

    async def test_callback_returns_to_the_requested_page(self) -> None:
        auth = await self.make_auth()
        for return_to, expected in (("/?lang=en", "/?lang=en"), ("//evil.example", "/")):
            with self.subTest(return_to=return_to):
                browser = Browser()
                state, nonce = await self.start_login(auth, browser, return_to)
                response = await self.finish_login(auth, browser, state, nonce)
                self.assertEqual(response.headers["location"], expected)

    def test_login_location_carries_the_deep_link(self) -> None:
        page = Browser().request("/gallery", "lang=ja&tab=2")
        location = OnlyWebAuth.login_location(page)
        self.assertTrue(location.startswith("/auth/login?"))
        return_to = parse_qs(urlsplit(location).query)["return_to"][0]
        self.assertEqual(safe_return_to(return_to), "/gallery?lang=ja&tab=2")


class PersistenceTests(OnlyWebAuthTestCase):
    async def test_session_survives_a_new_instance(self) -> None:
        first = await self.make_auth()
        browser = await self.signed_in(first)
        await first.aclose()
        token_requests = len(self.idp.token_requests)

        second = await self.make_auth()
        self.assertEqual(await second.user_id(browser.request("/")), LOCAL_ID)
        self.assertEqual(len(self.idp.token_requests), token_requests)

        # Only a digest of the cookie is stored.
        session_id = browser.cookies[OnlyWebAuth.cookie]
        stored = [row["id"] for row in second.db.execute("SELECT id FROM only_webauth_sessions")]
        self.assertEqual(stored, [OnlyWebAuth.session_key(session_id)])

    async def test_unmapped_subject_loses_its_persisted_session(self) -> None:
        browser = await self.signed_in(await self.make_auth())
        self.subject_map = {}
        auth = await self.make_auth()
        await self.assert_auth_error(auth.user_id(browser.request("/")), 401, "not_authenticated")


if __name__ == "__main__":
    unittest.main()
