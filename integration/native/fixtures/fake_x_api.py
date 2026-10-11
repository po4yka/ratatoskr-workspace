"""Loopback HTTPS fake of the X API v2 `GET /2/tweets`. Every request and failed TLS handshake is logged as a JSON line. Labelled in every result.txt: everything it returns is FAKED provider content.

usage: fake_x_api.py PORT CERTCHAIN KEY LOG [DELETED_LIST]

Behaviour by post id: ids ending in 404, or listed in the DELETED_LIST file, answer 200 with a `resource-not-found` problem (a deleted post); ids ending in 401 answer HTTP 401; every other id answers a public post."""
import http.server, json, os, socket, ssl, sys, time, urllib.parse
port, cert, key, log = int(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
DELETED = sys.argv[5] if len(sys.argv) > 5 else "/nonexistent"
def record(kind, **kw):
    with open(log, "a") as f: f.write(json.dumps({"t": time.time(), "kind": kind, **kw}) + "\n")
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def send(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code); self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)
    def do_GET(self):
        u = urllib.parse.urlparse(self.path); q = urllib.parse.parse_qs(u.query)
        auth = self.headers.get("Authorization", "")
        record("request", path=u.path, ids=q.get("ids"), auth_bearer=auth.startswith("Bearer "), accept=self.headers.get("Accept"))
        if u.path != "/2/tweets" or not q.get("ids"):
            return self.send(404, {"errors": [{"title": "not found"}]})
        pid = q["ids"][0]
        if pid.endswith("401"): return self.send(401, {"title": "Unauthorized"})
        deleted = os.path.exists(DELETED) and pid in open(DELETED).read().split()
        if pid.endswith("404") or deleted:
            return self.send(200, {"errors": [{"value": pid, "detail": "Could not find tweet with ids: [%s]." % pid, "title": "Not Found Error", "resource_type": "tweet", "parameter": "ids", "resource_id": pid, "type": "https://api.twitter.com/2/problems/resource-not-found"}]})
        self.send(200, {"data": [{"id": pid, "text": "A fixture post served by the loopback fake X API (FAKED provider content).", "author_id": "42",
              "created_at": "2026-08-16T09:30:00.120Z", "lang": "en"}],
              "includes": {"users": [{"id": "42", "name": "Ada Example", "username": "ada"}]}})
class S(http.server.ThreadingHTTPServer):
    daemon_threads = True
    def get_request(self):
        sock, addr = self.socket.accept()
        try:
            sock.settimeout(5); return self.ctx.wrap_socket(sock, server_side=True), addr
        except (ssl.SSLError, OSError, socket.timeout) as e:
            record("tls_handshake_failed", error=str(e)); sock.close(); raise OSError("handshake failed")
    def handle_error(self, *a): pass
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); ctx.load_cert_chain(cert, key)
srv = S(("127.0.0.1", port), H); srv.ctx = ctx
record("listening", port=port); srv.serve_forever()
