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
import os
from pathlib import Path
import secrets
import sqlite3
from typing import Any
from zipfile import ZipFile

from fastapi import Depends, FastAPI, HTTPException, Request, Response, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, StreamingResponse
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

DEFAULT_FREE_DAILY_LIMIT = int(os.environ.get("NAIWEAVER_FREE_DAILY_LIMIT", "200"))
DEFAULT_PAID_DAILY_LIMIT = int(os.environ.get("NAIWEAVER_PAID_DAILY_LIMIT", "1000"))
DEFAULT_PAID_POINT_LIMIT = int(os.environ.get("NAIWEAVER_PAID_POINT_LIMIT", "3000"))
DEFAULT_ADMIN_POINT_LIMIT = int(os.environ.get("NAIWEAVER_ADMIN_POINT_LIMIT", "5000"))
MAX_STEPS_FREE = int(os.environ.get("NAIWEAVER_FREE_MAX_STEPS", "28"))
MAX_STEPS_PAID = int(os.environ.get("NAIWEAVER_PAID_MAX_STEPS", "50"))
MAX_STEPS_ADMIN = int(os.environ.get("NAIWEAVER_ADMIN_MAX_STEPS", "50"))
MAX_DIMENSION = int(os.environ.get("NAIWEAVER_MAX_DIMENSION", "2048"))
FREE_IMAGE_SIZES = frozenset({(832, 1216), (1216, 832), (1024, 1024)})
TEXT_GLOBAL_CONCURRENCY = int(os.environ.get("NAIWEAVER_TEXT_CONCURRENCY", "3"))
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

CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  is_admin INTEGER NOT NULL DEFAULT 0,
  disabled INTEGER NOT NULL DEFAULT 0,
  can_generate_free INTEGER NOT NULL DEFAULT 1,
  can_generate_paid INTEGER NOT NULL DEFAULT 0,
  can_text_generate INTEGER NOT NULL DEFAULT 1,
  can_image_upscale INTEGER NOT NULL DEFAULT 1,
  can_image_augment INTEGER NOT NULL DEFAULT 1,
  can_image_encode_vibe INTEGER NOT NULL DEFAULT 1,
  daily_limit INTEGER,
  paid_daily_limit INTEGER,
  paid_point_limit INTEGER NOT NULL DEFAULT 3000,
  paid_point_used INTEGER NOT NULL DEFAULT 0,
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
  request_json TEXT NOT NULL,
  queued_at TEXT,
  started_at TEXT,
  completed_at TEXT,
  created_at TEXT NOT NULL
);

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
    username: str = field(compare=False)
    task_id: str = field(compare=False)
    service: str = field(compare=False)
    path: str = field(compare=False)
    future: asyncio.Future[tuple[int, dict[str, str], bytes]] = field(compare=False)
    body: bytes = field(compare=False)
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


class UserUpdateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    password: str | None = Field(default=None, min_length=1, max_length=256)
    is_admin: bool | None = None
    disabled: bool | None = None
    can_generate_free: bool | None = None
    can_generate_paid: bool | None = None
    can_text_generate: bool | None = None
    can_image_upscale: bool | None = None
    can_image_augment: bool | None = None
    can_image_encode_vibe: bool | None = None
    daily_limit: int | None = Field(default=None, ge=0)
    paid_daily_limit: int | None = Field(default=None, ge=0)
    paid_point_limit: int | None = Field(default=None, ge=0)
    paid_point_used: int | None = Field(default=None, ge=0)


class UserCreateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    username: str = Field(min_length=1, max_length=80)
    password: str | None = Field(default=None, min_length=1, max_length=256)
    is_admin: bool = False
    disabled: bool = False
    can_generate_free: bool = True
    can_generate_paid: bool = False
    can_text_generate: bool = True
    can_image_upscale: bool = True
    can_image_augment: bool = True
    can_image_encode_vibe: bool = True
    daily_limit: int | None = Field(default=DEFAULT_FREE_DAILY_LIMIT, ge=0)
    paid_daily_limit: int | None = Field(default=DEFAULT_PAID_DAILY_LIMIT, ge=0)
    paid_point_limit: int | None = Field(default=DEFAULT_PAID_POINT_LIMIT, ge=0)
    paid_point_used: int = Field(default=0, ge=0)


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
        "paid_point_limit": f"INTEGER NOT NULL DEFAULT {DEFAULT_PAID_POINT_LIMIT}",
        "paid_point_used": "INTEGER NOT NULL DEFAULT 0",
    }
    for name, definition in user_columns.items():
        if name not in table_columns:
            db.execute(f"ALTER TABLE users ADD COLUMN {name} {definition}")
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
    }
    for name, definition in generation_task_columns.items():
        if name not in task_columns:
            db.execute(f"ALTER TABLE generation_tasks ADD COLUMN {name} {definition}")
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
        ("admin", admin_password, 1, 1, 1, None, None, DEFAULT_ADMIN_POINT_LIMIT),
        ("free_user", "free-test-pass", 0, 1, 0, DEFAULT_FREE_DAILY_LIMIT, 0, 0),
        (
            "paid_user",
            "paid-test-pass",
            0,
            1,
            1,
            None,
            DEFAULT_PAID_DAILY_LIMIT,
            DEFAULT_PAID_POINT_LIMIT,
        ),
    ]
    with db_connect() as db:
        for (
            username,
            password,
            is_admin,
            can_free,
            can_paid,
            daily,
            paid_daily,
            paid_points,
        ) in samples:
            existing = db.execute("SELECT id FROM users WHERE username = ?", (username,)).fetchone()
            if existing:
                if username == "admin" and admin_password_env:
                    db.execute(
                        """
                        UPDATE users
                        SET password_hash = ?, is_admin = 1, disabled = 0,
                            can_generate_free = 1, can_generate_paid = 1,
                            paid_point_limit = ?
                        WHERE username = 'admin'
                        """,
                        (hash_password(admin_password), DEFAULT_ADMIN_POINT_LIMIT),
                    )
                continue
            db.execute(
                """
                INSERT INTO users(
                  username, password_hash, is_admin, can_generate_free,
                  can_generate_paid, daily_limit, paid_daily_limit,
                  paid_point_limit, paid_point_used, created_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?)
                """,
                (
                    username,
                    hash_password(password),
                    is_admin,
                    can_free,
                    can_paid,
                    daily,
                    paid_daily,
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
    if user["can_generate_free"]:
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
        "can_generate_free": bool(user["can_generate_free"]),
        "can_generate_paid": bool(user["can_generate_paid"]),
        "can_text_generate": bool(user["can_text_generate"]),
        "can_image_upscale": bool(user["can_image_upscale"]),
        "can_image_augment": bool(user["can_image_augment"]),
        "can_image_encode_vibe": bool(user["can_image_encode_vibe"]),
        "daily_limit": user["daily_limit"],
        "paid_daily_limit": user["paid_daily_limit"],
        "paid_point_limit": user["paid_point_limit"],
        "paid_point_used": user["paid_point_used"],
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
        if user["is_admin"]:
            return None
        if user["can_generate_paid"]:
            return None
        return user["daily_limit"] if user["daily_limit"] is not None else DEFAULT_FREE_DAILY_LIMIT
    if mode == "paid":
        if user["paid_point_limit"] is None:
            return DEFAULT_ADMIN_POINT_LIMIT if user["is_admin"] else DEFAULT_PAID_POINT_LIMIT
        return int(user["paid_point_limit"])
    return 0


def quota_bucket(db: sqlite3.Connection, user: sqlite3.Row, mode: str) -> dict[str, Any]:
    limit = quota_limit(user, mode)
    if mode == "paid":
        used = int(user["paid_point_used"])
        return {
            "date": None,
            "mode": mode,
            "kind": "points",
            "daily_limit": limit,
            "point_limit": limit,
            "used": used,
            "remaining": None if limit is None else limit - used,
            "unlimited": limit is None,
        }
    used = usage_for(db, int(user["id"]), mode)
    return {
        "date": today_key(),
        "mode": mode,
        "kind": "daily_count",
        "daily_limit": limit,
        "used": used,
        "remaining": None if limit is None else max(0, limit - used),
        "unlimited": limit is None,
    }


def quota_for_user(db: sqlite3.Connection, user: sqlite3.Row) -> dict[str, Any]:
    return {
        "free": quota_bucket(db, user, "free"),
        "paid": quota_bucket(db, user, "paid"),
    }


@app.get("/api/quota")
def quota(user: sqlite3.Row = Depends(require_user), db: sqlite3.Connection = Depends(get_db)):
    return quota_for_user(db, user)


@app.get("/api/queue")
async def queue_status(user: sqlite3.Row = Depends(require_user)):
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
    return {
        "queued": image_queued + text_queued,
        "active": image_active + text_active,
        "user_active": user_image_active or user_text_active,
        "user_queued": user_queued,
        "tasks_ahead": tasks_ahead,
        "text_concurrency": TEXT_GLOBAL_CONCURRENCY,
    }


@app.get("/api/admin/users")
def admin_users(
    _: sqlite3.Row = Depends(require_admin),
    db: sqlite3.Connection = Depends(get_db),
):
    rows = db.execute("SELECT * FROM users ORDER BY id").fetchall()
    return {"items": [user_admin_dict(row) for row in rows]}


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
              username, password_hash, is_admin, disabled, can_generate_free,
              can_generate_paid, can_text_generate, can_image_upscale,
              can_image_augment, can_image_encode_vibe, daily_limit,
              paid_daily_limit, paid_point_limit, paid_point_used, created_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                payload.username,
                hash_password(payload.password or secrets.token_urlsafe(32)),
                int(payload.is_admin),
                int(payload.disabled),
                int(payload.can_generate_free),
                int(payload.can_generate_paid),
                int(payload.can_text_generate),
                int(payload.can_image_upscale),
                int(payload.can_image_augment),
                int(payload.can_image_encode_vibe),
                payload.daily_limit,
                payload.paid_daily_limit,
                payload.paid_point_limit,
                payload.paid_point_used,
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
        "can_generate_free",
        "can_generate_paid",
        "can_text_generate",
        "can_image_upscale",
        "can_image_augment",
        "can_image_encode_vibe",
    }
    int_fields = {"daily_limit", "paid_daily_limit", "paid_point_limit", "paid_point_used"}
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
        "free_daily_limit": DEFAULT_FREE_DAILY_LIMIT,
        "paid_daily_limit": DEFAULT_PAID_DAILY_LIMIT,
        "paid_point_limit": DEFAULT_PAID_POINT_LIMIT,
        "admin_point_limit": DEFAULT_ADMIN_POINT_LIMIT,
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


def check_quota(db: sqlite3.Connection, user: sqlite3.Row, mode: str) -> None:
    bucket = quota_bucket(db, user, mode)
    if bucket["remaining"] is not None and bucket["remaining"] <= 0:
        if mode == "paid":
            raise HTTPException(status.HTTP_429_TOO_MANY_REQUESTS, "Paid points exhausted")
        raise HTTPException(status.HTTP_429_TOO_MANY_REQUESTS, "Daily quota exhausted")


def increment_quota(db: sqlite3.Connection, user_id: int, mode: str) -> None:
    if mode == "paid":
        charge_paid_points(db, user_id, 1)
        return
    db.execute(
        """
        INSERT INTO quota_usage(user_id, quota_date, mode, used)
        VALUES (?, ?, ?, 1)
        ON CONFLICT(user_id, quota_date, mode)
        DO UPDATE SET used = used + 1
        """,
        (user_id, today_key(), mode),
    )


def charge_paid_points(db: sqlite3.Connection, user_id: int, points: int) -> None:
    if points <= 0:
        return
    db.execute(
        "UPDATE users SET paid_point_used = paid_point_used + ? WHERE id = ?",
        (points, user_id),
    )


def sanitize_novelai_generate_body(
    body: bytes, user: sqlite3.Row
) -> tuple[bytes, dict[str, Any], str | None]:
    if not (user["can_generate_free"] or user["can_generate_paid"] or user["is_admin"]):
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
    if quota_mode == "free" and not user["can_generate_free"]:
        if user["can_generate_paid"]:
            quota_mode = "paid"
        else:
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Free image generation is not allowed")
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
            if not (user["can_generate_free"] or user["can_generate_paid"]):
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


async def enqueue_generate(
    *,
    user: sqlite3.Row,
    service: str,
    path: str,
    body: bytes,
    parsed: dict[str, Any],
    quota_mode: str | None,
    db: sqlite3.Connection,
) -> tuple[int, dict[str, str], bytes]:
    global queue_virtual_time
    assert queue_condition is not None
    user_id = int(user["id"])
    queue_class = mode_for_user(user)
    if quota_mode is not None:
        check_quota(db, user, quota_mode)
    async with queue_condition:
        if user_id in active_user_ids or any(job.user_id == user_id for job in pending_jobs):
            raise HTTPException(status.HTTP_429_TOO_MANY_REQUESTS, "User already has an active generation")
        weight = QUEUE_WEIGHTS[queue_class]
        base = max(queue_virtual_time, queue_last_finish[queue_class])
        virtual_finish = base + (1.0 / weight)
        queue_last_finish[queue_class] = virtual_finish
        task_id = secrets.token_urlsafe(18)
        params = parsed["parameters"]
        created = now_iso()
        billing_mode = quota_mode or queue_class
        db.execute(
            """
            INSERT INTO generation_tasks(
              id, user_id, mode, queue_class, queue_weight, virtual_finish,
              status, prompt, negative_prompt, width, height, steps, scale,
              sampler, seed, cost, request_json, queued_at, created_at
            )
            VALUES (?, ?, ?, ?, ?, ?, 'queued', ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?, ?)
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
                json.dumps(parsed, ensure_ascii=False),
                created,
                created,
            ),
        )
        db.commit()
        loop = asyncio.get_running_loop()
        future: asyncio.Future[tuple[int, dict[str, str], bytes]] = loop.create_future()
        pending_jobs.append(
            ProxyJob(
                virtual_finish=virtual_finish,
                negative_weight=-weight,
                created_at=created,
                user_id=user_id,
                username=user["username"],
                task_id=task_id,
                service=service,
                path=path,
                future=future,
                body=body,
                quota_mode=quota_mode,
            )
        )
        pending_jobs.sort(key=lambda job: job.sort_key)
        queue_condition.notify()
    return await future


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
                if status_code == 200:
                    image_path = await save_history_image(job.task_id, content)
                    if job.quota_mode == "paid":
                        anlas_after = await fetch_anlas_balance()
                        if anlas_after is not None and anlas_before is not None:
                            paid_points_charged = max(0, anlas_before - anlas_after)
                            charge_paid_points(db, job.user_id, paid_points_charged)
                    elif job.quota_mode == "free":
                        increment_quota(db, job.user_id, job.quota_mode)
                    db.execute(
                        """
                        UPDATE generation_tasks
                        SET status = 'success', image_path = ?, anlas_before = ?,
                            anlas_after = ?, paid_points_charged = ?, completed_at = ?
                        WHERE id = ?
                        """,
                        (
                            image_path,
                            anlas_before,
                            anlas_after,
                            paid_points_charged,
                            now_iso(),
                            job.task_id,
                        ),
                    )
                else:
                    db.execute(
                        """
                        UPDATE generation_tasks
                        SET status = 'failed', error_message = ?, anlas_before = ?,
                            anlas_after = ?, paid_points_charged = ?, completed_at = ?
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
                db.commit()
            if not job.future.done():
                job.future.set_result((status_code, headers, content))
        except HTTPException as exc:
            with db_connect() as db:
                db.execute(
                    """
                    UPDATE generation_tasks
                    SET status = 'failed', error_message = ?, completed_at = ?
                    WHERE id = ?
                    """,
                    (str(exc.detail), now_iso(), job.task_id),
                )
                db.commit()
            if not job.future.done():
                job.future.set_exception(exc)
        except Exception as exc:
            with db_connect() as db:
                db.execute(
                    """
                    UPDATE generation_tasks
                    SET status = 'failed', error_message = ?, completed_at = ?
                    WHERE id = ?
                    """,
                    ("Generation failed", now_iso(), job.task_id),
                )
                db.commit()
            if not job.future.done():
                job.future.set_exception(exc)
        finally:
            async with queue_condition:
                active_user_ids.discard(job.user_id)
                queue_condition.notify()


def mode_for_user_id(db: sqlite3.Connection, user_id: int) -> str:
    user = db.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
    if not user:
        return "free"
    return mode_for_user(user)


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
            result = await enqueue_generate(
                user=user,
                service=service,
                path=path,
                body=sanitized,
                parsed=parsed,
                quota_mode=quota_mode,
                db=db,
            )
            complete_audit_log(db, audit_id, status_code=result[0])
            return Response(content=result[2], status_code=result[0], headers=result[1])
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
        complete_audit_log(
            db,
            audit_id,
            status_code=exc.status_code,
            error_message=str(exc.detail),
        )
        raise
    except Exception:
        complete_audit_log(
            db, audit_id, status_code=500, error_message="Proxy request failed"
        )
        raise


@app.get("/api/history")
def history(
    limit: int = 50,
    user_id: int | None = None,
    user: sqlite3.Row = Depends(require_user),
    db: sqlite3.Connection = Depends(get_db),
):
    where = ["h.task_id IS NULL"]
    params: list[Any] = [user["id"]]
    if user["is_admin"]:
        if user_id is not None:
            where.append("t.user_id = ?")
            params.append(user_id)
    else:
        where.append("t.user_id = ?")
        params.append(user["id"])
    where_sql = f"WHERE {' AND '.join(where)}" if where else ""
    params.append(max(1, min(limit, 100)))
    rows = db.execute(
        f"""
        SELECT t.*, u.username
        FROM generation_tasks t
        JOIN users u ON u.id = t.user_id
        LEFT JOIN history_hidden h ON h.task_id = t.id AND h.user_id = ?
        {where_sql}
        ORDER BY t.created_at DESC
        LIMIT ?
        """,
        params,
    ).fetchall()
    return {"items": [dict(row) for row in rows]}


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
            return FileResponse(target)
    index = WEB_BUILD_DIR / "index.html"
    if index.exists():
        return FileResponse(index)
    fallback = STATIC_DIR / "index.html"
    if fallback.exists():
        return FileResponse(fallback)
    return Response("NAIWeaver web build not found", status_code=404)
