from __future__ import annotations

from pathlib import Path

from fastapi import APIRouter, HTTPException, Request, Response, status
from fastapi.responses import FileResponse, RedirectResponse

from . import config
from .auth import only_auth, require_user
from .db import db_connect
from .errors import api_error

router = APIRouter()


@router.get("/api/health")
def health():
    return {"ok": True}


@router.get("/{path:path}")
async def serve_web(path: str, request: Request):
    # Unknown API paths are JSON errors, never a redirect to the IdP.
    if path == "api" or path.startswith("api/"):
        raise api_error(status.HTTP_404_NOT_FOUND, "not_found", "Not found")
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
            # Flutter's entry scripts keep stable filenames across builds.
            # Revalidate them so a deployed UI cannot be held behind a stale
            # browser or installed-PWA cache.
            headers = (
                {"Cache-Control": "no-cache, must-revalidate"}
                if target.name
                in {"index.html", "flutter_bootstrap.js", "flutter.js", "main.dart.js"}
                else None
            )
            return FileResponse(target, headers=headers)
    index = config.WEB_BUILD_DIR / "index.html"
    if index.exists():
        return FileResponse(index, headers={"Cache-Control": "no-cache, must-revalidate"})
    fallback = config.STATIC_DIR / "index.html"
    if fallback.exists():
        return FileResponse(fallback)
    return Response("NAIWeaver web build not found", status_code=404)
