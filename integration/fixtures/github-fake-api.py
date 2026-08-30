#!/usr/bin/env python3
"""Credential-free GitHub API boundary for the GHB-017 composed profile."""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path


STATE = Path("/state/requests.jsonl")


class Handler(BaseHTTPRequestHandler):
    def log_message(self, _format: str, *_args: object) -> None:
        return

    def _record(self, body: bytes = b"") -> None:
        STATE.parent.mkdir(parents=True, exist_ok=True)
        with STATE.open("a", encoding="utf-8") as output:
            output.write(json.dumps({"method": self.command, "path": self.path, "bytes": len(body)}))
            output.write("\n")

    def _json(self, body: object, status: int = 200, scopes: bool = False) -> None:
        payload = json.dumps(body, separators=(",", ":")).encode()
        self.send_response(status)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(payload)))
        self.send_header("x-ratelimit-limit", "5000")
        self.send_header("x-ratelimit-remaining", "4999")
        self.send_header("x-ratelimit-reset", "1790000000")
        if scopes:
            self.send_header("x-oauth-scopes", "repo")
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self) -> None:
        self._record()
        if self.path == "/health":
            self._json({"status": "ok"})
        elif self.path == "/user":
            self._json({"id": 901, "login": "fixture-owner"}, scopes=True)
        elif self.path.startswith("/user/starred?"):
            self._json([])
        else:
            self._json({"error": "not_found"}, status=404)

    def do_POST(self) -> None:
        length = int(self.headers.get("content-length", "0"))
        body = self.rfile.read(length)
        self._record(body)
        if self.path == "/graphql":
            self._json(
                {
                    "data": {
                        "viewer": {
                            "lists": {
                                "edges": [],
                                "pageInfo": {"hasNextPage": False, "endCursor": None},
                            }
                        },
                        "rateLimit": {"remaining": 4998, "resetAt": "2026-08-30T12:00:00Z"},
                    }
                }
            )
        else:
            self._json({"error": "not_found"}, status=404)


ThreadingHTTPServer(("0.0.0.0", 18081), Handler).serve_forever()
