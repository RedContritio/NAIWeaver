"""End-to-end wiring through the full ASGI stack (routing, middleware, handlers)."""

from __future__ import annotations

import tests  # noqa: F401  # isolates the data directories before app imports

from unittest import mock
import unittest
from urllib.parse import parse_qs, urlsplit

from fastapi.testclient import TestClient

from app import auth, db as gwdb, main
from tests import support


class AsgiWiringTests(unittest.TestCase):
    def setUp(self) -> None:
        self.db = support.temporary_database(self)
        self.user = support.create_user(self.db, "tool-user", "paid")
        # No lifespan: the app is exercised without its workers or upstream.
        self.client = TestClient(main.app, follow_redirects=False)
        self.addCleanup(self.client.close)

    def sign_in(self) -> None:
        for name, value in support.session_cookies(self.db, self.user).items():
            self.client.cookies.set(name, value)

    def tool_post(self, path: str, headers: dict[str, str]):
        return self.client.post(f"/api/nai/image/{path}", content=b"{}", headers=headers)

    def test_tool_requests_need_the_contract_headers(self) -> None:
        self.sign_in()
        cases = [
            ({}, 400, "invalid_parameters", "Idempotency-Key"),
            ({"Idempotency-Key": "short"}, 400, "invalid_parameters", "Idempotency-Key"),
            ({"Idempotency-Key": "long-enough-key"}, 400, "invalid_parameters",
             "X-NAIWeaver-Expected-Points"),
            ({"Idempotency-Key": "long-enough-key", "X-NAIWeaver-Expected-Points": "ten"},
             400, "invalid_parameters", "X-NAIWeaver-Expected-Points"),
        ]
        for headers, status_code, code, field in cases:
            with self.subTest(headers=headers):
                response = self.tool_post("ai/upscale", headers)
                self.assertEqual(response.status_code, status_code)
                detail = response.json()["detail"]
                self.assertEqual((detail["code"], detail["field"]), (code, field))

        response = self.tool_post(
            "ai/upscale",
            {"Idempotency-Key": "long-enough-key", "X-NAIWeaver-Expected-Points": "9"},
        )
        self.assertEqual(response.status_code, 409)
        detail = response.json()["detail"]
        self.assertEqual(detail["code"], "quote_changed")
        self.assertEqual((detail["quote"]["mode"], detail["quote"]["points"]), ("paid", 10))

    def test_tool_requests_need_a_session(self) -> None:
        response = self.tool_post("ai/upscale", {})
        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.json()["detail"]["code"], "not_authenticated")

    def test_login_without_an_identity_provider_is_unavailable(self) -> None:
        response = self.client.get("/auth/login")
        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.json()["detail"]["code"], "auth_unavailable")

    def test_signed_out_page_loads_redirect_to_login_with_return_to(self) -> None:
        with mock.patch.object(auth.only_auth, "enabled", True), mock.patch.object(
            auth.only_auth, "connect", gwdb.db_connect
        ), mock.patch.object(auth.only_auth, "_db", None):
            response = self.client.get("/gallery", params={"tab": "2"})
            self.addCleanup(auth.only_auth._db.close)
        self.assertEqual(response.status_code, 302)
        location = urlsplit(response.headers["location"])
        self.assertEqual(location.path, "/auth/login")
        self.assertEqual(parse_qs(location.query), {"return_to": ["/gallery?tab=2"]})
        self.assertEqual(response.headers["cache-control"], "no-store")

    def test_unknown_api_paths_are_json_errors_not_redirects(self) -> None:
        with mock.patch.object(auth.only_auth, "enabled", True):
            response = self.client.get("/api/nope")
        self.assertEqual(response.status_code, 404)
        self.assertEqual(response.json()["detail"]["code"], "not_found")


if __name__ == "__main__":
    unittest.main()
