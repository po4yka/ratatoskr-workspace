"""LOOPBACK FAKE of the Telegram Bot API for flow F3 (the webhook and the dispatcher: RATATOSKR__BOT_API__BASE_URL). Labelled in every result.txt: nothing here is Telegram.

usage: fake_bot_api.py PORT LOGFILE FILESDIR

Answers the methods the Telegram services call (getMe, sendMessage, editMessageText, answerCallbackQuery, getFile and anything else with `result: true`), and serves downloads at /file/bot<token>/<file_path> from FILESDIR. Method names are matched case-insensitively. Every call is appended to LOGFILE as one JSON line {seq, method, request} with the bot token removed from the path, so a flow reads the replies in order and can show that an unsupported attachment produced exactly the static body."""
import http.server
import json
import os
import sys
import threading

PORT, LOG, FILES = int(sys.argv[1]), sys.argv[2], sys.argv[3]
LOCK = threading.Lock()
SEQ = [0]
MESSAGE_ID = [100]
BOT = {"id": 700100200, "is_bot": True, "first_name": "Ratatoskr", "username": "ratatoskr_smoke_bot", "can_join_groups": True, "can_read_all_group_messages": False, "supports_inline_queries": False, "can_connect_to_business": False, "has_main_web_app": False}


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def answer(self, status: int, body, raw: bool = False) -> None:
        data = body if raw else json.dumps(body, separators=(",", ":")).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/octet-stream" if raw else "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/health":
            return self.answer(200, {"ok": True})
        parts = self.path.split("/")
        if len(parts) >= 4 and parts[1] == "file":
            path = os.path.join(FILES, *parts[3:])
            if os.path.isfile(path):
                with open(path, "rb") as handle:
                    return self.answer(200, handle.read(), raw=True)
            return self.answer(404, {"ok": False, "description": "file not found"})
        return self.handle_method(parts[-1], {})

    def do_POST(self):
        length = int(self.headers.get("content-length", 0))
        raw = self.rfile.read(min(length, 1_048_576))
        try:
            request = json.loads(raw or b"{}")
        except json.JSONDecodeError:
            return self.answer(400, {"ok": False, "description": "invalid request"})
        return self.handle_method(self.path.rsplit("/", 1)[-1], request)

    def handle_method(self, method: str, request: dict) -> None:
        lowered = method.lower()
        with LOCK:
            SEQ[0] += 1
            with open(LOG, "a", encoding="utf-8") as handle:
                handle.write(json.dumps({"seq": SEQ[0], "method": method, "request": request}) + "\n")
            if lowered in ("sendmessage", "editmessagetext"):
                MESSAGE_ID[0] += lowered == "sendmessage"
                message = {"message_id": MESSAGE_ID[0] if lowered == "sendmessage" else int(request.get("message_id", MESSAGE_ID[0])),
                           "from": BOT, "date": 1787904000, "chat": {"id": int(request.get("chat_id", 900700601)), "type": "private", "first_name": "Synthetic"}, "text": str(request.get("text", ""))[:200]}
                return self.answer(200, {"ok": True, "result": message})
        if lowered == "getme":
            return self.answer(200, {"ok": True, "result": BOT})
        if lowered == "getfile":
            file_id = str(request.get("file_id", ""))
            known = os.path.join(FILES, file_id)
            if os.path.isfile(known):
                return self.answer(200, {"ok": True, "result": {"file_id": file_id, "file_unique_id": file_id, "file_size": os.path.getsize(known), "file_path": file_id}})
            return self.answer(400, {"ok": False, "error_code": 400, "description": "Bad Request: file not found"})
        return self.answer(200, {"ok": True, "result": True})


http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
