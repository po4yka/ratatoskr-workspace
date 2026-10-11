"""A recording reverse proxy between the Telegram services and Edge, for flow F3. Labelled in result.txt as the one deviation of that flow (RATATOSKR__PLATFORM__BASE_URL points here instead of at Edge): it forwards every request unchanged and answers with Edge's answer, and it records what passed so a flow can show what the webhook sent to Platform.

usage: tap_proxy.py PORT UPSTREAM_PORT LOGFILE

LOGFILE gets one JSON line per exchange: {seq, method, path, request (parsed JSON body or null), status, response_keys}. The Authorization header, assertions, credentials and response bodies are never recorded; only the keys of a JSON response are."""
import http.client
import http.server
import json
import sys
import threading

PORT, UPSTREAM, LOG = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
LOCK = threading.Lock()
SEQ = [0]
HOP_BY_HOP = {"connection", "keep-alive", "proxy-authenticate", "proxy-authorization", "te", "trailers", "transfer-encoding", "upgrade", "host", "content-length"}


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def forward(self):
        length = int(self.headers.get("content-length", 0))
        body = self.rfile.read(length) if length else b""
        headers = {k: v for k, v in self.headers.items() if k.lower() not in HOP_BY_HOP}
        connection = http.client.HTTPConnection("127.0.0.1", UPSTREAM, timeout=330)
        try:
            connection.request(self.command, self.path, body=body or None, headers=headers)
            response = connection.getresponse()
            data = response.read()
            status = response.status
            response_headers = [(k, v) for k, v in response.getheaders() if k.lower() not in HOP_BY_HOP]
        except OSError as error:
            status, data, response_headers = 502, json.dumps({"error": type(error).__name__}).encode(), [("Content-Type", "application/json")]
        finally:
            connection.close()
        try:
            parsed = json.loads(body) if body else None
        except json.JSONDecodeError:
            parsed = None
        if isinstance(parsed, dict):
            for secret_key in ("assertion", "credential"):
                if secret_key in parsed:
                    parsed[secret_key] = "[redacted]"
        try:
            keys = sorted(json.loads(data)) if data else []
        except (json.JSONDecodeError, TypeError):
            keys = []
        with LOCK:
            SEQ[0] += 1
            with open(LOG, "a", encoding="utf-8") as handle:
                handle.write(json.dumps({"seq": SEQ[0], "method": self.command, "path": self.path, "request": parsed, "status": status, "response_keys": keys}) + "\n")
        self.send_response(status)
        for key, value in response_headers:
            self.send_header(key, value)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    do_GET = do_POST = do_PUT = do_DELETE = do_PATCH = forward


http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
