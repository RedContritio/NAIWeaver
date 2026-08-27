from __future__ import annotations

import asyncio
import base64
import hashlib
from contextlib import asynccontextmanager
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta, timezone
import ipaddress
from io import BytesIO
import json
import math
import os
from pathlib import Path
import secrets
import sqlite3
from typing import Any
from zipfile import ZipFile

from fastapi import Depends, FastAPI, HTTPException, Request, Response, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse, StreamingResponse
import httpx
from pydantic import BaseModel, ConfigDict, Field
from webauthn import (
    generate_authentication_options,
    generate_registration_options,
    options_to_json,
    verify_authentication_response,
    verify_registration_response,
)
from webauthn.helpers.structs import (
    AuthenticatorSelectionCriteria,
    PublicKeyCredentialDescriptor,
    ResidentKeyRequirement,
    UserVerificationRequirement,
)

from .security import TokenError, create_jwt, decode_jwt, hash_password, verify_password


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
WEBAUTHN_RP_ID = os.environ.get("NAIWEAVER_WEBAUTHN_RP_ID", "localhost")
WEBAUTHN_RP_NAME = os.environ.get("NAIWEAVER_WEBAUTHN_RP_NAME", "NAIWeaver")
WEBAUTHN_ORIGIN = os.environ.get(
    "NAIWEAVER_WEBAUTHN_ORIGIN", "http://localhost:8000"
)
MAX_REQUEST_BODY_BYTES = int(os.environ.get("NAIWEAVER_MAX_REQUEST_BODY_BYTES", "25000000"))
ALLOWED_CLIENT_CIDRS = os.environ.get(
    "NAIWEAVER_ALLOWED_CLIENT_CIDRS",
    "127.0.0.1/32,::1/128,192.168.31.0/24",
)
CORS_ORIGINS = [
    origin.strip()
    for origin in os.environ.get("NAIWEAVER_CORS_ORIGINS", "").split(",")
    if origin.strip()
]

DEFAULT_GREEN_POINT_LIMIT = int(os.environ.get("NAIWEAVER_GREEN_POINT_LIMIT", "4000"))
STANDARD_GREEN_IMAGE_POINTS = 20
DEFAULT_RED_POINTS = int(os.environ.get("NAIWEAVER_RED_POINTS", "3000"))
DEFAULT_ADMIN_RED_POINTS = int(
    os.environ.get("NAIWEAVER_ADMIN_RED_POINTS", "5000")
)
MAX_STEPS_FREE = int(os.environ.get("NAIWEAVER_FREE_MAX_STEPS", "28"))
MAX_STEPS_PAID = int(os.environ.get("NAIWEAVER_PAID_MAX_STEPS", "50"))
MAX_STEPS_ADMIN = int(os.environ.get("NAIWEAVER_ADMIN_MAX_STEPS", "50"))
MAX_DIMENSION = int(os.environ.get("NAIWEAVER_MAX_DIMENSION", "2048"))
FREE_IMAGE_SIZES = frozenset({(832, 1216), (1216, 832), (1024, 1024)})
# A standard 1MP / 28-step image costs 20 green points without Opus.
TEXT_GLOBAL_CONCURRENCY = int(os.environ.get("NAIWEAVER_TEXT_CONCURRENCY", "3"))
MAX_QUEUED_IMAGE_TASKS_PER_USER = int(
    os.environ.get("NAIWEAVER_MAX_QUEUED_IMAGE_TASKS_PER_USER", "20")
)
THUMBNAIL_MAX_SIZE = int(os.environ.get("NAIWEAVER_THUMBNAIL_MAX_SIZE", "512"))
THUMBNAIL_WEBP_QUALITY = int(os.environ.get("NAIWEAVER_THUMBNAIL_WEBP_QUALITY", "76"))

QUEUE_WEIGHTS = {"free": 100, "paid": 500, "admin": 1000}
ALLOWED_SAMPLERS = {
    "k_euler_ancestral",
    "k_euler",
    "k_dpmpp_2s_ancestral",
    "k_dpmpp_2m",
    "k_dpmpp_sde",
}
PAID_ONLY_IMAGE_PARAMETERS = frozenset(
    {
        "image",
        "mask",
        "strength",
        "noise",
        "extra_noise_seed",
        "add_original_image",
        "mask_blur",
        "director_reference_images",
        "director_reference_descriptions",
        "director_reference_strength_values",
        "director_reference_secondary_strength_values",
        "director_reference_information_extracted",
        "reference_image_multiple",
        "reference_strength_multiple",
        "reference_information_extracted_multiple",
    }
)
AUDIT_MAX_STRING_CHARS = 20000
TARGET_BASES = {
    "image": "https://image.novelai.net",
    "api": "https://api.novelai.net",
    "text": "https://text.novelai.net",
}
NAI_V5_CURATED_MODEL = "nai-diffusion-5-curated"
NAI_V5_FULL_MODEL = "nai-diffusion-5-full"
NAI_V5_FULL_INPAINTING_MODEL = "nai-diffusion-5-full-inpainting"
NAI_V4_5_CURATED_INPAINTING_MODEL = "nai-diffusion-4-5-curated-inpainting"
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
ALLOWED_IMAGE_PROXY_PATHS = {
    "ai/generate-image",
    "ai/upscale",
    "ai/augment-image",
    "ai/encode-vibe",
}
PAID_DIRECT_IMAGE_PATHS = {
    "ai/upscale",
    "ai/augment-image",
    "ai/encode-vibe",
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

CREATE TABLE IF NOT EXISTS webauthn_credentials (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  credential_id TEXT NOT NULL UNIQUE,
  public_key TEXT NOT NULL,
  sign_count INTEGER NOT NULL DEFAULT 0,
  aaguid TEXT NOT NULL DEFAULT '',
  device_type TEXT NOT NULL DEFAULT '',
  backed_up INTEGER NOT NULL DEFAULT 0,
  transports TEXT NOT NULL DEFAULT '',
  disabled INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  last_used_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_webauthn_credentials_user_id ON webauthn_credentials(user_id);

CREATE TABLE IF NOT EXISTS webauthn_enrollment_tokens (
  token_hash TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  expires_at TEXT NOT NULL,
  used_at TEXT,
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_webauthn_enrollment_user_id ON webauthn_enrollment_tokens(user_id);

CREATE TABLE IF NOT EXISTS webauthn_challenges (
  id TEXT PRIMARY KEY,
  user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
  purpose TEXT NOT NULL,
  challenge TEXT NOT NULL,
  enrollment_token_hash TEXT,
  expires_at TEXT NOT NULL,
  used_at TEXT,
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_webauthn_challenges_user_id ON webauthn_challenges(user_id);
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


@dataclass(order=True)
class ProxyJob:
    sort_key: tuple[float, int, str] = field(init=False, repr=False)
    virtual_finish: float
    negative_weight: int
    created_at: str
    user_id: int = field(compare=False)
    task_id: str = field(compare=False)
    service: str = field(compare=False)
    path: str = field(compare=False)
    body: bytes = field(compare=False)
    cost: int = field(compare=False, default=1)
    quota_mode: str | None = field(compare=False, default=None)

    def __post_init__(self) -> None:
        self.sort_key = (self.virtual_finish, self.negative_weight, self.created_at)


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
    is_admin: bool = False
    disabled: bool = False
    green_point_discount: int = Field(default=0, ge=0, le=100)
    can_generate_paid: bool = False
    can_text_generate: bool = True
    can_image_upscale: bool = True
    can_image_augment: bool = True
    can_image_encode_vibe: bool = True
    green_point_limit: int = Field(default=DEFAULT_GREEN_POINT_LIMIT, ge=0)
    green_point_used: int = Field(default=0, ge=0)
    red_points: int = Field(default=DEFAULT_RED_POINTS, ge=0)
    red_points_used: int = Field(default=0, ge=0)


class WebAuthnRegisterOptionsRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    token: str = Field(min_length=16, max_length=512)


class WebAuthnRegisterVerifyRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    token: str = Field(min_length=16, max_length=512)
    challenge_id: str = Field(min_length=8, max_length=128)
    credential: dict[str, Any]


class WebAuthnLoginVerifyRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    challenge_id: str = Field(min_length=8, max_length=128)
    credential: dict[str, Any]


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def today_key() -> str:
    return date.today().isoformat()


def b64url_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def b64url_decode(value: str) -> bytes:
    padding = "=" * (-len(value) % 4)
    return base64.urlsafe_b64decode(value + padding)


def token_hash(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def parse_dt(value: str) -> datetime:
    return datetime.fromisoformat(value)


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
    return {"user": user_to_dict(user, db), "quota": quota_for_user(db, user)}


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


def init_db() -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    IMAGE_DIR.mkdir(parents=True, exist_ok=True)
    THUMBNAIL_DIR.mkdir(parents=True, exist_ok=True)
    AUDIT_DIR.mkdir(parents=True, exist_ok=True)
    with db_connect() as db:
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
    db.execute(
        """
        CREATE TABLE IF NOT EXISTS webauthn_credentials (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          credential_id TEXT NOT NULL UNIQUE,
          public_key TEXT NOT NULL,
          sign_count INTEGER NOT NULL DEFAULT 0,
          aaguid TEXT NOT NULL DEFAULT '',
          device_type TEXT NOT NULL DEFAULT '',
          backed_up INTEGER NOT NULL DEFAULT 0,
          transports TEXT NOT NULL DEFAULT '',
          disabled INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          last_used_at TEXT
        )
        """
    )
    db.execute(
        "CREATE INDEX IF NOT EXISTS idx_webauthn_credentials_user_id ON webauthn_credentials(user_id)"
    )
    db.execute(
        """
        CREATE TABLE IF NOT EXISTS webauthn_enrollment_tokens (
          token_hash TEXT PRIMARY KEY,
          user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          expires_at TEXT NOT NULL,
          used_at TEXT,
          created_at TEXT NOT NULL
        )
        """
    )
    db.execute(
        "CREATE INDEX IF NOT EXISTS idx_webauthn_enrollment_user_id ON webauthn_enrollment_tokens(user_id)"
    )
    db.execute(
        """
        CREATE TABLE IF NOT EXISTS webauthn_challenges (
          id TEXT PRIMARY KEY,
          user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
          purpose TEXT NOT NULL,
          challenge TEXT NOT NULL,
          enrollment_token_hash TEXT,
          expires_at TEXT NOT NULL,
          used_at TEXT,
          created_at TEXT NOT NULL
        )
        """
    )
    db.execute(
        "CREATE INDEX IF NOT EXISTS idx_webauthn_challenges_user_id ON webauthn_challenges(user_id)"
    )


def bootstrap_users() -> None:
    if not BOOTSTRAP_TEST_USERS:
        return
    admin_password_env = os.environ.get("NAIWEAVER_ADMIN_PASSWORD")
    admin_password = admin_password_env or "local-test-admin"
    samples = [
        ("admin", admin_password, 1, 1, 100, DEFAULT_GREEN_POINT_LIMIT, DEFAULT_ADMIN_RED_POINTS),
        ("free_user", "free-test-pass", 0, 0, 0, DEFAULT_GREEN_POINT_LIMIT, 0),
        (
            "paid_user",
            "paid-test-pass",
            0,
            1,
            0,
            DEFAULT_GREEN_POINT_LIMIT,
            DEFAULT_RED_POINTS,
        ),
    ]
    with db_connect() as db:
        for (
            username,
            password,
            is_admin,
            can_paid,
            green_discount,
            green_limit,
            paid_points,
        ) in samples:
            existing = db.execute("SELECT id FROM users WHERE username = ?", (username,)).fetchone()
            if existing:
                if username == "admin" and admin_password_env:
                    db.execute(
                        """
                        UPDATE users
                        SET password_hash = ?, is_admin = 1, disabled = 0,
                            green_point_discount = 100, can_generate_paid = 1,
                            red_points = ?
                        WHERE username = 'admin'
                        """,
                        (hash_password(admin_password), DEFAULT_ADMIN_RED_POINTS),
                    )
                continue
            db.execute(
                """
                INSERT INTO users(
                  username, password_hash, is_admin, green_point_discount,
                  can_generate_paid, green_point_limit,
                  red_points, red_points_used, created_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?)
                """,
                (
                    username,
                    hash_password(password),
                    is_admin,
                    green_discount,
                    can_paid,
                    green_limit,
                    paid_points,
                    now_iso(),
                ),
            )
        db.commit()


def allowed_networks() -> list[ipaddress._BaseNetwork]:
    return [
        ipaddress.ip_network(item.strip(), strict=False)
        for item in ALLOWED_CLIENT_CIDRS.split(",")
        if item.strip()
    ]


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
        if not WEBAUTHN_ORIGIN.startswith("https://"):
            raise RuntimeError("NAIWEAVER_WEBAUTHN_ORIGIN must be HTTPS in production")


@asynccontextmanager
async def lifespan(_: FastAPI):
    global http_client, queue_condition, queue_worker_task, text_queue_condition
    validate_runtime_config()
    init_db()
    bootstrap_users()
    timeout = httpx.Timeout(60.0, read=300.0)
    http_client = httpx.AsyncClient(timeout=timeout)
    queue_condition = asyncio.Condition()
    text_queue_condition = asyncio.Condition()
    await restore_generation_queue()
    queue_worker_task = asyncio.create_task(queue_worker())
    try:
        yield
    finally:
        if queue_worker_task is not None:
            queue_worker_task.cancel()
            try:
                await queue_worker_task
            except asyncio.CancelledError:
                pass
        if http_client is not None:
            await http_client.aclose()


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
async def client_ip_allowlist(request: Request, call_next):
    networks = allowed_networks()
    if networks:
        host = request.client.host if request.client else ""
        try:
            ip = ipaddress.ip_address(host)
        except ValueError:
            return Response("Forbidden", status_code=403)
        if not any(ip in network for network in networks):
            return Response("Forbidden", status_code=403)
    return await call_next(request)


@app.middleware("http")
async def request_limits_and_origin(request: Request, call_next):
    content_length = request.headers.get("content-length")
    if content_length:
        try:
            if int(content_length) > MAX_REQUEST_BODY_BYTES:
                return Response("Request body too large", status_code=413)
        except ValueError:
            return Response("Invalid Content-Length", status_code=400)
    if PRODUCTION and request.url.path.startswith("/api/") and request.method not in {
        "GET",
        "HEAD",
        "OPTIONS",
    }:
        origin = request.headers.get("origin")
        if origin and origin != WEBAUTHN_ORIGIN:
            return Response("Forbidden", status_code=403)
    return await call_next(request)


def novelai_token() -> str:
    token_file = os.environ.get("NOVELAI_TOKEN_FILE")
    if token_file:
        path = Path(token_file).expanduser()
        if path.exists():
            return path.read_text(encoding="utf-8").strip()
    return os.environ.get("NOVELAI_TOKEN", os.environ.get("NAI_TOKEN", "")).strip()


def paid_image_budget_available(
    user: sqlite3.Row, db: sqlite3.Connection | None = None
) -> bool:
    if not (user["can_generate_paid"] or user["is_admin"]):
        return False
    if db is None:
        return True
    paid = quota_bucket(db, user, "paid")
    return paid["remaining"] is None or paid["remaining"] > 0


def user_to_dict(
    user: sqlite3.Row, db: sqlite3.Connection | None = None
) -> dict[str, Any]:
    permissions = {"history.read"}
    has_paid_budget = paid_image_budget_available(user, db)
    if user["is_admin"] or user["green_point_discount"] > 0 or user["green_point_limit"] > user["green_point_used"]:
        permissions.add("image.generate.free")
    if has_paid_budget:
        permissions.add("image.generate.paid")
    if user["can_text_generate"] or user["is_admin"]:
        permissions.add("text.generate")
    if (user["can_image_upscale"] or user["is_admin"]) and has_paid_budget:
        permissions.add("image.upscale")
    if (user["can_image_augment"] or user["is_admin"]) and has_paid_budget:
        permissions.add("image.augment")
    if (user["can_image_encode_vibe"] or user["is_admin"]) and has_paid_budget:
        permissions.add("image.encode_vibe")
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


def require_user(request: Request, db: sqlite3.Connection = Depends(get_db)) -> sqlite3.Row:
    token = request.cookies.get("access_token")
    auth = request.headers.get("Authorization", "")
    if not token and auth.lower().startswith("bearer "):
        token = auth[7:].strip()
    if not token:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Not authenticated")
    try:
        payload = decode_jwt(token, SECRET_KEY)
    except TokenError:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid session")
    session_id = payload.get("jti")
    user_id = payload.get("sub")
    if not session_id or not user_id:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid session")
    try:
        user_id_int = int(user_id)
    except (TypeError, ValueError):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid session")
    session = db.execute(
        "SELECT * FROM sessions WHERE id = ? AND user_id = ? AND revoked_at IS NULL",
        (session_id, user_id_int),
    ).fetchone()
    if not session:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Session expired")
    if datetime.fromisoformat(session["expires_at"]) < datetime.now(timezone.utc):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Session expired")
    user = db.execute("SELECT * FROM users WHERE id = ?", (user_id_int,)).fetchone()
    if not user or user["disabled"]:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "User disabled")
    return user


def require_admin(user: sqlite3.Row = Depends(require_user)) -> sqlite3.Row:
    if not user["is_admin"]:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Admin required")
    return user


@app.get("/api/health")
def health():
    return {"ok": True}


@app.post("/api/login")
def login(payload: LoginRequest, response: Response, db: sqlite3.Connection = Depends(get_db)):
    if not ALLOW_PASSWORD_LOGIN:
        raise HTTPException(status.HTTP_410_GONE, "Password login is disabled")
    user = db.execute("SELECT * FROM users WHERE username = ?", (payload.username,)).fetchone()
    if not user or user["disabled"] or not verify_password(payload.password, user["password_hash"]):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid username or password")
    return session_response(response, db, user)


@app.post("/api/logout")
def logout(request: Request, response: Response, db: sqlite3.Connection = Depends(get_db)):
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


@app.get("/api/me")
def me(user: sqlite3.Row = Depends(require_user), db: sqlite3.Connection = Depends(get_db)):
    return {"user": user_to_dict(user, db), "quota": quota_for_user(db, user)}


def valid_enrollment(
    db: sqlite3.Connection, raw_token: str
) -> tuple[sqlite3.Row, sqlite3.Row, str]:
    hashed = token_hash(raw_token)
    token_row = db.execute(
        """
        SELECT e.*, u.*
        FROM webauthn_enrollment_tokens e
        JOIN users u ON u.id = e.user_id
        WHERE e.token_hash = ?
        """,
        (hashed,),
    ).fetchone()
    if not token_row:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Enrollment link not found")
    if token_row["used_at"]:
        raise HTTPException(status.HTTP_410_GONE, "Enrollment link already used")
    if parse_dt(token_row["expires_at"]) < datetime.now(timezone.utc):
        raise HTTPException(status.HTTP_410_GONE, "Enrollment link expired")
    user = db.execute("SELECT * FROM users WHERE id = ?", (token_row["user_id"],)).fetchone()
    if not user or user["disabled"]:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "User disabled")
    return token_row, user, hashed


def store_webauthn_challenge(
    db: sqlite3.Connection,
    *,
    purpose: str,
    challenge: bytes,
    user_id: int | None = None,
    enrollment_token_hash: str | None = None,
) -> str:
    challenge_id = secrets.token_urlsafe(18)
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=5)
    db.execute(
        """
        INSERT INTO webauthn_challenges(
          id, user_id, purpose, challenge, enrollment_token_hash, expires_at, created_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """,
        (
            challenge_id,
            user_id,
            purpose,
            b64url_encode(challenge),
            enrollment_token_hash,
            expires_at.isoformat(),
            now_iso(),
        ),
    )
    db.commit()
    return challenge_id


def consume_webauthn_challenge(
    db: sqlite3.Connection,
    *,
    challenge_id: str,
    purpose: str,
    user_id: int | None = None,
    enrollment_token_hash: str | None = None,
) -> bytes:
    row = db.execute(
        "SELECT * FROM webauthn_challenges WHERE id = ? AND purpose = ?",
        (challenge_id, purpose),
    ).fetchone()
    if not row or row["used_at"]:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Invalid challenge")
    if user_id is not None and row["user_id"] != user_id:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Invalid challenge")
    if (
        enrollment_token_hash is not None
        and row["enrollment_token_hash"] != enrollment_token_hash
    ):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Invalid challenge")
    if parse_dt(row["expires_at"]) < datetime.now(timezone.utc):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Challenge expired")
    db.execute(
        "UPDATE webauthn_challenges SET used_at = ? WHERE id = ?",
        (now_iso(), challenge_id),
    )
    db.commit()
    return b64url_decode(row["challenge"])


def webauthn_options_payload(options: Any, challenge_id: str) -> dict[str, Any]:
    data = json.loads(options_to_json(options))
    return {"challenge_id": challenge_id, "publicKey": data}


@app.post("/api/webauthn/register/options")
def webauthn_register_options(
    payload: WebAuthnRegisterOptionsRequest,
    db: sqlite3.Connection = Depends(get_db),
):
    _, user, hashed = valid_enrollment(db, payload.token)
    existing = db.execute(
        """
        SELECT credential_id, transports
        FROM webauthn_credentials
        WHERE user_id = ? AND disabled = 0
        """,
        (user["id"],),
    ).fetchall()
    exclude_credentials = [
        PublicKeyCredentialDescriptor(id=b64url_decode(row["credential_id"]))
        for row in existing
    ]
    options = generate_registration_options(
        rp_id=WEBAUTHN_RP_ID,
        rp_name=WEBAUTHN_RP_NAME,
        user_id=f"user:{user['id']}".encode("utf-8"),
        user_name=user["username"],
        user_display_name=user["username"],
        authenticator_selection=AuthenticatorSelectionCriteria(
            resident_key=ResidentKeyRequirement.PREFERRED,
            require_resident_key=False,
            user_verification=UserVerificationRequirement.REQUIRED,
        ),
        exclude_credentials=exclude_credentials,
    )
    challenge_id = store_webauthn_challenge(
        db,
        purpose="register",
        challenge=options.challenge,
        user_id=int(user["id"]),
        enrollment_token_hash=hashed,
    )
    return webauthn_options_payload(options, challenge_id)


@app.post("/api/webauthn/register/verify")
def webauthn_register_verify(
    payload: WebAuthnRegisterVerifyRequest,
    response: Response,
    db: sqlite3.Connection = Depends(get_db),
):
    _, user, hashed = valid_enrollment(db, payload.token)
    challenge = consume_webauthn_challenge(
        db,
        challenge_id=payload.challenge_id,
        purpose="register",
        user_id=int(user["id"]),
        enrollment_token_hash=hashed,
    )
    try:
        verified = verify_registration_response(
            credential=payload.credential,
            expected_challenge=challenge,
            expected_rp_id=WEBAUTHN_RP_ID,
            expected_origin=WEBAUTHN_ORIGIN,
            require_user_verification=True,
        )
    except Exception as exc:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "WebAuthn registration failed") from exc
    db.execute(
        """
        INSERT INTO webauthn_credentials(
          user_id, credential_id, public_key, sign_count, aaguid, device_type,
          backed_up, created_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            int(user["id"]),
            b64url_encode(verified.credential_id),
            b64url_encode(verified.credential_public_key),
            int(verified.sign_count),
            verified.aaguid,
            str(verified.credential_device_type.value),
            int(bool(verified.credential_backed_up)),
            now_iso(),
        ),
    )
    db.execute(
        "UPDATE webauthn_enrollment_tokens SET used_at = ? WHERE token_hash = ?",
        (now_iso(), hashed),
    )
    db.commit()
    return session_response(response, db, user)


@app.post("/api/webauthn/login/options")
def webauthn_login_options(db: sqlite3.Connection = Depends(get_db)):
    credentials = db.execute(
        """
        SELECT credential_id
        FROM webauthn_credentials
        WHERE disabled = 0
        """
    ).fetchall()
    allow_credentials = [
        PublicKeyCredentialDescriptor(id=b64url_decode(row["credential_id"]))
        for row in credentials
    ]
    options = generate_authentication_options(
        rp_id=WEBAUTHN_RP_ID,
        allow_credentials=allow_credentials or None,
        user_verification=UserVerificationRequirement.REQUIRED,
    )
    challenge_id = store_webauthn_challenge(
        db, purpose="login", challenge=options.challenge
    )
    return webauthn_options_payload(options, challenge_id)


@app.post("/api/webauthn/login/verify")
def webauthn_login_verify(
    payload: WebAuthnLoginVerifyRequest,
    response: Response,
    db: sqlite3.Connection = Depends(get_db),
):
    challenge = consume_webauthn_challenge(
        db, challenge_id=payload.challenge_id, purpose="login"
    )
    credential_id = payload.credential.get("id") or payload.credential.get("rawId")
    if not credential_id:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Missing credential id")
    credential = db.execute(
        """
        SELECT c.*, u.disabled
        FROM webauthn_credentials c
        JOIN users u ON u.id = c.user_id
        WHERE c.credential_id = ? AND c.disabled = 0
        """,
        (credential_id,),
    ).fetchone()
    if not credential or credential["disabled"]:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Unknown credential")
    user = db.execute("SELECT * FROM users WHERE id = ?", (credential["user_id"],)).fetchone()
    if not user or user["disabled"]:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "User disabled")
    try:
        verified = verify_authentication_response(
            credential=payload.credential,
            expected_challenge=challenge,
            expected_rp_id=WEBAUTHN_RP_ID,
            expected_origin=WEBAUTHN_ORIGIN,
            credential_public_key=b64url_decode(credential["public_key"]),
            credential_current_sign_count=int(credential["sign_count"]),
            require_user_verification=True,
        )
    except Exception as exc:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "WebAuthn login failed") from exc
    db.execute(
        """
        UPDATE webauthn_credentials
        SET sign_count = ?, last_used_at = ?
        WHERE id = ?
        """,
        (int(verified.new_sign_count), now_iso(), credential["id"]),
    )
    db.commit()
    return session_response(response, db, user)


def usage_for(db: sqlite3.Connection, user_id: int, mode: str) -> int:
    row = db.execute(
        "SELECT used FROM quota_usage WHERE user_id = ? AND quota_date = ? AND mode = ?",
        (user_id, today_key(), mode),
    ).fetchone()
    return int(row["used"]) if row else 0


def quota_limit(user: sqlite3.Row, mode: str) -> int | None:
    if mode == "free":
        configured = user["green_point_limit"]
        return DEFAULT_GREEN_POINT_LIMIT if configured is None else int(configured)
    if mode == "paid":
        if user["red_points"] is None:
            return DEFAULT_ADMIN_RED_POINTS if user["is_admin"] else DEFAULT_RED_POINTS
        return int(user["red_points"])
    return 0


def quota_bucket(db: sqlite3.Connection, user: sqlite3.Row, mode: str) -> dict[str, Any]:
    limit = quota_limit(user, mode)
    discount = green_point_discount_for(user)
    enabled = bool(
        user["is_admin"]
        or (mode == "free" and (
            discount > 0
            or user["green_point_limit"] > user["green_point_used"]
        ))
        or (mode == "paid" and user["can_generate_paid"])
    )
    if mode == "paid":
        reserved = int(user["red_points_reserved"])
        used = int(user["red_points_used"]) + reserved
        return {
            "date": None,
            "mode": mode,
            "kind": "points",
            "red_points": limit,
            "point_limit": limit,
            "used": used,
            "reserved": reserved,
            "remaining": None if limit is None else limit - used,
            "unlimited": limit is None,
            "enabled": enabled,
        }
    reserved = int(user["green_points_reserved"])
    used = int(user["green_point_used"]) + reserved
    fully_discounted = discount >= 100
    return {
        "date": None,
        "mode": mode,
        "kind": "points",
        "green_point_limit": limit,
        "green_point_discount": discount,
        "point_limit": limit,
        "used": used,
        "reserved": reserved,
        "remaining": 0 if fully_discounted else max(0, limit - used),
        "unlimited": fully_discounted,
        "enabled": enabled,
    }


def quota_for_user(db: sqlite3.Connection, user: sqlite3.Row) -> dict[str, Any]:
    return {
        "free": quota_bucket(db, user, "free"),
        "paid": quota_bucket(db, user, "paid"),
    }


@app.get("/api/quota")
def quota(user: sqlite3.Row = Depends(require_user), db: sqlite3.Connection = Depends(get_db)):
    return quota_for_user(db, user)


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
        raise HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS,
            "Too many feedback reports; please try again later",
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
        raise HTTPException(status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, "Diagnostic report too large")

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
    try:
        db.execute(
            """
            INSERT INTO users(
              username, password_hash, is_admin, disabled, green_point_discount,
              can_generate_paid, can_text_generate, can_image_upscale,
              can_image_augment, can_image_encode_vibe, green_point_limit,
              green_point_used, red_points, red_points_used, created_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                payload.username,
                hash_password(payload.password or secrets.token_urlsafe(32)),
                int(payload.is_admin),
                int(payload.disabled),
                100 if payload.is_admin else payload.green_point_discount,
                int(payload.can_generate_paid),
                int(payload.can_text_generate),
                int(payload.can_image_upscale),
                int(payload.can_image_augment),
                int(payload.can_image_encode_vibe),
                payload.green_point_limit,
                payload.green_point_used,
                payload.red_points,
                payload.red_points_used,
                now_iso(),
            ),
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
    for field in sorted(payload.model_fields_set):
        if field == "password":
            if payload.password:
                assignments.append("password_hash = ?")
                values.append(hash_password(payload.password))
        elif field in bool_fields:
            assignments.append(f"{field} = ?")
            values.append(int(bool(getattr(payload, field))))
        elif field in int_fields:
            assignments.append(f"{field} = ?")
            values.append(getattr(payload, field))
    if assignments:
        values.append(user_id)
        db.execute(f"UPDATE users SET {', '.join(assignments)} WHERE id = ?", values)
        db.commit()
    updated = db.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
    return {"user": user_admin_dict(updated)}


@app.get("/api/admin/config")
def admin_config(_: sqlite3.Row = Depends(require_admin)):
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
        "allowed_client_cidrs": ALLOWED_CLIENT_CIDRS,
        "fake_novelai": FAKE_NOVELAI,
        "has_novelai_token": bool(novelai_token()),
    }


def mode_for_user(user: sqlite3.Row) -> str:
    if user["is_admin"]:
        return "admin"
    if user["can_generate_paid"]:
        return "paid"
    return "free"


def truthy_parameter(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return value != 0
    if isinstance(value, str):
        return value.strip().lower() in {"1", "true", "yes", "on"}
    return bool(value)


def nonempty_parameter(params: dict[str, Any], key: str) -> bool:
    if key not in params:
        return False
    value = params[key]
    if value is None:
        return False
    if isinstance(value, (str, list, dict, tuple, set)):
        return bool(value)
    return bool(value)


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


def is_free_opus_generation(
    data: dict[str, Any],
    params: dict[str, Any],
    *,
    width: int,
    height: int,
    steps: int,
) -> bool:
    if data.get("action") not in (None, "generate"):
        return False
    if (width, height) not in FREE_IMAGE_SIZES:
        return False
    if steps > MAX_STEPS_FREE:
        return False
    if truthy_parameter(params.get("sm")) or truthy_parameter(params.get("sm_dyn")):
        return False
    return not any(nonempty_parameter(params, key) for key in PAID_ONLY_IMAGE_PARAMETERS)


def estimate_image_points(data: dict[str, Any], params: dict[str, Any]) -> int:
    """Match the client-side non-Opus Anlas estimate for green-point billing."""
    width = max(1, int(params.get("width", 1)))
    height = max(1, int(params.get("height", 1)))
    steps = max(1, int(params.get("steps", 1)))
    multiplier = 1.4 if truthy_parameter(params.get("sm_dyn")) else (
        1.2 if truthy_parameter(params.get("sm")) else 1.0
    )
    raw_base = (2.951823174884865e-6 * width * height) + (
        5.753298233447344e-7 * width * height * steps
    )
    base = max(math.ceil(math.ceil(raw_base) * multiplier), 2)
    director_count = len(params.get("director_reference_images", []) or [])
    vibe_count = len(params.get("reference_image_multiple", []) or [])
    return base + director_count * 5 + max(0, vibe_count - 4) * 2


def check_quota(
    db: sqlite3.Connection, user: sqlite3.Row, mode: str, required_points: int = 1
) -> None:
    if mode == "free":
        required_points = discounted_green_points(user, required_points)
        if required_points == 0:
            return
    bucket = quota_bucket(db, user, mode)
    if (
        bucket["remaining"] is not None
        and bucket["remaining"] < max(1, required_points)
    ):
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            detail={
                "code": "points_insufficient",
                "point_kind": "red" if mode == "paid" else "green",
                "message": "Available points are insufficient",
            },
        )


def reserve_generation_quota(
    db: sqlite3.Connection, user_id: int, mode: str | None, points: int
) -> int:
    """Reserve this task's cost at submit time.

    The full estimated cost must be available before the task is admitted.
    Zero-cost work never needs a reservation.
    """
    if mode is None:
        return 0
    user = db.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
    if not user:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "User not found")
    charge = discounted_green_points(user, points) if mode == "free" else max(0, points)
    if charge == 0:
        return 0
    bucket = quota_bucket(db, user, mode)
    remaining = bucket["remaining"]
    if remaining is not None and remaining < charge:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            detail={
                "code": "points_insufficient",
                "point_kind": "red" if mode == "paid" else "green",
                "message": "Available points are insufficient",
            },
        )
    column = "red_points_reserved" if mode == "paid" else "green_points_reserved"
    db.execute(f"UPDATE users SET {column} = {column} + ? WHERE id = ?", (charge, user_id))
    return charge


def settle_generation_reservation(
    db: sqlite3.Connection,
    user_id: int,
    mode: str | None,
    reserved_points: int,
    *,
    actual_points: int | None,
) -> None:
    if mode is None or reserved_points <= 0:
        return
    reserved_column = "red_points_reserved" if mode == "paid" else "green_points_reserved"
    used_column = "red_points_used" if mode == "paid" else "green_point_used"
    charged = reserved_points if actual_points is None else max(0, actual_points)
    db.execute(
        f"""
        UPDATE users
        SET {reserved_column} = MAX(0, {reserved_column} - ?),
            {used_column} = {used_column} + ?
        WHERE id = ?
        """,
        (reserved_points, charged, user_id),
    )


def release_generation_reservation(
    db: sqlite3.Connection, user_id: int, mode: str | None, reserved_points: int
) -> None:
    if mode is None or reserved_points <= 0:
        return
    reserved_column = "red_points_reserved" if mode == "paid" else "green_points_reserved"
    db.execute(
        f"UPDATE users SET {reserved_column} = MAX(0, {reserved_column} - ?) WHERE id = ?",
        (reserved_points, user_id),
    )


def increment_quota(
    db: sqlite3.Connection, user_id: int, mode: str, points: int = 1
) -> None:
    if mode == "paid":
        charge_paid_points(db, user_id, points)
        return
    row = db.execute(
        "SELECT green_point_discount FROM users WHERE id = ?", (user_id,)
    ).fetchone()
    if row and int(row["green_point_discount"]) >= 100:
        return
    discount = int(row["green_point_discount"]) if row else 0
    charged = max(0, math.ceil(max(1, points) * (100 - discount) / 100))
    db.execute(
        "UPDATE users SET green_point_used = green_point_used + ? WHERE id = ?",
        (charged, user_id),
    )


def discounted_green_points(user: sqlite3.Row, points: int) -> int:
    """Return the permanent green-point charge after the user's discount."""
    if points <= 0:
        return 0
    discount = green_point_discount_for(user)
    return max(0, math.ceil(points * (100 - discount) / 100))


def green_point_discount_for(user: sqlite3.Row) -> int:
    if user["is_admin"]:
        return 100
    return min(100, max(0, int(user["green_point_discount"])))


def charge_paid_points(db: sqlite3.Connection, user_id: int, points: int) -> None:
    if points <= 0:
        return
    db.execute(
        "UPDATE users SET red_points_used = red_points_used + ? WHERE id = ?",
        (points, user_id),
    )


def sanitize_novelai_generate_body(
    body: bytes, user: sqlite3.Row
) -> tuple[bytes, dict[str, Any], str | None]:
    if not (user["can_generate_paid"] or user["is_admin"] or user["green_point_limit"] > user["green_point_used"] or user["green_point_discount"] > 0):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Image generation is not allowed")
    try:
        data = json.loads(body.decode("utf-8"))
    except Exception:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Invalid JSON")
    if not isinstance(data, dict):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Invalid body")
    if data.get("action") not in (None, "generate", "img2img", "infill"):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Unsupported image action")
    params = data.get("parameters")
    if not isinstance(params, dict):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Missing parameters")

    try:
        width = int(params.get("width", 0))
        height = int(params.get("height", 0))
        steps = int(params.get("steps", 0))
    except (TypeError, ValueError):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Invalid generation parameters")
    sampler = str(params.get("sampler", ""))
    if width < 64 or height < 64 or width > MAX_DIMENSION or height > MAX_DIMENSION:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Resolution is not allowed")
    if width % 64 != 0 or height % 64 != 0:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Resolution must be a multiple of 64")
    max_steps = MAX_STEPS_ADMIN if user["is_admin"] else (MAX_STEPS_PAID if user["can_generate_paid"] else MAX_STEPS_FREE)
    if steps < 1 or steps > max_steps:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Steps exceed server limit")
    if sampler not in ALLOWED_SAMPLERS:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Sampler is not allowed")

    # Keep every gateway client on the same current models as novelai.net,
    # including older cached web builds that still submit a V4.5 model ID.
    # NovelAI currently routes Curated inpainting through V4.5 while Full has
    # a native V5 inpainting model.
    requested_model = str(data.get("model", ""))
    use_curated = "curated" in requested_model.lower()
    if data.get("action") == "infill":
        data["model"] = (
            NAI_V4_5_CURATED_INPAINTING_MODEL
            if use_curated
            else NAI_V5_FULL_INPAINTING_MODEL
        )
    else:
        data["model"] = NAI_V5_CURATED_MODEL if use_curated else NAI_V5_FULL_MODEL
    params["params_version"] = 4
    params["n_samples"] = 1
    data["parameters"] = params

    is_free_request = is_free_opus_generation(
        data, params, width=width, height=height, steps=steps
    )
    if is_free_request:
        quota_mode = None if user["is_admin"] else "free"
    else:
        if not (user["can_generate_paid"] or user["is_admin"]):
            raise HTTPException(
                status.HTTP_403_FORBIDDEN,
                "This image option requires paid image quota",
            )
        quota_mode = "paid"
    return (
        json.dumps(data, separators=(",", ":"), ensure_ascii=False).encode("utf-8"),
        data,
        quota_mode,
    )


def require_paid_image_feature(
    db: sqlite3.Connection,
    user: sqlite3.Row,
    enabled: bool,
    message: str,
) -> None:
    if not (enabled or user["is_admin"]) or not (
        user["can_generate_paid"] or user["is_admin"]
    ):
        raise HTTPException(status.HTTP_403_FORBIDDEN, message)
    check_quota(db, user, "paid")


def require_novelai_proxy_permission(
    service: str, path: str, method: str, user: sqlite3.Row, db: sqlite3.Connection
) -> None:
    if service == "text":
        if method != "POST":
            raise HTTPException(status.HTTP_403_FORBIDDEN, "NovelAI endpoint is not allowed")
        if path not in ALLOWED_TEXT_PROXY_PATHS:
            raise HTTPException(status.HTTP_403_FORBIDDEN, "NovelAI endpoint is not allowed")
        if not (user["can_text_generate"] or user["is_admin"]):
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Text generation is not allowed")
        return
    if service == "image":
        if method != "POST":
            raise HTTPException(status.HTTP_403_FORBIDDEN, "NovelAI endpoint is not allowed")
        if path not in ALLOWED_IMAGE_PROXY_PATHS:
            raise HTTPException(status.HTTP_403_FORBIDDEN, "NovelAI endpoint is not allowed")
        if path == "ai/generate-image":
            if not (user["can_generate_paid"] or user["green_point_limit"] > user["green_point_used"] or user["green_point_discount"] > 0):
                raise HTTPException(status.HTTP_403_FORBIDDEN, "Image generation is not allowed")
            return
        if path == "ai/upscale":
            require_paid_image_feature(
                db, user, bool(user["can_image_upscale"]), "Upscale requires paid image quota"
            )
            return
        if path == "ai/augment-image":
            require_paid_image_feature(
                db,
                user,
                bool(user["can_image_augment"]),
                "Image augmentation requires paid image quota",
            )
            return
        if path == "ai/encode-vibe":
            require_paid_image_feature(
                db,
                user,
                bool(user["can_image_encode_vibe"]),
                "Vibe transfer requires paid image quota",
            )
            return
    if service == "api":
        if method != "GET":
            raise HTTPException(status.HTTP_403_FORBIDDEN, "NovelAI endpoint is not allowed")
        if path not in ALLOWED_API_PROXY_PATHS:
            raise HTTPException(status.HTTP_403_FORBIDDEN, "NovelAI endpoint is not allowed")
        if path == "user/subscription" and not user["is_admin"]:
            raise HTTPException(status.HTTP_403_FORBIDDEN, "NovelAI subscription is admin-only")
        return
    if user["is_admin"]:
        return
    raise HTTPException(status.HTTP_403_FORBIDDEN, "NovelAI endpoint is not allowed")


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
    if service not in TARGET_BASES:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Unknown NovelAI service")
    token = novelai_token()
    if not token and not FAKE_NOVELAI:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "NovelAI token is not configured")
    if FAKE_NOVELAI:
        return fake_response(service, path, method)
    assert http_client is not None
    url = novelai_url(service, path)
    headers = {"Authorization": f"Bearer {token}"}
    if method.upper() == "POST":
        headers["Content-Type"] = "application/json"
    if stream:
        headers["Accept"] = "text/event-stream, application/json"
    if stream:
        req = http_client.build_request(method, url, content=body, headers=headers)
        upstream = await http_client.send(req, stream=True)

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
    return upstream.status_code, response_headers(upstream.headers), upstream.content


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
            raise HTTPException(
                status.HTTP_429_TOO_MANY_REQUESTS,
                "User already has an active text generation",
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
        with db_connect() as db:
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
                with db_connect() as db:
                    complete_audit_log(db, audit_id, status_code=result.status_code)
                await release_text_slot(ticket)

        return StreamingResponse(
            queued_body_iter(),
            status_code=result.status_code,
            headers=dict(result.headers),
            media_type=result.media_type,
        )
    await release_text_slot(ticket)
    with db_connect() as db:
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


async def forward_paid_image_tool_and_charge(
    user: sqlite3.Row,
    path: str,
    *,
    method: str,
    body: bytes,
    db: sqlite3.Connection,
) -> tuple[int, dict[str, str], bytes]:
    check_quota(db, user, "paid")
    anlas_before = await fetch_anlas_balance()
    if anlas_before is None:
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            "NovelAI Anlas balance is unavailable",
        )
    result = await forward_to_novelai("image", path, method=method, body=body)
    assert not isinstance(result, StreamingResponse)
    status_code, headers, content = result
    if status_code == 200:
        anlas_after = await fetch_anlas_balance()
        if anlas_after is not None:
            charge_paid_points(
                db,
                int(user["id"]),
                max(0, anlas_before - anlas_after),
            )
            db.commit()
    return status_code, headers, content


def fake_png() -> bytes:
    return bytes.fromhex(
        "89504e470d0a1a0a0000000d4948445200000001000000010802000000907753de"
        "0000000c49444154789c6360f8cf00000301010118dd8db00000000049454e44ae426082"
    )


def decode_zip_image(data: bytes) -> bytes | None:
    try:
        with ZipFile(BytesIO(data)) as archive:
            for item in archive.infolist():
                if item.is_dir():
                    continue
                raw = archive.read(item)
                if raw.startswith(b"\x89PNG") or raw.startswith(b"RIFF"):
                    return raw
    except Exception:
        return None
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


def job_from_task_row(task: sqlite3.Row) -> ProxyJob:
    """Rebuild an executable job from its durable queue record."""
    try:
        payload = json.loads(task["request_json"])
        if not isinstance(payload, dict) or not isinstance(payload.get("parameters"), dict):
            raise ValueError("Invalid request structure")
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    except (TypeError, ValueError, json.JSONDecodeError) as exc:
        raise ValueError(f"Task {task['id']} has invalid request data") from exc
    mode = str(task["mode"])
    cost = (
        estimate_image_points(payload, payload["parameters"])
        if mode == "free"
        else int(task["cost"] or 1)
    )
    return ProxyJob(
        virtual_finish=float(task["virtual_finish"] or 0),
        negative_weight=-int(task["queue_weight"] or QUEUE_WEIGHTS["free"]),
        created_at=str(task["queued_at"] or task["created_at"]),
        user_id=int(task["user_id"]),
        task_id=str(task["id"]),
        service="image",
        path="ai/generate-image",
        body=body,
        cost=cost,
        quota_mode=mode if mode in {"free", "paid"} else None,
    )


async def restore_generation_queue() -> None:
    """Restore queued work after a gateway restart instead of losing it in RAM."""
    global queue_virtual_time
    assert queue_condition is not None
    with db_connect() as db:
        # The prior process cannot still be executing after a clean restart.
        interrupted_parents = db.execute(
            "SELECT DISTINCT batch_id FROM generation_tasks "
            "WHERE status = 'running' AND batch_id IS NOT NULL"
        ).fetchall()
        db.execute(
            "UPDATE generation_tasks SET status = 'queued', started_at = NULL "
            "WHERE status = 'running'"
        )
        for parent in interrupted_parents:
            refresh_submission_task(db, str(parent["batch_id"]))
        rows = db.execute(
            "SELECT * FROM generation_tasks WHERE status = 'queued' "
            "ORDER BY virtual_finish ASC, queued_at ASC, id ASC"
        ).fetchall()
        db.commit()
    jobs: list[ProxyJob] = []
    for row in rows:
        try:
            jobs.append(job_from_task_row(row))
        except ValueError:
            with db_connect() as db:
                release_generation_reservation(
                    db,
                    int(row["user_id"]),
                    str(row["mode"]) if row["mode"] else None,
                    int(row["reserved_points"] or 0),
                )
                db.execute(
                    """
                    UPDATE generation_tasks
                    SET status = 'failed', error_message = ?,
                        released_green_points = CASE WHEN mode = 'free' THEN reserved_points ELSE 0 END,
                        released_red_points = CASE WHEN mode = 'paid' THEN reserved_points ELSE 0 END,
                        completed_at = ?
                    WHERE id = ?
                    """,
                    ("Queued request data is invalid", now_iso(), row["id"]),
                )
                if row["batch_id"]:
                    refresh_submission_task(db, str(row["batch_id"]))
                db.commit()
    async with queue_condition:
        pending_jobs.extend(jobs)
        pending_jobs.sort(key=lambda job: job.sort_key)
        if pending_jobs:
            queue_virtual_time = max(job.virtual_finish for job in pending_jobs)


def visible_history_task(
    task_id: str,
    user: sqlite3.Row,
    db: sqlite3.Connection,
) -> sqlite3.Row:
    task = db.execute("SELECT * FROM generation_tasks WHERE id = ?", (task_id,)).fetchone()
    if not task:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Task not found")
    hidden = db.execute(
        "SELECT 1 FROM history_hidden WHERE user_id = ? AND task_id = ?",
        (user["id"], task_id),
    ).fetchone()
    if hidden:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Task not found")
    if task["user_id"] != user["id"] and not user["is_admin"]:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Forbidden")
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


async def enqueue_generate(
    *,
    user: sqlite3.Row,
    service: str,
    path: str,
    body: bytes,
    parsed: dict[str, Any],
    quota_mode: str | None,
    db: sqlite3.Connection,
    batch_id: str | None = None,
    batch_index: int | None = None,
    task_type: str = "single",
) -> tuple[str, str]:
    global queue_virtual_time
    assert queue_condition is not None
    user_id = int(user["id"])
    fingerprint = generation_request_fingerprint(parsed)
    parent_task_id = batch_id or secrets.token_urlsafe(18)
    queue_class = mode_for_user(user)
    estimated_cost = estimate_image_points(parsed, parsed["parameters"])
    async with queue_condition:
        duplicate = db.execute(
            """
            SELECT id, status, created_at FROM generation_tasks
            WHERE user_id = ? AND request_fingerprint = ?
              AND status IN ('queued', 'running', 'success')
            ORDER BY created_at DESC LIMIT 1
            """,
            (user_id, fingerprint),
        ).fetchone()
        if duplicate:
            raise HTTPException(
                status.HTTP_409_CONFLICT,
                detail={
                    "code": "duplicate_generation",
                    "message": "No parameters varied. Check the seed.",
                    "task_id": duplicate["id"],
                    "task_status": duplicate["status"],
                    "created_at": duplicate["created_at"],
                },
            )
        outstanding = db.execute(
            """
            SELECT COUNT(*) FROM generation_tasks
            WHERE user_id = ? AND status IN ('queued', 'running')
            """,
            (user_id,),
        ).fetchone()[0]
        if outstanding >= MAX_QUEUED_IMAGE_TASKS_PER_USER:
            raise HTTPException(
                status.HTTP_429_TOO_MANY_REQUESTS,
                detail={
                    "code": "queue_capacity_reached",
                    "message": "Too many unfinished image tasks",
                    "limit": MAX_QUEUED_IMAGE_TASKS_PER_USER,
                },
            )
        weight = QUEUE_WEIGHTS[queue_class]
        task_id = secrets.token_urlsafe(18)
        params = parsed["parameters"]
        created = now_iso()
        billing_mode = quota_mode or queue_class
        existing_parent = db.execute(
            "SELECT user_id FROM generation_submission_tasks WHERE id = ?",
            (parent_task_id,),
        ).fetchone()
        if existing_parent and int(existing_parent["user_id"]) != user_id:
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Forbidden batch id")
        db.execute(
            "INSERT OR IGNORE INTO generation_submission_tasks "
            "(id, user_id, type, status, created_at) VALUES (?, ?, ?, 'queued', ?)",
            (parent_task_id, user_id, task_type if task_type in {"single", "batch"} else "single", created),
        )
        try:
            reserved_points = reserve_generation_quota(
                db, user_id, quota_mode, estimated_cost
            )
        except HTTPException as exc:
            db.execute(
                """
                INSERT INTO generation_tasks(
                  id, user_id, mode, queue_class, queue_weight, virtual_finish,
                  status, prompt, negative_prompt, width, height, steps, scale,
                  sampler, seed, cost, batch_id, batch_index, request_fingerprint,
                  request_json, error_message, completed_at, created_at
                ) VALUES (?, ?, ?, ?, ?, 0, 'rejected', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    task_id, user_id, billing_mode, queue_class, weight,
                    str(parsed.get("input", ""))[:4000], str(params.get("uc", ""))[:4000],
                    int(params.get("width", 0)), int(params.get("height", 0)),
                    int(params.get("steps", 0)), float(params.get("scale", 0)),
                    str(params.get("sampler", "")), params.get("seed"), estimated_cost,
                    parent_task_id, batch_index, fingerprint,
                    json.dumps(parsed, ensure_ascii=False), str(exc.detail), created, created,
                ),
            )
            refresh_submission_task(db, parent_task_id)
            db.commit()
            return parent_task_id, task_id
        base = max(queue_virtual_time, queue_last_finish[queue_class])
        virtual_finish = base + (1.0 / weight)
        queue_last_finish[queue_class] = virtual_finish
        db.execute(
            """
            INSERT INTO generation_tasks(
              id, user_id, mode, queue_class, queue_weight, virtual_finish,
              status, prompt, negative_prompt, width, height, steps, scale,
              sampler, seed, cost, reserved_points, reserved_green_points, reserved_red_points, batch_id, batch_index, request_fingerprint, request_json, queued_at, created_at
            )
            VALUES (?, ?, ?, ?, ?, ?, 'queued', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                task_id,
                user_id,
                billing_mode,
                queue_class,
                weight,
                virtual_finish,
                str(parsed.get("input", ""))[:4000],
                str(params.get("uc", ""))[:4000],
                int(params.get("width", 0)),
                int(params.get("height", 0)),
                int(params.get("steps", 0)),
                float(params.get("scale", 0)),
                str(params.get("sampler", "")),
                params.get("seed"),
                estimated_cost,
                reserved_points,
                reserved_points if billing_mode == "free" else 0,
                reserved_points if billing_mode == "paid" else 0,
                parent_task_id,
                batch_index,
                fingerprint,
                json.dumps(parsed, ensure_ascii=False),
                created,
                created,
            ),
        )
        db.commit()
        refresh_submission_task(db, parent_task_id)
        db.commit()
        pending_jobs.append(
            ProxyJob(
                virtual_finish=virtual_finish,
                negative_weight=-weight,
                created_at=created,
                user_id=user_id,
                task_id=task_id,
                service=service,
                path=path,
                body=body,
                cost=estimated_cost,
                quota_mode=quota_mode,
            )
        )
        pending_jobs.sort(key=lambda job: job.sort_key)
        queue_condition.notify_all()
    return parent_task_id, task_id


def generation_request_fingerprint(parsed: dict[str, Any]) -> str:
    """Hash the normalized, server-validated generation request deterministically."""
    normalized = json.dumps(
        parsed,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    )
    return hashlib.sha256(normalized.encode("utf-8")).hexdigest()


def generation_batch_request_hash(items: list[dict[str, Any]]) -> str:
    """Hash an ordered, normalized batch for idempotency-key validation."""
    normalized = json.dumps(
        items,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    )
    return hashlib.sha256(normalized.encode("utf-8")).hexdigest()


async def enqueue_generation_batch(
    *,
    user: sqlite3.Row,
    client_request_id: str,
    items: list[tuple[bytes, dict[str, Any], str | None]],
    db: sqlite3.Connection,
) -> tuple[str, list[str], bool]:
    """Atomically validate, reserve, and enqueue one complete image batch.

    The idempotency key is checked before semantic duplicate detection. A lost
    202 response can therefore be replayed safely, while a new user action with
    identical effective generation parameters is still rejected.
    """
    global queue_virtual_time
    assert queue_condition is not None
    if not items:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Batch is empty")
    if len(items) > 10:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Batch is too large")

    user_id = int(user["id"])
    parsed_items = [item[1] for item in items]
    request_hash = generation_batch_request_hash(parsed_items)
    fingerprints = [generation_request_fingerprint(item) for item in parsed_items]

    async with queue_condition:
        existing_submission = db.execute(
            """
            SELECT id, request_hash FROM generation_submission_tasks
            WHERE user_id = ? AND client_request_id = ?
            """,
            (user_id, client_request_id),
        ).fetchone()
        if existing_submission:
            if existing_submission["request_hash"] != request_hash:
                raise HTTPException(
                    status.HTTP_409_CONFLICT,
                    detail={
                        "code": "idempotency_key_conflict",
                        "message": "Idempotency key was reused with different parameters",
                    },
                )
            existing_items = db.execute(
                "SELECT id FROM generation_tasks WHERE batch_id = ? "
                "ORDER BY batch_index, created_at, id",
                (existing_submission["id"],),
            ).fetchall()
            return (
                str(existing_submission["id"]),
                [str(item["id"]) for item in existing_items],
                True,
            )

        duplicate_positions: dict[str, list[int]] = {}
        for index, fingerprint in enumerate(fingerprints):
            duplicate_positions.setdefault(fingerprint, []).append(index)
        repeated = [positions for positions in duplicate_positions.values() if len(positions) > 1]
        if repeated:
            first_positions = repeated[0]
            seed = parsed_items[first_positions[0]]["parameters"].get("seed")
            raise HTTPException(
                status.HTTP_409_CONFLICT,
                detail={
                    "code": "duplicate_within_batch",
                    "message": "No parameters varied. Check the seed.",
                    "batch_indexes": first_positions,
                    "seed": seed,
                },
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
                raise HTTPException(
                    status.HTTP_409_CONFLICT,
                    detail={
                        "code": "duplicate_generation",
                        "message": "No parameters varied. Check the seed.",
                        "task_id": duplicate["id"],
                        "task_status": duplicate["status"],
                        "created_at": duplicate["created_at"],
                        "batch_index": index,
                        "seed": duplicate["seed"],
                    },
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
            raise HTTPException(
                status.HTTP_429_TOO_MANY_REQUESTS,
                detail={
                    "code": "queue_capacity_reached",
                    "message": "Too many unfinished image tasks",
                    "limit": MAX_QUEUED_IMAGE_TASKS_PER_USER,
                },
            )

        fresh_user = db.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
        if not fresh_user:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "User not found")
        costs = [estimate_image_points(parsed, parsed["parameters"]) for parsed in parsed_items]
        reservations: list[int] = []
        green_total = 0
        red_total = 0
        for (_, _, quota_mode), cost in zip(items, costs):
            if quota_mode == "free":
                reserved = discounted_green_points(fresh_user, cost)
                green_total += reserved
            elif quota_mode == "paid":
                reserved = max(0, cost)
                red_total += reserved
            else:
                reserved = 0
            reservations.append(reserved)
        for mode, required in (("free", green_total), ("paid", red_total)):
            if required <= 0:
                continue
            remaining = quota_bucket(db, fresh_user, mode)["remaining"]
            if remaining is not None and remaining < required:
                raise HTTPException(
                    status.HTTP_409_CONFLICT,
                    detail={
                        "code": "points_insufficient",
                        "point_kind": "red" if mode == "paid" else "green",
                        "message": "Available points are insufficient",
                    },
                )

        queue_class = mode_for_user(user)
        weight = QUEUE_WEIGHTS[queue_class]
        parent_task_id = secrets.token_urlsafe(18)
        created = now_iso()
        item_ids: list[str] = []
        jobs: list[ProxyJob] = []
        try:
            db.execute("BEGIN IMMEDIATE")
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
                    created,
                ),
            )
            if green_total:
                db.execute(
                    "UPDATE users SET green_points_reserved = green_points_reserved + ? WHERE id = ?",
                    (green_total, user_id),
                )
            if red_total:
                db.execute(
                    "UPDATE users SET red_points_reserved = red_points_reserved + ? WHERE id = ?",
                    (red_total, user_id),
                )

            for index, ((body, parsed, quota_mode), cost, reserved, fingerprint) in enumerate(
                zip(items, costs, reservations, fingerprints)
            ):
                item_id = secrets.token_urlsafe(18)
                item_created = now_iso()
                billing_mode = quota_mode or queue_class
                base = max(queue_virtual_time, queue_last_finish[queue_class])
                virtual_finish = base + (1.0 / weight)
                queue_last_finish[queue_class] = virtual_finish
                params = parsed["parameters"]
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
                        billing_mode,
                        queue_class,
                        weight,
                        virtual_finish,
                        str(parsed.get("input", ""))[:4000],
                        str(params.get("uc", ""))[:4000],
                        int(params.get("width", 0)),
                        int(params.get("height", 0)),
                        int(params.get("steps", 0)),
                        float(params.get("scale", 0)),
                        str(params.get("sampler", "")),
                        params.get("seed"),
                        cost,
                        reserved,
                        reserved if billing_mode == "free" else 0,
                        reserved if billing_mode == "paid" else 0,
                        parent_task_id,
                        index,
                        fingerprint,
                        json.dumps(parsed, ensure_ascii=False),
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
                        body=body,
                        cost=cost,
                        quota_mode=quota_mode,
                    )
                )
            refresh_submission_task(db, parent_task_id)
            db.commit()
        except Exception:
            db.rollback()
            # These values are scheduling hints only, but keeping a failed
            # transaction out of their accounting avoids artificial gaps.
            for queue_name in queue_last_finish:
                queue_last_finish[queue_name] = max(
                    (
                        job.virtual_finish
                        for job in pending_jobs
                        if mode_for_user_id(db, job.user_id) == queue_name
                    ),
                    default=queue_virtual_time,
                )
            raise

        pending_jobs.extend(jobs)
        pending_jobs.sort(key=lambda job: job.sort_key)
        queue_condition.notify_all()
        return parent_task_id, item_ids, False


async def queue_worker() -> None:
    global queue_virtual_time
    assert queue_condition is not None
    while True:
        async with queue_condition:
            while not pending_jobs:
                await queue_condition.wait()
            job = pending_jobs.pop(0)
            active_user_ids.add(job.user_id)
            queue_virtual_time = max(queue_virtual_time, job.virtual_finish)
        with db_connect() as db:
            db.execute(
                "UPDATE generation_tasks SET status = 'running', started_at = ? WHERE id = ?",
                (now_iso(), job.task_id),
            )
            parent = db.execute(
                "SELECT batch_id FROM generation_tasks WHERE id = ?", (job.task_id,)
            ).fetchone()
            if parent and parent["batch_id"]:
                refresh_submission_task(db, parent["batch_id"])
            db.commit()
        try:
            anlas_before: int | None = None
            anlas_after: int | None = None
            paid_points_charged = 0
            if job.quota_mode == "paid":
                anlas_before = await fetch_anlas_balance()
                if anlas_before is None:
                    raise HTTPException(
                        status.HTTP_503_SERVICE_UNAVAILABLE,
                        "NovelAI Anlas balance is unavailable",
                    )
            result = await forward_to_novelai(job.service, job.path, method="POST", body=job.body)
            assert not isinstance(result, StreamingResponse)
            status_code, headers, content = result
            with db_connect() as db:
                task = db.execute(
                    "SELECT reserved_points, batch_id FROM generation_tasks WHERE id = ?",
                    (job.task_id,),
                ).fetchone()
                reserved_points = int(task["reserved_points"]) if task else 0
                if status_code == 200:
                    image_path = await save_history_image(job.task_id, content)
                    if image_path is None:
                        raise HTTPException(
                            status.HTTP_502_BAD_GATEWAY,
                            "NovelAI returned no valid image",
                        )
                    if job.quota_mode == "paid":
                        # If the post-request balance lookup fails, keep the
                        # conservative reservation instead of charging zero for
                        # work NovelAI already completed.
                        paid_points_charged = reserved_points
                        anlas_after = await fetch_anlas_balance()
                        if anlas_after is not None and anlas_before is not None:
                            paid_points_charged = max(0, anlas_before - anlas_after)
                    settle_generation_reservation(
                        db,
                        job.user_id,
                        job.quota_mode,
                        reserved_points,
                        actual_points=(
                            paid_points_charged if job.quota_mode == "paid" else None
                        ),
                    )
                    db.execute(
                        """
                        UPDATE generation_tasks
                        SET status = 'success', image_path = ?, anlas_before = ?,
                            anlas_after = ?, paid_points_charged = ?,
                            consumed_green_points = CASE WHEN mode = 'free' THEN reserved_points ELSE 0 END,
                            consumed_red_points = CASE WHEN mode = 'paid' THEN ? ELSE 0 END,
                            completed_at = ?
                        WHERE id = ?
                        """,
                        (
                            image_path,
                            anlas_before,
                            anlas_after,
                            paid_points_charged,
                            paid_points_charged,
                            now_iso(),
                            job.task_id,
                        ),
                    )
                else:
                    release_generation_reservation(
                        db, job.user_id, job.quota_mode, reserved_points
                    )
                    db.execute(
                        """
                        UPDATE generation_tasks
                        SET status = 'failed', error_message = ?, anlas_before = ?,
                            anlas_after = ?, paid_points_charged = ?,
                            released_green_points = CASE WHEN mode = 'free' THEN reserved_points ELSE 0 END,
                            released_red_points = CASE WHEN mode = 'paid' THEN reserved_points ELSE 0 END,
                            completed_at = ?
                        WHERE id = ?
                        """,
                        (
                            f"NovelAI HTTP {status_code}",
                            anlas_before,
                            anlas_after,
                            paid_points_charged,
                            now_iso(),
                            job.task_id,
                        ),
                    )
                if task and task["batch_id"]:
                    refresh_submission_task(db, task["batch_id"])
                db.commit()
        except HTTPException as exc:
            with db_connect() as db:
                task = db.execute(
                    "SELECT reserved_points, batch_id FROM generation_tasks WHERE id = ?",
                    (job.task_id,),
                ).fetchone()
                release_generation_reservation(
                    db,
                    job.user_id,
                    job.quota_mode,
                    int(task["reserved_points"]) if task else 0,
                )
                db.execute(
                    """
                    UPDATE generation_tasks
                    SET status = 'failed', error_message = ?,
                        released_green_points = CASE WHEN mode = 'free' THEN reserved_points ELSE 0 END,
                        released_red_points = CASE WHEN mode = 'paid' THEN reserved_points ELSE 0 END,
                        completed_at = ?
                    WHERE id = ?
                    """,
                    (str(exc.detail), now_iso(), job.task_id),
                )
                if task and task["batch_id"]:
                    refresh_submission_task(db, task["batch_id"])
                db.commit()
        except Exception as exc:
            with db_connect() as db:
                task = db.execute(
                    "SELECT reserved_points, batch_id FROM generation_tasks WHERE id = ?",
                    (job.task_id,),
                ).fetchone()
                release_generation_reservation(
                    db,
                    job.user_id,
                    job.quota_mode,
                    int(task["reserved_points"]) if task else 0,
                )
                db.execute(
                    """
                    UPDATE generation_tasks
                    SET status = 'failed', error_message = ?,
                        released_green_points = CASE WHEN mode = 'free' THEN reserved_points ELSE 0 END,
                        released_red_points = CASE WHEN mode = 'paid' THEN reserved_points ELSE 0 END,
                        completed_at = ?
                    WHERE id = ?
                    """,
                    ("Generation failed", now_iso(), job.task_id),
                )
                if task and task["batch_id"]:
                    refresh_submission_task(db, task["batch_id"])
                db.commit()
        finally:
            async with queue_condition:
                active_user_ids.discard(job.user_id)
                queue_condition.notify()


def mode_for_user_id(db: sqlite3.Connection, user_id: int) -> str:
    user = db.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
    if not user:
        return "free"
    return mode_for_user(user)


async def legacy_generation_response(item_id: str) -> Response:
    """Wait for a durable task and preserve the old synchronous ZIP contract."""
    deadline = asyncio.get_running_loop().time() + 10 * 60
    while asyncio.get_running_loop().time() < deadline:
        with db_connect() as task_db:
            item = task_db.execute(
                "SELECT status, image_path, error_message FROM generation_tasks WHERE id = ?",
                (item_id,),
            ).fetchone()
        if not item:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Generation task not found")
        item_status = str(item["status"])
        if item_status == "success":
            if not item["image_path"]:
                raise HTTPException(status.HTTP_502_BAD_GATEWAY, "Image not available")
            image = resolve_history_image_file(str(item["image_path"])).read_bytes()
            archive_buffer = BytesIO()
            with ZipFile(archive_buffer, "w") as archive:
                archive.writestr("image_0.png", image)
            return Response(
                content=archive_buffer.getvalue(),
                status_code=status.HTTP_200_OK,
                media_type="application/zip",
            )
        if item_status in {"failed", "rejected"}:
            raise HTTPException(
                status.HTTP_502_BAD_GATEWAY,
                str(item["error_message"] or "Generation failed"),
            )
        await asyncio.sleep(0.25)
    raise HTTPException(status.HTTP_504_GATEWAY_TIMEOUT, "Generation timed out")


@app.api_route("/api/nai/{service}/{path:path}", methods=["GET", "POST"])
async def novelai_proxy(
    service: str,
    path: str,
    request: Request,
    user: sqlite3.Row = Depends(require_user),
    db: sqlite3.Connection = Depends(get_db),
):
    method = request.method.upper()
    body = await request.body()
    audit_id: str | None = None
    try:
        require_novelai_proxy_permission(service, path, method, user, db)
        audit_id = create_audit_log(
            db,
            user,
            service=service,
            path=path,
            method=method,
            body=body,
            content_type=request.headers.get("content-type", ""),
        )
        if service == "image" and path == "ai/generate-image" and method == "POST":
            sanitized, parsed, quota_mode = sanitize_novelai_generate_body(body, user)
            _, item_id = await enqueue_generate(
                user=user,
                service=service,
                path=path,
                body=sanitized,
                parsed=parsed,
                quota_mode=quota_mode,
                db=db,
            )
            # New clients use /api/generation-tasks. This route deliberately
            # keeps the historical synchronous ZIP response for old clients.
            response = await legacy_generation_response(item_id)
            complete_audit_log(db, audit_id, status_code=response.status_code)
            return response
        if service == "image" and path in PAID_DIRECT_IMAGE_PATHS and method == "POST":
            result = await forward_paid_image_tool_and_charge(
                user,
                path,
                method=method,
                body=body,
                db=db,
            )
            complete_audit_log(db, audit_id, status_code=result[0])
            return Response(content=result[2], status_code=result[0], headers=result[1])
        stream = (
            service == "text"
            and "text/event-stream" in request.headers.get("accept", "")
        )
        if service == "text" and method == "POST":
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


@app.post("/api/generation-tasks", status_code=status.HTTP_202_ACCEPTED)
async def submit_generation_task(
    request: Request,
    user: sqlite3.Row = Depends(require_user),
    db: sqlite3.Connection = Depends(get_db),
):
    """Durably accept an image-generation request without waiting for it."""
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
        try:
            envelope = json.loads(body)
        except (TypeError, ValueError, json.JSONDecodeError):
            envelope = None
        is_atomic_batch = (
            isinstance(envelope, dict)
            and isinstance(envelope.get("request"), dict)
            and isinstance(envelope.get("seeds"), list)
        )
        if is_atomic_batch:
            client_request_id = str(envelope.get("client_request_id", "")).strip()
            if not (8 <= len(client_request_id) <= 128):
                raise HTTPException(
                    status.HTTP_400_BAD_REQUEST, "Invalid client request id"
                )
            seeds = envelope["seeds"]
            if not seeds or len(seeds) > 10:
                raise HTTPException(status.HTTP_400_BAD_REQUEST, "Invalid batch size")
            batch_items: list[tuple[bytes, dict[str, Any], str | None]] = []
            for raw_seed in seeds:
                if isinstance(raw_seed, bool) or not isinstance(raw_seed, int):
                    raise HTTPException(status.HTTP_400_BAD_REQUEST, "Invalid seed")
                if raw_seed < 0 or raw_seed > 0xFFFFFFFF:
                    raise HTTPException(status.HTTP_400_BAD_REQUEST, "Invalid seed")
                item_request = json.loads(
                    json.dumps(envelope["request"], ensure_ascii=False)
                )
                parameters = item_request.get("parameters")
                if not isinstance(parameters, dict):
                    raise HTTPException(
                        status.HTTP_400_BAD_REQUEST,
                        "Invalid generation parameters",
                    )
                parameters["seed"] = raw_seed
                if item_request.get("action") == "img2img":
                    parameters["extra_noise_seed"] = raw_seed
                item_body = json.dumps(item_request, ensure_ascii=False).encode("utf-8")
                batch_items.append(sanitize_novelai_generate_body(item_body, user))
            task_id, item_ids, _ = await enqueue_generation_batch(
                user=user,
                client_request_id=client_request_id,
                items=batch_items,
                db=db,
            )
        else:
            sanitized, parsed, quota_mode = sanitize_novelai_generate_body(body, user)
            task_id, item_id = await enqueue_generate(
                user=user,
                service="image",
                path="ai/generate-image",
                body=sanitized,
                parsed=parsed,
                quota_mode=quota_mode,
                db=db,
                batch_id=request.headers.get("x-naiweaver-batch-id") or None,
                batch_index=int(request.headers["x-naiweaver-batch-index"])
                if request.headers.get("x-naiweaver-batch-index", "").isdigit()
                else None,
                task_type=request.headers.get("x-naiweaver-task-type", "single"),
            )
            item_ids = [item_id]
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
    response_items = []
    for index, item_id in enumerate(item_ids):
        row = db.execute(
            "SELECT status, batch_index FROM generation_tasks WHERE id = ?",
            (item_id,),
        ).fetchone()
        response_items.append(
            {
                "id": item_id,
                "batch_index": (
                    int(row["batch_index"])
                    if row and row["batch_index"] is not None
                    else index
                ),
                "status": str(row["status"]) if row else "queued",
            }
        )
    response = JSONResponse(
        {
            "task_id": task_id,
            "item_id": item_ids[0],
            "items": response_items,
            "status": generation_task_status(task_id, user, db)["status"],
        },
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


def public_generation_item(item: sqlite3.Row) -> dict[str, Any]:
    """Return restorable parameters without echoing image/vector payloads."""
    result = dict(item)
    try:
        request_data = json.loads(str(item["request_json"]))
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
        result["request_json"] = json.dumps(request_data, ensure_ascii=False)
    except (TypeError, ValueError, json.JSONDecodeError):
        result["request_json"] = ""
    return result


@app.get("/api/generation-tasks/{task_id}")
def generation_task_status(
    task_id: str,
    user: sqlite3.Row = Depends(require_user),
    db: sqlite3.Connection = Depends(get_db),
):
    task = db.execute("SELECT * FROM generation_submission_tasks WHERE id = ?", (task_id,)).fetchone()
    if not task:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Task not found")
    if task["user_id"] != user["id"] and not user["is_admin"]:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Forbidden")
    items = db.execute(
        "SELECT * "
        "FROM generation_tasks WHERE batch_id = ? ORDER BY batch_index, created_at, id",
        (task_id,),
    ).fetchall()
    return {
        **dict(task),
        "items": [
            {
                **public_generation_item(item),
                "image_url": (
                    f"/api/history/{item['id']}/image"
                    if item["image_path"]
                    else None
                ),
            }
            for item in items
        ],
    }


@app.get("/api/generation-items/{item_id}")
def generation_item_status(
    item_id: str,
    user: sqlite3.Row = Depends(require_user),
    db: sqlite3.Connection = Depends(get_db),
):
    item = visible_history_task(item_id, user, db)
    return {
        "id": item["id"],
        "task_id": item["batch_id"],
        "status": item["status"],
        "error_message": item["error_message"],
        "image_url": f"/api/history/{item['id']}/image" if item["image_path"] else None,
    }


@app.get("/api/current-generation-task")
def current_generation_task(
    user: sqlite3.Row = Depends(require_user),
    db: sqlite3.Connection = Depends(get_db),
):
    task = db.execute(
        """
        SELECT * FROM generation_submission_tasks
        WHERE user_id = ?
        ORDER BY CASE WHEN status IN ('queued', 'running') THEN 0 ELSE 1 END,
                 created_at DESC
        LIMIT 1
        """,
        (user["id"],),
    ).fetchone()
    if not task:
        return {"task": None}
    return {"task": generation_task_status(str(task["id"]), user, db)}


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
            SELECT t.*, u.username
            FROM generation_tasks t
            JOIN users u ON u.id = t.user_id
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
        "items": [public_generation_item(row) for row in rows],
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
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Image not available")
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
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Thumbnail not available")
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
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Batch not found")
    if any(task["user_id"] != user["id"] for task in tasks) and not user["is_admin"]:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Forbidden")
    if any(task["status"] in {"queued", "running"} for task in tasks):
        raise HTTPException(status.HTTP_409_CONFLICT, "Cannot delete an active batch")

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
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Task not found")
    if task["user_id"] != user["id"] and not user["is_admin"]:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Forbidden")
    if task["status"] in {"queued", "running"}:
        raise HTTPException(status.HTTP_409_CONFLICT, "Cannot delete an active task")
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
def serve_web(path: str):
    if path.startswith("api/"):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Not found")
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
