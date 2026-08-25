from __future__ import annotations

import argparse
from datetime import datetime, timedelta, timezone
import secrets

from .main import (
    DEFAULT_ADMIN_RED_POINTS,
    DEFAULT_GREEN_POINT_LIMIT,
    DEFAULT_RED_POINTS,
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
            "green_point_discount": 100,
            "can_generate_paid": 1,
            "can_text_generate": 1,
            "can_image_upscale": 1,
            "can_image_augment": 1,
            "can_image_encode_vibe": 1,
            "green_point_limit": DEFAULT_GREEN_POINT_LIMIT,
            "red_points": DEFAULT_ADMIN_RED_POINTS,
        }
    if role == "paid":
        return {
            "is_admin": 0,
            "green_point_discount": 0,
            "can_generate_paid": 1,
            "can_text_generate": 1,
            "can_image_upscale": 1,
            "can_image_augment": 1,
            "can_image_encode_vibe": 1,
            "green_point_limit": DEFAULT_GREEN_POINT_LIMIT,
            "red_points": DEFAULT_RED_POINTS,
        }
    return {
        "is_admin": 0,
        "green_point_discount": 0,
        "can_generate_paid": 0,
        "can_text_generate": 1,
        "can_image_upscale": 0,
        "can_image_augment": 0,
        "can_image_encode_vibe": 0,
        "green_point_limit": DEFAULT_GREEN_POINT_LIMIT,
        "red_points": 0,
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
                SET is_admin = ?, disabled = 0, green_point_discount = ?,
                    can_generate_paid = ?, can_text_generate = ?,
                    can_image_upscale = ?, can_image_augment = ?,
                    can_image_encode_vibe = ?, green_point_limit = ?,
                    red_points = ?
                WHERE username = ?
                """,
                (
                    defaults["is_admin"],
                    defaults["green_point_discount"],
                    defaults["can_generate_paid"],
                    defaults["can_text_generate"],
                    defaults["can_image_upscale"],
                    defaults["can_image_augment"],
                    defaults["can_image_encode_vibe"],
                    defaults["green_point_limit"],
                    defaults["red_points"],
                    args.username,
                ),
            )
            action = "updated"
        else:
            db.execute(
                """
                INSERT INTO users(
                  username, password_hash, is_admin, disabled,
                  green_point_discount, can_generate_paid, can_text_generate,
                  can_image_upscale, can_image_augment, can_image_encode_vibe,
                  green_point_limit, red_points,
                  green_point_used, red_points_used, created_at
                )
                VALUES (?, ?, ?, 0, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0, ?)
                """,
                (
                    args.username,
                    password_hash,
                    defaults["is_admin"],
                    defaults["green_point_discount"],
                    defaults["can_generate_paid"],
                    defaults["can_text_generate"],
                    defaults["can_image_upscale"],
                    defaults["can_image_augment"],
                    defaults["can_image_encode_vibe"],
                    defaults["green_point_limit"],
                    defaults["red_points"],
                    now_iso(),
                ),
            )
            action = "created"
        db.commit()
    print(f"{action}: {args.username} ({args.role})")


def user_row_or_exit(db, username: str):
    user = db.execute("SELECT * FROM users WHERE username = ?", (username,)).fetchone()
    if not user:
        raise SystemExit(f"User not found: {username}")
    return user


def cmd_user_state(args: argparse.Namespace) -> None:
    init_db()
    disabled = int(args.state == "disable")
    with db_connect() as db:
        user_row_or_exit(db, args.username)
        db.execute("UPDATE users SET disabled = ? WHERE username = ?", (disabled, args.username))
        db.commit()
    print(f"{args.state}d: {args.username}")


def cmd_green_discount(args: argparse.Namespace) -> None:
    init_db()
    discount = max(0, min(100, int(args.percent)))
    with db_connect() as db:
        user_row_or_exit(db, args.username)
        db.execute(
            "UPDATE users SET green_point_discount = ? WHERE username = ?",
            (discount, args.username),
        )
        db.commit()
    print(f"green point discount for {args.username}: {discount}%")


def cmd_points_show(args: argparse.Namespace) -> None:
    init_db()
    with db_connect() as db:
        user = user_row_or_exit(db, args.username)
        green_limit = int(user["green_point_limit"])
        green_used = int(user["green_point_used"])
        green_discount = int(user["green_point_discount"])
        red_limit = int(user["red_points"] or 0)
        red_used = int(user["red_points_used"])
    print(f"user: {args.username}")
    if green_discount < 100:
        print(f"green: {max(0, green_limit - green_used)} remaining / {green_limit} total")
        print(f"green discount: {green_discount}%")
    print(f"red: {max(0, red_limit - red_used)} remaining / {red_limit} total")


def cmd_points_grant(args: argparse.Namespace) -> None:
    red = max(0, int(args.red))
    if red == 0:
        raise SystemExit("Specify a positive --red amount")
    init_db()
    with db_connect() as db:
        user = user_row_or_exit(db, args.username)
        red_limit = int(user["red_points"] or 0)
        db.execute(
            "UPDATE users SET red_points = ? WHERE id = ?",
            (red_limit + red, user["id"]),
        )
        db.commit()
    print(f"granted to {args.username}: red +{red}")


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

    for state in ("enable", "disable"):
        state_parser = user_sub.add_parser(state)
        state_parser.add_argument("username")
        state_parser.set_defaults(func=cmd_user_state, state=state)

    green_discount = user_sub.add_parser("green-discount")
    green_discount.add_argument("username")
    green_discount.add_argument("--percent", type=int, required=True)
    green_discount.set_defaults(func=cmd_green_discount)

    points = user_sub.add_parser("points")
    points_sub = points.add_subparsers(dest="points_command", required=True)
    points_show = points_sub.add_parser("show")
    points_show.add_argument("username")
    points_show.set_defaults(func=cmd_points_show)
    points_grant = points_sub.add_parser("grant")
    points_grant.add_argument("username")
    points_grant.add_argument("--red", type=int, default=0)
    points_grant.set_defaults(func=cmd_points_grant)

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
