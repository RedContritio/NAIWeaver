"""Uniform JSON errors for every gateway-originated failure (contract §1).

Every error leaves the gateway as ``{"detail": {"code": ..., "message": ...}}``
so the client can map ``code`` to localized text instead of showing raw
exception strings.
"""

from __future__ import annotations

from http import HTTPStatus
import logging
from typing import Any

from fastapi import FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException


logger = logging.getLogger("uvicorn.error.naiweaver")

# Codes used when a lower layer (FastAPI, Starlette, the auth module) raises a
# plain HTTPException without a contract code.
DEFAULT_ERROR_CODES = {
    400: "invalid_parameters",
    401: "not_authenticated",
    403: "permission_denied",
    404: "not_found",
    405: "method_not_allowed",
    409: "conflict",
    410: "gone",
    413: "request_too_large",
    429: "rate_limited",
    500: "internal_error",
    502: "upstream_error",
    503: "service_unavailable",
    504: "upstream_timeout",
}


def api_error(status_code: int, code: str, message: str, **extra: Any) -> HTTPException:
    return HTTPException(status_code, detail={"code": code, "message": message, **extra})


def invalid_parameters(field: str, message: str | None = None, **extra: Any) -> HTTPException:
    return api_error(
        400, "invalid_parameters", message or f"Invalid {field}", field=field, **extra
    )


def permission_denied(permission: str, message: str = "Permission denied") -> HTTPException:
    return api_error(403, "permission_denied", message, permission=permission)


def upstream_error(
    upstream_status: int | None, message: str = "NovelAI request failed"
) -> HTTPException:
    """NovelAI failures, including its 401/403, never pass through as-is."""
    return api_error(502, "upstream_error", message, upstream_status=upstream_status)


def error_payload(status_code: int, detail: Any) -> dict[str, Any]:
    if isinstance(detail, dict) and isinstance(detail.get("code"), str):
        payload = dict(detail)
        payload.setdefault("message", payload["code"])
        return payload
    try:
        phrase = HTTPStatus(status_code).phrase
    except ValueError:
        phrase = "Error"
    return {
        "code": DEFAULT_ERROR_CODES.get(status_code, "error"),
        "message": str(detail) if detail else phrase,
    }


def error_response(
    status_code: int, detail: Any, headers: dict[str, str] | None = None
) -> JSONResponse:
    return JSONResponse(
        {"detail": error_payload(status_code, detail)},
        status_code=status_code,
        headers=headers,
    )


async def _http_exception_handler(_: Request, exc: StarletteHTTPException) -> JSONResponse:
    return error_response(exc.status_code, exc.detail, getattr(exc, "headers", None))


async def _validation_exception_handler(_: Request, exc: RequestValidationError) -> JSONResponse:
    errors = exc.errors()
    first = errors[0] if errors else {}
    location = [str(part) for part in first.get("loc", ())]
    if location and location[0] in {"body", "query", "path", "header", "cookie"}:
        location = location[1:]
    return error_response(
        400,
        {
            "code": "invalid_parameters",
            "message": str(first.get("msg") or "Invalid request"),
            "field": ".".join(location) or None,
        },
    )


async def _unhandled_exception_handler(_: Request, exc: Exception) -> JSONResponse:
    logger.error("unhandled_gateway_exception type=%s", type(exc).__name__)
    return error_response(500, {"code": "internal_error", "message": "Internal server error"})


def install_error_handlers(app: FastAPI) -> None:
    app.add_exception_handler(StarletteHTTPException, _http_exception_handler)
    app.add_exception_handler(RequestValidationError, _validation_exception_handler)
    app.add_exception_handler(Exception, _unhandled_exception_handler)
