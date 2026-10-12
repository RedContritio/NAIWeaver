from __future__ import annotations

import tests  # noqa: F401  # isolates the data directories before app imports

import asyncio
import os
from pathlib import Path
import stat
import tempfile
import unittest
from unittest import mock

from fastapi import HTTPException

from app import config, db as gwdb, generation, history, proxy, state
from tests import support


class HiddenHistoryTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.db = support.temporary_database(self)
        support.reset_queue_state()
        self.addCleanup(support.reset_queue_state)
        self.owner = support.create_user(self.db, "owner")
        self.admin = support.create_user(self.db, "admin-user", "admin")
        submitted = await support.submit(
            self.db, self.owner, support.generation_request(), [1, 2]
        )
        self.task_id = submitted["task_id"]
        self.item_id = submitted["items"][0]["id"]
        # Final states, so the owner may delete them.
        self.db.execute("UPDATE generation_tasks SET status = 'failed'")
        self.db.commit()
        history.delete_history_item(self.item_id, user=self.owner, db=self.db)

    def test_admin_views_never_return_an_item_its_owner_hid(self) -> None:
        request = support.make_request("/api/history", method="GET")
        page = history.history(request, all_users=True, user=self.admin, db=self.db)
        self.assertEqual(
            [item["id"] for item in page["items"]],
            [row["id"] for row in self.db.execute(
                "SELECT id FROM generation_tasks WHERE id <> ? ORDER BY batch_index",
                (self.item_id,),
            )],
        )
        self.assertEqual(page["total"], 1)

        by_user = history.history(
            request, user_id=int(self.owner["id"]), user=self.admin, db=self.db
        )
        self.assertNotIn(self.item_id, [item["id"] for item in by_user["items"]])

        task = generation.generation_task_status(self.task_id, user=self.admin, db=self.db)
        self.assertNotIn(self.item_id, [item["id"] for item in task["items"]])

        with self.assertRaises(HTTPException) as raised:
            generation.generation_item_status(self.item_id, user=self.admin, db=self.db)
        self.assertEqual(raised.exception.status_code, 404)

    def test_a_task_whose_items_are_all_hidden_is_not_found_for_admins(self) -> None:
        other = self.db.execute(
            "SELECT id FROM generation_tasks WHERE id <> ?", (self.item_id,)
        ).fetchone()
        history.delete_history_item(other["id"], user=self.owner, db=self.db)
        with self.assertRaises(HTTPException) as raised:
            generation.generation_task_status(self.task_id, user=self.admin, db=self.db)
        self.assertEqual(raised.exception.status_code, 404)


class TextSlotTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.db = support.temporary_database(self)
        support.reset_queue_state()
        state.text_queue_condition = asyncio.Condition()
        state.active_text_user_ids.clear()
        state.pending_text_jobs.clear()
        state.active_text_count = 0
        self.addCleanup(support.reset_queue_state)
        self.user = support.create_user(self.db, "texter")

    async def test_cancelled_text_request_frees_its_slot(self) -> None:
        started = asyncio.Event()

        async def hang(*args, **kwargs):
            started.set()
            await asyncio.Event().wait()

        with mock.patch.object(proxy, "forward_to_novelai", hang):
            task = asyncio.create_task(
                proxy.forward_text_to_novelai_queued(
                    self.user, "text", "ai/generate", method="POST", body=b"{}", stream=False
                )
            )
            await started.wait()
            self.assertIn(int(self.user["id"]), state.active_text_user_ids)
            task.cancel()
            await asyncio.gather(task, return_exceptions=True)
        self.assertNotIn(int(self.user["id"]), state.active_text_user_ids)
        self.assertEqual(state.active_text_count, 0)


class DatabaseFileTests(unittest.TestCase):
    def test_database_is_created_owner_only(self) -> None:
        directory = tempfile.TemporaryDirectory(prefix="naiweaver-mode-")
        self.addCleanup(directory.cleanup)
        for name, path in (("DATA_DIR", Path(directory.name)),
                           ("DB_PATH", Path(directory.name) / "gateway.sqlite3")):
            patcher = mock.patch.object(config, name, path)
            patcher.start()
            self.addCleanup(patcher.stop)
        old = os.umask(0o022)
        self.addCleanup(os.umask, old)
        gwdb.db_connect().close()
        self.assertEqual(stat.S_IMODE(config.DB_PATH.stat().st_mode), 0o600)
        config.DB_PATH.chmod(0o644)
        for name in ("IMAGE_DIR", "THUMBNAIL_DIR", "AUDIT_DIR"):
            patcher = mock.patch.object(config, name, Path(directory.name) / name)
            patcher.start()
            self.addCleanup(patcher.stop)
        gwdb.init_db()
        self.assertEqual(stat.S_IMODE(config.DB_PATH.stat().st_mode), 0o600)


if __name__ == "__main__":
    unittest.main()
