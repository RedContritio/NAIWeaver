from __future__ import annotations

import argparse
from datetime import datetime, timedelta, timezone
import secrets

from .main import (
    DEFAULT_ADMIN_POINT_LIMIT,
    DEFAULT_FREE_DAILY_LIMIT,
    DEFAULT_PAID_POINT_LIMIT,
    PUBLIC_BASE_URL,
    db_connect,
    hash_password,
    init_db,
    now_iso,
    token_hash,
)


def parse_ttl(value: str) -> timedelta:
    value = value.strip().lower()
    if not value:
        raise argparse.ArgumentTypeError("TTL is required")
    suffix = value[-1]
    number = value[:-1] if suffix in {"s", "m", "h", "d"} else value
    try:
        amount = int(number)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("TTL must be like 10m, 1h, or 600s") from exc
    if amount <= 0:
        raise argparse.ArgumentTypeError("TTL must be positive")
    if suffix == "s":
        return timedelta(seconds=amount)
    if suffix == "m":
        return timedelta(minutes=amount)
    if suffix == "h":
        return timedelta(hours=amount)
    if suffix == "d":
        return timedelta(days=amount)
    return timedelta(seconds=amount)


def role_defaults(role: str) -> dict[str, object]:
    if role == "admin":
        return {
            "is_admin": 1,
            "can_generate_free": 1,
            "can_generate_paid": 1,
            "can_text_generate": 1,
            "can_image_upscale": 1,
            "can_image_augment": 1,
            "can_image_encode_vibe": 1,
            "daily_limit": None,
            "paid_daily_limit": None,
            "paid_point_limit": DEFAULT_ADMIN_POINT_LIMIT,
        }
    if role == "paid":
        return {
            "is_admin": 0,
            "can_generate_free": 1,
            "can_generate_paid": 1,
            "can_text_generate": 1,
            "can_image_upscale": 1,
            "can_image_augment": 1,
            "can_image_encode_vibe": 1,
            "daily_limit": None,
            "paid_daily_limit": None,
            "paid_point_limit": DEFAULT_PAID_POINT_LIMIT,
        }
    return {
        "is_admin": 0,
        "can_generate_free": 1,
        "can_generate_paid": 0,
        "can_text_generate": 1,
        "can_image_upscale": 0,
        "can_image_augment": 0,
        "can_image_encode_vibe": 0,
        "daily_limit": DEFAULT_FREE_DAILY_LIMIT,
        "paid_daily_limit": 0,
        "paid_point_limit": 0,
    }


def cmd_create_user(args: argparse.Namespace) -> None:
    init_db()
    defaults = role_defaults(args.role)
    with db_connect() as db:
        existing = db.execute(
            "SELECT id FROM users WHERE username = ?", (args.username,)
        ).fetchone()
        if existing and not args.update:
            raise SystemExit(f"User already exists: {args.username}")
        password_hash = hash_password(secrets.token_urlsafe(32))
        if existing:
            db.execute(
                """
                UPDATE users
                SET is_admin = ?, disabled = 0, can_generate_free = ?,
                    can_generate_paid = ?, can_text_generate = ?,
                    can_image_upscale = ?, can_image_augment = ?,
                    can_image_encode_vibe = ?, daily_limit = ?,
                    paid_daily_limit = ?, paid_point_limit = ?
                WHERE username = ?
                """,
                (
                    defaults["is_admin"],
                    defaults["can_generate_free"],
                    defaults["can_generate_paid"],
                    defaults["can_text_generate"],
                    defaults["can_image_upscale"],
                    defaults["can_image_augment"],
                    defaults["can_image_encode_vibe"],
                    defaults["daily_limit"],
                    defaults["paid_daily_limit"],
                    defaults["paid_point_limit"],
                    args.username,
                ),
            )
            action = "updated"
        else:
            db.execute(
                """
                INSERT INTO users(
                  username, password_hash, is_admin, disabled,
                  can_generate_free, can_generate_paid, can_text_generate,
                  can_image_upscale, can_image_augment, can_image_encode_vibe,
                  daily_limit, paid_daily_limit, paid_point_limit,
                  paid_point_used, created_at
                )
                VALUES (?, ?, ?, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?)
                """,
                (
                    args.username,
                    password_hash,
                    defaults["is_admin"],
                    defaults["can_generate_free"],
                    defaults["can_generate_paid"],
                    defaults["can_text_generate"],
                    defaults["can_image_upscale"],
                    defaults["can_image_augment"],
                    defaults["can_image_encode_vibe"],
                    defaults["daily_limit"],
                    defaults["paid_daily_limit"],
                    defaults["paid_point_limit"],
                    now_iso(),
                ),
            )
            action = "created"
        db.commit()
    print(f"{action}: {args.username} ({args.role})")


def cmd_bind(args: argparse.Namespace) -> None:
    init_db()
    base_url = (args.base_url or PUBLIC_BASE_URL).rstrip("/")
    raw_token = secrets.token_urlsafe(32)
    expires_at = datetime.now(timezone.utc) + args.ttl
    with db_connect() as db:
        user = db.execute(
            "SELECT * FROM users WHERE username = ?", (args.username,)
        ).fetchone()
        if not user:
            raise SystemExit(f"User not found: {args.username}")
        if user["disabled"]:
            raise SystemExit(f"User is disabled: {args.username}")
        db.execute(
            """
            INSERT INTO webauthn_enrollment_tokens(
              token_hash, user_id, expires_at, created_at
            )
            VALUES (?, ?, ?, ?)
            """,
            (token_hash(raw_token), user["id"], expires_at.isoformat(), now_iso()),
        )
        db.commit()
    print(f"bind link for {args.username}:")
    print(f"{base_url}/enroll?token={raw_token}")
    print(f"expires_at: {expires_at.isoformat()}")


def cmd_reset(args: argparse.Namespace) -> None:
    init_db()
    with db_connect() as db:
        user = db.execute(
            "SELECT * FROM users WHERE username = ?", (args.username,)
        ).fetchone()
        if not user:
            raise SystemExit(f"User not found: {args.username}")
        db.execute(
            "UPDATE webauthn_credentials SET disabled = 1 WHERE user_id = ?",
            (user["id"],),
        )
        db.commit()
    print(f"disabled webauthn credentials: {args.username}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="python -m app.cli")
    sub = parser.add_subparsers(dest="command", required=True)

    user = sub.add_parser("user")
    user_sub = user.add_subparsers(dest="user_command", required=True)
    create = user_sub.add_parser("create")
    create.add_argument("username")
    create.add_argument("--role", choices=["free", "paid", "admin"], default="free")
    create.add_argument("--update", action="store_true")
    create.set_defaults(func=cmd_create_user)

    webauthn = sub.add_parser("webauthn")
    webauthn_sub = webauthn.add_subparsers(dest="webauthn_command", required=True)
    bind = webauthn_sub.add_parser("bind")
    bind.add_argument("username")
    bind.add_argument("--ttl", type=parse_ttl, default=timedelta(minutes=10))
    bind.add_argument("--base-url")
    bind.set_defaults(func=cmd_bind)

    reset = webauthn_sub.add_parser("reset")
    reset.add_argument("username")
    reset.set_defaults(func=cmd_reset)

    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
