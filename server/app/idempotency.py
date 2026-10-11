"""Bounded in-memory replay cache for paid tool calls (contract §5).

A paid tool POST carries an ``Idempotency-Key``. A retry with the same key
and body receives the stored response instead of a second NovelAI call; the
same key with another body is rejected by the caller. Concurrent requests
with one key share the first call's result.
"""

from __future__ import annotations

import asyncio
from collections import OrderedDict
from dataclasses import dataclass, field
import time
from typing import Callable, Hashable


@dataclass(frozen=True)
class CachedResponse:
    status_code: int
    headers: dict[str, str]
    content: bytes


@dataclass(eq=False)
class CacheEntry:
    body_hash: str
    future: asyncio.Future = field(repr=False)
    expires_at: float = float("inf")
    size: int = 0


class ToolResponseCache:
    def __init__(
        self,
        *,
        max_entries: int = 32,
        ttl_seconds: float = 600.0,
        max_bytes: int = 128 * 1024 * 1024,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self.max_entries = max_entries
        self.ttl_seconds = ttl_seconds
        self.max_bytes = max_bytes
        self._clock = clock
        self._entries: OrderedDict[Hashable, CacheEntry] = OrderedDict()

    def __len__(self) -> int:
        return len(self._entries)

    def lookup(self, key: Hashable) -> CacheEntry | None:
        self._purge_expired()
        return self._entries.get(key)

    def begin(self, key: Hashable, body_hash: str) -> CacheEntry:
        entry = CacheEntry(body_hash, asyncio.get_running_loop().create_future())
        self._entries[key] = entry
        return entry

    def complete(self, key: Hashable, entry: CacheEntry, response: CachedResponse) -> None:
        entry.size = len(response.content)
        entry.expires_at = self._clock() + self.ttl_seconds
        if not entry.future.done():
            entry.future.set_result(response)
        if self._entries.get(key) is entry:
            self._entries.move_to_end(key)
        self._evict()

    def fail(self, key: Hashable, entry: CacheEntry) -> None:
        """Forget a failed call; waiters receive ``None`` and run their own."""
        if self._entries.get(key) is entry:
            del self._entries[key]
        if not entry.future.done():
            entry.future.set_result(None)

    def _purge_expired(self) -> None:
        now = self._clock()
        for key in [key for key, entry in self._entries.items() if entry.expires_at <= now]:
            del self._entries[key]

    def _evict(self) -> None:
        self._purge_expired()
        completed = [key for key, entry in self._entries.items() if entry.future.done()]
        total = sum(self._entries[key].size for key in completed)
        while completed and (
            len(self._entries) > self.max_entries or total > self.max_bytes
        ):
            oldest = completed.pop(0)
            total -= self._entries.pop(oldest).size
