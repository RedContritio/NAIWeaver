from __future__ import annotations

import tests  # noqa: F401  # isolates the data directories before app imports

import unittest
from unittest import mock


from app import admin, config, db as gwdb
from app.roles import role_defaults
from tests import support


class BootstrapTests(unittest.TestCase):
    def setUp(self) -> None:
        self.db = support.temporary_database(self)
        patcher = mock.patch.object(config, "BOOTSTRAP_TEST_USERS", True)
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_bootstrap_creates_passwordless_role_users_once(self) -> None:
        gwdb.bootstrap_users()
        self.db.execute("UPDATE users SET red_points = 42 WHERE username = 'admin'")
        self.db.commit()
        gwdb.bootstrap_users()
        rows = {row["username"]: row for row in self.db.execute("SELECT * FROM users")}
        self.assertEqual(set(rows), {"admin", "free_user", "paid_user"})
        self.assertTrue(all(row["password_hash"] == "" for row in rows.values()))
        self.assertEqual(rows["admin"]["is_admin"], 1)
        self.assertEqual(rows["paid_user"]["can_generate_paid"], 1)
        self.assertEqual(rows["admin"]["red_points"], 42)


class AdminUserTests(unittest.TestCase):
    def setUp(self) -> None:
        self.db = support.temporary_database(self)
        self.admin = support.create_user(self.db, "root", "admin")

    def create(self, **fields):
        admin.admin_create_user(admin.UserCreateRequest(**fields), self.admin, self.db)
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

    def test_created_users_have_no_password_and_the_field_is_rejected(self) -> None:
        user = self.create(username="nopass")
        self.assertEqual(user["password_hash"], "")
        with self.assertRaises(ValueError):
            admin.UserCreateRequest(username="x", password="secret")
        with self.assertRaises(ValueError):
            admin.UserUpdateRequest(password="secret")

    def test_promoting_to_admin_pins_the_discount(self) -> None:
        user = support.create_user(self.db, "member", green_point_discount=20)
        updated = admin.admin_update_user(
            user["id"], admin.UserUpdateRequest(is_admin=True), self.admin, self.db
        )
        self.assertEqual(updated["user"]["green_point_discount"], 100)


if __name__ == "__main__":
    unittest.main()
