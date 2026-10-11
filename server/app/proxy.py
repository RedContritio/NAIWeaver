from __future__ import annotations

import asyncio
from dataclasses import dataclass
import hashlib
from io import BytesIO
import json
import os
from pathlib import Path
import re
import secrets
import sqlite3
from typing import Any
from zipfile import ZipFile

from fastapi import APIRouter, Depends, HTTPException, Request, Response, status
from fastapi.responses import StreamingResponse
import httpx

from . import config, state
from .audit import complete_audit_log, create_audit_log
from .auth import require_user
from .billing import (
    ANOMALY_MEASURED_ABOVE_QUOTE,
    ANOMALY_UNMEASURED,
    TOOL_CAPS,
    immediate_transaction,
    record_billing_anomaly,
    release_tool_points,
    reserve_tool_points,
    settle_amount,
    settle_tool_points,
    settlement_transaction,
    tool_quote,
)
from .db import db_session, get_db, now_iso
from .errors import api_error, invalid_parameters, permission_denied, upstream_error
from .idempotency import CachedResponse
from .state import TextQueueTicket
from .storage import fake_png
from .upstream_lane import RED_PRIORITY
from .users import image_tool_allowed, mode_for_user, tool_permission_name

router = APIRouter()


def novelai_token() -> str:
    token_file = os.environ.get("NOVELAI_TOKEN_FILE")
    if token_file:
        path = Path(token_file).expanduser()
        if path.exists():
            return path.read_text(encoding="utf-8").strip()
    return os.environ.get("NOVELAI_TOKEN", os.environ.get("NAI_TOKEN", "")).strip()


def require_novelai_proxy_permission(
    service: str, path: str, method: str, user: sqlite3.Row
) -> None:
    endpoint_denied = permission_denied(
        "novelai.proxy", "NovelAI endpoint is not allowed"
    )
    if service == "text":
        if method != "POST" or path not in config.ALLOWED_TEXT_PROXY_PATHS:
            raise endpoint_denied
        if not (user["can_text_generate"] or user["is_admin"]):
            raise permission_denied("text.generate", "Text generation is not allowed")
        return
    if service == "image":
        if path == "ai/generate-image":
            raise invalid_parameters(
                "path", "Submit image generation through /api/generation-tasks"
            )
        tool = config.PAID_TOOL_PATHS.get(path)
        if method != "POST" or tool is None:
            raise endpoint_denied
        if not image_tool_allowed(user, tool):
            raise permission_denied(
                tool_permission_name(tool), "This image tool is not allowed"
            )
        return
    if service == "api":
        if method != "GET" or path not in config.ALLOWED_API_PROXY_PATHS:
            raise endpoint_denied
        if path == "user/subscription" and not user["is_admin"]:
            raise permission_denied("admin", "NovelAI subscription is admin-only")
        return
    raise endpoint_denied


def response_headers(headers: httpx.Headers) -> dict[str, str]:
    return {
        key: value
        for key, value in headers.items()
        if key.lower() not in config.HOP_BY_HOP_HEADERS
    }


def novelai_url(service: str, path: str) -> str:
    if path == "user/subscription" and service in {"api", "image", "text"}:
        return f"{config.TARGET_BASES['image']}/{path}"
    return f"{config.TARGET_BASES[service]}/{path}"


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
    if service not in config.TARGET_BASES:
        raise api_error(status.HTTP_404_NOT_FOUND, "not_found", "Unknown NovelAI service")
    token = novelai_token()
    if not token and not config.FAKE_NOVELAI:
        raise api_error(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            "service_unavailable",
            "NovelAI token is not configured",
        )
    if config.FAKE_NOVELAI:
        return fake_response(service, path, method)
    assert state.http_client is not None
    url = novelai_url(service, path)
    headers = {"Authorization": f"Bearer {token}"}
    if method.upper() == "POST":
        headers["Content-Type"] = "application/json"
    if stream:
        headers["Accept"] = "text/event-stream, application/json"
    try:
        if stream:
            req = state.http_client.build_request(method, url, content=body, headers=headers)
            upstream = await state.http_client.send(req, stream=True)
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
        upstream = await state.http_client.request(method, url, content=body, headers=headers)
    except httpx.HTTPError as exc:
        config.logger.warning(
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
    config.logger.warning(
        "novelai_upstream_error service=%s path=%s status_code=%s response_preview=%s",
        service,
        path,
        status_code,
        safe_upstream_error_preview(content, request_body),
    )
    raise upstream_error(status_code, f"NovelAI returned HTTP {status_code}")


async def acquire_text_slot(user: sqlite3.Row) -> TextQueueTicket:
    assert state.text_queue_condition is not None
    user_id = int(user["id"])
    queue_class = mode_for_user(user)
    weight = config.QUEUE_WEIGHTS[queue_class]
    async with state.text_queue_condition:
        if user_id in state.active_text_user_ids or any(
            job.user_id == user_id for job in state.pending_text_jobs
        ):
            raise api_error(
                status.HTTP_429_TOO_MANY_REQUESTS,
                "queue_full",
                "User already has an active text generation",
                limit=1,
            )
        base = max(state.text_queue_virtual_time, state.text_queue_last_finish[queue_class])
        virtual_finish = base + (1.0 / weight)
        state.text_queue_last_finish[queue_class] = virtual_finish
        ticket = TextQueueTicket(
            virtual_finish=virtual_finish,
            negative_weight=-weight,
            created_at=now_iso(),
            user_id=user_id,
            username=user["username"],
            ticket_id=secrets.token_urlsafe(12),
        )
        state.pending_text_jobs.append(ticket)
        state.pending_text_jobs.sort(key=lambda job: job.sort_key)
        state.text_queue_condition.notify_all()
        try:
            while True:
                is_next = bool(state.pending_text_jobs) and state.pending_text_jobs[0] == ticket
                has_capacity = state.active_text_count < config.TEXT_GLOBAL_CONCURRENCY
                if is_next and has_capacity:
                    state.pending_text_jobs.pop(0)
                    state.active_text_user_ids.add(user_id)
                    state.active_text_count += 1
                    state.text_queue_virtual_time = max(
                        state.text_queue_virtual_time, ticket.virtual_finish
                    )
                    state.text_queue_condition.notify_all()
                    return ticket
                await state.text_queue_condition.wait()
        except BaseException:
            if ticket in state.pending_text_jobs:
                state.pending_text_jobs.remove(ticket)
                state.text_queue_condition.notify_all()
            raise


async def release_text_slot(ticket: TextQueueTicket) -> None:
    assert state.text_queue_condition is not None
    async with state.text_queue_condition:
        if ticket.user_id in state.active_text_user_ids:
            state.active_text_user_ids.discard(ticket.user_id)
            state.active_text_count = max(0, state.active_text_count - 1)
            state.text_queue_condition.notify_all()


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
    # Anything that ends the request before a stream takes over the slot
    # (an error, or cancellation) frees it here.
    handed_over = False
    try:
        result = await forward_to_novelai(
            service, path, method=method, body=body, stream=stream
        )
        if isinstance(result, StreamingResponse):
            handed_over = True
    except Exception:
        with db_session() as db:
            complete_audit_log(
                db, audit_id, status_code=500, error_message="Text proxy failed"
            )
        raise
    finally:
        if not handed_over:
            await release_text_slot(ticket)
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


async def call_image_upstream(
    path: str, body: bytes, *, paid: bool = False
) -> UpstreamImageCall:
    """One NovelAI image call and its measured Anlas cost.

    The caller must hold ``upstream_lane``: NovelAI rejects a second
    concurrent image call on the account, and the balance delta is only
    attributable while nothing else runs.
    """
    assert state.upstream_lane.held, "image calls must hold the upstream lane"
    anlas_before = await fetch_anlas_balance()
    result = await forward_to_novelai("image", path, method="POST", body=body)
    assert not isinstance(result, StreamingResponse)
    status_code, headers, content = result
    anlas_after = await fetch_anlas_balance() if 200 <= status_code < 300 else None
    if paid and anlas_after is not None and anlas_after == anlas_before:
        # Paid work that cost nothing is more likely a stale balance than a
        # free call; read it once more before believing it.
        await asyncio.sleep(config.BALANCE_RECHECK_SECONDS)
        anlas_after = await fetch_anlas_balance()
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
        reservation_id = reserve_tool_points(db, user_id, cap, tool)
    settled = False
    try:
        async with state.upstream_lane.hold(RED_PRIORITY):
            call = await call_image_upstream(path, body, paid=True)
        raise_for_upstream_status("image", path, call.status_code, call.content)
        delta = call.measured_delta
        # A tool may really be free, so an unchanged balance is charged as
        # measured (0) but reported.
        charge, above_quote = settle_amount(cap, delta)
        with settlement_transaction(db):
            settle_tool_points(db, reservation_id, charge)
            if above_quote or delta == 0:
                record_billing_anomaly(
                    db,
                    kind=ANOMALY_MEASURED_ABOVE_QUOTE if above_quote else ANOMALY_UNMEASURED,
                    user_id=user_id,
                    mode="paid",
                    quoted=cap,
                    measured=delta,
                    note=(
                        "Measured Anlas delta exceeded the tool cap; charged the cap"
                        if above_quote
                        else "Tool call left the Anlas balance unchanged; charged 0"
                    ),
                    tool=tool,
                )
        settled = True
    finally:
        if not settled:
            # Upstream failure, cancellation or a settlement error: the user
            # is never charged for work that did not complete. If even the
            # release fails, the durable row is reclaimed at the next start.
            try:
                with settlement_transaction(db):
                    release_tool_points(db, reservation_id)
            except sqlite3.Error:
                config.logger.exception(
                    "tool_reservation_release_failed user_id=%s tool=%s reservation_id=%s",
                    user_id,
                    tool,
                    reservation_id,
                )
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
    cache_key = (int(user["id"]), path, idempotency_key)
    body_hash = hashlib.sha256(body).hexdigest()
    while (entry := state.tool_response_cache.lookup(cache_key)) is not None:
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
    entry = state.tool_response_cache.begin(cache_key, body_hash)
    try:
        result = await execute_paid_tool(
            db, int(user["id"]), path=path, tool=tool, body=body
        )
    except BaseException:
        state.tool_response_cache.fail(cache_key, entry)
        raise
    state.tool_response_cache.complete(cache_key, entry, result)
    return Response(
        content=result.content, status_code=result.status_code, headers=result.headers
    )


def _is_generation_log_sensitive_key(key: str) -> bool:
    normalized = key.strip().lower().replace("-", "_")
    if normalized in config.GENERATION_LOG_SENSITIVE_KEYS:
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
            and 4 <= len(value) <= config.AUDIT_MAX_STRING_CHARS
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
    if len(preview) > config.GENERATION_ERROR_PREVIEW_MAX_CHARS:
        omitted = len(preview) - config.GENERATION_ERROR_PREVIEW_MAX_CHARS
        return f"{preview[:config.GENERATION_ERROR_PREVIEW_MAX_CHARS]}<truncated {omitted} chars>"
    return preview


@router.api_route("/api/nai/{service}/{path:path}", methods=["GET", "POST"])
async def novelai_proxy(
    service: str,
    path: str,
    request: Request,
    user: sqlite3.Row = Depends(require_user),
    db: sqlite3.Connection = Depends(get_db),
):
    method = request.method.upper()
    require_novelai_proxy_permission(service, path, method, user)
    tool = config.PAID_TOOL_PATHS.get(path) if service == "image" else None
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
