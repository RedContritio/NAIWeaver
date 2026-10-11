from __future__ import annotations

import sqlite3
from typing import Any

from fastapi import APIRouter, Depends, Request, status
from fastapi.responses import FileResponse

from .auth import require_user
from .db import get_db, now_iso
from .errors import api_error, permission_denied
from .generation import (
    GENERATION_ITEM_SELECT,
    generation_item_dto,
    visible_history_task,
)
from .storage import ensure_history_thumbnail, resolve_history_image_file

router = APIRouter()


@router.get("/api/history")
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
        LEFT JOIN history_hidden h ON h.task_id = t.id AND h.user_id IN (?, t.user_id)
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
        LEFT JOIN history_hidden h ON h.task_id = t.id AND h.user_id IN (?, t.user_id)
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
            LEFT JOIN history_hidden h ON h.task_id = t.id AND h.user_id IN (?, t.user_id)
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


@router.get("/api/history/{task_id}/image")
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


@router.get("/api/history/{task_id}/thumbnail")
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


@router.delete("/api/history/batches/{batch_id}")
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


@router.delete("/api/history/{task_id}")
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
