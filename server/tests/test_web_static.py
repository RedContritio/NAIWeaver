from __future__ import annotations

import tests  # noqa: F401  # isolates the data directories before app imports

import gzip
import os
import tempfile
from pathlib import Path
import unittest
from unittest import mock

from fastapi.testclient import TestClient

from app import config, main


class StaticWebTests(unittest.TestCase):
    """The Flutter bundle is ~10 MB; it must go out compressed and revalidate."""

    def setUp(self) -> None:
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.web = Path(directory.name)
        self.bundle = b"void main(){}\n" * 4096
        (self.web / "main.dart.js").write_bytes(self.bundle)
        (self.web / "main.dart.js.gz").write_bytes(gzip.compress(self.bundle))
        (self.web / "index.html").write_text("<html></html>")
        patcher = mock.patch.object(config, "WEB_BUILD_DIR", self.web)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.client = TestClient(main.app, follow_redirects=False)

    def test_bundle_is_served_precompressed_when_accepted(self) -> None:
        response = self.client.get("/main.dart.js", headers={"Accept-Encoding": "gzip"})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.headers["content-encoding"], "gzip")
        self.assertIn("Accept-Encoding", response.headers["vary"])
        self.assertIn("javascript", response.headers["content-type"])
        self.assertLess(int(response.headers["content-length"]), len(self.bundle))
        self.assertEqual(response.content, self.bundle)

    def test_clients_without_compression_get_the_raw_file(self) -> None:
        response = self.client.get("/main.dart.js", headers={"Accept-Encoding": "identity"})
        self.assertEqual(response.status_code, 200)
        self.assertNotIn("content-encoding", response.headers)
        self.assertEqual(response.content, self.bundle)

    def test_unchanged_bundle_revalidates_with_304(self) -> None:
        first = self.client.get("/main.dart.js", headers={"Accept-Encoding": "gzip"})
        again = self.client.get(
            "/main.dart.js",
            headers={"Accept-Encoding": "gzip", "If-None-Match": first.headers["etag"]},
        )
        self.assertEqual(again.status_code, 304)
        self.assertEqual(again.content, b"")

    def test_raw_and_compressed_variants_never_share_an_etag(self) -> None:
        compressed = self.client.get("/main.dart.js", headers={"Accept-Encoding": "gzip"})
        raw = self.client.get(
            "/main.dart.js",
            headers={"Accept-Encoding": "identity", "If-None-Match": compressed.headers["etag"]},
        )
        self.assertEqual(raw.status_code, 200)
        self.assertNotEqual(raw.headers["etag"], compressed.headers["etag"])

    def test_stale_precompressed_sibling_is_ignored(self) -> None:
        gz = self.web / "main.dart.js.gz"
        source = self.web / "main.dart.js"
        stat = gz.stat()
        os.utime(source, ns=(stat.st_atime_ns, stat.st_mtime_ns + 5_000_000_000))
        response = self.client.get("/main.dart.js", headers={"Accept-Encoding": "gzip"})
        self.assertEqual(response.status_code, 200)
        self.assertNotIn("content-encoding", response.headers)

    def test_weakened_etag_still_revalidates(self) -> None:
        first = self.client.get("/main.dart.js", headers={"Accept-Encoding": "gzip"})
        again = self.client.get(
            "/main.dart.js",
            headers={"Accept-Encoding": "gzip", "If-None-Match": "W/" + first.headers["etag"]},
        )
        self.assertEqual(again.status_code, 304)

    def test_head_requests_return_headers_without_body(self) -> None:
        health = self.client.head("/api/health")
        self.assertEqual(health.status_code, 200)
        self.assertEqual(health.content, b"")
        page = self.client.head("/main.dart.js", headers={"Accept-Encoding": "gzip"})
        self.assertEqual(page.status_code, 200)
        self.assertEqual(page.content, b"")
        self.assertEqual(page.headers["content-encoding"], "gzip")
        self.assertEqual(self.client.head("/api/nope").status_code, 404)

    def test_paths_outside_the_build_are_never_served(self) -> None:
        (self.web.parent / "secret.txt").write_text("nope")
        self.addCleanup((self.web.parent / "secret.txt").unlink)
        response = self.client.get("/../secret.txt")
        self.assertNotEqual(response.text, "nope")


if __name__ == "__main__":
    unittest.main()
