from __future__ import annotations

import tests  # noqa: F401  # isolates the data directories before app imports

import unittest
from unittest import mock

from fastapi.testclient import TestClient

from app import auth, config, db as gwdb, main
from tests import support


class DevUserTests(unittest.TestCase):
    def setUp(self) -> None:
        self.db = support.temporary_database(self)
        support.create_user(self.db, "dev", "admin")
        for name, value in (("DEV_USER", "dev"), ("PRODUCTION", False)):
            patcher = mock.patch.object(config, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        patcher = mock.patch.object(auth.only_auth, "enabled", False)
        patcher.start()
        self.addCleanup(patcher.stop)

    def client(self, host: str) -> TestClient:
        client = TestClient(main.app, client=(host, 50000), follow_redirects=False)
        self.addCleanup(client.close)
        return client

    def test_loopback_clients_are_signed_in_as_the_dev_user(self) -> None:
        for host in ("127.0.0.1", "::1"):
            with self.subTest(host=host):
                response = self.client(host).get("/api/me")
                self.assertEqual(response.status_code, 200)
                self.assertEqual(response.json()["user"]["username"], "dev")

    def test_other_addresses_cannot_use_the_dev_user(self) -> None:
        for host in ("192.168.1.20", "10.0.0.2", "testclient"):
            with self.subTest(host=host):
                response = self.client(host).get("/api/me")
                self.assertEqual(response.status_code, 401)
                self.assertEqual(response.json()["detail"]["code"], "not_authenticated")

    def test_without_a_dev_user_the_error_names_the_setting(self) -> None:
        with mock.patch.object(config, "DEV_USER", ""):
            response = self.client("127.0.0.1").get("/api/me")
        self.assertEqual(response.status_code, 401)
        self.assertIn("NAIWEAVER_DEV_USER", response.json()["detail"]["message"])

    def test_unknown_or_disabled_dev_user_is_rejected(self) -> None:
        with mock.patch.object(config, "DEV_USER", "ghost"):
            self.assertEqual(self.client("127.0.0.1").get("/api/me").status_code, 401)
        self.db.execute("UPDATE users SET disabled = 1 WHERE username = 'dev'")
        self.db.commit()
        self.assertEqual(self.client("127.0.0.1").get("/api/me").status_code, 401)

    def test_it_is_ignored_when_only_webauth_is_enabled(self) -> None:
        with mock.patch.object(auth.only_auth, "enabled", True), mock.patch.object(
            auth.only_auth, "connect", gwdb.db_connect
        ), mock.patch.object(auth.only_auth, "_db", None):
            response = self.client("127.0.0.1").get("/api/me")
            if auth.only_auth._db is not None:
                self.addCleanup(auth.only_auth._db.close)
        self.assertEqual(response.status_code, 401)

    def test_it_is_ignored_in_production(self) -> None:
        with mock.patch.object(config, "PRODUCTION", True):
            self.assertEqual(self.client("127.0.0.1").get("/api/me").status_code, 401)

    def test_production_refuses_to_start_with_a_dev_user(self) -> None:
        with mock.patch.object(config, "PRODUCTION", True), mock.patch.object(
            auth.only_auth, "enabled", True
        ):
            with self.assertRaisesRegex(RuntimeError, "NAIWEAVER_DEV_USER"):
                auth.validate_runtime_config()
            with mock.patch.object(config, "DEV_USER", ""):
                auth.validate_runtime_config()

    def test_development_starts_with_or_without_a_dev_user(self) -> None:
        auth.validate_runtime_config()
        with mock.patch.object(config, "DEV_USER", ""):
            auth.validate_runtime_config()

    def test_logout_succeeds_for_the_dev_user(self) -> None:
        response = self.client("127.0.0.1").post("/api/logout")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"ok": True})

    def test_password_login_is_gone(self) -> None:
        response = self.client("127.0.0.1").post(
            "/api/login", json={"username": "dev", "password": "x"}
        )
        self.assertEqual(response.status_code, 404)
        self.assertEqual(response.json()["detail"]["code"], "not_found")

    def test_dev_user_pages_do_not_redirect_to_an_identity_provider(self) -> None:
        response = self.client("127.0.0.1").get("/gallery")
        self.assertNotEqual(response.status_code, 302)


if __name__ == "__main__":
    unittest.main()
