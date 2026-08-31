#!/usr/bin/env python3
"""Task-only HTTP fixtures for KNO-018 composed acceptance."""

import argparse
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


ARTICLE = b"""<!doctype html><html><head><title>Durable Knowledge</title></head>
<body><article><h1>Durable Knowledge</h1>
<p>Ratatoskr turns an extracted document into durable, searchable analysis.</p>
<p>This deterministic source has enough grounded content for the real Extractor quality gate.</p>
</article></body></html>"""


def provider_content(request):
    messages = request.get("messages", [])
    source = "\n".join(str(message.get("content", "")) for message in messages)
    if "family: social" in source:
        return {
            "summary": "Useful Ratatoskr post.",
            "topics": ["ratatoskr"],
            "evidence_excerpt": "useful Ratatoskr post",
            "confidence": "grounded",
        }
    if "family: ai_archive" in source:
        return {
            "summary": "The archive records a durable decision.",
            "summary_message_ids": ["msg-kno018"],
            "decisions": [{"text": "Keep durable evidence.", "message_id": "msg-kno018"}],
        }
    if "family: repository" in source:
        return {
            "summary": "A durable Ratatoskr repository.",
            "topics": ["rust"],
            "evidence_excerpt": "Durable Ratatoskr repository",
            "readme_evidence": "present",
        }
    return {
        "summary": "Ratatoskr turns an extracted document into durable analysis.",
        "key_points": [
            {
                "text": "The document describes durable searchable analysis.",
                "source_block_indexes": [0],
            }
        ],
    }


class Handler(BaseHTTPRequestHandler):
    mode = "provider"

    def log_message(self, _format, *_args):
        return

    def do_GET(self):
        if self.path == "/health":
            self.reply(200, b'{"ready":true}', "application/json")
        elif self.mode == "provider" and self.path == "/v1/key":
            self.reply(200, b'{"fixture":true}', "application/json")
        elif self.mode == "source" and self.path == "/article":
            self.reply(200, ARTICLE, "text/html; charset=utf-8")
        else:
            self.reply(404, b"", "text/plain")

    def do_POST(self):
        if self.mode != "provider" or self.path != "/v1/chat/completions":
            self.reply(404, b"", "text/plain")
            return
        try:
            length = int(self.headers.get("content-length", "0"))
            request = json.loads(self.rfile.read(length))
            content = json.dumps(provider_content(request), separators=(",", ":"))
            response = {
                "id": "kno018-scripted-request",
                "choices": [{"message": {"role": "assistant", "content": content}}],
                "usage": {"prompt_tokens": 10, "completion_tokens": 10},
            }
            self.reply(
                200,
                json.dumps(response, separators=(",", ":")).encode(),
                "application/json",
            )
        except (ValueError, json.JSONDecodeError):
            self.reply(400, b"", "text/plain")

    def reply(self, status, body, content_type):
        self.send_response(status)
        self.send_header("content-type", content_type)
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=["provider", "source"], required=True)
    parser.add_argument("--bind", default="0.0.0.0")
    parser.add_argument("--port", type=int, required=True)
    args = parser.parse_args()
    Handler.mode = args.mode
    ThreadingHTTPServer((args.bind, args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
