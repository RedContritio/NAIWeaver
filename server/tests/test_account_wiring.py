from __future__ import annotations

import tests  # noqa: F401  # isolates the data directories before app imports

import unittest
from unittest import mock


from app import admin, config, db as gwdb, security
from app.roles import POINT_TOTAL_FIELDS, role_defaults
from tests import support


class BootstrapTests(unittest.TestCase):
    def setUp(self) -> None:
        self.db = support.temporary_database(self)
        patcher = mock.patch.object(config, "BOOTSTRAP_TEST_USERS", True)
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_admin_password_update_keeps_point_totals(self) -> None:
        gwdb.bootstrap_users()
        self.db.execute(
            "UPDATE users SET red_points = 42, green_point_limit = 7, is_admin = 0, "
            "disabled = 1 WHERE username = 'admin'"
        )
        self.db.commit()
        with mock.patch.dict("os.environ", {"NAIWEAVER_ADMIN_PASSWORD": "new-secret"}):
            gwdb.bootstrap_users()
        admin = support.fetch_user(self.db, "admin")
        self.assertTrue(security.verify_password("new-secret", admin["password_hash"]))
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

    def test_promoting_to_admin_pins_the_discount(self) -> None:
        user = support.create_user(self.db, "member", green_point_discount=20)
        updated = admin.admin_update_user(
            user["id"], admin.UserUpdateRequest(is_admin=True), self.admin, self.db
        )
        self.assertEqual(updated["user"]["green_point_discount"], 100)


if __name__ == "__main__":
    unittest.main()
