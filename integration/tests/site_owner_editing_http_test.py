#!/usr/bin/env python3
"""Fault tests for the integration client's real HTTP transport, not service acceptance."""
import importlib.util
import json
import os
from pathlib import Path
import sys
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from unittest.mock import patch


class ClientBackoff(unittest.TestCase):
    def setUp(self):
        self.responses = []
        self.requests = []
        case = self

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                self.reply()

            def do_POST(self):
                self.reply()

            def reply(self):
                data = self.rfile.read(int(self.headers.get('Content-Length', '0')))
                case.requests.append((data, self.headers.get('Idempotency-Key')))
                status, retry = case.responses.pop(0)
                self.send_response(status)
                if retry is not None:
                    self.send_header('Retry-After', retry)
                self.end_headers()
                self.wfile.write(json.dumps({'status': status}).encode())

            def log_message(self, *args):
                pass

        self.server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        source = Path(__file__).resolve().parents[1] / 'fixtures/site-owner-editing.py'
        spec = importlib.util.spec_from_file_location('scenario_http_test', source)
        self.client = importlib.util.module_from_spec(spec)
        with patch.object(sys, 'argv', [str(source), 'test-http', 'test-profile']), patch.dict(os.environ, {
            'RATATOSKR_SITE027_URL': f'http://127.0.0.1:{self.server.server_port}',
            'RATATOSKR_EVIDENCE_DIR': '/tmp/ratatoskr-http-unit',
        }):
            spec.loader.exec_module(self.client)
        self.sleep = patch.object(self.client.time, 'sleep').start()
        self.addCleanup(patch.stopall)

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()

    def test_retry_after_keeps_write_identity(self):
        self.responses = [(429, '7'), (200, None)]
        self.assertEqual(self.client.call('/write', 'POST', {'value': 1}), {'status': 200})
        self.sleep.assert_called_once_with(7)
        self.assertEqual(self.requests[0], self.requests[1])
        self.assertIsNotNone(self.requests[0][1])

    def test_absent_or_invalid_retry_after_waits_one_second(self):
        for header in [None, 'invalid', '0', '-1']:
            with self.subTest(header=header):
                self.responses = [(429, header), (200, None)]
                self.sleep.reset_mock()
                self.assertEqual(self.client.call('/poll'), {'status': 200})
                self.sleep.assert_called_once_with(1)

    def test_persistent_limit_has_four_attempts(self):
        self.responses = [(429, None)] * 4
        with self.assertRaises(AssertionError):
            self.client.call('/poll')
        self.assertEqual(len(self.requests), 4)
        self.assertEqual(self.sleep.call_count, 3)

    def test_delay_beyond_total_budget_does_not_retry_early(self):
        self.responses = [(429, '151')]
        with self.assertRaisesRegex(AssertionError, 'retry budget'):
            self.client.call('/poll')
        self.sleep.assert_not_called()
        self.assertEqual(len(self.requests), 1)

    def test_sse_handshake_recovers_from_rate_limit(self):
        self.responses = [(429, '1'), (200, None)]
        events = self.client.Events()
        try:
            self.assertIsNone(events.error)
            self.sleep.assert_called_once_with(1)
            self.assertEqual(len(self.requests), 2)
        finally:
            events.close()
            events.thread.join(timeout=1)
        self.assertFalse(events.thread.is_alive())

    def test_sse_denial_is_not_a_successful_handshake(self):
        self.responses = [(403, None)]
        with self.assertRaisesRegex(AssertionError, '403'):
            self.client.Events()
        self.sleep.assert_not_called()
        self.assertEqual(len(self.requests), 1)

    def test_expected_limit_and_other_errors_are_not_retried(self):
        self.responses = [(429, '7'), (403, None)]
        self.assertEqual(self.client.call('/limit', expected=(429,)), {'status': 429})
        with self.assertRaises(AssertionError):
            self.client.call('/denied')
        self.sleep.assert_not_called()
        self.assertEqual(len(self.requests), 2)


if __name__ == '__main__':
    unittest.main()
