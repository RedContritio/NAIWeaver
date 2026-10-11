from __future__ import annotations

import mimetypes
from pathlib import Path

from fastapi import APIRouter, HTTPException, Request, Response, status
from fastapi.responses import FileResponse, RedirectResponse

from . import config
from .auth import only_auth, require_user
from .db import db_connect
from .errors import api_error

router = APIRouter()

# Precompressed siblings written by server/scripts/compress-web.sh, in the
# order they are preferred.
PRECOMPRESSED_ENCODINGS = (("br", ".br"), ("gzip", ".gz"))


def accepted_encodings(request: Request) -> set[str]:
    accepted = set()
    for part in request.headers.get("accept-encoding", "").split(","):
        name, _, params = part.strip().partition(";")
        if params.replace(" ", "") in {"q=0", "q=0.0", "q=0.00", "q=0.000"}:
            continue
        accepted.add(name.strip().lower())
    return accepted


def static_file_response(request: Request, target: Path) -> Response:
    """Serve a web build file with a precompressed variant and revalidation.

    Flutter keeps stable filenames (main.dart.js, assets) across builds, so
    every file is revalidated; an unchanged file costs a 304 instead of the
    whole bundle, and the bundle itself goes out brotli or gzip compressed.
    """
    body = target
    encoding = None
    accepted = accepted_encodings(request)
    for name, suffix in PRECOMPRESSED_ENCODINGS:
        candidate = target.with_name(target.name + suffix)
        if name in accepted and candidate.is_file():
            body, encoding = candidate, name
            break
    stat = body.stat()
    etag = f'"{stat.st_mtime_ns:x}-{stat.st_size:x}{"-" + encoding if encoding else ""}"'
    headers = {
        "Cache-Control": "no-cache",
        "ETag": etag,
        "Vary": "Accept-Encoding",
    }
    if_none_match = request.headers.get("if-none-match", "")
    if etag in {tag.strip() for tag in if_none_match.split(",")} or if_none_match.strip() == "*":
        return Response(status_code=status.HTTP_304_NOT_MODIFIED, headers=headers)
    if encoding:
        headers["Content-Encoding"] = encoding
    media_type = mimetypes.guess_type(target.name)[0] or "application/octet-stream"
    return FileResponse(body, media_type=media_type, headers=headers, stat_result=stat)


@router.get("/api/health")
def health():
    return {"ok": True}


@router.api_route(
    "/api",
    methods=["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    include_in_schema=False,
)
@router.api_route(
    "/api/{path:path}",
    methods=["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    include_in_schema=False,
)
def unknown_api(path: str = ""):
    # Unknown API paths are JSON 404s for every method, never a 405 from the
    # page catch-all and never a redirect to the IdP. This router is included
    # last, so real API routes always match first.
    raise api_error(status.HTTP_404_NOT_FOUND, "not_found", "Not found")


@router.get("/{path:path}")
async def serve_web(path: str, request: Request):
    # Authenticate document navigation before loading the Flutter application.
    if only_auth.enabled and (not path or path == "index.html" or "." not in path):
        db = db_connect()
        try:
            await require_user(request, db)
        except HTTPException as exc:
            if exc.status_code != 401:
                raise
            return RedirectResponse(
                only_auth.login_location(request),
                status_code=302,
                headers={"Cache-Control": "no-store"},
            )
        finally:
            db.close()
    web_root = config.WEB_BUILD_DIR.resolve()
    if path and ".." not in Path(path).parts and not Path(path).is_absolute():
        target = (web_root / path).resolve()
        if (
            target.exists()
            and target.is_file()
            and (target == web_root or web_root in target.parents)
        ):
            return static_file_response(request, target)
    index = config.WEB_BUILD_DIR / "index.html"
    if index.exists():
        return static_file_response(request, index)
    fallback = config.STATIC_DIR / "index.html"
    if fallback.exists():
        return FileResponse(fallback)
    return Response("NAIWeaver web build not found", status_code=404)
