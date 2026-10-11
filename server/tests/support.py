"""Shared fixtures: a temporary gateway database, users and a fake NovelAI."""

from __future__ import annotations

import asyncio
from io import BytesIO
import json
from pathlib import Path
import secrets
import sqlite3
import tempfile
from typing import Any, Callable
import unittest
from unittest import mock
from zipfile import ZipFile

from fastapi import HTTPException
from starlette.requests import Request

from app import config, db as gwdb, generation, proxy, state, storage, users
from app.billing import classify_and_quote
from app.idempotency import ToolResponseCache
from app.security import create_jwt
from app.upstream_lane import UpstreamLane


USER_DEFAULTS: dict[str, Any] = {
    "is_admin": 0,
    "disabled": 0,
    "can_generate_paid": 0,
    "can_image_upscale": 1,
    "can_image_augment": 1,
    "can_image_encode_vibe": 1,
    "green_point_limit": 4000,
    "green_point_used": 0,
    "green_point_discount": 0,
    "red_points": 0,
    "red_points_used": 0,
}
ROLE_VALUES: dict[str, dict[str, Any]] = {
    "free": {},
    "paid": {"can_generate_paid": 1, "red_points": 1000},
    "admin": {
        "is_admin": 1,
        "can_generate_paid": 1,
        "green_point_discount": 100,
        "red_points": 5000,
    },
}


def temporary_database(testcase: unittest.TestCase) -> sqlite3.Connection:
    """Point the gateway at a fresh file database for one test."""
    directory = tempfile.TemporaryDirectory(prefix="naiweaver-db-")
    testcase.addCleanup(directory.cleanup)
    patcher = mock.patch.object(config, "DB_PATH", Path(directory.name) / "gateway.sqlite3")
    patcher.start()
    testcase.addCleanup(patcher.stop)
    db = gwdb.db_connect()
    testcase.addCleanup(db.close)
    db.executescript(gwdb.SCHEMA)
    gwdb.migrate_db(db)
    db.commit()
    return db


def create_user(
    db: sqlite3.Connection, username: str, role: str = "free", **values: Any
) -> sqlite3.Row:
    row = {**USER_DEFAULTS, **ROLE_VALUES[role], **values}
    columns = ["username", "password_hash", "created_at", *row]
    db.execute(
        f"INSERT INTO users({', '.join(columns)}) VALUES ({', '.join('?' for _ in columns)})",
        [username, "unused", gwdb.now_iso(), *row.values()],
    )
    db.commit()
    return fetch_user(db, username)


def fetch_user(db: sqlite3.Connection, username: str) -> sqlite3.Row:
    return db.execute("SELECT * FROM users WHERE username = ?", (username,)).fetchone()


def session_cookies(db: sqlite3.Connection, user: sqlite3.Row) -> dict[str, str]:
    session_id = secrets.token_urlsafe(12)
    db.execute(
        "INSERT INTO sessions(id, user_id, expires_at, created_at) VALUES (?, ?, ?, ?)",
        (session_id, user["id"], "2999-01-01T00:00:00+00:00", gwdb.now_iso()),
    )
    db.commit()
    token = create_jwt({"sub": int(user["id"]), "jti": session_id}, config.SECRET_KEY, 3600)
    return {"access_token": token}


def generation_request(*, action: str = "generate", **parameters: Any) -> dict[str, Any]:
    params: dict[str, Any] = {
        "width": 832,
        "height": 1216,
        "steps": 28,
        "scale": 5.0,
        "sampler": "k_euler_ancestral",
        "sm": False,
        "sm_dyn": False,
        "uc": "",
    }
    params.update(parameters)
    return {
        "input": "1girl",
        "model": "nai-diffusion-4-5-full",
        "action": action,
        "parameters": params,
    }


def quote_for(db: sqlite3.Connection, user: sqlite3.Row, request: dict[str, Any], images: int):
    _, quote = classify_and_quote(
        request, users.image_rules_for_user(db, user), images=images
    )
    return quote


def make_request(
    path: str,
    body: bytes = b"",
    *,
    method: str = "POST",
    headers: dict[str, str] | None = None,
) -> Request:
    delivered = False

    async def receive():
        nonlocal delivered
        if delivered:
            return {"type": "http.disconnect"}
        delivered = True
        return {"type": "http.request", "body": body, "more_body": False}

    raw_headers = [(b"content-type", b"application/json")]
    raw_headers += [
        (name.lower().encode("latin-1"), value.encode("latin-1"))
        for name, value in (headers or {}).items()
    ]
    return Request(
        {
            "type": "http",
            "method": method,
            "path": path,
            "query_string": b"",
            "headers": raw_headers,
            "client": ("127.0.0.1", 12345),
        },
        receive,
    )


async def submit(
    db: sqlite3.Connection,
    user: sqlite3.Row,
    request: dict[str, Any],
    seeds: list[int],
    *,
    expected: dict[str, Any] | None = None,
    client_request_id: str | None = None,
) -> dict[str, Any]:
    """Submit through the HTTP handler; the expected quote defaults to the
    server's own quote, as a client would display it."""
    if expected is None:
        quote = quote_for(db, user, request, len(seeds))
        expected = {"mode": quote.mode, "points": quote.points}
    body = json.dumps(
        {
            "client_request_id": client_request_id or secrets.token_hex(8),
            "request": request,
            "seeds": seeds,
            "expected_quote": expected,
        }
    ).encode()
    response = await generation.submit_generation_task(
        request=make_request("/api/generation-tasks", body), user=user, db=db
    )
    assert response.status_code == 202, response.status_code
    return json.loads(response.body)


def error_detail(raised: unittest.case._AssertRaisesContext) -> dict[str, Any]:
    exc = raised.exception
    assert isinstance(exc, HTTPException)
    assert isinstance(exc.detail, dict), exc.detail
    return exc.detail


def reset_queue_state() -> None:
    state.pending_jobs.clear()
    state.active_user_ids.clear()
    state.queue_condition = asyncio.Condition()
    state.queue_virtual_time = 0.0
    for queue_name in state.queue_last_finish:
        state.queue_last_finish[queue_name] = 0.0
    state.upstream_lane = UpstreamLane()
    state.tool_response_cache = ToolResponseCache()


def zipped_png() -> bytes:
    buffer = BytesIO()
    with ZipFile(buffer, "w") as archive:
        archive.writestr("image_0.png", storage.fake_png())
    return buffer.getvalue()


class FakeNovelAI:
    """Replaces ``forward_to_novelai`` and ``fetch_anlas_balance``.

    Successful image calls lower the Anlas balance by ``costs[path]``.
    ``gate`` (an asyncio.Event) holds every image call until it is set.
    """

    def __init__(self, testcase: unittest.TestCase, *, balance: int = 10_000) -> None:
        self.balance = balance
        self.balance_available = True
        self.costs: dict[str, int] = {}
        self.statuses: dict[str, int] = {}
        # Paths answered 200 with this body instead of a zipped image.
        self.contents: dict[str, bytes] = {}
        # The next balance read after a call reports the balance from before it.
        self.stale_reads = 0
        self.stale_balance: int | None = None
        self.calls: list[str] = []
        self.bodies: list[bytes] = []
        self.gate: asyncio.Event | None = None
        self.in_flight = 0
        self.max_in_flight = 0
        for name, replacement in (
            ("forward_to_novelai", self.forward),
            ("fetch_anlas_balance", self.fetch_balance),
        ):
            patcher = mock.patch.object(proxy, name, replacement)
            patcher.start()
            testcase.addCleanup(patcher.stop)

    async def forward(self, service: str, path: str, *, method: str, body: bytes = b"", stream: bool = False):
        self.calls.append(path)
        self.bodies.append(body)
        self.in_flight += 1
        self.max_in_flight = max(self.max_in_flight, self.in_flight)
        try:
            if self.gate is not None:
                await self.gate.wait()
            status = self.statuses.get(path, 200)
            if not 200 <= status < 300:
                return status, {"content-type": "application/json"}, b'{"message":"rejected"}'
            self.stale_balance = self.balance
            self.balance -= self.costs.get(path, 0)
            if path in self.contents:
                return status, {"content-type": "application/zip"}, self.contents[path]
            if path == "ai/encode-vibe":
                return status, {"content-type": "application/octet-stream"}, b"vibe-" + body[:16]
            return status, {"content-type": "application/zip"}, zipped_png()
        finally:
            self.in_flight -= 1

    async def fetch_balance(self, retries: int = 2) -> int | None:
        if not self.balance_available:
            return None
        if self.stale_reads and self.stale_balance is not None:
            self.stale_reads -= 1
            return self.stale_balance
        return self.balance


async def wait_until(predicate: Callable[[], bool], timeout: float = 5.0) -> None:
    loop = asyncio.get_running_loop()
    deadline = loop.time() + timeout
    while not predicate():
        if loop.time() > deadline:
            raise AssertionError("condition was not reached in time")
        await asyncio.sleep(0.005)


def item_rows(db: sqlite3.Connection, task_id: str) -> list[sqlite3.Row]:
    return db.execute(
        "SELECT t.*, e.error_code FROM generation_tasks t "
        "LEFT JOIN generation_item_errors e ON e.item_id = t.id "
        "WHERE t.batch_id = ? ORDER BY t.batch_index",
        (task_id,),
    ).fetchall()


def items_final(db: sqlite3.Connection, task_id: str) -> bool:
    rows = item_rows(db, task_id)
    return bool(rows) and all(row["status"] not in ("queued", "running") for row in rows)
