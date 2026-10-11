"""Per-role account defaults. Every place that creates or re-roles a user reads
them from here so the rules cannot drift apart."""

from __future__ import annotations

import os

DEFAULT_GREEN_POINT_LIMIT = int(os.environ.get("NAIWEAVER_GREEN_POINT_LIMIT", "4000"))
DEFAULT_RED_POINTS = int(os.environ.get("NAIWEAVER_RED_POINTS", "3000"))
DEFAULT_ADMIN_RED_POINTS = int(os.environ.get("NAIWEAVER_ADMIN_RED_POINTS", "5000"))

ROLES = ("free", "paid", "admin")

# Point totals are balances: a role grants them once when the user is created.
# Changing an existing user's role must not reset them.
POINT_TOTAL_FIELDS = frozenset({"green_point_limit", "red_points"})


def role_defaults(role: str) -> dict[str, int]:
    if role not in ROLES:
        raise ValueError(f"Unknown role: {role}")
    admin = role == "admin"
    paid = role != "free"
    return {
        "is_admin": int(admin),
        "green_point_discount": 100 if admin else 0,
        "can_generate_paid": int(paid),
        "can_text_generate": 1,
        # Upscale, augment and vibe encoding are charged in red points.
        "can_image_upscale": int(paid),
        "can_image_augment": int(paid),
        "can_image_encode_vibe": int(paid),
        "green_point_limit": DEFAULT_GREEN_POINT_LIMIT,
        "red_points": (
            DEFAULT_ADMIN_RED_POINTS if admin else DEFAULT_RED_POINTS if paid else 0
        ),
    }
