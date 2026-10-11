"""Pricing rules, the single quote function and point accounting.

This module owns contract §2 (rules), §3 (``classify_and_quote``) and the
reservation/settlement arithmetic of §5 and §6. ``classify_and_quote`` is the
only place that decides whether an image request is free or paid and what it
costs; every submission path calls it.
"""

from __future__ import annotations

from contextlib import contextmanager
import copy
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
import logging
import math
import os
import sqlite3
import time
from typing import Any, Iterator, Mapping

from .errors import api_error, invalid_parameters


logger = logging.getLogger("uvicorn.error.naiweaver")

MAX_STEPS_FREE = int(os.environ.get("NAIWEAVER_FREE_MAX_STEPS", "28"))
MAX_STEPS_PAID = int(os.environ.get("NAIWEAVER_PAID_MAX_STEPS", "50"))
MAX_STEPS_ADMIN = int(os.environ.get("NAIWEAVER_ADMIN_MAX_STEPS", "50"))
MAX_DIMENSION = int(os.environ.get("NAIWEAVER_MAX_DIMENSION", "2048"))
FREE_IMAGE_SIZES = ((832, 1216), (1216, 832), (1024, 1024))
ALLOWED_SAMPLERS = (
    "k_dpmpp_2m",
    "k_dpmpp_2s_ancestral",
    "k_dpmpp_sde",
    "k_euler",
    "k_euler_ancestral",
)
BATCH_LIMIT_ADMIN = 10
BATCH_LIMIT_PAID = 8
BATCH_LIMIT_FREE = 4
MAX_SEED = 0xFFFFFFFF

PRICING = {
    "area_coefficient": 2.951823174884865e-6,
    "step_area_coefficient": 5.753298233447344e-7,
    "smea_multiplier": 1.2,
    "smea_dyn_multiplier": 1.4,
    "min_points": 2,
    "director_reference_points": 5,
    "free_vibe_count": 4,
    "extra_vibe_points": 2,
}
# NovelAI publishes no price for upscale/augment; these caps are the quote.
TOOL_CAPS = {
    "upscale": int(os.environ.get("NAIWEAVER_TOOL_CAP_UPSCALE", "10")),
    "augment": int(os.environ.get("NAIWEAVER_TOOL_CAP_AUGMENT", "80")),
    "encode_vibe": int(os.environ.get("NAIWEAVER_TOOL_CAP_ENCODE_VIBE", "2")),
}
FREE_ALLOWANCE_COOLDOWN_SECONDS = int(
    os.environ.get("NAIWEAVER_FREE_ALLOWANCE_COOLDOWN_SECONDS", "1800")
)

NAI_V5_CURATED_MODEL = "nai-diffusion-5-curated"
NAI_V5_FULL_MODEL = "nai-diffusion-5-full"
NAI_V5_FULL_INPAINTING_MODEL = "nai-diffusion-5-full-inpainting"
NAI_V4_5_CURATED_INPAINTING_MODEL = "nai-diffusion-4-5-curated-inpainting"
NAI_V4_5_FULL_INPAINTING_MODEL = "nai-diffusion-4-5-full-inpainting"
NAI_V4_5_CURATED_MODEL = "nai-diffusion-4-5-curated"
NAI_V4_5_FULL_MODEL = "nai-diffusion-4-5-full"

IMAGE_ACTIONS = (None, "generate", "img2img", "infill")
IMAGE_INPUT_PARAMETERS = frozenset(
    {
        "image",
        "mask",
        "strength",
        "noise",
        "extra_noise_seed",
        "add_original_image",
        "mask_blur",
    }
)
DIRECTOR_REFERENCE_PARAMETERS = frozenset(
    {
        "director_reference_images",
        "director_reference_descriptions",
        "director_reference_strength_values",
        "director_reference_secondary_strength_values",
        "director_reference_information_extracted",
    }
)
VIBE_PARAMETERS = frozenset(
    {
        "reference_image_multiple",
        "reference_strength_multiple",
        "reference_information_extracted_multiple",
    }
)
# Every key the web client sends (test/fixtures/image_request_keys.json lists
# them with their Dart source); anything else is rejected rather than
# forwarded to NovelAI unpriced. ``autoSmea`` is not sent by the client but
# turns SMEA on upstream, so it is accepted and priced as SMEA.
REQUEST_KEYS = frozenset({"input", "model", "action", "parameters"})
GENERATION_PARAMETERS = frozenset(
    {
        "params_version",
        "width",
        "height",
        "scale",
        "sampler",
        "steps",
        "seed",
        "n_samples",
        "noise_schedule",
        "sm",
        "sm_dyn",
        "autoSmea",
        "dynamic_thresholding",
        "uc",
        "characterPrompts",
        "v4_prompt",
        "v4_negative_prompt",
    }
)
ALLOWED_PARAMETERS = (
    GENERATION_PARAMETERS
    | IMAGE_INPUT_PARAMETERS
    | DIRECTOR_REFERENCE_PARAMETERS
    | VIBE_PARAMETERS
)
# Canonical order of ``Quote.reasons``; the client relies on it in golden tests.
REASON_ORDER = (
    "size_not_free",
    "steps_over_free_limit",
    "smea",
    "image_input",
    "director_refs",
    "vibes",
    "allowance_exhausted",
    "paid_tool",
)

ANOMALY_FREE_ALLOWANCE_EXHAUSTED = "free_allowance_exhausted"
ANOMALY_MEASURED_ABOVE_QUOTE = "measured_above_quote"
ANOMALY_UNMEASURED = "unmeasured"
ANOMALY_DECODE_FAILED = "decode_failed"

# Settlement and release retry a locked database a few times so a reservation
# is not left behind by a momentary writer.
SETTLEMENT_ATTEMPTS = 5
SETTLEMENT_BACKOFF_SECONDS = 0.1


@dataclass(frozen=True)
class Quote:
    mode: str
    per_image: int
    images: int
    base: int
    director_refs: int
    extra_vibes: int
    reasons: tuple[str, ...] = ()

    @property
    def points(self) -> int:
        return self.per_image * self.images

    @property
    def point_kind(self) -> str:
        return point_kind_for_mode(self.mode)

    def to_dict(self) -> dict[str, Any]:
        return {
            "mode": self.mode,
            "points": self.points,
            "per_image": self.per_image,
            "images": self.images,
            "breakdown": {
                "base": self.base,
                "director_refs": self.director_refs,
                "extra_vibes": self.extra_vibes,
            },
            "reasons": list(self.reasons),
        }

    def matches(self, expected: Any) -> bool:
        if not isinstance(expected, dict):
            return False
        points = expected.get("points")
        return (
            expected.get("mode") == self.mode
            and is_strict_int(points)
            and points == self.points
        )


def is_strict_int(value: Any) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def point_kind_for_mode(mode: str | None) -> str:
    return "red" if mode == "paid" else "green"


def green_point_discount_for(user: Mapping[str, Any]) -> int:
    if user["is_admin"]:
        return 100
    return min(100, max(0, int(user["green_point_discount"])))


def max_steps_for(*, is_admin: bool, can_generate_paid: bool) -> int:
    if is_admin:
        return MAX_STEPS_ADMIN
    return MAX_STEPS_PAID if can_generate_paid else MAX_STEPS_FREE


def batch_limit_for(*, is_admin: bool, can_generate_paid: bool) -> int:
    if is_admin:
        return BATCH_LIMIT_ADMIN
    return BATCH_LIMIT_PAID if can_generate_paid else BATCH_LIMIT_FREE


def build_image_rules(
    *,
    is_admin: bool,
    can_generate_paid: bool,
    green_point_discount: int,
    allowance_exhausted: bool,
) -> dict[str, Any]:
    """Return ``rules.image`` (contract §2), resolved for one user."""
    return {
        "free_sizes": [list(size) for size in FREE_IMAGE_SIZES],
        "free_max_steps": MAX_STEPS_FREE,
        "max_steps": max_steps_for(
            is_admin=is_admin, can_generate_paid=can_generate_paid
        ),
        "max_dimension": MAX_DIMENSION,
        "allowed_samplers": list(ALLOWED_SAMPLERS),
        "batch_limit": batch_limit_for(
            is_admin=is_admin, can_generate_paid=can_generate_paid
        ),
        "green_point_discount": green_point_discount,
        "free_allowance_exhausted": allowance_exhausted,
        "pricing": dict(PRICING),
        "tool_caps": dict(TOOL_CAPS),
    }


def nonempty_parameter(params: Mapping[str, Any], key: str) -> bool:
    return params.get(key) is not None and bool(params[key])


def _strict_int(params: Mapping[str, Any], key: str) -> int:
    value = params.get(key)
    if not is_strict_int(value):
        raise invalid_parameters(key, f"{key} must be a JSON integer")
    return value


def _optional_flag(params: Mapping[str, Any], key: str) -> bool:
    value = params.get(key)
    if value is None:
        return False
    if not isinstance(value, bool):
        raise invalid_parameters(key, f"{key} must be a boolean")
    return value


def _reference_count(params: Mapping[str, Any], key: str) -> int:
    value = params.get(key)
    if value is None:
        return 0
    if not isinstance(value, list):
        raise invalid_parameters(key, f"{key} must be a list")
    return len(value)


def _normalize_model(data: dict[str, Any]) -> None:
    # Keep every gateway client on the models novelai.net uses, whatever model
    # ID an older cached build submits. V5 has no Vibe Transfer, Precise
    # Reference or Curated inpainting yet, so a request using any of them runs
    # on V4.5 (vibes are encoded with the V4.5 models too); everything else
    # runs on V5.
    params = data["parameters"]
    use_curated = "curated" in str(data.get("model", "")).lower()
    needs_v4_5 = any(
        nonempty_parameter(params, key)
        for key in VIBE_PARAMETERS | DIRECTOR_REFERENCE_PARAMETERS
    )
    if data.get("action") == "infill":
        if use_curated:
            model = NAI_V4_5_CURATED_INPAINTING_MODEL
        elif needs_v4_5:
            model = NAI_V4_5_FULL_INPAINTING_MODEL
        else:
            model = NAI_V5_FULL_INPAINTING_MODEL
    elif needs_v4_5:
        model = NAI_V4_5_CURATED_MODEL if use_curated else NAI_V4_5_FULL_MODEL
    else:
        model = NAI_V5_CURATED_MODEL if use_curated else NAI_V5_FULL_MODEL
    data["model"] = model


def classify_and_quote(
    request: Any, rules: Mapping[str, Any], *, images: int = 1
) -> tuple[dict[str, Any], Quote]:
    """Validate, normalize and price one image request (contract §3).

    Returns the normalized request that must be forwarded to NovelAI, so the
    values that were priced are exactly the values that are executed.
    """
    if not isinstance(request, dict):
        raise invalid_parameters("request", "request must be a JSON object")
    if not is_strict_int(images) or images < 1:
        raise invalid_parameters("seeds", "At least one image is required")
    for key in request:
        if key not in REQUEST_KEYS:
            raise invalid_parameters(key, f"{key} is not a supported request field")
    data = copy.deepcopy(request)
    action = data.get("action")
    if action not in IMAGE_ACTIONS:
        raise invalid_parameters("action", "Unsupported image action")
    params = data.get("parameters")
    if not isinstance(params, dict):
        raise invalid_parameters("parameters", "parameters must be a JSON object")
    for key in params:
        if key not in ALLOWED_PARAMETERS:
            raise invalid_parameters(
                f"parameters.{key}", f"{key} is not a supported parameter"
            )

    width = _strict_int(params, "width")
    height = _strict_int(params, "height")
    steps = _strict_int(params, "steps")
    max_dimension = int(rules["max_dimension"])
    for key, value in (("width", width), ("height", height)):
        if value < 64 or value > max_dimension or value % 64:
            raise invalid_parameters(
                key,
                f"{key} must be a multiple of 64 between 64 and {max_dimension}",
                limit=max_dimension,
            )
    max_steps = int(rules["max_steps"])
    if steps < 1 or steps > max_steps:
        raise invalid_parameters(
            "steps", f"steps must be between 1 and {max_steps}", limit=max_steps
        )
    sampler = params.get("sampler")
    if not isinstance(sampler, str) or sampler not in rules["allowed_samplers"]:
        raise invalid_parameters("sampler", "Sampler is not allowed")
    scale = params.get("scale")
    if scale is not None and (
        isinstance(scale, bool)
        or not isinstance(scale, (int, float))
        or not math.isfinite(scale)
    ):
        raise invalid_parameters("scale", "scale must be a number")
    smea = _optional_flag(params, "sm")
    smea_dyn = _optional_flag(params, "sm_dyn")
    # Unsure whether NovelAI bills autoSmea as SMEA: price it as SMEA.
    auto_smea = _optional_flag(params, "autoSmea")
    director_count = _reference_count(params, "director_reference_images")
    vibe_count = _reference_count(params, "reference_image_multiple")

    # Write the validated values back: NovelAI receives what was priced.
    params["width"] = width
    params["height"] = height
    params["steps"] = steps
    if "sm" in params:
        params["sm"] = smea
    if "sm_dyn" in params:
        params["sm_dyn"] = smea_dyn
    if "autoSmea" in params:
        params["autoSmea"] = auto_smea
    params["params_version"] = 4
    params["n_samples"] = 1
    data["parameters"] = params
    _normalize_model(data)

    reasons: set[str] = set()
    if action not in (None, "generate"):
        reasons.add("image_input")
    free_sizes = {tuple(size) for size in rules["free_sizes"]}
    if (width, height) not in free_sizes:
        reasons.add("size_not_free")
    if steps > int(rules["free_max_steps"]):
        reasons.add("steps_over_free_limit")
    if smea or smea_dyn or auto_smea:
        reasons.add("smea")
    if any(nonempty_parameter(params, key) for key in IMAGE_INPUT_PARAMETERS):
        reasons.add("image_input")
    if any(nonempty_parameter(params, key) for key in DIRECTOR_REFERENCE_PARAMETERS):
        reasons.add("director_refs")
    if any(nonempty_parameter(params, key) for key in VIBE_PARAMETERS):
        reasons.add("vibes")
    if not reasons and rules["free_allowance_exhausted"]:
        reasons.add("allowance_exhausted")

    pricing = rules["pricing"]
    # Evaluate left to right in IEEE-754 doubles so the client's estimate
    # rounds identically (contract §3).
    raw = (
        pricing["area_coefficient"] * width * height
        + pricing["step_area_coefficient"] * width * height * steps
    )
    multiplier = (
        pricing["smea_dyn_multiplier"]
        if smea_dyn
        else pricing["smea_multiplier"]
        if smea or auto_smea
        else 1.0
    )
    base = max(math.ceil(math.ceil(raw) * multiplier), int(pricing["min_points"]))
    director_points = director_count * int(pricing["director_reference_points"])
    vibe_points = max(0, vibe_count - int(pricing["free_vibe_count"])) * int(
        pricing["extra_vibe_points"]
    )
    points = base + director_points + vibe_points
    if reasons:
        mode = "paid"
        per_image = points
    else:
        mode = "free"
        discount = min(100, max(0, int(rules["green_point_discount"])))
        per_image = -(-points * (100 - discount) // 100)
    return data, Quote(
        mode=mode,
        per_image=per_image,
        images=images,
        base=base,
        director_refs=director_points,
        extra_vibes=vibe_points,
        reasons=tuple(reason for reason in REASON_ORDER if reason in reasons),
    )


def tool_quote(tool: str) -> Quote:
    cap = TOOL_CAPS[tool]
    return Quote(
        mode="paid",
        per_image=cap,
        images=1,
        base=cap,
        director_refs=0,
        extra_vibes=0,
        reasons=("paid_tool",),
    )


def settle_amount(reserved: int, measured_delta: int | None) -> tuple[int, bool]:
    """Return ``(charge, above_quote)`` for red-point work (contract §6).

    The charge is the measured Anlas delta capped by the reservation. The
    reservation is charged when the delta is unavailable or negative; a delta
    above the reservation is reported so the caller records an anomaly.
    """
    if measured_delta is None or measured_delta < 0:
        return reserved, False
    if measured_delta > reserved:
        return reserved, True
    return measured_delta, False


_POINT_COLUMNS = {
    "green": ("green_points_reserved", "green_point_used"),
    "red": ("red_points_reserved", "red_points_used"),
}


def remaining_points(user: Mapping[str, Any], kind: str) -> int | None:
    """Points still available to reserve; ``None`` means unlimited."""
    if kind == "red":
        return (
            int(user["red_points"])
            - int(user["red_points_used"])
            - int(user["red_points_reserved"])
        )
    if green_point_discount_for(user) >= 100:
        return None
    return (
        int(user["green_point_limit"])
        - int(user["green_point_used"])
        - int(user["green_points_reserved"])
    )


@contextmanager
def immediate_transaction(
    db: sqlite3.Connection, *, attempts: int = 1
) -> Iterator[None]:
    """Hold SQLite's write lock from the balance check to the commit.

    A locked database is retried ``attempts`` times with exponential backoff
    before the error is raised.
    """
    if db.in_transaction:
        db.commit()
    for attempt in range(attempts):
        try:
            db.execute("BEGIN IMMEDIATE")
            break
        except sqlite3.OperationalError:
            if attempt + 1 == attempts:
                logger.error("write lock unavailable after %d attempts", attempts)
                raise
            time.sleep(SETTLEMENT_BACKOFF_SECONDS * 2**attempt)
    try:
        yield
    except BaseException:
        db.rollback()
        raise
    db.commit()


def settlement_transaction(db: sqlite3.Connection):
    """``immediate_transaction`` for settling or releasing a reservation."""
    return immediate_transaction(db, attempts=SETTLEMENT_ATTEMPTS)


def reserve_points(db: sqlite3.Connection, user_id: int, kind: str, amount: int) -> None:
    """Reserve ``amount`` points; call inside ``immediate_transaction``."""
    if amount <= 0:
        return
    user = db.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
    if user is None:
        raise api_error(404, "not_found", "User not found")
    remaining = remaining_points(user, kind)
    if remaining is not None and remaining < amount:
        raise api_error(
            409,
            "points_insufficient",
            "Available points are insufficient",
            point_kind=kind,
            required=amount,
            remaining=max(0, remaining),
        )
    reserved_column, _ = _POINT_COLUMNS[kind]
    db.execute(
        f"UPDATE users SET {reserved_column} = {reserved_column} + ? WHERE id = ?",
        (amount, user_id),
    )


def settle_points(
    db: sqlite3.Connection, user_id: int, kind: str, reserved: int, charged: int
) -> None:
    reserved_column, used_column = _POINT_COLUMNS[kind]
    db.execute(
        f"""
        UPDATE users
        SET {reserved_column} = MAX(0, {reserved_column} - ?),
            {used_column} = {used_column} + ?
        WHERE id = ?
        """,
        (max(0, reserved), max(0, charged), user_id),
    )


def release_points(db: sqlite3.Connection, user_id: int, kind: str, reserved: int) -> None:
    if reserved <= 0:
        return
    reserved_column, _ = _POINT_COLUMNS[kind]
    db.execute(
        f"UPDATE users SET {reserved_column} = MAX(0, {reserved_column} - ?) WHERE id = ?",
        (reserved, user_id),
    )


def reserve_tool_points(
    db: sqlite3.Connection, user_id: int, amount: int, tool: str
) -> int:
    """Reserve red points for a tool call and return the durable reservation id.

    The row lets the counters be rebuilt (``recompute_reserved_points``) while the call is in
    flight. Call inside ``immediate_transaction``.
    """
    reserve_points(db, user_id, "red", amount)
    cursor = db.execute(
        "INSERT INTO tool_reservations(user_id, mode, points, tool, created_at) "
        "VALUES (?, 'paid', ?, ?, ?)",
        (user_id, amount, tool, datetime.now(timezone.utc).isoformat()),
    )
    return int(cursor.lastrowid)


def _take_tool_reservation(db: sqlite3.Connection, reservation_id: int) -> sqlite3.Row | None:
    row = db.execute(
        "SELECT user_id, points FROM tool_reservations WHERE id = ?", (reservation_id,)
    ).fetchone()
    if row is not None:
        db.execute("DELETE FROM tool_reservations WHERE id = ?", (reservation_id,))
    return row


def settle_tool_points(db: sqlite3.Connection, reservation_id: int, charged: int) -> None:
    """Charge a tool reservation and drop it; a reservation already reclaimed
    (and so already out of the counters) is left alone."""
    row = _take_tool_reservation(db, reservation_id)
    if row is not None:
        settle_points(db, int(row["user_id"]), "red", int(row["points"]), charged)


def release_tool_points(db: sqlite3.Connection, reservation_id: int) -> None:
    row = _take_tool_reservation(db, reservation_id)
    if row is not None:
        release_points(db, int(row["user_id"]), "red", int(row["points"]))


def record_billing_anomaly(
    db: sqlite3.Connection,
    *,
    kind: str,
    user_id: int,
    mode: str,
    quoted: int,
    measured: int | None,
    note: str,
    task_id: str | None = None,
    tool: str | None = None,
    created_at: datetime | None = None,
) -> None:
    db.execute(
        """
        INSERT INTO billing_anomalies(
          kind, user_id, task_id, tool, mode, quoted, measured, note, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            kind,
            user_id,
            task_id,
            tool,
            mode,
            quoted,
            measured,
            note,
            (created_at or datetime.now(timezone.utc)).isoformat(),
        ),
    )


def free_allowance_exhausted_until(
    db: sqlite3.Connection, now: datetime | None = None
) -> datetime | None:
    """Return when the free-allowance cooldown ends, or ``None`` if inactive."""
    row = db.execute(
        "SELECT MAX(created_at) FROM billing_anomalies WHERE kind = ?",
        (ANOMALY_FREE_ALLOWANCE_EXHAUSTED,),
    ).fetchone()
    if not row or not row[0]:
        return None
    until = datetime.fromisoformat(row[0]) + timedelta(
        seconds=FREE_ALLOWANCE_COOLDOWN_SECONDS
    )
    return until if until > (now or datetime.now(timezone.utc)) else None
