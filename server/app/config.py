from __future__ import annotations

import logging
import os
from pathlib import Path

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

# Audit body files older than this are deleted at startup and daily; the audit
# rows stay and are marked expired. 0 keeps bodies forever.
AUDIT_RETENTION_DAYS = int(os.environ.get("NAIWEAVER_AUDIT_RETENTION_DAYS", "30"))
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


BALANCE_RECHECK_SECONDS = float(os.environ.get("NAIWEAVER_BALANCE_RECHECK_SECONDS", "1"))
