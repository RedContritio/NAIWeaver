from __future__ import annotations

import asyncio
import copy
from dataclasses import dataclass
import hashlib
import json
import secrets
import sqlite3
import time
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.responses import JSONResponse

from . import config, state
from .audit import complete_audit_log, create_audit_log
from .auth import require_user
from .billing import (
    ANOMALY_DECODE_FAILED,
    ANOMALY_FREE_ALLOWANCE_EXHAUSTED,
    ANOMALY_MEASURED_ABOVE_QUOTE,
    ANOMALY_UNMEASURED,
    MAX_SEED,
    Quote,
    classify_and_quote,
    free_allowance_exhausted_until,
    immediate_transaction,
    is_strict_int,
    point_kind_for_mode,
    record_billing_anomaly,
    release_points,
    reserve_points,
    settle_amount,
    settle_points,
)
from .db import (
    db_session,
    generation_request_fingerprint,
    get_db,
    now_iso,
    refresh_submission_task,
)
from .errors import api_error, invalid_parameters, permission_denied
from .proxy import UpstreamImageCall, call_image_upstream, safe_upstream_error_preview
from .state import ProxyJob
from .storage import save_history_image
from .upstream_lane import FREE_PRIORITY
from .users import (
    generation_permission_name,
    image_generation_allowed,
    image_rules_for_user,
    mode_for_user,
)

router = APIRouter()


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


@router.get("/api/queue")
async def queue_status(
    user: sqlite3.Row = Depends(require_user),
    db: sqlite3.Connection = Depends(get_db),
):
    assert state.queue_condition is not None
    assert state.text_queue_condition is not None
    async with state.queue_condition:
        image_own_index = next(
            (index for index, job in enumerate(state.pending_jobs) if job.user_id == user["id"]),
            None,
        )
        image_queued = len(state.pending_jobs)
        image_active = len(state.active_user_ids)
        user_image_active = int(user["id"]) in state.active_user_ids
        user_pending_count = sum(job.user_id == user["id"] for job in state.pending_jobs)
    async with state.text_queue_condition:
        text_own_index = next(
            (
                index
                for index, job in enumerate(state.pending_text_jobs)
                if job.user_id == user["id"]
            ),
            None,
        )
        text_queued = len(state.pending_text_jobs)
        text_active = state.active_text_count
        user_text_active = int(user["id"]) in state.active_text_user_ids
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
        "text_concurrency": config.TEXT_GLOBAL_CONCURRENCY,
    }


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
        negative_weight=-int(task["queue_weight"] or config.QUEUE_WEIGHTS["free"]),
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
    assert state.queue_condition is not None
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
    async with state.queue_condition:
        state.pending_jobs.extend(jobs)
        state.pending_jobs.sort(key=lambda job: job.sort_key)
        if state.pending_jobs:
            state.queue_virtual_time = max(job.virtual_finish for job in state.pending_jobs)


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
    # Hidden by the viewer or by the owner: never returned, even to admins.
    hidden = db.execute(
        "SELECT 1 FROM history_hidden WHERE user_id IN (?, ?) AND task_id = ?",
        (user["id"], task["user_id"], task_id),
    ).fetchone()
    if hidden:
        raise api_error(status.HTTP_404_NOT_FOUND, "not_found", "Task not found")
    if task["user_id"] != user["id"] and not user["is_admin"]:
        raise permission_denied("history.all", "This task belongs to another user")
    return task


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
    assert state.queue_condition is not None
    if not items or len(items) != quote.images:
        raise invalid_parameters("seeds", "Every image needs exactly one seed")

    user_id = int(user["id"])
    fingerprints = [generation_request_fingerprint(item) for item in items]

    async with state.queue_condition:
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
        if outstanding + len(items) > config.MAX_QUEUED_IMAGE_TASKS_PER_USER:
            raise api_error(
                status.HTTP_429_TOO_MANY_REQUESTS,
                "queue_full",
                "Too many unfinished image tasks",
                limit=config.MAX_QUEUED_IMAGE_TASKS_PER_USER,
            )

        queue_class = mode_for_user(user)
        weight = config.QUEUE_WEIGHTS[queue_class]
        last_finish = state.queue_last_finish[queue_class]
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
                virtual_finish = max(state.queue_virtual_time, last_finish) + (1.0 / weight)
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
        state.queue_last_finish[queue_class] = last_finish
        state.pending_jobs.extend(jobs)
        state.pending_jobs.sort(key=lambda job: job.sort_key)
        state.queue_condition.notify_all()
        return parent_task_id, item_ids, False


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
    config.logger.error(
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
    config.logger.exception(
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
    assert state.queue_condition is not None
    async with state.queue_condition:
        state.pending_jobs[:] = [job for job in state.pending_jobs if job.quota_mode == "paid"]
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


def record_free_measurement(
    db: sqlite3.Connection, job: ProxyJob, reserved: int, delta: int | None
) -> bool:
    """Audit what a free-eligible image cost in Anlas.

    Any Anlas spent means NovelAI's free allowance has run out (returns True);
    a balance that could not be read is reported as unmeasured.
    """
    if delta is None:
        record_billing_anomaly(
            db,
            kind=ANOMALY_UNMEASURED,
            user_id=job.user_id,
            task_id=job.task_id,
            mode="free",
            quoted=reserved,
            measured=None,
            note="Anlas balance could not be read; free allowance not verified",
        )
        return False
    if delta <= 0:
        return False
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
    return True


def record_decode_failure(job: ProxyJob, call: UpstreamImageCall) -> bool:
    """NovelAI answered 2xx without a usable image: keep the measured cost.

    The caller releases the reservation, so the user pays nothing; the
    anomaly shows what the account paid upstream. Returns True when a free
    item proved the allowance exhausted.
    """
    delta = call.measured_delta
    exhausted = False
    with db_session() as db:
        item = db.execute(
            "SELECT reserved_points FROM generation_tasks WHERE id = ?", (job.task_id,)
        ).fetchone()
        reserved = int(item["reserved_points"] or 0) if item else 0
        if job.quota_mode == "paid":
            record_billing_anomaly(
                db,
                kind=ANOMALY_DECODE_FAILED,
                user_id=job.user_id,
                task_id=job.task_id,
                mode="paid",
                quoted=reserved,
                measured=delta,
                note="NovelAI returned no valid image; reservation released",
            )
        else:
            exhausted = record_free_measurement(db, job, reserved, delta)
        db.commit()
    return exhausted


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
            if delta == 0:
                # Paid work cannot cost nothing: the balance was not
                # measurable, so the quote stands.
                charged = reserved
                record_billing_anomaly(
                    db,
                    kind=ANOMALY_UNMEASURED,
                    user_id=job.user_id,
                    task_id=job.task_id,
                    mode="paid",
                    quoted=reserved,
                    measured=delta,
                    note="Anlas balance did not change; charged the quote",
                )
            elif above_quote:
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
            # Free work is always charged its green quote.
            charged = reserved
            exhausted = record_free_measurement(db, job, reserved, delta)
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
        call = await call_image_upstream(
            job.path, job.body, paid=job.quota_mode == "paid"
        )
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
            exhausted = record_decode_failure(job, call)
            persist_generation_failure(
                job,
                error_code="upstream_error",
                error_message="NovelAI returned no valid image",
            )
            if exhausted:
                await fail_queued_free_jobs()
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
            config.logger.exception(
                "generation_failure_persistence_failed %s original_error_type=%s "
                "original_error=%r persistence_error_type=%s persistence_error=%r",
                generation_job_log_context(job, batch_id),
                type(exc).__name__,
                str(exc),
                type(persistence_exc).__name__,
                str(persistence_exc),
            )


def _head_lane_priority() -> int:
    return state.pending_jobs[0].lane_priority if state.pending_jobs else FREE_PRIORITY


async def queue_worker() -> None:
    assert state.queue_condition is not None
    while True:
        async with state.queue_condition:
            while not state.pending_jobs:
                await state.queue_condition.wait()
        # Each item runs inside the upstream lane. The lane is requested with
        # the priority of whatever heads the queue at hand-off time, so a paid
        # tool already waiting goes before queued free work.
        await state.upstream_lane.acquire(_head_lane_priority)
        job: ProxyJob | None = None
        try:
            async with state.queue_condition:
                if not state.pending_jobs:
                    continue
                job = state.pending_jobs.pop(0)
                state.active_user_ids.add(job.user_id)
                state.queue_virtual_time = max(state.queue_virtual_time, job.virtual_finish)
            await run_generation_job(job)
        finally:
            state.upstream_lane.release()
            if job is not None:
                state.active_user_ids.discard(job.user_id)


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


async def record_submission_audit(
    db: sqlite3.Connection,
    user: sqlite3.Row,
    *,
    body: bytes,
    content_type: str,
    store_body: bool,
    status_code: int,
    error_message: str | None = None,
) -> None:
    """Audit a submission after its outcome is known.

    A failure to write the audit must not turn an accepted (durably queued)
    submission into an error, so it is logged instead of raised.
    """
    try:
        audit_id = await create_audit_log(
            db,
            user,
            service="image",
            path="ai/generate-image",
            method="POST",
            body=body,
            content_type=content_type,
            store_body=store_body,
        )
        complete_audit_log(
            db, audit_id, status_code=status_code, error_message=error_message
        )
    except Exception:
        config.logger.exception("submission_audit_failed status_code=%s", status_code)


@router.post("/api/generation-tasks", status_code=status.HTTP_202_ACCEPTED)
async def submit_generation_task(
    request: Request,
    user: sqlite3.Row = Depends(require_user),
    db: sqlite3.Connection = Depends(get_db),
):
    """Durably accept an image-generation submission (contract §4)."""
    body = await request.body()
    content_type = request.headers.get("content-type", "")
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
        # Rejected: keep the metadata, never the full body.
        await record_submission_audit(
            db,
            user,
            body=body,
            content_type=content_type,
            store_body=False,
            status_code=exc.status_code,
            error_message=str(exc.detail),
        )
        raise
    except Exception:
        db.rollback()
        await record_submission_audit(
            db,
            user,
            body=body,
            content_type=content_type,
            store_body=False,
            status_code=500,
            error_message="Submission failed",
        )
        raise
    # Accepted: the full body is written only now, off the event loop.
    await record_submission_audit(
        db,
        user,
        body=body,
        content_type=content_type,
        store_body=True,
        status_code=status.HTTP_202_ACCEPTED,
    )
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
        secure=config.COOKIE_SECURE,
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
        LEFT JOIN history_hidden h ON h.task_id = t.id AND h.user_id IN (?, t.user_id)
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


@router.get("/api/generation-tasks/{task_id}")
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


@router.get("/api/generation-items/{item_id}")
def generation_item_status(
    item_id: str,
    user: sqlite3.Row = Depends(require_user),
    db: sqlite3.Connection = Depends(get_db),
):
    return generation_item_dto(visible_history_task(item_id, user, db))


@router.get("/api/current-generation-task")
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
            LEFT JOIN history_hidden h ON h.task_id = t.id AND h.user_id IN (?, t.user_id)
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
