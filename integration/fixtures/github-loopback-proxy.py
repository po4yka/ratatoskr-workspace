#!/usr/bin/env python3
"""Expose only the composed fixture ports while GitHub keeps strict loopback binds."""

import socket
import socketserver
import threading


def copy(source: socket.socket, destination: socket.socket) -> None:
    try:
        while chunk := source.recv(65536):
            destination.sendall(chunk)
    finally:
        try:
            destination.shutdown(socket.SHUT_WR)
        except OSError:
            pass


class Proxy(socketserver.BaseRequestHandler):
    def handle(self) -> None:
        upstream_port = self.server.upstream_port  # type: ignore[attr-defined]
        with socket.create_connection(("127.0.0.1", upstream_port), timeout=5) as upstream:
            outgoing = threading.Thread(target=copy, args=(self.request, upstream), daemon=True)
            outgoing.start()
            copy(upstream, self.request)
            outgoing.join(timeout=5)


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True

    def __init__(self, listen_port: int, upstream_port: int) -> None:
        super().__init__(("0.0.0.0", listen_port), Proxy)
        self.upstream_port = upstream_port


servers = [Server(8092, 18092), Server(9469, 19469)]
threading.Thread(target=servers[0].serve_forever, daemon=True).start()
servers[1].serve_forever()
