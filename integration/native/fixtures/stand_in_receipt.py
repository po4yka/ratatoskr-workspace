"""LOOPBACK STAND-IN for the Claude receipt listener (port 8097), used by flow F1 to show how Edge reports a receiver that answers 401 (R3-03: Edge relays 502 edge.upstream_invalid_response and device pairing keeps working). usage: stand_in_receipt.py PORT. It answers every request with 401 and an empty JSON object. Labelled in result.txt; it is not the Claude receiver."""
import http.server
import sys


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def respond(self):
        length = int(self.headers.get("content-length", 0))
        self.rfile.read(length)
        self.send_response(401)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", "2")
        self.end_headers()
        self.wfile.write(b"{}")

    do_GET = do_POST = do_PUT = respond


http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
