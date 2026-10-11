from __future__ import annotations

import asyncio
from contextlib import asynccontextmanager, closing

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
import httpx

from . import admin, auth, config, feedback, generation, history, proxy, state, web
from .auth import only_auth, validate_runtime_config
from .audit import audit_retention_loop, run_audit_retention
from .body_limit import BodySizeLimitMiddleware
from .db import bootstrap_users, db_connect, init_db, reclaim_tool_reservations
from .errors import error_response, install_error_handlers
from .generation import queue_worker, restore_generation_queue
from .idempotency import ToolResponseCache
from .upstream_lane import UpstreamLane


@asynccontextmanager
async def lifespan(_: FastAPI):
    validate_runtime_config()
    init_db()
    with closing(db_connect()) as db:
        reclaim_tool_reservations(db)
        db.commit()
    bootstrap_users()
    timeout = httpx.Timeout(60.0, read=300.0)
    state.http_client = httpx.AsyncClient(timeout=timeout)
    state.queue_condition = asyncio.Condition()
    state.text_queue_condition = asyncio.Condition()
    state.upstream_lane = UpstreamLane()
    state.tool_response_cache = ToolResponseCache()
    await restore_generation_queue()
    state.queue_worker_task = asyncio.create_task(queue_worker())
    await run_audit_retention()
    state.audit_retention_task = asyncio.create_task(audit_retention_loop())
    try:
        yield
    finally:
        if state.audit_retention_task is not None:
            state.audit_retention_task.cancel()
            try:
                await state.audit_retention_task
            except asyncio.CancelledError:
                pass
        if state.queue_worker_task is not None:
            # The worker marks its running item 'interrupted' on cancellation.
            state.queue_worker_task.cancel()
            try:
                await state.queue_worker_task
            except asyncio.CancelledError:
                pass
        if state.http_client is not None:
            await state.http_client.aclose()
        await only_auth.aclose()


def api_docs_urls(production: bool) -> dict[str, str | None]:
    """Interactive API docs and the schema are for development only."""
    if production:
        return {"docs_url": None, "redoc_url": None, "openapi_url": None}
    return {"docs_url": "/docs", "redoc_url": "/redoc", "openapi_url": "/openapi.json"}


app = FastAPI(
    title="NAIWeaver Web Gateway",
    version="0.2.0",
    lifespan=lifespan,
    **api_docs_urls(config.PRODUCTION),
)

@app.middleware("http")
async def same_origin_writes(request: Request, call_next):
    if config.PRODUCTION and request.url.path.startswith("/api/") and request.method not in {
        "GET",
        "HEAD",
        "OPTIONS",
    }:
        origin = request.headers.get("origin")
        if origin and origin != config.PUBLIC_BASE_URL:
            return error_response(
                403,
                {
                    "code": "permission_denied",
                    "message": "Cross-origin request rejected",
                    "permission": "origin",
                },
            )
    return await call_next(request)


# The size limit counts the bytes every inner layer reads, including chunked
# uploads without Content-Length, so it sits outside everything that reads the
# body. CORS never reads the body, so it is added after (outermost) and the
# limiter's 413 and 400 responses still carry CORS headers.
def install_edge_middleware(app: FastAPI) -> None:
    app.add_middleware(BodySizeLimitMiddleware, max_bytes=config.MAX_REQUEST_BODY_BYTES)
    if config.CORS_ORIGINS:
        # Cross-origin development (flutter run -d chrome against a local gateway).
        # Every method and header the client sends must be listed or preflights fail.
        app.add_middleware(
            CORSMiddleware,
            allow_origins=config.CORS_ORIGINS,
            allow_credentials=True,
            allow_methods=["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
            allow_headers=[
                "Accept",
                "Authorization",
                "Content-Type",
                "Idempotency-Key",
                "X-NAIWeaver-Expected-Points",
            ],
        )


install_edge_middleware(app)
install_error_handlers(app)

# The web router holds the catch-all, so it is included last.
for _router in (
    auth.router,
    feedback.router,
    generation.router,
    admin.router,
    proxy.router,
    history.router,
    web.router,
):
    app.include_router(_router)
