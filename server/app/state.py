from __future__ import annotations

import asyncio
from dataclasses import dataclass, field

import httpx

from .idempotency import ToolResponseCache
from .upstream_lane import FREE_PRIORITY, RED_PRIORITY, UpstreamLane

http_client: httpx.AsyncClient | None = None
queue_condition: asyncio.Condition | None = None
queue_worker_task: asyncio.Task | None = None
audit_retention_task: asyncio.Task | None = None
pending_jobs: list["ProxyJob"] = []
active_user_ids: set[int] = set()
queue_virtual_time = 0.0
queue_last_finish: dict[str, float] = {"free": 0.0, "paid": 0.0, "admin": 0.0}
text_queue_condition: asyncio.Condition | None = None
pending_text_jobs: list["TextQueueTicket"] = []
active_text_user_ids: set[int] = set()
active_text_count = 0
text_queue_virtual_time = 0.0
text_queue_last_finish: dict[str, float] = {"free": 0.0, "paid": 0.0, "admin": 0.0}
upstream_lane = UpstreamLane()
tool_response_cache = ToolResponseCache()


@dataclass(order=True)
class ProxyJob:
    sort_key: tuple[int, float, int, str] = field(init=False, repr=False)
    virtual_finish: float
    negative_weight: int
    created_at: str
    user_id: int = field(compare=False)
    task_id: str = field(compare=False)
    service: str = field(compare=False)
    path: str = field(compare=False)
    body: bytes = field(compare=False)
    quota_mode: str = field(compare=False, default="free")

    def __post_init__(self) -> None:
        # Red-point work runs before free work; free work keeps the weighted
        # fair order among user classes.
        self.sort_key = (
            self.lane_priority,
            self.virtual_finish,
            self.negative_weight,
            self.created_at,
        )

    @property
    def lane_priority(self) -> int:
        return RED_PRIORITY if self.quota_mode == "paid" else FREE_PRIORITY


@dataclass(order=True)
class TextQueueTicket:
    sort_key: tuple[float, int, str] = field(init=False, repr=False)
    virtual_finish: float
    negative_weight: int
    created_at: str
    user_id: int = field(compare=False)
    username: str = field(compare=False)
    ticket_id: str = field(compare=False)

    def __post_init__(self) -> None:
        self.sort_key = (self.virtual_finish, self.negative_weight, self.created_at)
