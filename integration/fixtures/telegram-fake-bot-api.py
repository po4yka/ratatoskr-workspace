#!/usr/bin/env python3
"""Content-free synthetic Telegram Bot API for the TG-010 composed profile."""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import threading


STATE = Path("/state/counts.json")
LOCK = threading.Lock()
COUNTS: dict[str, int] = {}
NEXT_MESSAGE_ID = 55


def persist() -> None:
    temporary = STATE.with_suffix(".tmp")
    temporary.write_text(json.dumps(COUNTS, sort_keys=True) + "\n", encoding="utf-8")
    temporary.replace(STATE)


class Handler(BaseHTTPRequestHandler):
    server_version = "tg010-fake-bot"

    def log_message(self, _format: str, *_args: object) -> None:
        # Bot tokens live in Bot API paths; default request logging would expose them.
        return

    def answer(self, status: int, body: object) -> None:
        encoded = json.dumps(body, separators=(",", ":")).encode()
        self.send_response(status)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def do_GET(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        if self.path == "/health":
            self.answer(200, {"ok": True})
        elif self.path == "/counts":
            with LOCK:
                self.answer(200, dict(COUNTS))
        else:
            self.answer(404, {"ok": False})

    def do_POST(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        global NEXT_MESSAGE_ID
        length = int(self.headers.get("content-length", "0"))
        raw = self.rfile.read(min(length, 1_048_576))
        try:
            request = json.loads(raw or b"{}")
        except json.JSONDecodeError:
            self.answer(400, {"ok": False, "description": "invalid synthetic request"})
            return

        method = self.path.rsplit("/", 1)[-1]
        with LOCK:
            COUNTS[method] = COUNTS.get(method, 0) + 1
            persist()

        if method == "GetMe":
            result = {
                "id": 700100200,
                "is_bot": True,
                "first_name": "Ratatoskr",
                "username": "ratatoskr_test_bot",
                "can_join_groups": True,
                "can_read_all_group_messages": False,
                "supports_inline_queries": False,
                "can_connect_to_business": False,
                "has_main_web_app": False,
            }
        elif method in {"SendMessage", "EditMessageText"}:
            with LOCK:
                if method == "SendMessage":
                    message_id = NEXT_MESSAGE_ID
                    NEXT_MESSAGE_ID += 1
                else:
                    message_id = int(request.get("message_id", 55))
            result = {
                "message_id": message_id,
                "from": {
                    "id": 700100200,
                    "is_bot": True,
                    "first_name": "Ratatoskr",
                    "username": "ratatoskr_test_bot",
                },
                "date": 1787904000,
                "chat": {
                    "id": 900700601,
                    "type": "private",
                    "first_name": "Synthetic",
                },
                "text": "synthetic projection",
            }
        else:
            result = True
        self.answer(200, {"ok": True, "result": result})


STATE.parent.mkdir(parents=True, exist_ok=True)
with LOCK:
    persist()
ThreadingHTTPServer(("0.0.0.0", 18080), Handler).serve_forever()
