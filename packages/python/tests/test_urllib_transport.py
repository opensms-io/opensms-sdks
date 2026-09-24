"""The default ``urllib`` transport against a local stdlib HTTP server."""

from __future__ import annotations

import json
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest

from opensms import Opensms, OpensmsError

KEY = "sk_test_" + "A" * 32


class _Handler(BaseHTTPRequestHandler):
    def _handle(self) -> None:
        srv = self.server
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length) if length else b""
        srv.seen.append({"method": self.command, "path": self.path, "headers": dict(self.headers), "body": raw})
        status, headers, body = srv.replies[min(len(srv.seen) - 1, len(srv.replies) - 1)]
        self.send_response(status)
        for k, v in headers.items():
            self.send_header(k, v)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = _handle

    def log_message(self, *args):  # silence the test server
        pass


@pytest.fixture
def server():
    srv = HTTPServer(("127.0.0.1", 0), _Handler)
    srv.seen = []
    srv.replies = []
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    yield srv
    srv.shutdown()
    srv.server_close()


def client_for(srv, **kw):
    return Opensms(KEY, base_url=f"http://127.0.0.1:{srv.server_address[1]}/", sleep=lambda s: None, **kw)


def test_json_roundtrip_and_headers(server):
    server.replies = [(201, {"Content-Type": "application/json"}, b'{"id":"m1","price":"0.000000"}')]
    out = client_for(server).messages.send(to="+254700000012", text="hi")
    assert out == {"id": "m1", "price": "0.000000"}
    seen = server.seen[0]
    assert seen["path"] == "/v1/messages"
    assert seen["headers"]["Authorization"] == f"Bearer {KEY}"
    assert seen["headers"]["Content-Type"] == "application/json"
    assert len(seen["headers"]["Idempotency-Key"]) == 36
    assert json.loads(seen["body"]) == {"to": "+254700000012", "text": "hi"}


def test_204_and_problem_with_retry(server):
    problem = b'{"type":"about:blank","title":"Service Unavailable","status":503,"detail":"database unavailable"}'
    server.replies = [
        (503, {"Content-Type": "application/problem+json", "Retry-After": "0"}, problem),
        (204, {}, b""),
    ]
    assert client_for(server).contacts.delete("c1") is None
    assert [s["method"] for s in server.seen] == ["DELETE", "DELETE"]


def test_error_mapping_over_http(server):
    server.replies = [(422, {"Content-Type": "application/problem+json", "X-Request-ID": "r9"},
                       b'{"type":"about:blank","title":"Unprocessable Entity","status":422,"detail":"destination is suppressed"}')]
    with pytest.raises(OpensmsError) as info:
        client_for(server).messages.send(to="+254700000012", text="hi")
    assert info.value.status == 422
    assert info.value.detail == "destination is suppressed"
    assert info.value.request_id == "r9"
    assert len(server.seen) == 1


def test_connection_refused_is_status_zero():
    srv = HTTPServer(("127.0.0.1", 0), _Handler)
    port = srv.server_address[1]
    srv.server_close()
    client = Opensms(KEY, base_url=f"http://127.0.0.1:{port}", max_retries=1, sleep=lambda s: None, timeout=5)
    with pytest.raises(OpensmsError) as info:
        client.messages.get("m1")
    assert info.value.status == 0
