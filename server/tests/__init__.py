"""Isolate every test run from the gateway's real data directories.

``app.main`` resolves its data, database, image, thumbnail and audit paths at
import time, so they are pointed at a fresh temporary directory here, before
any test imports ``app``. ``python -m unittest discover -s tests`` imports the
test modules as top-level modules and never runs this file on its own, so
every test module starts with ``import tests``.
"""

from __future__ import annotations

import atexit
import os
from pathlib import Path
import shutil
import tempfile


TEMP_ROOT = Path(tempfile.mkdtemp(prefix="naiweaver-tests-"))
atexit.register(shutil.rmtree, TEMP_ROOT, ignore_errors=True)

_DATA_DIR = TEMP_ROOT / "data"
os.environ["NAIWEAVER_DATA_DIR"] = str(_DATA_DIR)
os.environ["NAIWEAVER_DB_PATH"] = str(_DATA_DIR / "naiweaver.sqlite3")
os.environ["NAIWEAVER_IMAGE_DIR"] = str(_DATA_DIR / "images")
os.environ["NAIWEAVER_THUMBNAIL_DIR"] = str(_DATA_DIR / "thumbnails")
os.environ["NAIWEAVER_AUDIT_DIR"] = str(_DATA_DIR / "audit")

# Never reach NovelAI or a production identity provider from a unit test, and
# keep pricing and limits at their documented defaults.
for _name in (
    "NAIWEAVER_ENV",
    "NAIWEAVER_AUTH_ISSUER",
    "NAIWEAVER_FAKE_NOVELAI",
    "NOVELAI_TOKEN",
    "NOVELAI_TOKEN_FILE",
    "NAI_TOKEN",
    "NAIWEAVER_FREE_MAX_STEPS",
    "NAIWEAVER_PAID_MAX_STEPS",
    "NAIWEAVER_ADMIN_MAX_STEPS",
    "NAIWEAVER_MAX_DIMENSION",
    "NAIWEAVER_MAX_REQUEST_BODY_BYTES",
    "NAIWEAVER_TOOL_CAP_UPSCALE",
    "NAIWEAVER_TOOL_CAP_AUGMENT",
    "NAIWEAVER_TOOL_CAP_ENCODE_VIBE",
    "NAIWEAVER_FREE_ALLOWANCE_COOLDOWN_SECONDS",
):
    os.environ.pop(_name, None)
