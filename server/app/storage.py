from __future__ import annotations

import asyncio
import hashlib
from io import BytesIO
from pathlib import Path
from zipfile import ZipFile

from fastapi import HTTPException, status

from . import config
from .db import today_key

def fake_png() -> bytes:
    return bytes.fromhex(
        "89504e470d0a1a0a0000000d4948445200000001000000010802000000907753de"
        "0000000c49444154789c6360f8cf00000301010118dd8db00000000049454e44ae426082"
    )


def decode_zip_image(data: bytes) -> bytes | None:
    entry_sizes: list[int] = []
    try:
        with ZipFile(BytesIO(data)) as archive:
            for item in archive.infolist():
                if item.is_dir():
                    continue
                entry_sizes.append(item.file_size)
                raw = archive.read(item)
                if raw.startswith(b"\x89PNG") or raw.startswith(b"RIFF"):
                    return raw
    except Exception as exc:
        config.logger.exception(
            "novelai_image_archive_decode_failed exception_type=%s error=%r "
            "response_bytes=%s response_sha256=%s",
            type(exc).__name__,
            str(exc),
            len(data),
            hashlib.sha256(data).hexdigest(),
        )
        return None
    config.logger.error(
        "novelai_image_archive_missing_valid_image response_bytes=%s "
        "response_sha256=%s archive_entry_count=%s archive_entry_sizes=%s",
        len(data),
        hashlib.sha256(data).hexdigest(),
        len(entry_sizes),
        entry_sizes,
    )
    return None


def history_thumbnail_relative_path(image_path: str) -> Path:
    relative = Path(image_path).with_suffix(".webp")
    if relative.is_absolute() or ".." in relative.parts:
        raise ValueError("Invalid image path")
    return relative


def resolve_history_image_file(image_path: str) -> Path:
    relative = Path(image_path)
    if relative.is_absolute() or ".." in relative.parts:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Image not found")
    path = (config.IMAGE_DIR / relative).resolve()
    image_root = config.IMAGE_DIR.resolve()
    if not path.exists() or not path.is_file() or image_root not in path.parents:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Image not found")
    return path


def resolve_history_thumbnail_file(image_path: str) -> Path:
    try:
        relative = history_thumbnail_relative_path(image_path)
    except ValueError:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Thumbnail not found") from None
    path = (config.THUMBNAIL_DIR / relative).resolve()
    thumbnail_root = config.THUMBNAIL_DIR.resolve()
    if thumbnail_root not in path.parents:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Thumbnail not found")
    return path


def generate_history_thumbnail(source: Path, target: Path) -> None:
    try:
        from PIL import Image, ImageOps, UnidentifiedImageError
    except ModuleNotFoundError as exc:
        raise RuntimeError("Pillow is not installed") from exc

    target.parent.mkdir(parents=True, exist_ok=True)
    tmp = target.with_name(f"{target.stem}.tmp{target.suffix}")
    try:
        with Image.open(source) as image:
            thumbnail = ImageOps.exif_transpose(image)
            thumbnail.thumbnail(
                (config.THUMBNAIL_MAX_SIZE, config.THUMBNAIL_MAX_SIZE),
                Image.Resampling.LANCZOS,
            )
            if thumbnail.mode not in {"RGB", "RGBA"}:
                mode = "RGBA" if "A" in thumbnail.getbands() else "RGB"
                thumbnail = thumbnail.convert(mode)
            thumbnail.save(
                tmp,
                format="WEBP",
                quality=config.THUMBNAIL_WEBP_QUALITY,
                method=4,
            )
        tmp.replace(target)
    finally:
        if tmp.exists():
            tmp.unlink(missing_ok=True)


def ensure_history_thumbnail(image_path: str) -> Path:
    source = resolve_history_image_file(image_path)
    target = resolve_history_thumbnail_file(image_path)
    if target.exists() and target.stat().st_mtime >= source.stat().st_mtime:
        return target
    try:
        generate_history_thumbnail(source, target)
    except (OSError, RuntimeError, ValueError):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Thumbnail not available") from None
    return target


async def save_history_image(task_id: str, data: bytes) -> str | None:
    image = decode_zip_image(data)
    if image is None:
        return None
    day_dir = config.IMAGE_DIR / today_key()
    day_dir.mkdir(parents=True, exist_ok=True)
    path = day_dir / f"{task_id}.png"
    path.write_bytes(image)
    image_path = str(path.relative_to(config.IMAGE_DIR))
    try:
        await asyncio.to_thread(ensure_history_thumbnail, image_path)
    except HTTPException:
        pass
    return image_path
