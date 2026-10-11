from __future__ import annotations

import tests  # noqa: F401  # isolates the data directories before app imports

import unittest
from unittest import mock
from urllib.parse import parse_qs, urlsplit

import httpx

from app import main
from app.roles import POINT_TOTAL_FIELDS, role_defaults
from tests import support


class BootstrapTests(unittest.TestCase):
    def setUp(self) -> None:
        self.db = support.temporary_database(self)
        patcher = mock.patch.object(main, "BOOTSTRAP_TEST_USERS", True)
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_sample_users_get_their_role_defaults(self) -> None:
        main.bootstrap_users()
        for username, role in (("admin", "admin"), ("free_user", "free"), ("paid_user", "paid")):
            user = support.fetch_user(self.db, username)
            for name, value in role_defaults(role).items():
                self.assertEqual(user[name], value, f"{username}.{name}")

    def test_admin_password_update_keeps_point_totals(self) -> None:
        main.bootstrap_users()
        self.db.execute(
            "UPDATE users SET red_points = 42, green_point_limit = 7, is_admin = 0, "
            "disabled = 1 WHERE username = 'admin'"
        )
        self.db.commit()
        with mock.patch.dict("os.environ", {"NAIWEAVER_ADMIN_PASSWORD": "new-secret"}):
            main.bootstrap_users()
        admin = support.fetch_user(self.db, "admin")
        self.assertTrue(main.verify_password("new-secret", admin["password_hash"]))
        self.assertEqual(admin["is_admin"], 1)
        self.assertEqual(admin["disabled"], 0)
        self.assertEqual(admin["green_point_discount"], 100)
        for name in POINT_TOTAL_FIELDS:
            self.assertNotEqual(admin[name], role_defaults("admin")[name])
        self.assertEqual((admin["red_points"], admin["green_point_limit"]), (42, 7))


class AdminUserTests(unittest.TestCase):
    def setUp(self) -> None:
        self.db = support.temporary_database(self)
        self.admin = support.create_user(self.db, "root", "admin")

    def create(self, **fields):
        main.admin_create_user(main.UserCreateRequest(**fields), self.admin, self.db)
        return support.fetch_user(self.db, fields["username"])

    def test_admin_role_gets_admin_points_and_discount(self) -> None:
        user = self.create(username="boss", role="admin", green_point_discount=10)
        self.assertEqual(user["is_admin"], 1)
        self.assertEqual(user["green_point_discount"], 100)
        self.assertEqual(user["red_points"], role_defaults("admin")["red_points"])

    def test_explicit_fields_override_the_role(self) -> None:
        user = self.create(username="p", role="paid", red_points=5, can_image_upscale=False)
        self.assertEqual(user["red_points"], 5)
        self.assertEqual(user["can_image_upscale"], 0)
        self.assertEqual(user["can_generate_paid"], 1)

    def test_default_role_is_free(self) -> None:
        user = self.create(username="f")
        for name, value in role_defaults("free").items():
            self.assertEqual(user[name], value, name)

    def test_promoting_to_admin_pins_the_discount(self) -> None:
        user = support.create_user(self.db, "member", green_point_discount=20)
        updated = main.admin_update_user(
            user["id"], main.UserUpdateRequest(is_admin=True), self.admin, self.db
        )
        self.assertEqual(updated["user"]["green_point_discount"], 100)


class WebAuthWiringTests(unittest.IsolatedAsyncioTestCase):
    def client(self) -> httpx.AsyncClient:
        client = httpx.AsyncClient(
            transport=httpx.ASGITransport(app=main.app), base_url="http://testserver"
        )
        self.addAsyncCleanup(client.aclose)
        return client

    async def test_unauthenticated_page_redirects_with_return_to(self) -> None:
        support.temporary_database(self)
        with mock.patch.object(main.only_auth, "enabled", True):
            response = await self.client().get("/gallery?tab=2")
        self.assertEqual(response.status_code, 302)
        self.assertEqual(response.headers["cache-control"], "no-store")
        location = urlsplit(response.headers["location"])
        self.assertEqual(location.path, "/auth/login")
        self.assertEqual(parse_qs(location.query)["return_to"], ["/gallery?tab=2"])

    async def test_sessions_are_stored_in_the_gateway_database(self) -> None:
        db = support.temporary_database(self)
        with mock.patch.object(main.only_auth, "_db", None):
            session_db = main.only_auth.db
            session_db.close()
        tables = {row[0] for row in db.execute("SELECT name FROM sqlite_master")}
        self.assertIn("only_webauth_sessions", tables)

    async def test_login_without_idp_is_a_contract_503(self) -> None:
        response = await self.client().get("/auth/login")
        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.json()["detail"]["code"], "auth_unavailable")


if __name__ == "__main__":
    unittest.main()
