from __future__ import annotations

from datetime import datetime, timedelta, timezone
import json
import secrets
import sqlite3

from fastapi import APIRouter, Depends, status
from pydantic import BaseModel, ConfigDict, Field

from .auth import require_user
from .db import get_db, now_iso
from .errors import api_error

router = APIRouter()


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


@router.post("/api/feedback", status_code=status.HTTP_201_CREATED)
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
