"""The interactive API docs exist in development and are gone in production."""

from __future__ import annotations

import tests  # noqa: F401  # isolates the data directories before app imports

import os
import subprocess
import sys
import unittest
from pathlib import Path

from fastapi.testclient import TestClient

from app import main

DOC_PATHS = ("/docs", "/redoc", "/openapi.json")
SERVER_DIR = Path(__file__).resolve().parents[1]


class ApiDocsTests(unittest.TestCase):
    def test_development_keeps_the_docs(self) -> None:
        client = TestClient(main.app)
        self.addCleanup(client.close)
        for path in DOC_PATHS:
            with self.subTest(path=path):
                self.assertEqual(client.get(path).status_code, 200)

    def test_production_serves_no_docs_or_schema(self) -> None:
        # PRODUCTION is read when the app is built, so build it in a fresh
        # interpreter instead of reloading modules in this one.
        script = (
            "import json\n"
            "from fastapi.testclient import TestClient\n"
            "from app import main\n"
            "client = TestClient(main.app)\n"
            f"for path in {DOC_PATHS!r}:\n"
            "    body = client.get(path).text.lower()\n"
            "    leaked = any(m in body for m in ('swagger-ui', 'redoc', '\"openapi\"'))\n"
            "    print(path, leaked)\n"
        )
        env = {**os.environ, "NAIWEAVER_ENV": "production"}
        result = subprocess.run(
            [sys.executable, "-c", script],
            cwd=SERVER_DIR, env=env, capture_output=True, text=True, timeout=60,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = [line.split() for line in result.stdout.strip().splitlines()]
        # The web fallback may answer these paths with the app shell; what
        # matters is that neither the docs UI nor the schema is served.
        self.assertEqual(lines, [[path, "False"] for path in DOC_PATHS])


if __name__ == "__main__":
    unittest.main()
