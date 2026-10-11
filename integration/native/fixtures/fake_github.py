"""LOOPBACK FAKE of the GitHub REST API for flow F7 (GitHub: RATATOSKR__PROVIDER__BASE_URL). Labelled in every result.txt: everything it returns is FAKED provider content.

usage: fake_github.py PORT LOGFILE RUNDIR

Serves GET /repos/{owner}/{name} (the fields the catalog parses: id, full_name, description, language, stargazers_count, topics, default_branch, pushed_at, with an ETag so an unchanged poll answers 304) and GET /repos/{owner}/{name}/readme (raw text). Control files under RUNDIR change its behaviour while a flow runs: github-description holds the description to serve (a change is what makes the observer queue a second analysis request), and github-stall makes every answer wait 20 seconds (a stalled provider, to show that the catalog's calls are bounded). Every request is appended to LOGFILE as one JSON line without credentials."""
import hashlib
import http.server
import json
import os
import re
import sys
import time

PORT, LOG, RUNDIR = int(sys.argv[1]), sys.argv[2], sys.argv[3]


def control(name: str, default: str = "") -> str:
    try:
        return open(os.path.join(RUNDIR, name), encoding="utf-8").read().strip()
    except OSError:
        return default


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def reply(self, status: int, body: bytes, content_type: str, etag: str | None = None) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        if etag:
            self.send_header("ETag", etag)
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        with open(LOG, "a", encoding="utf-8") as handle:
            handle.write(json.dumps({"t": time.time(), "path": self.path, "auth": "present" if self.headers.get("authorization") else "absent", "accept": self.headers.get("accept")}) + "\n")
        if control("github-stall"):
            time.sleep(20)
        match = re.fullmatch(r"/repos/([^/]+)/([^/]+)(/readme)?", self.path.split("?")[0])
        if self.path == "/user":
            return self.reply(200, b'{"login":"smoke"}', "application/json")
        if not match:
            return self.reply(404, b'{"message":"Not Found"}', "application/json")
        owner, name, readme = match.group(1), match.group(2), match.group(3)
        description = control("github-description", "A synthetic repository served by the loopback fake GitHub API")
        if readme:
            text = f"# {name}\n\n{description}\n\nSynthetic README text from the loopback fake GitHub API.\n".encode()
            etag = '"' + hashlib.sha256(text).hexdigest()[:16] + '"'
            if self.headers.get("if-none-match") == etag:
                return self.reply(304, b"", "text/plain", etag)
            return self.reply(200, text, "text/plain", etag)
        body = {
            "id": 42 if (owner, name) == ("owner", "repository") else 1000000 + int(hashlib.sha256(f"{owner}/{name}".encode()).hexdigest()[:6], 16),
            "full_name": f"{owner}/{name}",
            "description": description,
            "language": "Rust",
            "stargazers_count": 7,
            "topics": ["smoke"],
            "default_branch": "main",
            "pushed_at": "2026-08-01T00:00:00Z",
        }
        raw = json.dumps(body).encode()
        etag = '"' + hashlib.sha256(raw).hexdigest()[:16] + '"'
        if self.headers.get("if-none-match") == etag:
            return self.reply(304, b"", "application/json", etag)
        return self.reply(200, raw, "application/json", etag)


http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
