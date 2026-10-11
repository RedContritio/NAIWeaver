"""Request body limit counted on the received stream (contract §1).

Checking only ``Content-Length`` lets a chunked upload bypass the limit, so
this pure ASGI middleware counts the bytes the application actually reads.
"""

from __future__ import annotations

import json
from typing import Any

from fastapi import HTTPException
from starlette.types import ASGIApp, Message, Receive, Scope, Send


class RequestTooLarge(HTTPException):
    """Raised from ``receive``; an HTTPException so FastAPI's body parsing
    re-raises it unchanged and the exception handlers render it."""

    def __init__(self, limit: int) -> None:
        super().__init__(
            413,
            detail={
                "code": "request_too_large",
                "message": "Request body is too large",
                "limit": limit,
            },
        )


async def _send_error(send: Send, status_code: int, detail: dict[str, Any]) -> None:
    body = json.dumps({"detail": detail}, separators=(",", ":")).encode("utf-8")
    await send(
        {
            "type": "http.response.start",
            "status": status_code,
            "headers": [
                (b"content-type", b"application/json"),
                (b"content-length", str(len(body)).encode("ascii")),
            ],
        }
    )
    await send({"type": "http.response.body", "body": body})


class BodySizeLimitMiddleware:
    def __init__(self, app: ASGIApp, max_bytes: int) -> None:
        self.app = app
        self.max_bytes = max_bytes

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        limit = self.max_bytes
        for name, value in scope.get("headers", []):
            if name.lower() != b"content-length":
                continue
            try:
                declared = int(value)
            except ValueError:
                await _send_error(
                    send,
                    400,
                    {
                        "code": "invalid_parameters",
                        "message": "Invalid Content-Length",
                        "field": "Content-Length",
                    },
                )
                return
            if declared > limit:
                await _send_error(send, 413, RequestTooLarge(limit).detail)
                return

        received = 0
        exceeded = False
        response_started = False

        async def limited_receive() -> Message:
            nonlocal received, exceeded
            message = await receive()
            if message["type"] == "http.request":
                received += len(message.get("body", b""))
                if received > limit:
                    exceeded = True
                    raise RequestTooLarge(limit)
            return message

        async def guarded_send(message: Message) -> None:
            nonlocal response_started
            if exceeded and not response_started:
                # Inner layers may wrap or translate the overflow (Starlette's
                # BaseHTTPMiddleware runs the app in a task group, FastAPI maps
                # body errors to 400); whatever they answer is replaced below.
                return
            if message["type"] == "http.response.start":
                response_started = True
            await send(message)

        try:
            await self.app(scope, limited_receive, guarded_send)
        except Exception:
            if not exceeded or response_started:
                raise
        if exceeded and not response_started:
            await _send_error(send, 413, RequestTooLarge(limit).detail)
