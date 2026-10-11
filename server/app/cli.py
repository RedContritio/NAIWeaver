from __future__ import annotations

import argparse
from contextlib import closing
import secrets

from .db import db_connect, init_db, now_iso
from .security import hash_password
from .roles import POINT_TOTAL_FIELDS, ROLES, role_defaults


def cmd_create_user(args: argparse.Namespace) -> None:
    init_db()
    with closing(db_connect()) as db:
        existing = db.execute(
            "SELECT id FROM users WHERE username = ?", (args.username,)
        ).fetchone()
        if existing and not args.update:
            raise SystemExit(f"User already exists: {args.username}")
        if existing:
            # Change only what was passed: a role re-applies its permissions,
            # while point totals (including earlier grants) stay as they are.
            changes = {}
            if args.role:
                changes.update(
                    (name, value)
                    for name, value in role_defaults(args.role).items()
                    if name not in POINT_TOTAL_FIELDS
                )
            if args.green_points is not None:
                changes["green_point_limit"] = args.green_points
            if not changes:
                print(f"unchanged: {args.username}")
                return
            assignments = ", ".join(f"{name} = ?" for name in changes)
            db.execute(
                f"UPDATE users SET {assignments} WHERE id = ?",
                (*changes.values(), existing["id"]),
            )
            db.commit()
            print(f"updated: {args.username} ({', '.join(changes)})")
            return
        role = args.role or "free"
        values = role_defaults(role)
        if args.green_points is not None:
            values["green_point_limit"] = args.green_points
        columns = {
            "username": args.username,
            "password_hash": hash_password(secrets.token_urlsafe(32)),
            **values,
            "created_at": now_iso(),
        }
        db.execute(
            f"INSERT INTO users({', '.join(columns)}) "
            f"VALUES ({', '.join('?' for _ in columns)})",
            tuple(columns.values()),
        )
        db.commit()
    print(f"created: {args.username} ({role})")


def user_row_or_exit(db, username: str):
    user = db.execute("SELECT * FROM users WHERE username = ?", (username,)).fetchone()
    if not user:
        raise SystemExit(f"User not found: {username}")
    return user


def cmd_user_state(args: argparse.Namespace) -> None:
    init_db()
    disabled = int(args.state == "disable")
    with closing(db_connect()) as db:
        user_row_or_exit(db, args.username)
        db.execute("UPDATE users SET disabled = ? WHERE username = ?", (disabled, args.username))
        db.commit()
    print(f"{args.state}d: {args.username}")


def cmd_green_discount(args: argparse.Namespace) -> None:
    init_db()
    discount = max(0, min(100, int(args.percent)))
    with closing(db_connect()) as db:
        user_row_or_exit(db, args.username)
        db.execute(
            "UPDATE users SET green_point_discount = ? WHERE username = ?",
            (discount, args.username),
        )
        db.commit()
    print(f"green point discount for {args.username}: {discount}%")


def cmd_points_show(args: argparse.Namespace) -> None:
    init_db()
    with closing(db_connect()) as db:
        user = user_row_or_exit(db, args.username)
        green_limit = int(user["green_point_limit"])
        green_used = int(user["green_point_used"])
        green_reserved = int(user["green_points_reserved"])
        green_discount = int(user["green_point_discount"])
        red_limit = int(user["red_points"] or 0)
        red_used = int(user["red_points_used"])
        red_reserved = int(user["red_points_reserved"])
    # Reserved points belong to queued or running work and cannot be spent again.
    print(f"user: {args.username}")
    if green_discount < 100:
        green_remaining = max(0, green_limit - green_used - green_reserved)
        print(
            f"green: {green_remaining} remaining / {green_limit} total"
            f" ({green_reserved} reserved)"
        )
        print(f"green discount: {green_discount}%")
    red_remaining = max(0, red_limit - red_used - red_reserved)
    print(f"red: {red_remaining} remaining / {red_limit} total ({red_reserved} reserved)")


def cmd_points_grant(args: argparse.Namespace) -> None:
    red = max(0, int(args.red))
    if red == 0:
        raise SystemExit("Specify a positive --red amount")
    init_db()
    with closing(db_connect()) as db:
        user_row_or_exit(db, args.username)
        db.execute(
            "UPDATE users SET red_points = COALESCE(red_points, 0) + ? WHERE username = ?",
            (red, args.username),
        )
        db.commit()
    print(f"granted to {args.username}: red +{red}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="python -m app.cli")
    sub = parser.add_subparsers(dest="command", required=True)

    user = sub.add_parser("user")
    user_sub = user.add_subparsers(dest="user_command", required=True)
    create = user_sub.add_parser("create")
    create.add_argument("username")
    create.add_argument(
        "--role",
        choices=ROLES,
        help="new users default to free; with --update, re-applies the role's permissions",
    )
    create.add_argument(
        "--green-points",
        type=lambda value: max(0, int(value)),
        help="override the role's permanent green-point total",
    )
    create.add_argument(
        "--update",
        action="store_true",
        help="update an existing user, changing only the options given",
    )
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

    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
