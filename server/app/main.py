from __future__ import annotations

import asyncio
import copy
import hashlib
from contextlib import asynccontextmanager, closing, contextmanager
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta, timezone
from io import BytesIO
import json
import logging
import os
from pathlib import Path
import re
import secrets
import sqlite3
import time
from typing import Any, Iterator, Literal
from zipfile import ZipFile

from fastapi import Depends, FastAPI, HTTPException, Request, Response, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse, RedirectResponse, StreamingResponse
import httpx
from pydantic import BaseModel, ConfigDict, Field
from .only_webauth import OnlyWebAuth
from .roles import (
    DEFAULT_ADMIN_RED_POINTS,
    DEFAULT_GREEN_POINT_LIMIT,
    DEFAULT_RED_POINTS,
    POINT_TOTAL_FIELDS,
    role_defaults,
)

from .billing import (
    ALLOWED_SAMPLERS,
    ANOMALY_FREE_ALLOWANCE_EXHAUSTED,
    ANOMALY_MEASURED_ABOVE_QUOTE,
    FREE_ALLOWANCE_COOLDOWN_SECONDS,
    MAX_DIMENSION,
    MAX_SEED,
    MAX_STEPS_ADMIN,
    MAX_STEPS_FREE,
    MAX_STEPS_PAID,
    TOOL_CAPS,
    Quote,
    build_image_rules,
    classify_and_quote,
    free_allowance_exhausted_until,
    green_point_discount_for,
    immediate_transaction,
    is_strict_int,
    point_kind_for_mode,
    record_billing_anomaly,
    release_points,
    remaining_points,
    reserve_points,
    settle_amount,
    settle_points,
    tool_quote,
)
from .body_limit import BodySizeLimitMiddleware
from .errors import (
    api_error,
    error_response,
    install_error_handlers,
    invalid_parameters,
    permission_denied,
    upstream_error,
)
from .idempotency import CachedResponse, ToolResponseCache
from .security import TokenError, create_jwt, decode_jwt, hash_password, verify_password
from .upstream_lane import FREE_PRIORITY, RED_PRIORITY, UpstreamLane


logger = logging.getLogger("uvicorn.error.naiweaver")

SERVER_DIR = Path(__file__).resolve().parents[1]
DATA_DIR = Path(os.environ.get("NAIWEAVER_DATA_DIR", SERVER_DIR / "data"))
DB_PATH = Path(os.environ.get("NAIWEAVER_DB_PATH", DATA_DIR / "naiweaver.sqlite3"))
IMAGE_DIR = Path(os.environ.get("NAIWEAVER_IMAGE_DIR", DATA_DIR / "images"))
THUMBNAIL_DIR = Path(os.environ.get("NAIWEAVER_THUMBNAIL_DIR", DATA_DIR / "thumbnails"))
AUDIT_DIR = Path(os.environ.get("NAIWEAVER_AUDIT_DIR", DATA_DIR / "audit"))
STATIC_DIR = SERVER_DIR / "static"
WEB_BUILD_DIR = Path(os.environ.get("NAIWEAVER_WEB_BUILD_DIR", STATIC_DIR / "web"))

APP_ENV = os.environ.get("NAIWEAVER_ENV", "development").lower()
PRODUCTION = APP_ENV == "production"
SECRET_KEY = os.environ.get("NAIWEAVER_SECRET_KEY") or (
    "" if PRODUCTION else "local-dev-change-me"
)
COOKIE_SECURE = os.environ.get(
    "NAIWEAVER_COOKIE_SECURE", "1" if PRODUCTION else "0"
) == "1"
ALLOW_PASSWORD_LOGIN = os.environ.get("NAIWEAVER_ALLOW_PASSWORD_LOGIN", "0") == "1"
BOOTSTRAP_TEST_USERS = (
    os.environ.get("NAIWEAVER_BOOTSTRAP_TEST_USERS", "0" if PRODUCTION else "1")
    == "1"
)
SESSION_TTL_SECONDS = int(os.environ.get("NAIWEAVER_SESSION_TTL_SECONDS", "604800"))
FAKE_NOVELAI = os.environ.get("NAIWEAVER_FAKE_NOVELAI", "0") == "1"
PUBLIC_BASE_URL = os.environ.get(
    "NAIWEAVER_PUBLIC_BASE_URL", "http://127.0.0.1:8000"
).rstrip("/")
only_auth = OnlyWebAuth(PUBLIC_BASE_URL, SESSION_TTL_SECONDS, lambda: db_connect())
MAX_REQUEST_BODY_BYTES = int(os.environ.get("NAIWEAVER_MAX_REQUEST_BODY_BYTES", "25000000"))
CORS_ORIGINS = [
    origin.strip()
    for origin in os.environ.get("NAIWEAVER_CORS_ORIGINS", "").split(",")
    if origin.strip()
]

STANDARD_GREEN_IMAGE_POINTS = 20
TEXT_GLOBAL_CONCURRENCY = int(os.environ.get("NAIWEAVER_TEXT_CONCURRENCY", "3"))
MAX_QUEUED_IMAGE_TASKS_PER_USER = int(
    os.environ.get("NAIWEAVER_MAX_QUEUED_IMAGE_TASKS_PER_USER", "20")
)
THUMBNAIL_MAX_SIZE = int(os.environ.get("NAIWEAVER_THUMBNAIL_MAX_SIZE", "512"))
THUMBNAIL_WEBP_QUALITY = int(os.environ.get("NAIWEAVER_THUMBNAIL_WEBP_QUALITY", "76"))

QUEUE_WEIGHTS = {"free": 100, "paid": 500, "admin": 1000}
AUDIT_MAX_STRING_CHARS = 20000
GENERATION_ERROR_PREVIEW_MAX_CHARS = 4000
GENERATION_LOG_SENSITIVE_KEYS = frozenset(
    {
        "authorization",
        "base_caption",
        "char_caption",
        "char_captions",
        "cookie",
        "director_reference_descriptions",
        "director_reference_images",
        "image",
        "input",
        "mask",
        "negative_prompt",
        "password",
        "prompt",
        "reference_image_multiple",
        "secret",
        "set-cookie",
        "token",
        "uc",
    }
)
TARGET_BASES = {
    "image": "https://image.novelai.net",
    "api": "https://api.novelai.net",
    "text": "https://text.novelai.net",
}
HOP_BY_HOP_HEADERS = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailers",
    "transfer-encoding",
    "upgrade",
    "content-encoding",
    "content-length",
}
# Paid image tools reachable through the proxy, keyed by NovelAI path. Image
# generation is only accepted through /api/generation-tasks.
PAID_TOOL_PATHS = {
    "ai/upscale": "upscale",
    "ai/augment-image": "augment",
    "ai/encode-vibe": "encode_vibe",
}
TOOL_PERMISSION_COLUMNS = {
    "upscale": "can_image_upscale",
    "augment": "can_image_augment",
    "encode_vibe": "can_image_encode_vibe",
}
ALLOWED_TEXT_PROXY_PATHS = {
    "ai/generate",
    "ai/generate-stream",
    "oa/v1/completions",
    "oa/v1/chat/completions",
}
ALLOWED_API_PROXY_PATHS = {"user/subscription"}

SCHEMA = """
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS schema_migrations (
  migration_key TEXT PRIMARY KEY,
  applied_at TEXT NOT NULL
);

-- Keep the source values for destructive quota-schema migrations. This is
-- intentionally separate from users so a later repair never has to guess
-- what a retired column contained.
CREATE TABLE IF NOT EXISTS legacy_quota_snapshots (
  user_id INTEGER PRIMARY KEY,
  values_json TEXT NOT NULL,
  captured_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  is_admin INTEGER NOT NULL DEFAULT 0,
  disabled INTEGER NOT NULL DEFAULT 0,
  can_generate_paid INTEGER NOT NULL DEFAULT 0,
  can_text_generate INTEGER NOT NULL DEFAULT 1,
  can_image_upscale INTEGER NOT NULL DEFAULT 1,
  can_image_augment INTEGER NOT NULL DEFAULT 1,
  can_image_encode_vibe INTEGER NOT NULL DEFAULT 1,
  green_point_limit INTEGER NOT NULL DEFAULT 4000,
  green_point_used INTEGER NOT NULL DEFAULT 0,
  green_points_reserved INTEGER NOT NULL DEFAULT 0,
  green_point_discount INTEGER NOT NULL DEFAULT 0,
  red_points INTEGER NOT NULL DEFAULT 3000,
  red_points_used INTEGER NOT NULL DEFAULT 0,
  red_points_reserved INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS sessions (
  id TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  expires_at TEXT NOT NULL,
  revoked_at TEXT,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS quota_usage (
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  quota_date TEXT NOT NULL,
  mode TEXT NOT NULL,
  used INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, quota_date, mode)
);

CREATE TABLE IF NOT EXISTS generation_tasks (
  id TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  mode TEXT NOT NULL,
  queue_class TEXT,
  queue_weight INTEGER,
  virtual_finish REAL,
  status TEXT NOT NULL,
  prompt TEXT NOT NULL,
  negative_prompt TEXT NOT NULL DEFAULT '',
  width INTEGER NOT NULL,
  height INTEGER NOT NULL,
  steps INTEGER NOT NULL,
  scale REAL NOT NULL,
  sampler TEXT NOT NULL,
  seed INTEGER NOT NULL,
  cost INTEGER NOT NULL DEFAULT 1,
  image_path TEXT,
  error_message TEXT,
  anlas_before INTEGER,
  anlas_after INTEGER,
  paid_points_charged INTEGER NOT NULL DEFAULT 0,
  reserved_points INTEGER NOT NULL DEFAULT 0,
  reserved_green_points INTEGER NOT NULL DEFAULT 0,
  reserved_red_points INTEGER NOT NULL DEFAULT 0,
  consumed_green_points INTEGER NOT NULL DEFAULT 0,
  consumed_red_points INTEGER NOT NULL DEFAULT 0,
  released_green_points INTEGER NOT NULL DEFAULT 0,
  released_red_points INTEGER NOT NULL DEFAULT 0,
  batch_id TEXT,
  batch_index INTEGER,
  request_fingerprint TEXT,
  request_json TEXT NOT NULL,
  queued_at TEXT,
  started_at TEXT,
  completed_at TEXT,
  created_at TEXT NOT NULL
);

-- A task is one user submission. Existing generation_tasks rows are its
-- image-level items; their batch_id is migrated into this parent record.
CREATE TABLE IF NOT EXISTS generation_submission_tasks (
  id TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  client_request_id TEXT,
  request_hash TEXT,
  type TEXT NOT NULL CHECK(type IN ('single', 'batch')),
  status TEXT NOT NULL,
  item_count INTEGER NOT NULL DEFAULT 0,
  reserved_points INTEGER NOT NULL DEFAULT 0,
  consumed_points INTEGER NOT NULL DEFAULT 0,
  released_points INTEGER NOT NULL DEFAULT 0,
  reserved_green_points INTEGER NOT NULL DEFAULT 0,
  reserved_red_points INTEGER NOT NULL DEFAULT 0,
  consumed_green_points INTEGER NOT NULL DEFAULT 0,
  consumed_red_points INTEGER NOT NULL DEFAULT 0,
  released_green_points INTEGER NOT NULL DEFAULT 0,
  released_red_points INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  completed_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_generation_submission_tasks_user_created
ON generation_submission_tasks(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS history_hidden (
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  task_id TEXT NOT NULL REFERENCES generation_tasks(id) ON DELETE CASCADE,
  hidden_at TEXT NOT NULL,
  PRIMARY KEY (user_id, task_id)
);

CREATE INDEX IF NOT EXISTS idx_history_hidden_task_id ON history_hidden(task_id);

CREATE TABLE IF NOT EXISTS request_audit_logs (
  id TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  service TEXT NOT NULL,
  path TEXT NOT NULL,
  method TEXT NOT NULL,
  status_code INTEGER,
  request_content_type TEXT NOT NULL DEFAULT '',
  request_json TEXT NOT NULL DEFAULT '',
  request_body_path TEXT,
  request_body_bytes INTEGER NOT NULL DEFAULT 0,
  request_body_sha256 TEXT NOT NULL DEFAULT '',
  error_message TEXT,
  created_at TEXT NOT NULL,
  completed_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_request_audit_logs_user_id ON request_audit_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_request_audit_logs_created_at ON request_audit_logs(created_at);

CREATE TABLE IF NOT EXISTS client_feedback_reports (
  id TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  description TEXT NOT NULL DEFAULT '',
  client_context_json TEXT NOT NULL,
  diagnostics_json TEXT NOT NULL,
  event_count INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_client_feedback_reports_user_created
ON client_feedback_reports(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_client_feedback_reports_created
ON client_feedback_reports(created_at DESC);

-- Machine-readable failure reason of a generation item (contract §1 codes).
CREATE TABLE IF NOT EXISTS generation_item_errors (
  item_id TEXT PRIMARY KEY REFERENCES generation_tasks(id) ON DELETE CASCADE,
  error_code TEXT NOT NULL,
  created_at TEXT NOT NULL
);

-- Settlements that disagreed with the quote. A 'free_allowance_exhausted'
-- row also starts the free-allowance cooldown (contract §4).
CREATE TABLE IF NOT EXISTS billing_anomalies (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  kind TEXT NOT NULL,
  user_id INTEGER NOT NULL,
  task_id TEXT,
  tool TEXT,
  mode TEXT NOT NULL,
  quoted INTEGER NOT NULL,
  measured INTEGER,
  note TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_billing_anomalies_kind_created
ON billing_anomalies(kind, created_at);

"""


http_client: httpx.AsyncClient | None = None
queue_condition: asyncio.Condition | None = None
queue_worker_task: asyncio.Task | None = None
pending_jobs: list["ProxyJob"] = []
active_user_ids: set[int] = set()
queue_virtual_time = 0.0
queue_last_finish: dict[str, float] = {"free": 0.0, "paid": 0.0, "admin": 0.0}
text_queue_condition: asyncio.Condition | None = None
pending_text_jobs: list["TextQueueTicket"] = []
active_text_user_ids: set[int] = set()
active_text_count = 0
text_queue_virtual_time = 0.0
text_queue_last_finish: dict[str, float] = {"free": 0.0, "paid": 0.0, "admin": 0.0}
upstream_lane = UpstreamLane()
tool_response_cache = ToolResponseCache()


@dataclass(order=True)
class ProxyJob:
    sort_key: tuple[int, float, int, str] = field(init=False, repr=False)
    virtual_finish: float
    negative_weight: int
    created_at: str
    user_id: int = field(compare=False)
    task_id: str = field(compare=False)
    service: str = field(compare=False)
    path: str = field(compare=False)
    body: bytes = field(compare=False)
    quota_mode: str = field(compare=False, default="free")

    def __post_init__(self) -> None:
        # Red-point work runs before free work; free work keeps the weighted
        # fair order among user classes.
        self.sort_key = (
            self.lane_priority,
            self.virtual_finish,
            self.negative_weight,
            self.created_at,
        )

    @property
    def lane_priority(self) -> int:
        return RED_PRIORITY if self.quota_mode == "paid" else FREE_PRIORITY


@dataclass(order=True)
class TextQueueTicket:
    sort_key: tuple[float, int, str] = field(init=False, repr=False)
    virtual_finish: float
    negative_weight: int
    created_at: str
    user_id: int = field(compare=False)
    username: str = field(compare=False)
    ticket_id: str = field(compare=False)

    def __post_init__(self) -> None:
        self.sort_key = (self.virtual_finish, self.negative_weight, self.created_at)


class LoginRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    username: str = Field(min_length=1, max_length=80)
    password: str = Field(min_length=1, max_length=256)


class ClientDiagnosticEventRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    timestamp: str = Field(min_length=1, max_length=64)
    sequence: int | None = Field(default=None, ge=0)
    elapsed_ms: int | None = Field(default=None, ge=0)
    event: str = Field(min_length=1, max_length=96)
    details: dict[str, bool | int | float | str | None] = Field(
        default_factory=dict, max_length=48
    )


class ClientFeedbackContextRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    app_version: str = Field(default="", max_length=64)
    build_number: str = Field(default="", max_length=64)
    platform: str = Field(default="", max_length=128)
    web: bool = True
    user_agent: str = Field(default="", max_length=768)
    language: str = Field(default="", max_length=64)
    viewport_width: float | None = Field(default=None, ge=0, le=100000)
    viewport_height: float | None = Field(default=None, ge=0, le=100000)
    view_padding_top: float | None = Field(default=None, ge=0, le=100000)
    view_padding_right: float | None = Field(default=None, ge=0, le=100000)
    view_padding_bottom: float | None = Field(default=None, ge=0, le=100000)
    view_padding_left: float | None = Field(default=None, ge=0, le=100000)
    view_insets_top: float | None = Field(default=None, ge=0, le=100000)
    view_insets_right: float | None = Field(default=None, ge=0, le=100000)
    view_insets_bottom: float | None = Field(default=None, ge=0, le=100000)
    view_insets_left: float | None = Field(default=None, ge=0, le=100000)
    padding_top: float | None = Field(default=None, ge=0, le=100000)
    padding_right: float | None = Field(default=None, ge=0, le=100000)
    padding_bottom: float | None = Field(default=None, ge=0, le=100000)
    padding_left: float | None = Field(default=None, ge=0, le=100000)
    orientation: str = Field(default="", max_length=32)
    window_width: float | None = Field(default=None, ge=0, le=100000)
    window_height: float | None = Field(default=None, ge=0, le=100000)
    device_pixel_ratio: float | None = Field(default=None, ge=0, le=100)
    screen_width: float | None = Field(default=None, ge=0, le=100000)
    screen_height: float | None = Field(default=None, ge=0, le=100000)
    screen_available_width: float | None = Field(default=None, ge=0, le=100000)
    screen_available_height: float | None = Field(default=None, ge=0, le=100000)
    color_depth: int | None = Field(default=None, ge=0, le=128)
    screen_orientation_type: str = Field(default="", max_length=64)
    screen_orientation_angle: int | None = Field(default=None, ge=-360, le=360)
    visual_viewport_width: float | None = Field(default=None, ge=0, le=100000)
    visual_viewport_height: float | None = Field(default=None, ge=0, le=100000)
    visual_viewport_offset_left: float | None = Field(default=None, ge=-100000, le=100000)
    visual_viewport_offset_top: float | None = Field(default=None, ge=-100000, le=100000)
    visual_viewport_scale: float | None = Field(default=None, ge=0, le=1000)
    document_client_width: float | None = Field(default=None, ge=0, le=1000000)
    document_client_height: float | None = Field(default=None, ge=0, le=1000000)
    document_scroll_width: float | None = Field(default=None, ge=0, le=1000000)
    document_scroll_height: float | None = Field(default=None, ge=0, le=1000000)
    page_scroll_x: float | None = Field(default=None, ge=-1000000, le=1000000)
    page_scroll_y: float | None = Field(default=None, ge=-1000000, le=1000000)
    max_touch_points: int | None = Field(default=None, ge=0, le=1000)
    hardware_concurrency: int | None = Field(default=None, ge=0, le=10000)
    online: bool | None = None
    cookie_enabled: bool | None = None
    document_visibility: str = Field(default="", max_length=64)
    document_has_focus: bool | None = None
    timezone_name: str = Field(default="", max_length=128)
    timezone_offset_minutes: int | None = Field(default=None, ge=-1440, le=1440)
    diagnostic_session_id: str = Field(default="", max_length=128)
    diagnostic_session_started_at: str = Field(default="", max_length=64)
    diagnostic_session_duration_ms: int | None = Field(default=None, ge=0)
    diagnostic_event_capacity: int | None = Field(default=None, ge=0, le=10000)
    diagnostic_event_count: int | None = Field(default=None, ge=0, le=10000)
    diagnostic_dropped_event_count: int | None = Field(default=None, ge=0)


class ClientFeedbackCreateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    description: str = Field(default="", max_length=2000)
    client_context: ClientFeedbackContextRequest
    diagnostics: list[ClientDiagnosticEventRequest] = Field(max_length=1200)


class UserUpdateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    password: str | None = Field(default=None, min_length=1, max_length=256)
    is_admin: bool | None = None
    disabled: bool | None = None
    green_point_discount: int | None = Field(default=None, ge=0, le=100)
    can_generate_paid: bool | None = None
    can_text_generate: bool | None = None
    can_image_upscale: bool | None = None
    can_image_augment: bool | None = None
    can_image_encode_vibe: bool | None = None
    green_point_limit: int | None = Field(default=None, ge=0)
    green_point_used: int | None = Field(default=None, ge=0)
    red_points: int | None = Field(default=None, ge=0)
    red_points_used: int | None = Field(default=None, ge=0)


class UserCreateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    username: str = Field(min_length=1, max_length=80)
    password: str | None = Field(default=None, min_length=1, max_length=256)
    # The role supplies every default; fields left out take its values.
    role: Literal["free", "paid", "admin"] = "free"
    is_admin: bool | None = None
    disabled: bool = False
    green_point_discount: int | None = Field(default=None, ge=0, le=100)
    can_generate_paid: bool | None = None
    can_text_generate: bool | None = None
    can_image_upscale: bool | None = None
    can_image_augment: bool | None = None
    can_image_encode_vibe: bool | None = None
    green_point_limit: int | None = Field(default=None, ge=0)
    green_point_used: int = Field(default=0, ge=0)
    red_points: int | None = Field(default=None, ge=0)
    red_points_used: int = Field(default=0, ge=0)




def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def today_key() -> str:
    return date.today().isoformat()




def session_response(
    response: Response, db: sqlite3.Connection, user: sqlite3.Row
) -> dict[str, Any]:
    session_id = secrets.token_urlsafe(24)
    expires_at = datetime.now(timezone.utc) + timedelta(seconds=SESSION_TTL_SECONDS)
    db.execute(
        "INSERT INTO sessions(id, user_id, expires_at, created_at) VALUES (?, ?, ?, ?)",
        (session_id, user["id"], expires_at.isoformat(), now_iso()),
    )
    db.commit()
    token = create_jwt(
        {"sub": int(user["id"]), "jti": session_id}, SECRET_KEY, SESSION_TTL_SECONDS
    )
    response.set_cookie(
        "access_token",
        token,
        httponly=True,
        secure=COOKIE_SECURE,
        samesite="strict" if PRODUCTION else "lax",
        max_age=SESSION_TTL_SECONDS,
        path="/",
    )
    return {"user": user_to_dict(user), "quota": quota_for_user(user)}


def db_connect() -> sqlite3.Connection:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("PRAGMA journal_mode = WAL")
    return conn


def get_db():
    conn = db_connect()
    try:
        yield conn
    finally:
        conn.close()


@contextmanager
def db_session() -> Iterator[sqlite3.Connection]:
    """A short-lived connection for background work; always closed."""
    conn = db_connect()
    try:
        yield conn
    finally:
        conn.close()


def init_db() -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    IMAGE_DIR.mkdir(parents=True, exist_ok=True)
    THUMBNAIL_DIR.mkdir(parents=True, exist_ok=True)
    AUDIT_DIR.mkdir(parents=True, exist_ok=True)
    with closing(db_connect()) as db:
        db.executescript(SCHEMA)
        migrate_db(db)
        db.commit()


def migrate_db(db: sqlite3.Connection) -> None:
    table_columns = {
        row["name"] for row in db.execute("PRAGMA table_info(users)").fetchall()
    }
    user_columns = {
        "can_text_generate": "INTEGER NOT NULL DEFAULT 1",
        "can_image_upscale": "INTEGER NOT NULL DEFAULT 1",
        "can_image_augment": "INTEGER NOT NULL DEFAULT 1",
        "can_image_encode_vibe": "INTEGER NOT NULL DEFAULT 1",
        "green_point_limit": f"INTEGER NOT NULL DEFAULT {DEFAULT_GREEN_POINT_LIMIT}",
        "green_point_used": "INTEGER NOT NULL DEFAULT 0",
        "green_points_reserved": "INTEGER NOT NULL DEFAULT 0",
        "green_point_discount": "INTEGER NOT NULL DEFAULT 0",
        "red_points": f"INTEGER NOT NULL DEFAULT {DEFAULT_RED_POINTS}",
        "red_points_used": "INTEGER NOT NULL DEFAULT 0",
        "red_points_reserved": "INTEGER NOT NULL DEFAULT 0",
    }
    for name, definition in user_columns.items():
        if name not in table_columns:
            db.execute(f"ALTER TABLE users ADD COLUMN {name} {definition}")
    submission_columns = {
        "client_request_id": "TEXT",
        "request_hash": "TEXT",
        "reserved_green_points": "INTEGER NOT NULL DEFAULT 0",
        "reserved_red_points": "INTEGER NOT NULL DEFAULT 0",
        "consumed_green_points": "INTEGER NOT NULL DEFAULT 0",
        "consumed_red_points": "INTEGER NOT NULL DEFAULT 0",
        "released_green_points": "INTEGER NOT NULL DEFAULT 0",
        "released_red_points": "INTEGER NOT NULL DEFAULT 0",
    }
    existing_submission_columns = {
        row["name"] for row in db.execute("PRAGMA table_info(generation_submission_tasks)").fetchall()
    }
    for name, definition in submission_columns.items():
        if name not in existing_submission_columns:
            db.execute(f"ALTER TABLE generation_submission_tasks ADD COLUMN {name} {definition}")
    db.execute(
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_generation_submission_tasks_idempotency "
        "ON generation_submission_tasks(user_id, client_request_id) "
        "WHERE client_request_id IS NOT NULL"
    )
    legacy_quota_columns = (
        "daily_limit",
        "paid_daily_limit",
        "can_generate_free",
        "paid_point_limit",
        "paid_point_used",
        "red_point_limit",
        "red_point_used",
    )
    present_legacy_columns = [
        name for name in legacy_quota_columns if name in table_columns
    ]
    if present_legacy_columns:
        # Snapshot before ALTER TABLE DROP COLUMN. Do not include credentials or
        # other unrelated user data in the recovery record.
        select_columns = ", ".join(["id", *present_legacy_columns])
        for row in db.execute(f"SELECT {select_columns} FROM users").fetchall():
            values = {name: row[name] for name in present_legacy_columns}
            db.execute(
                "INSERT OR IGNORE INTO legacy_quota_snapshots"
                "(user_id, values_json, captured_at) VALUES (?, ?, ?)",
                (row["id"], json.dumps(values, sort_keys=True), now_iso()),
            )

    # Copy retired quota values once before physically removing their columns.
    if "green_point_limit" not in table_columns and "daily_limit" in table_columns:
        free_permission = (
            "WHEN can_generate_free = 0 THEN 0 "
            if "can_generate_free" in table_columns
            else ""
        )
        db.execute(
            "UPDATE users SET green_point_limit = CASE "
            "WHEN is_admin = 1 THEN ? "
            f"{free_permission}"
            "WHEN daily_limit IS NULL OR daily_limit < 0 THEN ? "
            "ELSE daily_limit * ? END",
            (
                DEFAULT_GREEN_POINT_LIMIT,
                DEFAULT_GREEN_POINT_LIMIT,
                STANDARD_GREEN_IMAGE_POINTS,
            ),
        )
    if "green_point_used" not in table_columns:
        db.execute(
            """
            UPDATE users
            SET green_point_used = COALESCE((
              SELECT SUM(used) * ? FROM quota_usage
              WHERE quota_usage.user_id = users.id AND mode = 'free'
                AND quota_date = ?
            ), 0)
            """,
            (STANDARD_GREEN_IMAGE_POINTS, today_key()),
        )
    if "green_point_discount" not in table_columns:
        # Only administrators are unlimited. Legacy free-generation access is
        # represented by the migrated green-point limit, not a 100% discount.
        db.execute(
            "UPDATE users SET green_point_discount = CASE "
            "WHEN is_admin = 1 THEN 100 ELSE 0 END"
        )
    if "red_points" not in table_columns:
        if "red_point_limit" in table_columns:
            db.execute("UPDATE users SET red_points = red_point_limit")
        else:
            db.execute("UPDATE users SET red_points = COALESCE(paid_point_limit, 0)")
    if "red_points_used" not in table_columns:
        if "red_point_used" in table_columns:
            db.execute("UPDATE users SET red_points_used = red_point_used")
        else:
            db.execute("UPDATE users SET red_points_used = COALESCE(paid_point_used, 0)")
    # This is a one-time physical schema migration, not a compatibility layer.
    # All values are copied above before the retired quota columns are removed.
    for legacy_column in legacy_quota_columns:
        if legacy_column in table_columns:
            db.execute(f"ALTER TABLE users DROP COLUMN {legacy_column}")
    task_columns = {
        row["name"] for row in db.execute("PRAGMA table_info(generation_tasks)").fetchall()
    }
    generation_task_columns = {
        "queue_class": "TEXT",
        "queue_weight": "INTEGER",
        "virtual_finish": "REAL",
        "anlas_before": "INTEGER",
        "anlas_after": "INTEGER",
        "paid_points_charged": "INTEGER NOT NULL DEFAULT 0",
        "reserved_points": "INTEGER NOT NULL DEFAULT 0",
        "reserved_green_points": "INTEGER NOT NULL DEFAULT 0",
        "reserved_red_points": "INTEGER NOT NULL DEFAULT 0",
        "consumed_green_points": "INTEGER NOT NULL DEFAULT 0",
        "consumed_red_points": "INTEGER NOT NULL DEFAULT 0",
        "released_green_points": "INTEGER NOT NULL DEFAULT 0",
        "released_red_points": "INTEGER NOT NULL DEFAULT 0",
        "batch_id": "TEXT",
        "batch_index": "INTEGER",
        "request_fingerprint": "TEXT",
    }
    for name, definition in generation_task_columns.items():
        if name not in task_columns:
            db.execute(f"ALTER TABLE generation_tasks ADD COLUMN {name} {definition}")
    # Only backfill accounting columns when upgrading a schema that did not
    # have them. Rewriting them on every boot can destroy legitimate manual
    # adjustments and makes an interrupted migration impossible to audit.
    accounting_columns = {
        "reserved_green_points",
        "reserved_red_points",
        "consumed_green_points",
        "consumed_red_points",
        "released_green_points",
        "released_red_points",
    }
    if not accounting_columns.issubset(task_columns):
        db.execute(
            """
            UPDATE generation_tasks
            SET reserved_green_points = CASE WHEN mode = 'free' THEN reserved_points ELSE 0 END,
                reserved_red_points = CASE WHEN mode = 'paid' THEN reserved_points ELSE 0 END,
                consumed_green_points = CASE WHEN mode = 'free' AND status = 'success' THEN reserved_points ELSE 0 END,
                consumed_red_points = CASE WHEN mode = 'paid' AND status = 'success' THEN paid_points_charged ELSE 0 END,
                released_green_points = CASE WHEN mode = 'free' AND status IN ('failed', 'rejected', 'cancelled') THEN reserved_points ELSE 0 END,
                released_red_points = CASE WHEN mode = 'paid' AND status IN ('failed', 'rejected', 'cancelled') THEN reserved_points ELSE 0 END
            """
        )
    fingerprint_rows = db.execute(
        "SELECT id, request_json FROM generation_tasks WHERE request_fingerprint IS NULL"
    ).fetchall()
    for row in fingerprint_rows:
        try:
            parsed_request = json.loads(row["request_json"])
            fingerprint = generation_request_fingerprint(parsed_request)
        except (TypeError, ValueError, json.JSONDecodeError):
            continue
        db.execute(
            "UPDATE generation_tasks SET request_fingerprint = ? WHERE id = ?",
            (fingerprint, row["id"]),
        )
    db.execute(
        "CREATE INDEX IF NOT EXISTS idx_generation_tasks_user_fingerprint "
        "ON generation_tasks(user_id, request_fingerprint)"
    )
    # Backfill the outer task for every historical image item. Explicit batch
    # IDs are authoritative. Rows from before explicit batch IDs are kept as
    # separate submissions; timing proximity is not proof of one batch.
    rows = db.execute(
        "SELECT id, user_id, batch_id, created_at, status, reserved_points "
        "FROM generation_tasks ORDER BY user_id, created_at, id"
    ).fetchall()
    for row in rows:
        explicit = row["batch_id"]
        if explicit:
            parent_id = explicit
        else:
            parent_id = f"legacy-{row['id']}"
        db.execute(
            "INSERT OR IGNORE INTO generation_submission_tasks "
            "(id, user_id, type, status, created_at) VALUES (?, ?, 'single', 'queued', ?)",
            (parent_id, row["user_id"], row["created_at"]),
        )
        db.execute("UPDATE generation_tasks SET batch_id = ? WHERE id = ?", (parent_id, row["id"]))
    db.execute(
        """
        UPDATE generation_submission_tasks
        SET item_count = (SELECT COUNT(*) FROM generation_tasks i WHERE i.batch_id = generation_submission_tasks.id),
            reserved_points = (SELECT COALESCE(SUM(reserved_points), 0) FROM generation_tasks i WHERE i.batch_id = generation_submission_tasks.id),
            type = CASE WHEN (SELECT COUNT(*) FROM generation_tasks i WHERE i.batch_id = generation_submission_tasks.id) > 1 THEN 'batch' ELSE 'single' END
        """
    )
    for row in db.execute("SELECT id FROM generation_submission_tasks").fetchall():
        refresh_submission_task(db, row["id"])
    # A submission without items cannot ever run. Removing stale active shells
    # lets an idempotent client retry instead of replaying an empty task.
    db.execute(
        """
        DELETE FROM generation_submission_tasks
        WHERE status IN ('queued', 'running')
          AND NOT EXISTS (
            SELECT 1 FROM generation_tasks i
            WHERE i.batch_id = generation_submission_tasks.id
          )
        """
    )
    # Reserved counters are a cache of durable active item reservations. This
    # repairs leaked counters after an interrupted older implementation while
    # preserving consumed point balances.
    db.execute(
        """
        UPDATE users
        SET green_points_reserved = COALESCE((
              SELECT SUM(reserved_points) FROM generation_tasks i
              WHERE i.user_id = users.id AND i.mode = 'free'
                AND i.status IN ('queued', 'running')
            ), 0),
            red_points_reserved = COALESCE((
              SELECT SUM(reserved_points) FROM generation_tasks i
              WHERE i.user_id = users.id AND i.mode = 'paid'
                AND i.status IN ('queued', 'running')
            ), 0)
        """
    )
    db.execute(
        """
        CREATE TABLE IF NOT EXISTS history_hidden (
          user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          task_id TEXT NOT NULL REFERENCES generation_tasks(id) ON DELETE CASCADE,
          hidden_at TEXT NOT NULL,
          PRIMARY KEY (user_id, task_id)
        )
        """
    )
    db.execute(
        "CREATE INDEX IF NOT EXISTS idx_history_hidden_task_id ON history_hidden(task_id)"
    )
    db.execute(
        """
        CREATE TABLE IF NOT EXISTS request_audit_logs (
          id TEXT PRIMARY KEY,
          user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          service TEXT NOT NULL,
          path TEXT NOT NULL,
          method TEXT NOT NULL,
          status_code INTEGER,
          request_content_type TEXT NOT NULL DEFAULT '',
          request_json TEXT NOT NULL DEFAULT '',
          request_body_path TEXT,
          request_body_bytes INTEGER NOT NULL DEFAULT 0,
          request_body_sha256 TEXT NOT NULL DEFAULT '',
          error_message TEXT,
          created_at TEXT NOT NULL,
          completed_at TEXT
        )
        """
    )
    audit_columns = {
        row["name"]
        for row in db.execute("PRAGMA table_info(request_audit_logs)").fetchall()
    }
    audit_log_columns = {
        "request_content_type": "TEXT NOT NULL DEFAULT ''",
        "request_body_path": "TEXT",
        "request_body_bytes": "INTEGER NOT NULL DEFAULT 0",
        "request_body_sha256": "TEXT NOT NULL DEFAULT ''",
    }
    for name, definition in audit_log_columns.items():
        if name not in audit_columns:
            db.execute(f"ALTER TABLE request_audit_logs ADD COLUMN {name} {definition}")
    db.execute(
        "CREATE INDEX IF NOT EXISTS idx_request_audit_logs_user_id ON request_audit_logs(user_id)"
    )
    db.execute(
        "CREATE INDEX IF NOT EXISTS idx_request_audit_logs_created_at ON request_audit_logs(created_at)"
    )
    db.execute(
        """
        CREATE TABLE IF NOT EXISTS client_feedback_reports (
          id TEXT PRIMARY KEY,
          user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          description TEXT NOT NULL DEFAULT '',
          client_context_json TEXT NOT NULL,
          diagnostics_json TEXT NOT NULL,
          event_count INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL
        )
        """
    )
    db.execute(
        "CREATE INDEX IF NOT EXISTS idx_client_feedback_reports_user_created "
        "ON client_feedback_reports(user_id, created_at DESC)"
    )
    db.execute(
        "CREATE INDEX IF NOT EXISTS idx_client_feedback_reports_created "
        "ON client_feedback_reports(created_at DESC)"
    )


def bootstrap_users() -> None:
    if not BOOTSTRAP_TEST_USERS:
        return
    admin_password_env = os.environ.get("NAIWEAVER_ADMIN_PASSWORD")
    admin_password = admin_password_env or "local-test-admin"
    samples = [
        ("admin", admin_password, "admin"),
        ("free_user", "free-test-pass", "free"),
        ("paid_user", "paid-test-pass", "paid"),
    ]
    with closing(db_connect()) as db:
        for username, password, role in samples:
            existing = db.execute("SELECT id FROM users WHERE username = ?", (username,)).fetchone()
            if existing:
                if username == "admin" and admin_password_env:
                    # Point totals are balances; only permissions are re-applied.
                    changes = {
                        "password_hash": hash_password(admin_password),
                        "disabled": 0,
                        **{
                            name: value
                            for name, value in role_defaults("admin").items()
                            if name not in POINT_TOTAL_FIELDS
                        },
                    }
                    assignments = ", ".join(f"{name} = ?" for name in changes)
                    db.execute(
                        f"UPDATE users SET {assignments} WHERE id = ?",
                        (*changes.values(), existing["id"]),
                    )
                continue
            columns = {
                "username": username,
                "password_hash": hash_password(password),
                **role_defaults(role),
                "created_at": now_iso(),
            }
            db.execute(
                f"INSERT INTO users({', '.join(columns)}) "
                f"VALUES ({', '.join('?' for _ in columns)})",
                tuple(columns.values()),
            )
        db.commit()


def validate_runtime_config() -> None:
    if not SECRET_KEY:
        raise RuntimeError("NAIWEAVER_SECRET_KEY is required in production")
    if PRODUCTION:
        if SECRET_KEY == "local-dev-change-me" or len(SECRET_KEY) < 32:
            raise RuntimeError("NAIWEAVER_SECRET_KEY must be a strong production secret")
        if not COOKIE_SECURE:
            raise RuntimeError("NAIWEAVER_COOKIE_SECURE=1 is required in production")
        if ALLOW_PASSWORD_LOGIN:
            raise RuntimeError("Password login must stay disabled in production")
        if not only_auth.enabled:
            raise RuntimeError("NAIWEAVER_AUTH_ISSUER is required in production")


@asynccontextmanager
async def lifespan(_: FastAPI):
    global http_client, queue_condition, queue_worker_task, text_queue_condition
    global upstream_lane, tool_response_cache
    validate_runtime_config()
    init_db()
    bootstrap_users()
    timeout = httpx.Timeout(60.0, read=300.0)
    http_client = httpx.AsyncClient(timeout=timeout)
    queue_condition = asyncio.Condition()
    text_queue_condition = asyncio.Condition()
    upstream_lane = UpstreamLane()
    tool_response_cache = ToolResponseCache()
    await restore_generation_queue()
    queue_worker_task = asyncio.create_task(queue_worker())
    try:
        yield
    finally:
        if queue_worker_task is not None:
            # The worker marks its running item 'interrupted' on cancellation.
            queue_worker_task.cancel()
            try:
                await queue_worker_task
            except asyncio.CancelledError:
                pass
        if http_client is not None:
            await http_client.aclose()
        await only_auth.aclose()


app = FastAPI(title="NAIWeaver Web Gateway", version="0.2.0", lifespan=lifespan)

if CORS_ORIGINS:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=CORS_ORIGINS,
        allow_credentials=True,
        allow_methods=["GET", "POST", "OPTIONS"],
        allow_headers=["Content-Type", "Authorization"],
    )


@app.middleware("http")
async def same_origin_writes(request: Request, call_next):
    if PRODUCTION and request.url.path.startswith("/api/") and request.method not in {
        "GET",
        "HEAD",
        "OPTIONS",
    }:
        origin = request.headers.get("origin")
        if origin and origin != PUBLIC_BASE_URL:
            return error_response(
                403,
                {
                    "code": "permission_denied",
                    "message": "Cross-origin request rejected",
                    "permission": "origin",
                },
            )
    return await call_next(request)


# Added last so it is the outermost layer: it counts the bytes every inner
# layer reads, including chunked uploads without Content-Length.
app.add_middleware(BodySizeLimitMiddleware, max_bytes=MAX_REQUEST_BODY_BYTES)
install_error_handlers(app)


def novelai_token() -> str:
    token_file = os.environ.get("NOVELAI_TOKEN_FILE")
    if token_file:
        path = Path(token_file).expanduser()
        if path.exists():
            return path.read_text(encoding="utf-8").strip()
    return os.environ.get("NOVELAI_TOKEN", os.environ.get("NAI_TOKEN", "")).strip()


def image_generation_allowed(user: Any, mode: str) -> bool:
    """The only rule for "may this user generate images in this mode".

    It describes capability, not balance: reservations report missing points
    as ``points_insufficient``. /api/me, quota, submission and the worker all
    call this function.
    """
    if user is None or user["disabled"]:
        return False
    if user["is_admin"]:
        return True
    if mode == "paid":
        return bool(user["can_generate_paid"])
    return (
        int(user["green_point_discount"]) > 0
        or int(user["green_point_limit"]) > int(user["green_point_used"])
    )


def image_tool_allowed(user: Any, tool: str) -> bool:
    if user is None or user["disabled"]:
        return False
    if user["is_admin"]:
        return True
    return bool(user[TOOL_PERMISSION_COLUMNS[tool]]) and image_generation_allowed(
        user, "paid"
    )


def generation_permission_name(mode: str) -> str:
    return "image.generate.paid" if mode == "paid" else "image.generate.free"


def tool_permission_name(tool: str) -> str:
    return f"image.{tool}"


def user_to_dict(user: sqlite3.Row) -> dict[str, Any]:
    permissions = {"history.read"}
    for mode in ("free", "paid"):
        if image_generation_allowed(user, mode):
            permissions.add(generation_permission_name(mode))
    if user["can_text_generate"] or user["is_admin"]:
        permissions.add("text.generate")
    for tool in TOOL_PERMISSION_COLUMNS:
        if image_tool_allowed(user, tool):
            permissions.add(tool_permission_name(tool))
    if any(
        permission.startswith(("image.", "text."))
        for permission in permissions
    ):
        permissions.add("novelai.proxy")
    if user["is_admin"]:
        permissions.update({"history.all", "admin.users", "admin.config"})
    return {
        "id": user["id"],
        "username": user["username"],
        "is_admin": bool(user["is_admin"]),
        "permissions": sorted(permissions),
    }


def user_admin_dict(user: sqlite3.Row) -> dict[str, Any]:
    return {
        **user_to_dict(user),
        "disabled": bool(user["disabled"]),
        "green_point_discount": user["green_point_discount"],
        "can_generate_paid": bool(user["can_generate_paid"]),
        "can_text_generate": bool(user["can_text_generate"]),
        "can_image_upscale": bool(user["can_image_upscale"]),
        "can_image_augment": bool(user["can_image_augment"]),
        "can_image_encode_vibe": bool(user["can_image_encode_vibe"]),
        "green_point_limit": user["green_point_limit"],
        "green_point_used": user["green_point_used"],
        "red_points": user["red_points"],
        "red_points_used": user["red_points_used"],
        "created_at": user["created_at"],
    }


def not_authenticated(message: str) -> HTTPException:
    return api_error(status.HTTP_401_UNAUTHORIZED, "not_authenticated", message)


async def require_user(request: Request, db: sqlite3.Connection = Depends(get_db)) -> sqlite3.Row:
    if only_auth.enabled:
        local_id = await only_auth.user_id(request)
        user = db.execute("SELECT * FROM users WHERE id = ?", (local_id,)).fetchone()
        if not user or user["disabled"]:
            raise not_authenticated("User disabled")
        return user
    token = request.cookies.get("access_token")
    auth = request.headers.get("Authorization", "")
    if not token and auth.lower().startswith("bearer "):
        token = auth[7:].strip()
    if not token:
        raise not_authenticated("Not authenticated")
    try:
        payload = decode_jwt(token, SECRET_KEY)
    except TokenError:
        raise not_authenticated("Invalid session")
    session_id = payload.get("jti")
    user_id = payload.get("sub")
    if not session_id or not user_id:
        raise not_authenticated("Invalid session")
    try:
        user_id_int = int(user_id)
    except (TypeError, ValueError):
        raise not_authenticated("Invalid session")
    session = db.execute(
        "SELECT * FROM sessions WHERE id = ? AND user_id = ? AND revoked_at IS NULL",
        (session_id, user_id_int),
    ).fetchone()
    if not session:
        raise not_authenticated("Session expired")
    if datetime.fromisoformat(session["expires_at"]) < datetime.now(timezone.utc):
        raise not_authenticated("Session expired")
    user = db.execute("SELECT * FROM users WHERE id = ?", (user_id_int,)).fetchone()
    if not user or user["disabled"]:
        raise not_authenticated("User disabled")
    return user


def require_admin(user: sqlite3.Row = Depends(require_user)) -> sqlite3.Row:
    if not user["is_admin"]:
        raise permission_denied("admin", "Admin required")
    return user


@app.get("/api/health")
def health():
    return {"ok": True}


@app.post("/api/login")
def login(payload: LoginRequest, response: Response, db: sqlite3.Connection = Depends(get_db)):
    if only_auth.enabled or not ALLOW_PASSWORD_LOGIN:
        raise HTTPException(status.HTTP_410_GONE, "Password login is disabled")
    user = db.execute("SELECT * FROM users WHERE username = ?", (payload.username,)).fetchone()
    if not user or user["disabled"] or not verify_password(payload.password, user["password_hash"]):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid username or password")
    return session_response(response, db, user)


@app.post("/api/logout")
async def logout(request: Request, response: Response, db: sqlite3.Connection = Depends(get_db)):
    if only_auth.enabled:
        await only_auth.logout(request)
        response.delete_cookie(only_auth.cookie, secure=True, httponly=True, samesite="lax")
        response.delete_cookie("access_token", path="/")
        response.delete_cookie("naiweaver_current_task", path="/")
        return {"ok": True}
    token = request.cookies.get("access_token")
    if token:
        try:
            payload = decode_jwt(token, SECRET_KEY)
            session_id = payload.get("jti")
            if session_id:
                db.execute(
                    "UPDATE sessions SET revoked_at = ? WHERE id = ?",
                    (now_iso(), session_id),
                )
                db.commit()
        except TokenError:
            pass
    response.delete_cookie("access_token", path="/")
    response.delete_cookie("naiweaver_current_task", path="/")
    return {"ok": True}


def image_rules_for_user(db: sqlite3.Connection, user: sqlite3.Row) -> dict[str, Any]:
    """``rules.image`` for this user (contract §2), the input of every quote."""
    return build_image_rules(
        is_admin=bool(user["is_admin"]),
        can_generate_paid=bool(user["can_generate_paid"]),
        green_point_discount=green_point_discount_for(user),
        allowance_exhausted=free_allowance_exhausted_until(db) is not None,
    )


@app.get("/api/me")
def me(user: sqlite3.Row = Depends(require_user), db: sqlite3.Connection = Depends(get_db)):
    return {
        "user": user_to_dict(user),
        "quota": quota_for_user(user),
        "rules": {"image": image_rules_for_user(db, user)},
    }


@app.get("/auth/login")
async def only_webauth_login(request: Request):
    return await only_auth.login(request)


@app.get("/auth/callback")
async def only_webauth_callback(request: Request, db: sqlite3.Connection = Depends(get_db)):
    if not only_auth.enabled:
        raise HTTPException(404, "Not found")
    return await only_auth.callback(request, db)


def usage_for(db: sqlite3.Connection, user_id: int, mode: str) -> int:
    row = db.execute(
        "SELECT used FROM quota_usage WHERE user_id = ? AND quota_date = ? AND mode = ?",
        (user_id, today_key(), mode),
    ).fetchone()
    return int(row["used"]) if row else 0


def quota_bucket(user: sqlite3.Row, mode: str) -> dict[str, Any]:
    enabled = image_generation_allowed(user, mode)
    if mode == "paid":
        limit = int(user["red_points"])
        reserved = int(user["red_points_reserved"])
        return {
            "date": None,
            "mode": mode,
            "kind": "points",
            "red_points": limit,
            "point_limit": limit,
            "used": int(user["red_points_used"]) + reserved,
            "reserved": reserved,
            "remaining": remaining_points(user, "red"),
            "unlimited": False,
            "enabled": enabled,
        }
    limit = int(user["green_point_limit"])
    reserved = int(user["green_points_reserved"])
    remaining = remaining_points(user, "green")
    return {
        "date": None,
        "mode": mode,
        "kind": "points",
        "green_point_limit": limit,
        "green_point_discount": green_point_discount_for(user),
        "point_limit": limit,
        "used": int(user["green_point_used"]) + reserved,
        "reserved": reserved,
        "remaining": 0 if remaining is None else max(0, remaining),
        "unlimited": remaining is None,
        "enabled": enabled,
    }


def quota_for_user(user: sqlite3.Row) -> dict[str, Any]:
    return {
        "free": quota_bucket(user, "free"),
        "paid": quota_bucket(user, "paid"),
    }


@app.get("/api/quota")
def quota(user: sqlite3.Row = Depends(require_user)):
    return quota_for_user(user)


@app.post("/api/feedback", status_code=status.HTTP_201_CREATED)
def create_client_feedback(
    payload: ClientFeedbackCreateRequest,
    user: sqlite3.Row = Depends(require_user),
    db: sqlite3.Connection = Depends(get_db),
):
    cutoff = (datetime.now(timezone.utc) - timedelta(hours=1)).isoformat()
    recent_count = db.execute(
        "SELECT COUNT(*) FROM client_feedback_reports "
        "WHERE user_id = ? AND created_at >= ?",
        (user["id"], cutoff),
    ).fetchone()[0]
    if recent_count >= 10:
        raise api_error(
            status.HTTP_429_TOO_MANY_REQUESTS,
            "rate_limited",
            "Too many feedback reports; please try again later",
            limit=10,
        )

    context_json = json.dumps(
        payload.client_context.model_dump(mode="json"),
        ensure_ascii=False,
        separators=(",", ":"),
    )
    diagnostics_json = json.dumps(
        [event.model_dump(mode="json") for event in payload.diagnostics],
        ensure_ascii=False,
        separators=(",", ":"),
    )
    if len(context_json.encode("utf-8")) + len(diagnostics_json.encode("utf-8")) > 1_000_000:
        raise api_error(
            status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            "request_too_large",
            "Diagnostic report too large",
            limit=1_000_000,
        )

    report_id = f"fb_{secrets.token_urlsafe(12)}"
    created_at = now_iso()
    db.execute(
        """
        INSERT INTO client_feedback_reports(
          id, user_id, description, client_context_json, diagnostics_json,
          event_count, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
        """,
        (
            report_id,
            user["id"],
            payload.description.strip(),
            context_json,
            diagnostics_json,
            len(payload.diagnostics),
            created_at,
        ),
    )
    db.commit()
    return {"id": report_id, "created_at": created_at}


def recent_image_generation_seconds(db: sqlite3.Connection) -> float:
    """Use recent successful jobs to give the queue a deliberately simple ETA."""
    row = db.execute(
        """
        SELECT AVG((julianday(completed_at) - julianday(started_at)) * 86400.0)
        FROM (
          SELECT started_at, completed_at
          FROM generation_tasks
          WHERE status = 'success' AND started_at IS NOT NULL AND completed_at IS NOT NULL
          ORDER BY completed_at DESC
          LIMIT 50
        )
        """
    ).fetchone()
    value = float(row[0]) if row and row[0] is not None else 30.0
    return max(5.0, min(value, 300.0))


@app.get("/api/queue")
async def queue_status(
    user: sqlite3.Row = Depends(require_user),
    db: sqlite3.Connection = Depends(get_db),
):
    assert queue_condition is not None
    assert text_queue_condition is not None
    async with queue_condition:
        image_own_index = next(
            (index for index, job in enumerate(pending_jobs) if job.user_id == user["id"]),
            None,
        )
        image_queued = len(pending_jobs)
        image_active = len(active_user_ids)
        user_image_active = int(user["id"]) in active_user_ids
        user_pending_count = sum(job.user_id == user["id"] for job in pending_jobs)
    async with text_queue_condition:
        text_own_index = next(
            (
                index
                for index, job in enumerate(pending_text_jobs)
                if job.user_id == user["id"]
            ),
            None,
        )
        text_queued = len(pending_text_jobs)
        text_active = active_text_count
        user_text_active = int(user["id"]) in active_text_user_ids
    own_indices = [
        index for index in (image_own_index, text_own_index) if index is not None
    ]
    tasks_ahead = min(own_indices) if own_indices else None
    user_queued = image_own_index is not None or text_own_index is not None
    # A single image worker executes the ordered image queue. The currently
    # running request counts as one average job before the first queued item.
    image_wait_seconds = (
        0
        if user_image_active
        else round((image_own_index + image_active) * recent_image_generation_seconds(db))
        if image_own_index is not None
        else None
    )
    return {
        "queued": image_queued + text_queued,
        "active": image_active + text_active,
        "user_active": user_image_active or user_text_active,
        "user_queued": user_queued,
        "tasks_ahead": tasks_ahead,
        "estimated_wait_seconds": image_wait_seconds,
        "user_pending_count": user_pending_count,
        "text_concurrency": TEXT_GLOBAL_CONCURRENCY,
    }


@app.get("/api/admin/users")
def admin_users(
    _: sqlite3.Row = Depends(require_admin),
    db: sqlite3.Connection = Depends(get_db),
):
    rows = db.execute("SELECT * FROM users ORDER BY id").fetchall()
    return {"items": [user_admin_dict(row) for row in rows]}


@app.get("/api/admin/feedback")
def admin_feedback_reports(
    limit: int = 100,
    user_id: int | None = None,
    _: sqlite3.Row = Depends(require_admin),
    db: sqlite3.Connection = Depends(get_db),
):
    where: list[str] = []
    params: list[Any] = []
    if user_id is not None:
        where.append("f.user_id = ?")
        params.append(user_id)
    where_sql = f"WHERE {' AND '.join(where)}" if where else ""
    params.append(max(1, min(limit, 500)))
    rows = db.execute(
        f"""
        SELECT f.id, f.user_id, u.username, f.description,
               f.client_context_json, f.event_count, f.created_at
        FROM client_feedback_reports f
        JOIN users u ON u.id = f.user_id
        {where_sql}
        ORDER BY f.created_at DESC
        LIMIT ?
        """,
        params,
    ).fetchall()
    items = []
    for row in rows:
        item = dict(row)
        item["client_context"] = json.loads(item.pop("client_context_json"))
        items.append(item)
    return {"items": items}


@app.get("/api/admin/feedback/{feedback_id}")
def admin_feedback_report(
    feedback_id: str,
    _: sqlite3.Row = Depends(require_admin),
    db: sqlite3.Connection = Depends(get_db),
):
    row = db.execute(
        """
        SELECT f.*, u.username
        FROM client_feedback_reports f
        JOIN users u ON u.id = f.user_id
        WHERE f.id = ?
        """,
        (feedback_id,),
    ).fetchone()
    if not row:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Feedback report not found")
    item = dict(row)
    item["client_context"] = json.loads(item.pop("client_context_json"))
    item["diagnostics"] = json.loads(item.pop("diagnostics_json"))
    return item


@app.get("/api/admin/audit")
def admin_audit_logs(
    limit: int = 100,
    user_id: int | None = None,
    _: sqlite3.Row = Depends(require_admin),
    db: sqlite3.Connection = Depends(get_db),
):
    where: list[str] = []
    params: list[Any] = []
    if user_id is not None:
        where.append("a.user_id = ?")
        params.append(user_id)
    where_sql = f"WHERE {' AND '.join(where)}" if where else ""
    params.append(max(1, min(limit, 500)))
    rows = db.execute(
        f"""
        SELECT a.*, u.username
        FROM request_audit_logs a
        JOIN users u ON u.id = a.user_id
        {where_sql}
        ORDER BY a.created_at DESC
        LIMIT ?
        """,
        params,
    ).fetchall()
    items = []
    for row in rows:
        item = dict(row)
        item["request_body_available"] = bool(item["request_body_path"])
        item["request_body_url"] = (
            f"/api/admin/audit/{item['id']}/body"
            if item["request_body_path"]
            else None
        )
        items.append(item)
    return {"items": items}


@app.get("/api/admin/audit/{audit_id}/body")
def admin_audit_body(
    audit_id: str,
    _: sqlite3.Row = Depends(require_admin),
    db: sqlite3.Connection = Depends(get_db),
):
    row = db.execute(
        """
        SELECT request_body_path, request_content_type
        FROM request_audit_logs
        WHERE id = ?
        """,
        (audit_id,),
    ).fetchone()
    if not row or not row["request_body_path"]:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Audit body not found")
    audit_root = AUDIT_DIR.resolve()
    body_path = (audit_root / row["request_body_path"]).resolve()
    if audit_root not in body_path.parents or not body_path.exists():
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Audit body not found")
    return FileResponse(
        body_path,
        media_type=row["request_content_type"] or "application/octet-stream",
        filename=f"{audit_id}.body",
    )


@app.post("/api/admin/users")
def admin_create_user(
    payload: UserCreateRequest,
    _: sqlite3.Row = Depends(require_admin),
    db: sqlite3.Connection = Depends(get_db),
):
    values = role_defaults(payload.role)
    values.update(
        (name, value)
        for name in values
        if (value := getattr(payload, name)) is not None
    )
    if values["is_admin"]:
        values["green_point_discount"] = 100
    columns = {
        "username": payload.username,
        "password_hash": hash_password(payload.password or secrets.token_urlsafe(32)),
        **{name: int(value) for name, value in values.items()},
        "disabled": int(payload.disabled),
        "green_point_used": payload.green_point_used,
        "red_points_used": payload.red_points_used,
        "created_at": now_iso(),
    }
    try:
        db.execute(
            f"INSERT INTO users({', '.join(columns)}) "
            f"VALUES ({', '.join('?' for _ in columns)})",
            tuple(columns.values()),
        )
        db.commit()
    except sqlite3.IntegrityError:
        raise HTTPException(status.HTTP_409_CONFLICT, "Username already exists")
    user = db.execute("SELECT * FROM users WHERE username = ?", (payload.username,)).fetchone()
    return {"user": user_admin_dict(user)}


@app.patch("/api/admin/users/{user_id}")
def admin_update_user(
    user_id: int,
    payload: UserUpdateRequest,
    _: sqlite3.Row = Depends(require_admin),
    db: sqlite3.Connection = Depends(get_db),
):
    user = db.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
    if not user:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "User not found")

    values: list[Any] = []
    assignments: list[str] = []
    bool_fields = {
        "is_admin",
        "disabled",
        "can_generate_paid",
        "can_text_generate",
        "can_image_upscale",
        "can_image_augment",
        "can_image_encode_vibe",
    }
    int_fields = {
        "green_point_discount",
        "green_point_limit",
        "green_point_used",
        "red_points",
        "red_points_used",
    }
    fields = set(payload.model_fields_set)
    makes_admin = bool(payload.is_admin) and "is_admin" in fields
    if makes_admin:
        # Administrators are always unlimited, as when one is created.
        fields.add("green_point_discount")
    for field in sorted(fields):
        if field == "password":
            if payload.password:
                assignments.append("password_hash = ?")
                values.append(hash_password(payload.password))
        elif field in bool_fields:
            assignments.append(f"{field} = ?")
            values.append(int(bool(getattr(payload, field))))
        elif field in int_fields:
            assignments.append(f"{field} = ?")
            values.append(
                100
                if makes_admin and field == "green_point_discount"
                else getattr(payload, field)
            )
    if assignments:
        values.append(user_id)
        db.execute(f"UPDATE users SET {', '.join(assignments)} WHERE id = ?", values)
        db.commit()
    updated = db.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
    return {"user": user_admin_dict(updated)}


@app.get("/api/admin/config")
def admin_config(
    _: sqlite3.Row = Depends(require_admin),
    db: sqlite3.Connection = Depends(get_db),
):
    exhausted_until = free_allowance_exhausted_until(db)
    return {
        "green_point_limit": DEFAULT_GREEN_POINT_LIMIT,
        "green_point_discount": 0,
        "red_points": DEFAULT_RED_POINTS,
        "admin_red_points": DEFAULT_ADMIN_RED_POINTS,
        "free_max_steps": MAX_STEPS_FREE,
        "paid_max_steps": MAX_STEPS_PAID,
        "admin_max_steps": MAX_STEPS_ADMIN,
        "max_dimension": MAX_DIMENSION,
        "allowed_samplers": sorted(ALLOWED_SAMPLERS),
        "queue_weights": QUEUE_WEIGHTS,
        "text_concurrency": TEXT_GLOBAL_CONCURRENCY,
        "fake_novelai": FAKE_NOVELAI,
        "has_novelai_token": bool(novelai_token()),
        "tool_caps": dict(TOOL_CAPS),
        "free_allowance": {
            "exhausted": exhausted_until is not None,
            "exhausted_until": exhausted_until.isoformat() if exhausted_until else None,
            "cooldown_seconds": FREE_ALLOWANCE_COOLDOWN_SECONDS,
        },
    }


def mode_for_user(user: sqlite3.Row) -> str:
    if user["is_admin"]:
        return "admin"
    if user["can_generate_paid"]:
        return "paid"
    return "free"


def audit_request_preview(body: bytes) -> str:
    if not body:
        return ""
    text = body.decode("utf-8", errors="replace")
    if len(text) > AUDIT_MAX_STRING_CHARS:
        omitted = len(text) - AUDIT_MAX_STRING_CHARS
        return f"{text[:AUDIT_MAX_STRING_CHARS]}<truncated {omitted} chars>"
    return text


def write_audit_body_file(
    *,
    audit_id: str,
    user_id: int,
    created_at: str,
    body: bytes,
) -> tuple[str | None, int, str]:
    if not body:
        return None, 0, ""
    day = created_at[:10]
    relative_path = Path(day) / f"user-{user_id}" / f"{audit_id}.body"
    audit_root = AUDIT_DIR.resolve()
    body_path = (audit_root / relative_path).resolve()
    if audit_root not in body_path.parents:
        raise RuntimeError("Invalid audit body path")
    body_path.parent.mkdir(parents=True, exist_ok=True)
    body_path.write_bytes(body)
    return relative_path.as_posix(), len(body), hashlib.sha256(body).hexdigest()


def create_audit_log(
    db: sqlite3.Connection,
    user: sqlite3.Row,
    *,
    service: str,
    path: str,
    method: str,
    body: bytes,
    content_type: str,
) -> str:
    audit_id = secrets.token_urlsafe(18)
    created_at = now_iso()
    body_path, body_bytes, body_sha256 = write_audit_body_file(
        audit_id=audit_id,
        user_id=int(user["id"]),
        created_at=created_at,
        body=body,
    )
    db.execute(
        """
        INSERT INTO request_audit_logs(
          id, user_id, service, path, method, request_content_type,
          request_json, request_body_path, request_body_bytes,
          request_body_sha256, created_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            audit_id,
            int(user["id"]),
            service,
            path,
            method,
            content_type,
            audit_request_preview(body),
            body_path,
            body_bytes,
            body_sha256,
            created_at,
        ),
    )
    db.commit()
    return audit_id


def complete_audit_log(
    db: sqlite3.Connection,
    audit_id: str | None,
    *,
    status_code: int | None,
    error_message: str | None = None,
) -> None:
    if audit_id is None:
        return
    db.execute(
        """
        UPDATE request_audit_logs
        SET status_code = ?, error_message = ?, completed_at = ?
        WHERE id = ?
        """,
        (status_code, error_message, now_iso(), audit_id),
    )
    db.commit()


def require_novelai_proxy_permission(
    service: str, path: str, method: str, user: sqlite3.Row
) -> None:
    endpoint_denied = permission_denied(
        "novelai.proxy", "NovelAI endpoint is not allowed"
    )
    if service == "text":
        if method != "POST" or path not in ALLOWED_TEXT_PROXY_PATHS:
            raise endpoint_denied
        if not (user["can_text_generate"] or user["is_admin"]):
            raise permission_denied("text.generate", "Text generation is not allowed")
        return
    if service == "image":
        if path == "ai/generate-image":
            raise invalid_parameters(
                "path", "Submit image generation through /api/generation-tasks"
            )
        tool = PAID_TOOL_PATHS.get(path)
        if method != "POST" or tool is None:
            raise endpoint_denied
        if not image_tool_allowed(user, tool):
            raise permission_denied(
                tool_permission_name(tool), "This image tool is not allowed"
            )
        return
    if service == "api":
        if method != "GET" or path not in ALLOWED_API_PROXY_PATHS:
            raise endpoint_denied
        if path == "user/subscription" and not user["is_admin"]:
            raise permission_denied("admin", "NovelAI subscription is admin-only")
        return
    raise endpoint_denied


def response_headers(headers: httpx.Headers) -> dict[str, str]:
    return {
        key: value
        for key, value in headers.items()
        if key.lower() not in HOP_BY_HOP_HEADERS
    }


def novelai_url(service: str, path: str) -> str:
    if path == "user/subscription" and service in {"api", "image", "text"}:
        return f"{TARGET_BASES['image']}/{path}"
    return f"{TARGET_BASES[service]}/{path}"


async def forward_to_novelai(
    service: str,
    path: str,
    *,
    method: str,
    body: bytes = b"",
    stream: bool = False,
) -> tuple[int, dict[str, str], bytes] | StreamingResponse:
    """Call NovelAI. Only a successful streamed call returns a stream; every
    other outcome is a complete ``(status, headers, body)`` tuple."""
    if service not in TARGET_BASES:
        raise api_error(status.HTTP_404_NOT_FOUND, "not_found", "Unknown NovelAI service")
    token = novelai_token()
    if not token and not FAKE_NOVELAI:
        raise api_error(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            "service_unavailable",
            "NovelAI token is not configured",
        )
    if FAKE_NOVELAI:
        return fake_response(service, path, method)
    assert http_client is not None
    url = novelai_url(service, path)
    headers = {"Authorization": f"Bearer {token}"}
    if method.upper() == "POST":
        headers["Content-Type"] = "application/json"
    if stream:
        headers["Accept"] = "text/event-stream, application/json"
    try:
        if stream:
            req = http_client.build_request(method, url, content=body, headers=headers)
            upstream = await http_client.send(req, stream=True)
            if not 200 <= upstream.status_code < 300:
                try:
                    content = await upstream.aread()
                finally:
                    await upstream.aclose()
                return upstream.status_code, response_headers(upstream.headers), content

            async def body_iter():
                try:
                    async for chunk in upstream.aiter_bytes():
                        yield chunk
                finally:
                    await upstream.aclose()

            return StreamingResponse(
                body_iter(),
                status_code=upstream.status_code,
                headers=response_headers(upstream.headers),
                media_type=upstream.headers.get("content-type"),
            )
        upstream = await http_client.request(method, url, content=body, headers=headers)
    except httpx.HTTPError as exc:
        logger.warning(
            "novelai_request_failed service=%s path=%s exception_type=%s",
            service,
            path,
            type(exc).__name__,
        )
        raise upstream_error(None, "NovelAI is unreachable") from None
    return upstream.status_code, response_headers(upstream.headers), upstream.content


def raise_for_upstream_status(
    service: str, path: str, status_code: int, content: bytes, request_body: bytes = b""
) -> None:
    """Map any NovelAI non-2xx (including its 401/403) to 502 upstream_error."""
    if 200 <= status_code < 300:
        return
    logger.warning(
        "novelai_upstream_error service=%s path=%s status_code=%s response_preview=%s",
        service,
        path,
        status_code,
        safe_upstream_error_preview(content, request_body),
    )
    raise upstream_error(status_code, f"NovelAI returned HTTP {status_code}")


async def acquire_text_slot(user: sqlite3.Row) -> TextQueueTicket:
    global text_queue_virtual_time, active_text_count
    assert text_queue_condition is not None
    user_id = int(user["id"])
    queue_class = mode_for_user(user)
    weight = QUEUE_WEIGHTS[queue_class]
    async with text_queue_condition:
        if user_id in active_text_user_ids or any(
            job.user_id == user_id for job in pending_text_jobs
        ):
            raise api_error(
                status.HTTP_429_TOO_MANY_REQUESTS,
                "queue_full",
                "User already has an active text generation",
                limit=1,
            )
        base = max(text_queue_virtual_time, text_queue_last_finish[queue_class])
        virtual_finish = base + (1.0 / weight)
        text_queue_last_finish[queue_class] = virtual_finish
        ticket = TextQueueTicket(
            virtual_finish=virtual_finish,
            negative_weight=-weight,
            created_at=now_iso(),
            user_id=user_id,
            username=user["username"],
            ticket_id=secrets.token_urlsafe(12),
        )
        pending_text_jobs.append(ticket)
        pending_text_jobs.sort(key=lambda job: job.sort_key)
        text_queue_condition.notify_all()
        try:
            while True:
                is_next = bool(pending_text_jobs) and pending_text_jobs[0] == ticket
                has_capacity = active_text_count < TEXT_GLOBAL_CONCURRENCY
                if is_next and has_capacity:
                    pending_text_jobs.pop(0)
                    active_text_user_ids.add(user_id)
                    active_text_count += 1
                    text_queue_virtual_time = max(
                        text_queue_virtual_time, ticket.virtual_finish
                    )
                    text_queue_condition.notify_all()
                    return ticket
                await text_queue_condition.wait()
        except BaseException:
            if ticket in pending_text_jobs:
                pending_text_jobs.remove(ticket)
                text_queue_condition.notify_all()
            raise


async def release_text_slot(ticket: TextQueueTicket) -> None:
    global active_text_count
    assert text_queue_condition is not None
    async with text_queue_condition:
        if ticket.user_id in active_text_user_ids:
            active_text_user_ids.discard(ticket.user_id)
            active_text_count = max(0, active_text_count - 1)
            text_queue_condition.notify_all()


async def forward_text_to_novelai_queued(
    user: sqlite3.Row,
    service: str,
    path: str,
    *,
    method: str,
    body: bytes,
    stream: bool,
    audit_id: str | None = None,
) -> tuple[int, dict[str, str], bytes] | StreamingResponse:
    ticket = await acquire_text_slot(user)
    try:
        result = await forward_to_novelai(
            service, path, method=method, body=body, stream=stream
        )
    except Exception:
        with db_session() as db:
            complete_audit_log(
                db, audit_id, status_code=500, error_message="Text proxy failed"
            )
        await release_text_slot(ticket)
        raise
    if isinstance(result, StreamingResponse):
        body_iterator = result.body_iterator

        async def queued_body_iter():
            try:
                async for chunk in body_iterator:
                    yield chunk
            finally:
                close = getattr(body_iterator, "aclose", None)
                if close is not None:
                    await close()
                with db_session() as db:
                    complete_audit_log(db, audit_id, status_code=result.status_code)
                await release_text_slot(ticket)

        return StreamingResponse(
            queued_body_iter(),
            status_code=result.status_code,
            headers=dict(result.headers),
            media_type=result.media_type,
        )
    await release_text_slot(ticket)
    with db_session() as db:
        complete_audit_log(db, audit_id, status_code=result[0])
    return result


def fake_response(service: str, path: str, method: str) -> tuple[int, dict[str, str], bytes]:
    if path == "user/subscription":
        return 200, {"content-type": "application/json"}, json.dumps(
            {"trainingStepsLeft": {"fixedTrainingStepsLeft": 9999, "purchasedTrainingSteps": 0}}
        ).encode()
    if path.endswith("generate-image") or path.endswith("augment-image") or path.endswith("upscale"):
        buf = BytesIO()
        with ZipFile(buf, "w") as archive:
            archive.writestr("image.png", fake_png())
        return 200, {"content-type": "application/zip"}, buf.getvalue()
    if path.endswith("encode-vibe"):
        return 200, {"content-type": "application/octet-stream"}, b"fake-vibe"
    if service == "text":
        return 200, {"content-type": "application/json"}, json.dumps({"output": "fake text"}).encode()
    return 404, {"content-type": "application/json"}, b'{"error":"not found"}'


def parse_anlas_balance(data: Any) -> int | None:
    if not isinstance(data, dict):
        return None
    steps = data.get("trainingStepsLeft")
    if isinstance(steps, int):
        return steps
    if isinstance(steps, dict):
        fixed = steps.get("fixedTrainingStepsLeft") or 0
        purchased = steps.get("purchasedTrainingSteps") or 0
        try:
            return int(fixed) + int(purchased)
        except (TypeError, ValueError):
            return None
    return None


async def fetch_anlas_balance(retries: int = 2) -> int | None:
    for attempt in range(retries + 1):
        try:
            result = await forward_to_novelai(
                "image", "user/subscription", method="GET"
            )
            if isinstance(result, StreamingResponse):
                return None
            status_code, _, content = result
            if status_code == 200:
                return parse_anlas_balance(json.loads(content.decode("utf-8")))
        except Exception:
            pass
        if attempt < retries:
            await asyncio.sleep(0.5)
    return None


@dataclass(frozen=True)
class UpstreamImageCall:
    status_code: int
    headers: dict[str, str]
    content: bytes
    anlas_before: int | None
    anlas_after: int | None

    @property
    def ok(self) -> bool:
        return 200 <= self.status_code < 300

    @property
    def measured_delta(self) -> int | None:
        if self.anlas_before is None or self.anlas_after is None:
            return None
        return self.anlas_before - self.anlas_after


async def call_image_upstream(path: str, body: bytes) -> UpstreamImageCall:
    """One NovelAI image call and its measured Anlas cost.

    The caller must hold ``upstream_lane``: NovelAI rejects a second
    concurrent image call on the account, and the balance delta is only
    attributable while nothing else runs.
    """
    assert upstream_lane.held, "image calls must hold the upstream lane"
    anlas_before = await fetch_anlas_balance()
    result = await forward_to_novelai("image", path, method="POST", body=body)
    assert not isinstance(result, StreamingResponse)
    status_code, headers, content = result
    anlas_after = await fetch_anlas_balance() if 200 <= status_code < 300 else None
    return UpstreamImageCall(status_code, headers, content, anlas_before, anlas_after)


def paid_tool_idempotency_key(request: Request, tool: str) -> str:
    """Validate the paid-tool headers (contract §5) and return the key."""
    key = request.headers.get("idempotency-key", "").strip()
    if not 8 <= len(key) <= 128:
        raise invalid_parameters(
            "Idempotency-Key", "An Idempotency-Key header of 8-128 characters is required"
        )
    expected = request.headers.get("x-naiweaver-expected-points", "").strip()
    if not re.fullmatch(r"[0-9]{1,9}", expected):
        raise invalid_parameters(
            "X-NAIWeaver-Expected-Points",
            "X-NAIWeaver-Expected-Points must be the integer tool price",
        )
    quote = tool_quote(tool)
    if int(expected) != quote.points:
        raise api_error(
            status.HTTP_409_CONFLICT,
            "quote_changed",
            "The tool price has changed",
            quote=quote.to_dict(),
        )
    return key


async def execute_paid_tool(
    db: sqlite3.Connection, user_id: int, *, path: str, tool: str, body: bytes
) -> CachedResponse:
    """Reserve the tool cap, call NovelAI in the lane, settle the measured cost."""
    cap = TOOL_CAPS[tool]
    with immediate_transaction(db):
        reserve_points(db, user_id, "red", cap)
    settled = False
    try:
        async with upstream_lane.hold(RED_PRIORITY):
            call = await call_image_upstream(path, body)
        raise_for_upstream_status("image", path, call.status_code, call.content)
        charge, above_quote = settle_amount(cap, call.measured_delta)
        with immediate_transaction(db):
            settle_points(db, user_id, "red", cap, charge)
            if above_quote:
                record_billing_anomaly(
                    db,
                    kind=ANOMALY_MEASURED_ABOVE_QUOTE,
                    user_id=user_id,
                    mode="paid",
                    quoted=cap,
                    measured=call.measured_delta,
                    note="Measured Anlas delta exceeded the tool cap; charged the cap",
                    tool=tool,
                )
        settled = True
    finally:
        if not settled:
            # Upstream failure, cancellation or a settlement error: the user
            # is never charged for work that did not complete.
            with immediate_transaction(db):
                release_points(db, user_id, "red", cap)
    return CachedResponse(call.status_code, call.headers, call.content)


async def run_paid_tool(
    db: sqlite3.Connection,
    user: sqlite3.Row,
    *,
    path: str,
    tool: str,
    body: bytes,
    idempotency_key: str,
) -> Response:
    cache_key = (int(user["id"]), idempotency_key)
    body_hash = hashlib.sha256(body).hexdigest()
    while (entry := tool_response_cache.lookup(cache_key)) is not None:
        if entry.body_hash != body_hash:
            raise api_error(
                status.HTTP_409_CONFLICT,
                "duplicate_request",
                "Idempotency-Key was reused with a different request body",
            )
        cached = await asyncio.shield(entry.future)
        if cached is not None:
            return Response(
                content=cached.content,
                status_code=cached.status_code,
                headers=cached.headers,
            )
        # The first attempt failed and released its reservation; try again.
    entry = tool_response_cache.begin(cache_key, body_hash)
    try:
        result = await execute_paid_tool(
            db, int(user["id"]), path=path, tool=tool, body=body
        )
    except BaseException:
        tool_response_cache.fail(cache_key, entry)
        raise
    tool_response_cache.complete(cache_key, entry, result)
    return Response(
        content=result.content, status_code=result.status_code, headers=result.headers
    )


def fake_png() -> bytes:
    return bytes.fromhex(
        "89504e470d0a1a0a0000000d4948445200000001000000010802000000907753de"
        "0000000c49444154789c6360f8cf00000301010118dd8db00000000049454e44ae426082"
    )


def decode_zip_image(data: bytes) -> bytes | None:
    entry_sizes: list[int] = []
    try:
        with ZipFile(BytesIO(data)) as archive:
            for item in archive.infolist():
                if item.is_dir():
                    continue
                entry_sizes.append(item.file_size)
                raw = archive.read(item)
                if raw.startswith(b"\x89PNG") or raw.startswith(b"RIFF"):
                    return raw
    except Exception as exc:
        logger.exception(
            "novelai_image_archive_decode_failed exception_type=%s error=%r "
            "response_bytes=%s response_sha256=%s",
            type(exc).__name__,
            str(exc),
            len(data),
            hashlib.sha256(data).hexdigest(),
        )
        return None
    logger.error(
        "novelai_image_archive_missing_valid_image response_bytes=%s "
        "response_sha256=%s archive_entry_count=%s archive_entry_sizes=%s",
        len(data),
        hashlib.sha256(data).hexdigest(),
        len(entry_sizes),
        entry_sizes,
    )
    return None


def history_thumbnail_relative_path(image_path: str) -> Path:
    relative = Path(image_path).with_suffix(".webp")
    if relative.is_absolute() or ".." in relative.parts:
        raise ValueError("Invalid image path")
    return relative


def resolve_history_image_file(image_path: str) -> Path:
    relative = Path(image_path)
    if relative.is_absolute() or ".." in relative.parts:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Image not found")
    path = (IMAGE_DIR / relative).resolve()
    image_root = IMAGE_DIR.resolve()
    if not path.exists() or not path.is_file() or image_root not in path.parents:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Image not found")
    return path


def resolve_history_thumbnail_file(image_path: str) -> Path:
    try:
        relative = history_thumbnail_relative_path(image_path)
    except ValueError:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Thumbnail not found") from None
    path = (THUMBNAIL_DIR / relative).resolve()
    thumbnail_root = THUMBNAIL_DIR.resolve()
    if thumbnail_root not in path.parents:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Thumbnail not found")
    return path


def generate_history_thumbnail(source: Path, target: Path) -> None:
    try:
        from PIL import Image, ImageOps, UnidentifiedImageError
    except ModuleNotFoundError as exc:
        raise RuntimeError("Pillow is not installed") from exc

    target.parent.mkdir(parents=True, exist_ok=True)
    tmp = target.with_name(f"{target.stem}.tmp{target.suffix}")
    try:
        with Image.open(source) as image:
            thumbnail = ImageOps.exif_transpose(image)
            thumbnail.thumbnail(
                (THUMBNAIL_MAX_SIZE, THUMBNAIL_MAX_SIZE),
                Image.Resampling.LANCZOS,
            )
            if thumbnail.mode not in {"RGB", "RGBA"}:
                mode = "RGBA" if "A" in thumbnail.getbands() else "RGB"
                thumbnail = thumbnail.convert(mode)
            thumbnail.save(
                tmp,
                format="WEBP",
                quality=THUMBNAIL_WEBP_QUALITY,
                method=4,
            )
        tmp.replace(target)
    finally:
        if tmp.exists():
            tmp.unlink(missing_ok=True)


def ensure_history_thumbnail(image_path: str) -> Path:
    source = resolve_history_image_file(image_path)
    target = resolve_history_thumbnail_file(image_path)
    if target.exists() and target.stat().st_mtime >= source.stat().st_mtime:
        return target
    try:
        generate_history_thumbnail(source, target)
    except (OSError, RuntimeError, ValueError):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Thumbnail not available") from None
    return target


async def save_history_image(task_id: str, data: bytes) -> str | None:
    image = decode_zip_image(data)
    if image is None:
        return None
    day_dir = IMAGE_DIR / today_key()
    day_dir.mkdir(parents=True, exist_ok=True)
    path = day_dir / f"{task_id}.png"
    path.write_bytes(image)
    image_path = str(path.relative_to(IMAGE_DIR))
    try:
        await asyncio.to_thread(ensure_history_thumbnail, image_path)
    except HTTPException:
        pass
    return image_path


INTERRUPTED_MESSAGE = (
    "The gateway stopped while this image was running; its points were released"
)
FREE_ALLOWANCE_EXHAUSTED_MESSAGE = (
    "The free allowance is temporarily exhausted; the reservation was released"
)


def job_from_task_row(task: sqlite3.Row) -> ProxyJob:
    """Rebuild an executable job from its durable queue record."""
    try:
        payload = json.loads(task["request_json"])
        if not isinstance(payload, dict) or not isinstance(payload.get("parameters"), dict):
            raise ValueError("Invalid request structure")
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    except (TypeError, ValueError, json.JSONDecodeError) as exc:
        raise ValueError(f"Task {task['id']} has invalid request data") from exc
    return ProxyJob(
        virtual_finish=float(task["virtual_finish"] or 0),
        negative_weight=-int(task["queue_weight"] or QUEUE_WEIGHTS["free"]),
        created_at=str(task["queued_at"] or task["created_at"]),
        user_id=int(task["user_id"]),
        task_id=str(task["id"]),
        service="image",
        path="ai/generate-image",
        body=body,
        quota_mode="paid" if task["mode"] == "paid" else "free",
    )


def fail_generation_item(
    db: sqlite3.Connection,
    item_id: str,
    *,
    error_code: str,
    error_message: str,
) -> str | None:
    """Mark an unfinished item failed and release its whole reservation.

    Items already in a final state are left untouched, so a reservation is
    never released twice. Returns the item's batch id. The caller commits.
    """
    item = db.execute(
        "SELECT user_id, mode, status, reserved_points, batch_id "
        "FROM generation_tasks WHERE id = ?",
        (item_id,),
    ).fetchone()
    if item is None:
        return None
    batch_id = str(item["batch_id"]) if item["batch_id"] else None
    if item["status"] not in ("queued", "running"):
        return batch_id
    release_points(
        db,
        int(item["user_id"]),
        point_kind_for_mode(item["mode"]),
        int(item["reserved_points"] or 0),
    )
    completed = now_iso()
    db.execute(
        """
        UPDATE generation_tasks
        SET status = 'failed', error_message = ?,
            released_green_points = CASE WHEN mode = 'paid' THEN 0 ELSE reserved_points END,
            released_red_points = CASE WHEN mode = 'paid' THEN reserved_points ELSE 0 END,
            completed_at = ?
        WHERE id = ?
        """,
        (error_message, completed, item_id),
    )
    db.execute(
        "INSERT OR REPLACE INTO generation_item_errors(item_id, error_code, created_at) "
        "VALUES (?, ?, ?)",
        (item_id, error_code, completed),
    )
    if batch_id:
        refresh_submission_task(db, batch_id)
    return batch_id


async def restore_generation_queue() -> None:
    """Restore queued work after a restart; interrupted work is never re-run."""
    global queue_virtual_time
    assert queue_condition is not None
    jobs: list[ProxyJob] = []
    with db_session() as db:
        # The previous process cannot still be executing these. NovelAI may or
        # may not have produced the image, so they fail and release points.
        running = db.execute(
            "SELECT id FROM generation_tasks WHERE status = 'running'"
        ).fetchall()
        for row in running:
            fail_generation_item(
                db,
                str(row["id"]),
                error_code="interrupted",
                error_message=INTERRUPTED_MESSAGE,
            )
        rows = db.execute(
            "SELECT * FROM generation_tasks WHERE status = 'queued' "
            "ORDER BY virtual_finish ASC, queued_at ASC, id ASC"
        ).fetchall()
        for row in rows:
            try:
                jobs.append(job_from_task_row(row))
            except ValueError:
                fail_generation_item(
                    db,
                    str(row["id"]),
                    error_code="invalid_parameters",
                    error_message="Queued request data is invalid",
                )
        db.commit()
    async with queue_condition:
        pending_jobs.extend(jobs)
        pending_jobs.sort(key=lambda job: job.sort_key)
        if pending_jobs:
            queue_virtual_time = max(job.virtual_finish for job in pending_jobs)


# Every item endpoint returns exactly these fields (contract §7).
GENERATION_ITEM_SELECT = """
SELECT t.*, u.username, e.error_code, COALESCE(s.item_count, 1) AS batch_size
FROM generation_tasks t
JOIN users u ON u.id = t.user_id
LEFT JOIN generation_item_errors e ON e.item_id = t.id
LEFT JOIN generation_submission_tasks s ON s.id = t.batch_id
"""


def visible_history_task(
    task_id: str,
    user: sqlite3.Row,
    db: sqlite3.Connection,
) -> sqlite3.Row:
    task = db.execute(f"{GENERATION_ITEM_SELECT} WHERE t.id = ?", (task_id,)).fetchone()
    if not task:
        raise api_error(status.HTTP_404_NOT_FOUND, "not_found", "Task not found")
    hidden = db.execute(
        "SELECT 1 FROM history_hidden WHERE user_id = ? AND task_id = ?",
        (user["id"], task_id),
    ).fetchone()
    if hidden:
        raise api_error(status.HTTP_404_NOT_FOUND, "not_found", "Task not found")
    if task["user_id"] != user["id"] and not user["is_admin"]:
        raise permission_denied("history.all", "This task belongs to another user")
    return task


def refresh_submission_task(db: sqlite3.Connection, task_id: str) -> None:
    """Derive durable outer-task status and point totals from its items."""
    items = db.execute(
        "SELECT status, mode, reserved_points, paid_points_charged FROM generation_tasks "
        "WHERE batch_id = ? ORDER BY batch_index, created_at, id",
        (task_id,),
    ).fetchall()
    if not items:
        return
    statuses = [str(item["status"]) for item in items]
    active = any(value in {"queued", "running"} for value in statuses)
    success = sum(value == "success" for value in statuses)
    if active:
        task_status = "running" if ("running" in statuses or success) else "queued"
    elif success == len(items):
        task_status = "success"
    elif success:
        task_status = "partial_failed"
    elif all(value == "cancelled" for value in statuses):
        task_status = "cancelled"
    else:
        task_status = "failed"
    reserved_green = sum(int(item["reserved_points"] or 0) for item in items if item["mode"] == "free")
    reserved_red = sum(int(item["reserved_points"] or 0) for item in items if item["mode"] == "paid")
    consumed_green = sum(int(item["reserved_points"] or 0) for item in items if item["mode"] == "free" and item["status"] == "success")
    consumed_red = sum(int(item["paid_points_charged"] or 0) for item in items if item["mode"] == "paid" and item["status"] == "success")
    released_green = sum(int(item["reserved_points"] or 0) for item in items if item["mode"] == "free" and item["status"] in {"failed", "rejected", "cancelled"})
    released_red = sum(int(item["reserved_points"] or 0) for item in items if item["mode"] == "paid" and item["status"] in {"failed", "rejected", "cancelled"})
    db.execute(
        """
        UPDATE generation_submission_tasks
        SET status = ?, item_count = ?, reserved_points = ?, consumed_points = ?,
            released_points = ?, reserved_green_points = ?, reserved_red_points = ?,
            consumed_green_points = ?, consumed_red_points = ?, released_green_points = ?,
            released_red_points = ?,
            completed_at = CASE WHEN ? THEN COALESCE(completed_at, ?) ELSE NULL END
        WHERE id = ?
        """,
        (task_status, len(items), reserved_green + reserved_red, consumed_green + consumed_red,
         released_green + released_red, reserved_green, reserved_red, consumed_green,
         consumed_red, released_green, released_red, not active, now_iso(), task_id),
    )


def generation_request_fingerprint(parsed: dict[str, Any]) -> str:
    """Hash the normalized, server-validated generation request deterministically."""
    normalized = json.dumps(
        parsed,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    )
    return hashlib.sha256(normalized.encode("utf-8")).hexdigest()


def submission_request_hash(envelope: dict[str, Any]) -> str:
    """Hash a submission body without its idempotency key (contract §4)."""
    body = {key: value for key, value in envelope.items() if key != "client_request_id"}
    normalized = json.dumps(
        body,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    )
    return hashlib.sha256(normalized.encode("utf-8")).hexdigest()


@dataclass(frozen=True)
class GenerationSubmission:
    client_request_id: str
    request: dict[str, Any]
    seeds: list[int]
    expected_quote: dict[str, Any]
    request_hash: str


def parse_generation_submission(body: bytes) -> GenerationSubmission:
    try:
        envelope = json.loads(body)
    except ValueError:
        raise invalid_parameters("body", "The body must be JSON") from None
    if not isinstance(envelope, dict):
        raise invalid_parameters("body", "The body must be a JSON object")
    client_request_id = envelope.get("client_request_id")
    if not isinstance(client_request_id, str) or not (
        8 <= len(client_request_id.strip()) <= 128
    ):
        raise invalid_parameters(
            "client_request_id", "client_request_id must have 8-128 characters"
        )
    request_data = envelope.get("request")
    if not isinstance(request_data, dict):
        raise invalid_parameters("request", "request must be a JSON object")
    seeds = envelope.get("seeds")
    if (
        not isinstance(seeds, list)
        or not seeds
        or any(not is_strict_int(seed) or not 0 <= seed <= MAX_SEED for seed in seeds)
    ):
        raise invalid_parameters(
            "seeds", f"seeds must be a non-empty list of integers in 0..{MAX_SEED}"
        )
    expected = envelope.get("expected_quote")
    if (
        not isinstance(expected, dict)
        or expected.get("mode") not in ("free", "paid")
        or not is_strict_int(expected.get("points"))
    ):
        raise invalid_parameters(
            "expected_quote", "expected_quote with mode and integer points is required"
        )
    return GenerationSubmission(
        client_request_id=client_request_id.strip(),
        request=request_data,
        seeds=seeds,
        expected_quote=expected,
        request_hash=submission_request_hash(envelope),
    )


def existing_submission(
    db: sqlite3.Connection, user_id: int, client_request_id: str, request_hash: str
) -> sqlite3.Row | None:
    """Return the earlier submission for this idempotency key, if any."""
    row = db.execute(
        "SELECT id, request_hash FROM generation_submission_tasks "
        "WHERE user_id = ? AND client_request_id = ?",
        (user_id, client_request_id),
    ).fetchone()
    if row is not None and row["request_hash"] != request_hash:
        raise api_error(
            status.HTTP_409_CONFLICT,
            "duplicate_request",
            "client_request_id was reused with a different request body",
        )
    return row


def authorize_generation_quote(user: sqlite3.Row, quote: Quote, expected: dict[str, Any]) -> None:
    """Permission and price confirmation for a quoted submission (contract §4)."""
    if "allowance_exhausted" in quote.reasons:
        if not image_generation_allowed(user, "paid") or not quote.matches(expected):
            raise api_error(
                status.HTTP_409_CONFLICT,
                "free_allowance_exhausted",
                "The free allowance is temporarily exhausted; this request costs red points",
                quote=quote.to_dict(),
            )
        return
    if not image_generation_allowed(user, quote.mode):
        raise permission_denied(
            generation_permission_name(quote.mode),
            "This image request is not allowed for this account",
        )
    if not quote.matches(expected):
        raise api_error(
            status.HTTP_409_CONFLICT,
            "quote_changed",
            "The price has changed",
            quote=quote.to_dict(),
        )


def request_for_seed(request: dict[str, Any], seed: int) -> dict[str, Any]:
    item = copy.deepcopy(request)
    item["parameters"]["seed"] = seed
    if item.get("action") == "img2img":
        item["parameters"]["extra_noise_seed"] = seed
    return item


async def enqueue_generation_batch(
    *,
    user: sqlite3.Row,
    client_request_id: str,
    request_hash: str,
    items: list[dict[str, Any]],
    quote: Quote,
    db: sqlite3.Connection,
) -> tuple[str, list[str], bool]:
    """Atomically reserve the quote and enqueue one complete submission.

    This is the only way work enters the image queue; a single image is a
    batch with one seed. Returns ``(task_id, item_ids, replayed)``.
    """
    assert queue_condition is not None
    if not items or len(items) != quote.images:
        raise invalid_parameters("seeds", "Every image needs exactly one seed")

    user_id = int(user["id"])
    fingerprints = [generation_request_fingerprint(item) for item in items]

    async with queue_condition:
        replay = existing_submission(db, user_id, client_request_id, request_hash)
        if replay is not None:
            existing_items = db.execute(
                "SELECT id FROM generation_tasks WHERE batch_id = ? "
                "ORDER BY batch_index, created_at, id",
                (replay["id"],),
            ).fetchall()
            return str(replay["id"]), [str(item["id"]) for item in existing_items], True

        duplicate_positions: dict[str, list[int]] = {}
        for index, fingerprint in enumerate(fingerprints):
            duplicate_positions.setdefault(fingerprint, []).append(index)
        repeated = [positions for positions in duplicate_positions.values() if len(positions) > 1]
        if repeated:
            first_positions = repeated[0]
            raise api_error(
                status.HTTP_409_CONFLICT,
                "duplicate_within_batch",
                "No parameters varied. Check the seed.",
                batch_indexes=first_positions,
                seed=items[first_positions[0]]["parameters"].get("seed"),
            )

        for index, fingerprint in enumerate(fingerprints):
            duplicate = db.execute(
                """
                SELECT id, status, created_at, seed FROM generation_tasks
                WHERE user_id = ? AND request_fingerprint = ?
                  AND status IN ('queued', 'running', 'success')
                ORDER BY created_at DESC LIMIT 1
                """,
                (user_id, fingerprint),
            ).fetchone()
            if duplicate:
                raise api_error(
                    status.HTTP_409_CONFLICT,
                    "duplicate_generation",
                    "No parameters varied. Check the seed.",
                    task_id=duplicate["id"],
                    task_status=duplicate["status"],
                    created_at=duplicate["created_at"],
                    batch_index=index,
                    seed=duplicate["seed"],
                )

        outstanding = int(
            db.execute(
                """
                SELECT COUNT(*) FROM generation_tasks
                WHERE user_id = ? AND status IN ('queued', 'running')
                """,
                (user_id,),
            ).fetchone()[0]
        )
        if outstanding + len(items) > MAX_QUEUED_IMAGE_TASKS_PER_USER:
            raise api_error(
                status.HTTP_429_TOO_MANY_REQUESTS,
                "queue_full",
                "Too many unfinished image tasks",
                limit=MAX_QUEUED_IMAGE_TASKS_PER_USER,
            )

        queue_class = mode_for_user(user)
        weight = QUEUE_WEIGHTS[queue_class]
        last_finish = queue_last_finish[queue_class]
        parent_task_id = secrets.token_urlsafe(18)
        item_ids: list[str] = []
        jobs: list[ProxyJob] = []
        green = quote.per_image if quote.point_kind == "green" else 0
        red = quote.per_image if quote.point_kind == "red" else 0
        with immediate_transaction(db):
            reserve_points(db, user_id, quote.point_kind, quote.points)
            db.execute(
                """
                INSERT INTO generation_submission_tasks(
                  id, user_id, client_request_id, request_hash, type, status,
                  item_count, created_at
                ) VALUES (?, ?, ?, ?, ?, 'queued', ?, ?)
                """,
                (
                    parent_task_id,
                    user_id,
                    client_request_id,
                    request_hash,
                    "batch" if len(items) > 1 else "single",
                    len(items),
                    now_iso(),
                ),
            )
            for index, (item, fingerprint) in enumerate(zip(items, fingerprints)):
                item_id = secrets.token_urlsafe(18)
                item_created = now_iso()
                virtual_finish = max(queue_virtual_time, last_finish) + (1.0 / weight)
                last_finish = virtual_finish
                params = item["parameters"]
                db.execute(
                    """
                    INSERT INTO generation_tasks(
                      id, user_id, mode, queue_class, queue_weight, virtual_finish,
                      status, prompt, negative_prompt, width, height, steps, scale,
                      sampler, seed, cost, reserved_points, reserved_green_points,
                      reserved_red_points, batch_id, batch_index, request_fingerprint,
                      request_json, queued_at, created_at
                    ) VALUES (?, ?, ?, ?, ?, ?, 'queued', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        item_id,
                        user_id,
                        quote.mode,
                        queue_class,
                        weight,
                        virtual_finish,
                        str(item.get("input", ""))[:4000],
                        str(params.get("uc", ""))[:4000],
                        params["width"],
                        params["height"],
                        params["steps"],
                        float(params.get("scale") or 0),
                        params["sampler"],
                        params["seed"],
                        quote.per_image,
                        quote.per_image,
                        green,
                        red,
                        parent_task_id,
                        index,
                        fingerprint,
                        json.dumps(item, ensure_ascii=False),
                        item_created,
                        item_created,
                    ),
                )
                item_ids.append(item_id)
                jobs.append(
                    ProxyJob(
                        virtual_finish=virtual_finish,
                        negative_weight=-weight,
                        created_at=item_created,
                        user_id=user_id,
                        task_id=item_id,
                        service="image",
                        path="ai/generate-image",
                        body=json.dumps(
                            item, separators=(",", ":"), ensure_ascii=False
                        ).encode("utf-8"),
                        quota_mode=quote.mode,
                    )
                )
            refresh_submission_task(db, parent_task_id)

        # Scheduling state only advances once the submission is durable.
        queue_last_finish[queue_class] = last_finish
        pending_jobs.extend(jobs)
        pending_jobs.sort(key=lambda job: job.sort_key)
        queue_condition.notify_all()
        return parent_task_id, item_ids, False


def _is_generation_log_sensitive_key(key: str) -> bool:
    normalized = key.strip().lower().replace("-", "_")
    if normalized in GENERATION_LOG_SENSITIVE_KEYS:
        return True
    return any(
        marker in normalized
        for marker in ("authorization", "cookie", "password", "secret", "token")
    )


def _generation_request_sensitive_values(body: bytes) -> tuple[str, ...]:
    """Return bounded request values that must never be echoed by error logs."""
    try:
        request = json.loads(body)
    except (TypeError, ValueError, json.JSONDecodeError):
        return ()
    values: set[str] = set()

    def visit(value: Any, *, sensitive: bool = False) -> None:
        if isinstance(value, dict):
            for key, child in value.items():
                visit(
                    child,
                    sensitive=sensitive or _is_generation_log_sensitive_key(str(key)),
                )
            return
        if isinstance(value, list):
            for child in value:
                visit(child, sensitive=sensitive)
            return
        if (
            sensitive
            and isinstance(value, str)
            and 4 <= len(value) <= AUDIT_MAX_STRING_CHARS
        ):
            values.add(value)

    visit(request)
    return tuple(sorted(values, key=len, reverse=True))


def _redact_generation_log_text(text: str, sensitive_values: tuple[str, ...]) -> str:
    redacted = text
    for value in sensitive_values:
        redacted = redacted.replace(value, "<redacted-request-value>")
    redacted = re.sub(
        r"(?i)\bBearer\s+[A-Za-z0-9._~+/-]+=*",
        "Bearer <redacted-token>",
        redacted,
    )
    redacted = re.sub(r"\bpst-[A-Za-z0-9._~-]+", "<redacted-token>", redacted)
    return redacted


def safe_upstream_error_preview(content: bytes, request_body: bytes = b"") -> str:
    """Render a bounded JSON error response without prompts or credentials."""
    if not content:
        return "<empty>"
    try:
        parsed = json.loads(content.decode("utf-8"))
    except (UnicodeDecodeError, TypeError, ValueError, json.JSONDecodeError):
        return "<non-json-response-not-logged>"
    sensitive_values = _generation_request_sensitive_values(request_body)

    def redact(value: Any, *, key: str = "") -> Any:
        if _is_generation_log_sensitive_key(key):
            return "<redacted>"
        if isinstance(value, dict):
            return {
                str(child_key): redact(child, key=str(child_key))
                for child_key, child in value.items()
            }
        if isinstance(value, list):
            return [redact(child) for child in value]
        if isinstance(value, str):
            return _redact_generation_log_text(value, sensitive_values)
        return value

    preview = json.dumps(redact(parsed), ensure_ascii=False, separators=(",", ":"))
    if len(preview) > GENERATION_ERROR_PREVIEW_MAX_CHARS:
        omitted = len(preview) - GENERATION_ERROR_PREVIEW_MAX_CHARS
        return f"{preview[:GENERATION_ERROR_PREVIEW_MAX_CHARS]}<truncated {omitted} chars>"
    return preview


def generation_job_log_context(job: ProxyJob, batch_id: str | None) -> str:
    try:
        request = json.loads(job.body)
        if not isinstance(request, dict):
            request = {}
        params = request.get("parameters", {})
        if not isinstance(params, dict):
            params = {}
    except (TypeError, ValueError, json.JSONDecodeError):
        request = {}
        params = {}
    return (
        f"task_id={job.task_id} batch_id={batch_id or '-'} user_id={job.user_id} "
        f"service={job.service} path={job.path} quota_mode={job.quota_mode or '-'} "
        f"model={request.get('model', '-')} action={request.get('action', '-')} "
        f"seed={params.get('seed', '-')} width={params.get('width', '-')} "
        f"height={params.get('height', '-')} steps={params.get('steps', '-')} "
        f"sampler={params.get('sampler', '-')} "
        f"request_sha256={hashlib.sha256(job.body).hexdigest()}"
    )


def log_generation_upstream_failure(
    job: ProxyJob,
    *,
    batch_id: str | None,
    status_code: int,
    headers: dict[str, str],
    content: bytes,
    elapsed_ms: int,
    kind: str = "upstream_http",
    stage: str = "upstream_response",
) -> None:
    logger.error(
        "generation_failed kind=%s stage=%s %s "
        "status_code=%s elapsed_ms=%s content_type=%s response_bytes=%s "
        "response_sha256=%s upstream_request_id=%s cf_ray=%s retry_after=%s "
        "response_preview=%s",
        kind,
        stage,
        generation_job_log_context(job, batch_id),
        status_code,
        elapsed_ms,
        headers.get("content-type", "-"),
        len(content),
        hashlib.sha256(content).hexdigest(),
        headers.get("x-request-id", headers.get("request-id", "-")),
        headers.get("cf-ray", "-"),
        headers.get("retry-after", "-"),
        safe_upstream_error_preview(content, job.body),
    )


def log_generation_exception(
    job: ProxyJob,
    *,
    batch_id: str | None,
    stage: str,
    exc: BaseException,
    elapsed_ms: int,
) -> None:
    logger.exception(
        "generation_failed kind=exception stage=%s %s exception_type=%s "
        "error=%r elapsed_ms=%s",
        stage,
        generation_job_log_context(job, batch_id),
        type(exc).__name__,
        str(exc),
        elapsed_ms,
    )


def persist_generation_failure(
    job: ProxyJob, *, error_code: str, error_message: str
) -> str | None:
    """Durably fail one item and release its reservation."""
    with db_session() as db:
        batch_id = fail_generation_item(
            db, job.task_id, error_code=error_code, error_message=error_message
        )
        db.commit()
    return batch_id


async def fail_queued_free_jobs() -> None:
    """The free allowance ran out: free work that has not started fails."""
    assert queue_condition is not None
    async with queue_condition:
        pending_jobs[:] = [job for job in pending_jobs if job.quota_mode == "paid"]
    with db_session() as db:
        rows = db.execute(
            "SELECT id FROM generation_tasks WHERE status = 'queued' AND mode <> 'paid'"
        ).fetchall()
        for row in rows:
            fail_generation_item(
                db,
                str(row["id"]),
                error_code="free_allowance_exhausted",
                error_message=FREE_ALLOWANCE_EXHAUSTED_MESSAGE,
            )
        db.commit()


def settle_generation_success(
    job: ProxyJob, call: UpstreamImageCall, image_path: str
) -> bool:
    """Persist a successful item and charge it (contract §4, §6).

    Returns True when this item proved the free allowance is exhausted.
    """
    exhausted = False
    with db_session() as db:
        item = db.execute(
            "SELECT status, reserved_points, batch_id FROM generation_tasks WHERE id = ?",
            (job.task_id,),
        ).fetchone()
        if item is None or item["status"] != "running":
            return False
        reserved = int(item["reserved_points"] or 0)
        kind = point_kind_for_mode(job.quota_mode)
        delta = call.measured_delta
        if job.quota_mode == "paid":
            charged, above_quote = settle_amount(reserved, delta)
            if above_quote:
                record_billing_anomaly(
                    db,
                    kind=ANOMALY_MEASURED_ABOVE_QUOTE,
                    user_id=job.user_id,
                    task_id=job.task_id,
                    mode="paid",
                    quoted=reserved,
                    measured=delta,
                    note="Measured Anlas delta exceeded the quote; charged the quote",
                )
        else:
            # Free work is always charged its green quote. Any Anlas spent on
            # it means NovelAI's free allowance has run out.
            charged = reserved
            if delta is not None and delta > 0:
                record_billing_anomaly(
                    db,
                    kind=ANOMALY_FREE_ALLOWANCE_EXHAUSTED,
                    user_id=job.user_id,
                    task_id=job.task_id,
                    mode="free",
                    quoted=reserved,
                    measured=delta,
                    note="Free-eligible image consumed Anlas; free work is paused",
                )
                exhausted = True
        settle_points(db, job.user_id, kind, reserved, charged)
        db.execute(
            """
            UPDATE generation_tasks
            SET status = 'success', image_path = ?, anlas_before = ?,
                anlas_after = ?, paid_points_charged = ?,
                consumed_green_points = ?, consumed_red_points = ?,
                completed_at = ?
            WHERE id = ?
            """,
            (
                image_path,
                call.anlas_before,
                call.anlas_after,
                charged if kind == "red" else 0,
                charged if kind == "green" else 0,
                charged if kind == "red" else 0,
                now_iso(),
                job.task_id,
            ),
        )
        if item["batch_id"]:
            refresh_submission_task(db, str(item["batch_id"]))
        db.commit()
    return exhausted


async def run_generation_job(job: ProxyJob) -> None:
    """Execute one queued item. The caller holds the upstream lane."""
    started_monotonic = time.monotonic()
    batch_id: str | None = None
    stage = "mark_running"

    def elapsed_ms() -> int:
        return int((time.monotonic() - started_monotonic) * 1000)

    try:
        with db_session() as db:
            item = db.execute(
                "SELECT status, batch_id FROM generation_tasks WHERE id = ?",
                (job.task_id,),
            ).fetchone()
            if item is None or item["status"] != "queued":
                return
            batch_id = str(item["batch_id"]) if item["batch_id"] else None
            owner = db.execute(
                "SELECT * FROM users WHERE id = ?", (job.user_id,)
            ).fetchone()
            refusal: tuple[str, str] | None = None
            if job.quota_mode != "paid" and free_allowance_exhausted_until(db):
                refusal = ("free_allowance_exhausted", FREE_ALLOWANCE_EXHAUSTED_MESSAGE)
            elif not image_generation_allowed(owner, job.quota_mode):
                refusal = (
                    "permission_denied",
                    "The account can no longer run this image request",
                )
            if refusal is not None:
                fail_generation_item(
                    db, job.task_id, error_code=refusal[0], error_message=refusal[1]
                )
                db.commit()
                return
            db.execute(
                "UPDATE generation_tasks SET status = 'running', started_at = ? WHERE id = ?",
                (now_iso(), job.task_id),
            )
            if batch_id:
                refresh_submission_task(db, batch_id)
            db.commit()

        stage = "upstream_request"
        call = await call_image_upstream(job.path, job.body)
        if not call.ok:
            log_generation_upstream_failure(
                job,
                batch_id=batch_id,
                status_code=call.status_code,
                headers=call.headers,
                content=call.content,
                elapsed_ms=elapsed_ms(),
            )
            persist_generation_failure(
                job,
                error_code="upstream_error",
                error_message=f"NovelAI HTTP {call.status_code}",
            )
            return
        stage = "decode_and_save_image"
        image_path = await save_history_image(job.task_id, call.content)
        if image_path is None:
            log_generation_upstream_failure(
                job,
                batch_id=batch_id,
                status_code=call.status_code,
                headers=call.headers,
                content=call.content,
                elapsed_ms=elapsed_ms(),
                kind="invalid_image_response",
                stage=stage,
            )
            persist_generation_failure(
                job,
                error_code="upstream_error",
                error_message="NovelAI returned no valid image",
            )
            return
        stage = "settle"
        if settle_generation_success(job, call, image_path):
            await fail_queued_free_jobs()
    except asyncio.CancelledError:
        # Shutdown: the item must not stay 'running'; it is never re-run.
        persist_generation_failure(
            job, error_code="interrupted", error_message=INTERRUPTED_MESSAGE
        )
        raise
    except Exception as exc:
        detail = exc.detail if isinstance(exc, HTTPException) else None
        if isinstance(detail, dict):
            error_code = str(detail.get("code", "internal_error"))
            error_message = str(detail.get("message", "Generation failed"))
        else:
            error_code, error_message = "internal_error", "Generation failed"
        log_generation_exception(
            job, batch_id=batch_id, stage=stage, exc=exc, elapsed_ms=elapsed_ms()
        )
        try:
            persist_generation_failure(
                job, error_code=error_code, error_message=error_message
            )
        except Exception as persistence_exc:
            logger.exception(
                "generation_failure_persistence_failed %s original_error_type=%s "
                "original_error=%r persistence_error_type=%s persistence_error=%r",
                generation_job_log_context(job, batch_id),
                type(exc).__name__,
                str(exc),
                type(persistence_exc).__name__,
                str(persistence_exc),
            )


def _head_lane_priority() -> int:
    return pending_jobs[0].lane_priority if pending_jobs else FREE_PRIORITY


async def queue_worker() -> None:
    global queue_virtual_time
    assert queue_condition is not None
    while True:
        async with queue_condition:
            while not pending_jobs:
                await queue_condition.wait()
        # Each item runs inside the upstream lane. The lane is requested with
        # the priority of whatever heads the queue at hand-off time, so a paid
        # tool already waiting goes before queued free work.
        await upstream_lane.acquire(_head_lane_priority)
        job: ProxyJob | None = None
        try:
            async with queue_condition:
                if not pending_jobs:
                    continue
                job = pending_jobs.pop(0)
                active_user_ids.add(job.user_id)
                queue_virtual_time = max(queue_virtual_time, job.virtual_finish)
            await run_generation_job(job)
        finally:
            upstream_lane.release()
            if job is not None:
                active_user_ids.discard(job.user_id)


@app.api_route("/api/nai/{service}/{path:path}", methods=["GET", "POST"])
async def novelai_proxy(
    service: str,
    path: str,
    request: Request,
    user: sqlite3.Row = Depends(require_user),
    db: sqlite3.Connection = Depends(get_db),
):
    method = request.method.upper()
    require_novelai_proxy_permission(service, path, method, user)
    tool = PAID_TOOL_PATHS.get(path) if service == "image" else None
    idempotency_key = paid_tool_idempotency_key(request, tool) if tool else None
    body = await request.body()
    audit_id = create_audit_log(
        db,
        user,
        service=service,
        path=path,
        method=method,
        body=body,
        content_type=request.headers.get("content-type", ""),
    )
    try:
        if tool is not None and idempotency_key is not None:
            response = await run_paid_tool(
                db,
                user,
                path=path,
                tool=tool,
                body=body,
                idempotency_key=idempotency_key,
            )
            complete_audit_log(db, audit_id, status_code=response.status_code)
            return response
        stream = (
            service == "text"
            and "text/event-stream" in request.headers.get("accept", "")
        )
        if service == "text":
            result = await forward_text_to_novelai_queued(
                user,
                service,
                path,
                method=method,
                body=body,
                stream=stream,
                audit_id=audit_id,
            )
        else:
            result = await forward_to_novelai(
                service, path, method=method, body=body, stream=stream
            )
        if isinstance(result, StreamingResponse):
            return result
        status_code, headers, content = result
        raise_for_upstream_status(service, path, status_code, content, body)
        complete_audit_log(db, audit_id, status_code=status_code)
        return Response(content=content, status_code=status_code, headers=headers)
    except HTTPException as exc:
        db.rollback()
        complete_audit_log(
            db,
            audit_id,
            status_code=exc.status_code,
            error_message=str(exc.detail),
        )
        raise
    except Exception:
        db.rollback()
        complete_audit_log(
            db, audit_id, status_code=500, error_message="Proxy request failed"
        )
        raise


def submission_response_payload(db: sqlite3.Connection, task_id: str) -> dict[str, Any]:
    task = db.execute(
        "SELECT status FROM generation_submission_tasks WHERE id = ?", (task_id,)
    ).fetchone()
    items = db.execute(
        "SELECT id, batch_index, status FROM generation_tasks WHERE batch_id = ? "
        "ORDER BY batch_index, created_at, id",
        (task_id,),
    ).fetchall()
    return {
        "task_id": task_id,
        "item_id": str(items[0]["id"]) if items else None,
        "items": [
            {
                "id": str(item["id"]),
                "batch_index": int(item["batch_index"] or 0),
                "status": str(item["status"]),
            }
            for item in items
        ],
        "status": str(task["status"]) if task else "queued",
    }


@app.post("/api/generation-tasks", status_code=status.HTTP_202_ACCEPTED)
async def submit_generation_task(
    request: Request,
    user: sqlite3.Row = Depends(require_user),
    db: sqlite3.Connection = Depends(get_db),
):
    """Durably accept an image-generation submission (contract §4)."""
    body = await request.body()
    audit_id = create_audit_log(
        db,
        user,
        service="image",
        path="ai/generate-image",
        method="POST",
        body=body,
        content_type=request.headers.get("content-type", ""),
    )
    try:
        submission = parse_generation_submission(body)
        replay = existing_submission(
            db, int(user["id"]), submission.client_request_id, submission.request_hash
        )
        if replay is not None:
            task_id = str(replay["id"])
        else:
            rules = image_rules_for_user(db, user)
            if len(submission.seeds) > rules["batch_limit"]:
                raise invalid_parameters(
                    "seeds",
                    f"At most {rules['batch_limit']} images per submission",
                    limit=rules["batch_limit"],
                )
            normalized, quote = classify_and_quote(
                submission.request, rules, images=len(submission.seeds)
            )
            authorize_generation_quote(user, quote, submission.expected_quote)
            task_id, _, _ = await enqueue_generation_batch(
                user=user,
                client_request_id=submission.client_request_id,
                request_hash=submission.request_hash,
                items=[request_for_seed(normalized, seed) for seed in submission.seeds],
                quote=quote,
                db=db,
            )
    except HTTPException as exc:
        db.rollback()
        complete_audit_log(
            db,
            audit_id,
            status_code=exc.status_code,
            error_message=str(exc.detail),
        )
        raise
    complete_audit_log(db, audit_id, status_code=status.HTTP_202_ACCEPTED)
    response = JSONResponse(
        submission_response_payload(db, task_id),
        status_code=status.HTTP_202_ACCEPTED,
    )
    response.set_cookie(
        "naiweaver_current_task",
        task_id,
        max_age=60 * 60 * 24 * 14,
        httponly=True,
        samesite="lax",
        secure=COOKIE_SECURE,
    )
    return response


def public_request_json(raw: Any) -> str:
    """Restorable parameters without echoing image/vector payloads."""
    try:
        request_data = json.loads(str(raw))
        if not isinstance(request_data, dict):
            raise ValueError("Invalid generation request")
        parameters = request_data.get("parameters")
        if isinstance(parameters, dict):
            parameters = dict(parameters)
            for key in (
                "image",
                "mask",
                "director_reference_images",
                "reference_image_multiple",
            ):
                value = parameters.pop(key, None)
                if isinstance(value, list):
                    parameters[f"{key}_count"] = len(value)
                elif value is not None:
                    parameters[f"{key}_available"] = True
            request_data = {**request_data, "parameters": parameters}
        return json.dumps(request_data, ensure_ascii=False)
    except (TypeError, ValueError, json.JSONDecodeError):
        return ""


def generation_item_dto(item: sqlite3.Row) -> dict[str, Any]:
    """The public shape of one generation item (contract §7)."""
    mode = str(item["mode"])
    return {
        "id": item["id"],
        "user_id": item["user_id"],
        "username": item["username"],
        "batch_id": item["batch_id"],
        "batch_index": item["batch_index"],
        "batch_size": int(item["batch_size"] or 1),
        "status": item["status"],
        "error_code": item["error_code"],
        "error_message": item["error_message"],
        "mode": mode,
        "points_charged": int(
            (item["consumed_red_points"] if mode == "paid" else item["consumed_green_points"])
            or 0
        ),
        "prompt": item["prompt"],
        "negative_prompt": item["negative_prompt"],
        "width": item["width"],
        "height": item["height"],
        "steps": item["steps"],
        "scale": item["scale"],
        "sampler": item["sampler"],
        "seed": item["seed"],
        "request_json": public_request_json(item["request_json"]),
        "has_image": bool(item["image_path"]),
        "created_at": item["created_at"],
        "completed_at": item["completed_at"],
    }


def submission_task_payload(
    db: sqlite3.Connection, task: sqlite3.Row, viewer: sqlite3.Row
) -> dict[str, Any] | None:
    """A submission with the items the viewer has not hidden; None if all are."""
    items = db.execute(
        f"""
        {GENERATION_ITEM_SELECT}
        LEFT JOIN history_hidden h ON h.task_id = t.id AND h.user_id = ?
        WHERE t.batch_id = ? AND h.task_id IS NULL
        ORDER BY t.batch_index, t.created_at, t.id
        """,
        (viewer["id"], task["id"]),
    ).fetchall()
    if not items:
        return None
    return {
        "id": task["id"],
        "user_id": task["user_id"],
        "type": task["type"],
        "status": task["status"],
        "item_count": task["item_count"],
        "created_at": task["created_at"],
        "completed_at": task["completed_at"],
        "items": [generation_item_dto(item) for item in items],
    }


@app.get("/api/generation-tasks/{task_id}")
def generation_task_status(
    task_id: str,
    user: sqlite3.Row = Depends(require_user),
    db: sqlite3.Connection = Depends(get_db),
):
    task = db.execute(
        "SELECT * FROM generation_submission_tasks WHERE id = ?", (task_id,)
    ).fetchone()
    if not task:
        raise api_error(status.HTTP_404_NOT_FOUND, "not_found", "Task not found")
    if task["user_id"] != user["id"] and not user["is_admin"]:
        raise permission_denied("history.all", "This task belongs to another user")
    payload = submission_task_payload(db, task, user)
    if payload is None:
        raise api_error(status.HTTP_404_NOT_FOUND, "not_found", "Task not found")
    return payload


@app.get("/api/generation-items/{item_id}")
def generation_item_status(
    item_id: str,
    user: sqlite3.Row = Depends(require_user),
    db: sqlite3.Connection = Depends(get_db),
):
    return generation_item_dto(visible_history_task(item_id, user, db))


@app.get("/api/current-generation-task")
def current_generation_task(
    user: sqlite3.Row = Depends(require_user),
    db: sqlite3.Connection = Depends(get_db),
):
    task = db.execute(
        """
        SELECT s.* FROM generation_submission_tasks s
        WHERE s.user_id = ?
          AND EXISTS (
            SELECT 1 FROM generation_tasks t
            LEFT JOIN history_hidden h ON h.task_id = t.id AND h.user_id = ?
            WHERE t.batch_id = s.id AND h.task_id IS NULL
          )
        ORDER BY CASE WHEN s.status IN ('queued', 'running') THEN 0 ELSE 1 END,
                 s.created_at DESC
        LIMIT 1
        """,
        (user["id"], user["id"]),
    ).fetchone()
    if not task:
        return {"task": None}
    return {"task": submission_task_payload(db, task, user)}


@app.get("/api/history")
def history(
    request: Request,
    limit: int = 20,
    offset: int = 0,
    user_id: int | None = None,
    all_users: bool = False,
    current_batch: bool = False,
    user: sqlite3.Row = Depends(require_user),
    db: sqlite3.Connection = Depends(get_db),
):
    where = ["h.task_id IS NULL"]
    params: list[Any] = [user["id"]]
    if user["is_admin"] and user_id is not None:
        where.append("t.user_id = ?")
        params.append(user_id)
    elif not (user["is_admin"] and all_users):
        where.append("t.user_id = ?")
        params.append(user["id"])
    if current_batch:
        task_id = request.cookies.get("naiweaver_current_task")
        if task_id:
            where.append("t.batch_id = ?")
            params.append(task_id)
    where_sql = f"WHERE {' AND '.join(where)}" if where else ""
    page_limit = max(1, min(limit, 100))
    page_offset = max(0, offset)
    total = db.execute(
        f"""
        SELECT COUNT(DISTINCT COALESCE(t.batch_id, t.id))
        FROM generation_tasks t
        JOIN users u ON u.id = t.user_id
        LEFT JOIN history_hidden h ON h.task_id = t.id AND h.user_id = ?
        {where_sql}
        """,
        params,
    ).fetchone()[0]
    page_params = [*params, page_limit, page_offset]
    batch_rows = db.execute(
        f"""
        SELECT COALESCE(t.batch_id, t.id) AS batch_key,
               MAX(t.created_at) AS latest_created_at
        FROM generation_tasks t
        JOIN users u ON u.id = t.user_id
        LEFT JOIN history_hidden h ON h.task_id = t.id AND h.user_id = ?
        {where_sql}
        GROUP BY COALESCE(t.batch_id, t.id)
        ORDER BY latest_created_at DESC, batch_key DESC
        LIMIT ? OFFSET ?
        """,
        page_params,
    ).fetchall()
    batch_keys = [str(row["batch_key"]) for row in batch_rows]
    rows: list[sqlite3.Row] = []
    if batch_keys:
        placeholders = ", ".join("?" for _ in batch_keys)
        rows = db.execute(
            f"""
            {GENERATION_ITEM_SELECT}
            LEFT JOIN history_hidden h ON h.task_id = t.id AND h.user_id = ?
            {where_sql}
              AND COALESCE(t.batch_id, t.id) IN ({placeholders})
            """,
            [*params, *batch_keys],
        ).fetchall()
        batch_order = {key: index for index, key in enumerate(batch_keys)}
        rows = sorted(
            rows,
            key=lambda row: (
                batch_order[str(row["batch_id"] or row["id"])],
                int(row["batch_index"] if row["batch_index"] is not None else 0),
                str(row["created_at"]),
            ),
        )
    return {
        "items": [generation_item_dto(row) for row in rows],
        "total": int(total),
        "limit": page_limit,
        "offset": page_offset,
    }


@app.get("/api/history/{task_id}/image")
def history_image(
    task_id: str,
    user: sqlite3.Row = Depends(require_user),
    db: sqlite3.Connection = Depends(get_db),
):
    task = visible_history_task(task_id, user, db)
    if not task["image_path"]:
        raise api_error(status.HTTP_404_NOT_FOUND, "not_found", "Image not available")
    path = resolve_history_image_file(task["image_path"])
    return FileResponse(
        path,
        media_type="image/png",
        headers={"Cache-Control": "private, max-age=86400"},
    )


@app.get("/api/history/{task_id}/thumbnail")
def history_thumbnail(
    task_id: str,
    user: sqlite3.Row = Depends(require_user),
    db: sqlite3.Connection = Depends(get_db),
):
    task = visible_history_task(task_id, user, db)
    if not task["image_path"]:
        raise api_error(status.HTTP_404_NOT_FOUND, "not_found", "Thumbnail not available")
    path = ensure_history_thumbnail(task["image_path"])
    return FileResponse(
        path,
        media_type="image/webp",
        headers={"Cache-Control": "private, max-age=86400"},
    )


@app.delete("/api/history/batches/{batch_id}")
def delete_history_batch(
    batch_id: str,
    user: sqlite3.Row = Depends(require_user),
    db: sqlite3.Connection = Depends(get_db),
):
    tasks = db.execute(
        "SELECT id, user_id, status FROM generation_tasks WHERE batch_id = ?",
        (batch_id,),
    ).fetchall()
    if not tasks:
        raise api_error(status.HTTP_404_NOT_FOUND, "not_found", "Batch not found")
    if any(task["user_id"] != user["id"] for task in tasks) and not user["is_admin"]:
        raise permission_denied("history.all", "This batch belongs to another user")
    if any(task["status"] in {"queued", "running"} for task in tasks):
        raise api_error(
            status.HTTP_409_CONFLICT, "task_active", "Cannot delete an active batch"
        )

    hidden_at = now_iso()
    with db:
        db.executemany(
            """
            INSERT OR IGNORE INTO history_hidden(user_id, task_id, hidden_at)
            VALUES (?, ?, ?)
            """,
            [(user["id"], task["id"], hidden_at) for task in tasks],
        )
    return {"ok": True, "hidden": len(tasks)}


@app.delete("/api/history/{task_id}")
def delete_history_item(
    task_id: str,
    user: sqlite3.Row = Depends(require_user),
    db: sqlite3.Connection = Depends(get_db),
):
    task = db.execute("SELECT * FROM generation_tasks WHERE id = ?", (task_id,)).fetchone()
    if not task:
        raise api_error(status.HTTP_404_NOT_FOUND, "not_found", "Task not found")
    if task["user_id"] != user["id"] and not user["is_admin"]:
        raise permission_denied("history.all", "This task belongs to another user")
    if task["status"] in {"queued", "running"}:
        raise api_error(
            status.HTTP_409_CONFLICT, "task_active", "Cannot delete an active task"
        )
    db.execute(
        """
        INSERT OR IGNORE INTO history_hidden(user_id, task_id, hidden_at)
        VALUES (?, ?, ?)
        """,
        (user["id"], task_id, now_iso()),
    )
    db.commit()
    return {"ok": True, "hidden": True}


@app.get("/{path:path}")
async def serve_web(path: str, request: Request):
    # Unknown API paths are JSON errors, never a redirect to the IdP.
    if path == "api" or path.startswith("api/"):
        raise api_error(status.HTTP_404_NOT_FOUND, "not_found", "Not found")
    # Authenticate document navigation before loading the Flutter application.
    if only_auth.enabled and (not path or path == "index.html" or "." not in path):
        db = db_connect()
        try:
            await require_user(request, db)
        except HTTPException as exc:
            if exc.status_code != 401:
                raise
            return RedirectResponse(
                only_auth.login_location(request),
                status_code=302,
                headers={"Cache-Control": "no-store"},
            )
        finally:
            db.close()
    web_root = WEB_BUILD_DIR.resolve()
    if path and ".." not in Path(path).parts and not Path(path).is_absolute():
        target = (web_root / path).resolve()
        if (
            target.exists()
            and target.is_file()
            and (target == web_root or web_root in target.parents)
        ):
            # Flutter's entry scripts keep stable filenames across builds.
            # Revalidate them so a deployed UI cannot be held behind a stale
            # browser or installed-PWA cache.
            headers = (
                {"Cache-Control": "no-cache, must-revalidate"}
                if target.name
                in {"index.html", "flutter_bootstrap.js", "flutter.js", "main.dart.js"}
                else None
            )
            return FileResponse(target, headers=headers)
    index = WEB_BUILD_DIR / "index.html"
    if index.exists():
        return FileResponse(index, headers={"Cache-Control": "no-cache, must-revalidate"})
    fallback = STATIC_DIR / "index.html"
    if fallback.exists():
        return FileResponse(fallback)
    return Response("NAIWeaver web build not found", status_code=404)
