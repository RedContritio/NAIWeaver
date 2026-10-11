"""The single serialized lane for NovelAI image calls (contract §6).

NovelAI allows one image generation per account at a time; a second
concurrent call fails with 429 "Concurrent generation is locked". Every image
call (queued generations and paid tools) therefore holds this lane. It is a
priority mutex: when it is released, the waiter with the lowest priority value
takes over (FIFO within a priority), so red-point work never waits behind
queued free work.
"""

from __future__ import annotations

import asyncio
from contextlib import asynccontextmanager
from dataclasses import dataclass, field
import itertools
from typing import AsyncIterator, Callable, Union


RED_PRIORITY = 0
FREE_PRIORITY = 1

Priority = Union[int, Callable[[], int]]


@dataclass(eq=False)
class _Waiter:
    priority: Priority
    sequence: int
    future: asyncio.Future = field(repr=False)

    def current_priority(self) -> int:
        return self.priority() if callable(self.priority) else self.priority


class UpstreamLane:
    def __init__(self) -> None:
        self._held = False
        self._waiters: list[_Waiter] = []
        self._sequence = itertools.count()

    @property
    def held(self) -> bool:
        return self._held

    @property
    def waiting(self) -> int:
        return sum(not waiter.future.done() for waiter in self._waiters)

    async def acquire(self, priority: Priority) -> None:
        """Wait for the lane.

        ``priority`` may be a callable; it is evaluated at hand-off time so a
        waiter can represent "whatever is at the head of the queue now".
        """
        if not self._held and not self._waiters:
            self._held = True
            return
        waiter = _Waiter(
            priority,
            next(self._sequence),
            asyncio.get_running_loop().create_future(),
        )
        self._waiters.append(waiter)
        try:
            await waiter.future
        except BaseException:
            if waiter in self._waiters:
                self._waiters.remove(waiter)
            elif waiter.future.done() and not waiter.future.cancelled():
                # Ownership was handed over just before the cancellation.
                self.release()
            raise

    def release(self) -> None:
        while self._waiters:
            nxt = min(
                self._waiters,
                key=lambda waiter: (waiter.current_priority(), waiter.sequence),
            )
            self._waiters.remove(nxt)
            if not nxt.future.done():
                nxt.future.set_result(None)
                return
        self._held = False

    @asynccontextmanager
    async def hold(self, priority: Priority) -> AsyncIterator[None]:
        await self.acquire(priority)
        try:
            yield
        finally:
            self.release()
