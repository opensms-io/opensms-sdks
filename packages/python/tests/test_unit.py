"""Offline unit tests: the client is driven through an injected mock transport
and a zero-delay sleeper (CONFORMANCE.md "Mock-transport unit tests")."""

from __future__ import annotations

import json
import re
from typing import Any, Dict, List, Optional, Union
from urllib.parse import parse_qs, urlsplit

import pytest

from opensms import (
    Opensms,
    OpensmsError,
    TransportRequest,
    TransportResponse,
    __version__,
    construct_event,
    verify_signature,
)

KEY = "sk_test_" + "A" * 32
LIVE_KEY = "sk_live_" + "B" * 32
UUID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")

Canned = Union[TransportResponse, BaseException]


def resp(status: int, body: Any = None, headers: Optional[Dict[str, str]] = None) -> TransportResponse:
    if body is None:
        raw = b""
    elif isinstance(body, (bytes, str)):
        raw = body.encode() if isinstance(body, str) else body
    else:
        raw = json.dumps(body).encode()
    hdrs = {"Content-Type": "application/json"} if raw else {}
    hdrs.update(headers or {})
    return TransportResponse(status, hdrs, raw)


def problem(status: int, detail: str, **extra: Any) -> TransportResponse:
    headers = extra.pop("headers", {})
    body = {"type": "about:blank", "title": "Error", "status": status, "detail": detail}
    body.update(extra)
    return resp(status, body, {"Content-Type": "application/problem+json", **headers})


class MockTransport:
    """Records requests and replays canned responses (the last one repeats)."""

    def __init__(self, *responses: Canned) -> None:
        self.responses: List[Canned] = list(responses) or [resp(200, {})]
        self.requests: List[TransportRequest] = []

    def __call__(self, request: TransportRequest) -> TransportResponse:
        self.requests.append(request)
        index = min(len(self.requests) - 1, len(self.responses) - 1)
        out = self.responses[index]
        if isinstance(out, BaseException):
            raise out
        return out

    @property
    def last(self) -> TransportRequest:
        return self.requests[-1]


class Sleeper:
    def __init__(self) -> None:
        self.delays: List[float] = []

    def __call__(self, seconds: float) -> None:
        self.delays.append(seconds)


def make(*responses: Canned, **kwargs: Any):
    transport = MockTransport(*responses)
    sleeper = Sleeper()
    kwargs.setdefault("base_url", "http://host")
    client = Opensms(KEY, transport=transport, sleep=sleeper, **kwargs)
    return client, transport, sleeper


def header(req: TransportRequest, name: str) -> Optional[str]:
    for key, value in req.headers.items():
        if key.lower() == name.lower():
            return value
    return None


def body_of(req: TransportRequest) -> Any:
    return json.loads(req.body.decode()) if req.body else None


def query_of(req: TransportRequest) -> Dict[str, List[str]]:
    return parse_qs(urlsplit(req.url).query, keep_blank_values=True)


MESSAGE = {"id": "7f1c1d2e-0000-4000-8000-000000000001", "status": "queued", "price": "0.000000"}


# 1. Header injection
def test_headers_are_injected_and_workspace_headers_never_sent():
    client, t, _ = make(resp(201, MESSAGE), resp(200, MESSAGE))
    client.messages.send(to="+254700000012", text="hi")
    client.messages.get(MESSAGE["id"])
    for req in t.requests:
        assert header(req, "Authorization") == f"Bearer {KEY}"
        assert header(req, "Accept") == "application/json"
        assert header(req, "User-Agent") == f"opensms-python/{__version__}"
        assert header(req, "X-Workspace-ID") is None
        assert header(req, "X-Environment") is None
    assert header(t.requests[0], "Content-Type") == "application/json"
    assert header(t.requests[1], "Content-Type") is None
    assert __version__ == "0.1.1"


# 2. Base URL
def test_default_base_url():
    t = MockTransport(resp(200, {"items": [], "next_cursor": None}))
    client = Opensms(KEY, transport=t)
    client.messages.list()
    assert t.last.url == "https://opensms.io/v1/messages"
    assert client.base_url == "https://opensms.io"


def test_custom_base_url_trailing_slash_is_stripped():
    client, t, _ = make(resp(201, MESSAGE), base_url="http://host/")
    client.messages.send(to="+254700000012", text="hi")
    assert t.last.url == "http://host/v1/messages"


# 3. Key validation
@pytest.mark.parametrize("bad", [None, "", "pk_test_x", "sk_test_short", "sk_test_" + "a" * 12, "not_a_key"])
def test_invalid_keys_fail_at_construction(bad):
    t = MockTransport()
    with pytest.raises((ValueError, TypeError)):
        Opensms(bad, transport=t)  # type: ignore[arg-type]
    assert t.requests == []


def test_valid_keys_set_environment():
    assert Opensms(LIVE_KEY).environment == "live"
    assert Opensms(KEY).environment == "sandbox"
    assert Opensms("sk_test_" + "a" * 13).environment == "sandbox"


# 4. Body mapping
def test_send_body_mapping_and_omitted_optionals():
    from datetime import datetime, timezone

    client, t, _ = make(resp(201, MESSAGE), resp(201, MESSAGE))
    client.messages.send(
        to="+254700000012",
        text="hi",
        sender_id="ACME",
        traffic_type="transactional",
        scheduled_at=datetime(2026, 9, 24, 10, 0, tzinfo=timezone.utc),
        callback_url="https://example.com/cb",
        metadata={"order": 1},
    )
    body = body_of(t.requests[0])
    assert set(body) == {"to", "text", "sender_id", "traffic_type", "scheduled_at", "callback_url", "metadata"}
    assert body["scheduled_at"] == "2026-09-24T10:00:00Z"
    client.messages.send(to="+254700000012", text="hi")
    assert body_of(t.requests[1]) == {"to": "+254700000012", "text": "hi"}
    assert b"null" not in t.requests[1].body


def test_other_bodies_use_snake_case():
    client, t, _ = make(resp(200, {}))
    client.otp.verify(otp_id="o1", code="123456")
    assert body_of(t.last) == {"otp_id": "o1", "code": "123456"}
    client.contact_groups.create(name="g", contact_ids=["c1"])
    assert body_of(t.last) == {"name": "g", "contact_ids": ["c1"]}
    client.templates.create(name="n", body="Hi {{name}}", traffic_type="marketing")
    assert body_of(t.last) == {"name": "n", "body": "Hi {{name}}", "traffic_type": "marketing"}
    client.otp.send(to="+254700000012", ttl_seconds=300)
    assert body_of(t.last) == {"to": "+254700000012", "ttl_seconds": 300}
    client.webhooks.update("w1", url="https://x", events=["a"], enabled=False)
    assert t.last.method == "PUT"
    assert body_of(t.last) == {"url": "https://x", "events": ["a"], "enabled": False}
    client.sender_ids.update_draft("d1", version=1, sample_message="x")
    assert body_of(t.last) == {"version": 1, "sample_message": "x"}
    client.suppressions.import_([{"e164": "+254700000001", "reason": "complaint"}])
    assert body_of(t.last) == {"items": [{"e164": "+254700000001", "reason": "complaint"}]}
    getattr(client.suppressions, "import")([{"e164": "+254700000002", "reason": "manual"}])
    assert t.last.url.endswith("/v1/compliance/suppressions/import")


# 5. Idempotency-Key auto
def test_idempotency_key_generated_explicit_and_absent_on_get():
    client, t, _ = make(resp(201, MESSAGE))
    client.messages.send(to="+254700000012", text="hi")
    key = header(t.last, "Idempotency-Key")
    assert key is not None and len(key) == 36 and UUID_RE.match(key)
    client.messages.send(to="+254700000012", text="hi", idempotency_key="my-key-1")
    assert header(t.last, "Idempotency-Key") == "my-key-1"
    client.messages.get("m1")
    assert header(t.last, "Idempotency-Key") is None
    client.otp.verify(otp_id="o", code="1234")
    assert header(t.last, "Idempotency-Key") is None


def test_fresh_key_per_call():
    client, t, _ = make(resp(201, MESSAGE))
    client.messages.send(to="+254700000012", text="hi")
    client.messages.send(to="+254700000012", text="hi")
    assert header(t.requests[0], "Idempotency-Key") != header(t.requests[1], "Idempotency-Key")


# 6. Retry on 429 with Retry-After
def test_retry_on_429_honours_retry_after_and_reuses_key():
    client, t, sleep = make(problem(429, "rate limited", headers={"Retry-After": "2"}), resp(201, MESSAGE))
    out = client.messages.send(to="+254700000012", text="hi")
    assert out["id"] == MESSAGE["id"]
    assert len(t.requests) == 2
    assert sleep.delays == [2.0]
    k1, k2 = (header(r, "Idempotency-Key") for r in t.requests)
    assert k1 == k2 and k1 is not None


def test_retry_after_http_date():
    from email.utils import formatdate
    import time

    date = formatdate(time.time() + 3, usegmt=True)
    client, t, sleep = make(problem(503, "x", headers={"Retry-After": date}), resp(200, MESSAGE))
    client.messages.get("m1")
    assert len(t.requests) == 2
    assert 0 <= sleep.delays[0] <= 4


# 7. Retry on 503 without Retry-After
def test_retry_on_503_uses_jittered_backoff():
    client, t, sleep = make(problem(503, "database unavailable"), resp(200, MESSAGE))
    assert client.messages.get("m1")["id"] == MESSAGE["id"]
    assert len(t.requests) == 2
    assert len(sleep.delays) == 1 and 0 <= sleep.delays[0] <= 0.5


def test_backoff_grows_and_is_capped():
    from opensms._transport import HttpTransport

    for n, ceiling in [(1, 0.5), (2, 1.0), (3, 2.0), (5, 8.0), (9, 8.0)]:
        for _ in range(50):
            assert 0 <= HttpTransport._backoff(n) <= ceiling


# 8. Retries exhausted
def test_retries_exhausted_raises_last_error():
    client, t, sleep = make(problem(500, "boom"), max_retries=2)
    with pytest.raises(OpensmsError) as info:
        client.messages.get("m1")
    assert info.value.status == 500
    assert len(t.requests) == 3
    assert len(sleep.delays) == 2


def test_max_retries_zero_disables_retries():
    client, t, _ = make(problem(503, "x"), max_retries=0)
    with pytest.raises(OpensmsError):
        client.messages.get("m1")
    assert len(t.requests) == 1


# 9. Retry-After too large
def test_retry_after_above_60_is_not_waited_for():
    client, t, sleep = make(problem(429, "slow down", headers={"Retry-After": "120"}), resp(201, MESSAGE))
    with pytest.raises(OpensmsError) as info:
        client.messages.send(to="+254700000012", text="hi")
    assert info.value.status == 429
    assert info.value.retry_after == 120
    assert len(t.requests) == 1
    assert sleep.delays == []


# 10. No retry on client errors
@pytest.mark.parametrize("status", [400, 401, 402, 403, 404, 409, 410, 413, 422])
def test_no_retry_on_4xx(status):
    client, t, _ = make(problem(status, "nope"), resp(201, MESSAGE))
    with pytest.raises(OpensmsError) as info:
        client.messages.send(to="+254700000012", text="hi")
    assert info.value.status == status
    assert len(t.requests) == 1


# 11. No retry for non-idempotent POSTs
@pytest.mark.parametrize(
    "call",
    [
        lambda c: c.otp.verify(otp_id="o1", code="123456"),
        lambda c: c.messages.cancel("m1"),
        lambda c: c.suppressions.create(e164="+254700000001", reason="manual"),
        lambda c: c.suppressions.import_([{"e164": "+254700000001", "reason": "manual"}]),
        lambda c: c.sender_ids.create(value="ACME", kind="alphanumeric", countries=["KE"], documents=[]),
        lambda c: c.sender_ids.create_draft(source="application"),
    ],
)
def test_non_idempotent_posts_are_not_retried(call):
    client, t, _ = make(problem(503, "unavailable"), resp(200, {}))
    with pytest.raises(OpensmsError) as info:
        call(client)
    assert info.value.status == 503
    assert len(t.requests) == 1
    assert header(t.last, "Idempotency-Key") is None


def test_idempotent_non_get_verbs_are_retried():
    client, t, _ = make(problem(502, "x"), resp(200, {"id": "c1"}))
    client.contacts.update("c1", name="x")
    assert len(t.requests) == 2
    client, t, _ = make(problem(504, "x"), resp(204))
    client.contacts.delete("c1")
    assert len(t.requests) == 2


# 12. Network error
def test_network_errors_are_retried_on_get():
    client, t, sleep = make(ConnectionResetError("reset"), TimeoutError("timed out"), resp(200, MESSAGE))
    assert client.messages.get("m1")["id"] == MESSAGE["id"]
    assert len(t.requests) == 3
    assert len(sleep.delays) == 2


def test_persistent_network_error_becomes_status_zero():
    client, t, _ = make(ConnectionRefusedError("refused"))
    with pytest.raises(OpensmsError) as info:
        client.messages.get("m1")
    assert info.value.status == 0
    assert len(t.requests) == 3


def test_network_error_on_non_idempotent_post_not_retried():
    client, t, _ = make(ConnectionResetError("reset"), resp(200, {}))
    with pytest.raises(OpensmsError) as info:
        client.otp.verify(otp_id="o", code="1234")
    assert info.value.status == 0
    assert len(t.requests) == 1


# 13. Error mapping
def test_problem_json_is_mapped():
    body = {
        "type": "https://api.opensms.io/problems/invalid_message_id",
        "title": "Bad Request",
        "status": 400,
        "detail": "Message ID must be a valid UUID.",
        "code": "invalid_message_id",
        "trace_id": "t1",
        "errors": {"to": ["bad"]},
        "extra": "kept",
    }
    client, _, _ = make(resp(400, body, {"Content-Type": "application/problem+json"}))
    with pytest.raises(OpensmsError) as info:
        client.messages.get("x")
    e = info.value
    assert e.status == 400
    assert e.type == "https://api.opensms.io/problems/invalid_message_id"
    assert e.title == "Bad Request"
    assert e.detail == "Message ID must be a valid UUID."
    assert e.code == "invalid_message_id"
    assert e.trace_id == "t1"
    assert e.errors == {"to": ["bad"]}
    assert str(e) == e.detail == e.message
    assert e.body["extra"] == "kept"


def test_about_blank_has_no_code():
    client, _, _ = make(problem(404, "message not found", title="Not Found"))
    with pytest.raises(OpensmsError) as info:
        client.messages.get("x")
    assert info.value.code is None
    assert info.value.type == "about:blank"
    assert info.value.request_id is None


def test_request_id_header_is_surfaced():
    client, _, _ = make(problem(422, "destination is suppressed", headers={"X-Request-ID": "r1"}))
    with pytest.raises(OpensmsError) as info:
        client.messages.send(to="+254700000012", text="x")
    assert info.value.request_id == "r1"


def test_html_error_body():
    html = "<html><body>Bad gateway</body></html>"
    client, _, _ = make(TransportResponse(502, {"Content-Type": "text/html"}, html.encode()), max_retries=0)
    with pytest.raises(OpensmsError) as info:
        client.messages.get("x")
    e = info.value
    assert e.status == 502
    assert e.detail is None and e.title is None and e.code is None
    assert e.body == html
    assert str(e) == "OpenSMS request failed with status 502"


def test_title_used_when_no_detail():
    client, _, _ = make(resp(403, {"type": "about:blank", "title": "Forbidden", "status": 403}))
    with pytest.raises(OpensmsError) as info:
        client.contacts.list()
    assert str(info.value) == "Forbidden"


# 14. 204 handling
def test_204_returns_none_without_parsing():
    client, t, _ = make(TransportResponse(204, {}, b""))
    assert client.contacts.delete("c1") is None
    assert t.last.method == "DELETE"
    assert t.last.url == "http://host/v1/contacts/c1"


# 15. Pagination
def test_paginate_follows_cursor():
    a, b, c = {"id": "a"}, {"id": "b"}, {"id": "c"}
    client, t, _ = make(
        resp(200, {"items": [a, b], "next_cursor": "c1"}),
        resp(200, {"items": [c], "next_cursor": None}),
    )
    items = list(client.paginate(client.messages.list, limit=2))
    assert [i["id"] for i in items] == ["a", "b", "c"]
    assert len(t.requests) == 2
    q1, q2 = query_of(t.requests[0]), query_of(t.requests[1])
    assert q1 == {"limit": ["2"]}
    assert q2 == {"limit": ["2"], "cursor": ["c1"]}


def test_paginate_is_lazy_and_supports_id_lists():
    client, t, _ = make(resp(200, {"items": [{"id": "x"}, {"id": "y"}], "next_cursor": "n"}))
    it = client.paginate(client.batches.list_items, "b1", limit=2)
    assert t.requests == []
    assert next(it)["id"] == "x"
    assert t.last.url.startswith("http://host/v1/batches/b1/items?")


def test_page_object():
    client, _, _ = make(resp(200, {"items": [{"id": "a"}], "next_cursor": "c2"}))
    page = client.contacts.list(limit=1)
    assert len(page) == 1 and page.items[0]["id"] == "a"
    assert page.next_cursor == "c2" and page.has_more
    assert [x["id"] for x in page] == ["a"]


# 16. Query encoding
def test_query_encoding():
    client, t, _ = make(resp(200, {"quote_id": "sq_1"}))
    client.sender_ids.quote(countries=["KE", "NG"])
    assert t.last.url == "http://host/v1/sender-ids/quote?countries=KE,NG"
    client, t, _ = make(resp(200, {"items": [], "next_cursor": None}))
    client.messages.list(status="delivered", to="+2547")
    assert t.last.url == "http://host/v1/messages?status=delivered&to=%2B2547"
    client.messages.list()
    assert t.last.url == "http://host/v1/messages"


def test_analytics_from_and_wallet_ledger_query():
    from datetime import datetime, timezone

    client, t, _ = make(resp(200, {"data": [{"id": 1}]}))
    client.analytics.overview(from_=datetime(2026, 9, 1, tzinfo=timezone.utc), to="2026-09-24")
    assert query_of(t.last) == {"from": ["2026-09-01T00:00:00Z"], "to": ["2026-09-24"]}
    entries = client.wallet.ledger(limit=1, before=10)
    assert entries == [{"id": 1}]
    assert query_of(t.last) == {"limit": ["1"], "before": ["10"]}


# 17. Path escaping
def test_path_escaping():
    client, t, _ = make(resp(200, MESSAGE))
    client.messages.get("a/b")
    assert t.last.url == "http://host/v1/messages/a%2Fb"
    client.webhooks.replay_delivery("w 1", 42, generation=1, reason="because")
    assert t.last.url == "http://host/v1/webhooks/w%201/deliveries/42/replay"


@pytest.mark.parametrize("bad", ["", "  ", None])
def test_empty_ids_rejected_without_request(bad):
    client, t, _ = make()
    with pytest.raises(ValueError):
        client.messages.get(bad)  # type: ignore[arg-type]
    assert t.requests == []


# 18. Webhook signature vector (DESIGN.md)
SECRET = "whsec_c2RrLWNvbmZvcm1hbmNlLXRlc3QtdmVjdG9yLTAwMDE"
TS = 1790208000
BODY = (
    '{"id":"evt_01","type":"message.delivered","workspace_id":"00000000-0000-0000-0000-000000000001",'
    '"environment":"sandbox","created_at":"2026-09-24T00:00:00Z",'
    '"data":{"id":"00000000-0000-0000-0000-000000000002","status":"delivered"}}'
)
DIGEST = "eeb2ec420dd348b253dae35c1f3bce03d261109eb8788e3ad836072e894fac23"
HEADER = f"t={TS},v1={DIGEST}"


def test_vector_body_is_230_bytes():
    assert len(BODY.encode()) == 230


@pytest.mark.parametrize(
    "payload,header,secret,now,valid",
    [
        (BODY, HEADER, SECRET, TS, True),
        (BODY, HEADER, SECRET, TS + 300, True),
        (BODY, HEADER, SECRET, TS + 301, False),
        (BODY, HEADER, SECRET, TS - 301, False),
        (BODY.replace('"status":"delivered"', '"status":"failed"'), HEADER, SECRET, TS, False),
        (BODY, HEADER, SECRET[len("whsec_"):], TS, False),
        (BODY, f"v1={DIGEST},t={TS}", SECRET, TS, True),
        (BODY, HEADER + ",v0=abc", SECRET, TS, False),
        (BODY, f"t={TS}", SECRET, TS, False),
        (BODY, f"t={TS},v1={DIGEST.upper()}", SECRET, TS, True),
        (BODY, HEADER, "", TS, False),
        (BODY, "", SECRET, TS, False),
        (BODY, f"t={TS},t={TS},v1={DIGEST}", SECRET, TS, False),
        (BODY, f"t=abc,v1={DIGEST}", SECRET, TS, False),
        (BODY, f"t={TS},v1={DIGEST[:-2]}", SECRET, TS, False),
    ],
)
def test_signature_vector(payload, header, secret, now, valid):
    assert verify_signature(payload, header, secret, now=now) is valid
    assert verify_signature(payload.encode(), header, secret, now=now) is valid


def test_construct_event():
    client, _, _ = make()
    event = construct_event(BODY.encode(), HEADER, SECRET, now=TS)
    assert event["type"] == "message.delivered"
    assert event["data"]["status"] == "delivered"
    assert client.webhooks.construct_event(BODY, HEADER, SECRET, now=TS)["id"] == "evt_01"
    assert client.webhooks.verify_signature(BODY, HEADER, SECRET, now=TS)

    tampered = BODY.replace('"status":"delivered"', '"status":"failed"')
    with pytest.raises(OpensmsError) as info:
        construct_event(tampered, HEADER, SECRET, now=TS)
    assert info.value.code == "invalid_signature" and info.value.status == 0

    with pytest.raises(OpensmsError) as info:
        construct_event(BODY, HEADER, SECRET, now=TS + 301)
    assert info.value.code == "expired_signature" and info.value.status == 0


def test_custom_tolerance():
    assert verify_signature(BODY, HEADER, SECRET, now=TS + 500, tolerance_seconds=600)
    assert not verify_signature(BODY, HEADER, SECRET, now=TS + 61, tolerance_seconds=60)


# 19. Batch CSV
def test_create_from_csv_posts_text_csv():
    client, t, _ = make(resp(202, {"id": "b1", "status": "ready"}))
    csv = "to,text\n+254700000014,csv run\n"
    out = client.batches.create_from_csv(csv)
    assert out["status"] == "ready"
    assert t.last.method == "POST" and t.last.url == "http://host/v1/messages/batch"
    assert header(t.last, "Content-Type") == "text/csv"
    assert t.last.body == csv.encode()
    assert UUID_RE.match(header(t.last, "Idempotency-Key") or "")


def test_create_from_csv_with_dedupe_uses_multipart():
    client, t, _ = make(resp(202, {"id": "b1"}))
    client.batches.create_from_csv(b"to,text\n+254700000014,x\n", dedupe=False)
    ctype = header(t.last, "Content-Type") or ""
    assert ctype.startswith("multipart/form-data; boundary=")
    assert b'name="dedupe"\r\n\r\nfalse' in t.last.body
    assert b"+254700000014,x" in t.last.body


def test_batch_create_json():
    client, t, _ = make(resp(202, {"id": "b1"}))
    client.batches.create(items=[{"to": "+254700000012", "text": "a", "sender_id": None}], dedupe=False)
    assert body_of(t.last) == {"items": [{"to": "+254700000012", "text": "a"}], "dedupe": False}
    assert header(t.last, "Content-Type") == "application/json"


# 20. Decimal strings and unknown fields
def test_decimal_strings_and_unknown_fields():
    client, _, _ = make(resp(200, {**MESSAGE, "price": "0.000000", "brand_new_field": {"x": 1}}))
    msg = client.messages.get(MESSAGE["id"])
    assert msg["price"] == "0.000000" and isinstance(msg["price"], str)


def test_wallet_balances_unwraps_data_and_documents_unwraps_items():
    client, _, _ = make(resp(200, {"data": [{"currency": "KES", "balance": "10.50"}]}))
    assert client.wallet.balances() == [{"currency": "KES", "balance": "10.50"}]
    client, _, _ = make(resp(200, {"items": [{"id": "d1"}]}))
    assert client.sender_ids.list_documents() == [{"id": "d1"}]


def test_every_surface_method_exists():
    client, _, _ = make()
    surface = {
        "messages": ["send", "list", "get", "attempts", "cancel"],
        "batches": ["create", "create_from_csv", "get", "validation", "start", "stop", "list_items"],
        "otp": ["send", "verify"],
        "lookups": ["create", "get"],
        "contacts": ["list", "create", "get", "update", "delete"],
        "contact_groups": ["list", "create", "get", "update", "delete", "send"],
        "templates": ["list", "create", "get", "update", "delete"],
        "webhooks": ["list", "create", "get", "update", "delete", "test", "list_deliveries", "replay_delivery"],
        "inbound": ["list", "reply"],
        "numbers": ["list", "available", "assign", "release", "list_rules", "create_rule", "update_rule", "delete_rule"],
        "sender_ids": [
            "list", "get", "create", "update", "delete", "check", "quote", "list_documents",
            "list_drafts", "create_draft", "get_draft", "update_draft", "delete_draft",
        ],
        "suppressions": ["list", "create", "import_", "delete"],
        "compliance": ["list_countries", "get_country", "list_content_rules"],
        "wallet": ["balances", "ledger", "create_topup"],
        "pricing": ["get"],
        "analytics": ["overview", "by_country", "by_carrier", "by_sender_id", "timeseries"],
        "sandbox": ["list_messages"],
        "countries": ["list", "carriers", "routes", "compliance"],
    }
    count = 0
    for resource, methods in surface.items():
        for method in methods:
            assert callable(getattr(getattr(client, resource), method)), f"{resource}.{method}"
            if method != "create_from_csv":
                count += 1
    assert len(surface) == 18
    assert count == 83


@pytest.mark.parametrize(
    "call,method,path",
    [
        (lambda c: c.messages.attempts("m"), "GET", "/v1/messages/m/attempts"),
        (lambda c: c.messages.cancel("m"), "POST", "/v1/messages/m/cancel"),
        (lambda c: c.batches.get("b"), "GET", "/v1/batches/b"),
        (lambda c: c.batches.validation("b"), "GET", "/v1/batches/b/validation"),
        (lambda c: c.batches.start("b"), "POST", "/v1/batches/b/start"),
        (lambda c: c.batches.stop("b"), "POST", "/v1/batches/b/stop"),
        (lambda c: c.otp.send(to="+254700000012"), "POST", "/v1/otp/send"),
        (lambda c: c.lookups.create(to="+254700000012"), "POST", "/v1/lookup"),
        (lambda c: c.lookups.get("l"), "GET", "/v1/lookup/l"),
        (lambda c: c.contact_groups.send("g", text="x"), "POST", "/v1/contact-groups/g/send"),
        (lambda c: c.contact_groups.update("g", name="x"), "PATCH", "/v1/contact-groups/g"),
        (lambda c: c.templates.update("t", body="x"), "PATCH", "/v1/templates/t"),
        (lambda c: c.webhooks.test("w"), "POST", "/v1/webhooks/w/test"),
        (lambda c: c.webhooks.delete("w"), "DELETE", "/v1/webhooks/w"),
        (lambda c: c.webhooks.list_deliveries("w"), "GET", "/v1/webhooks/w/deliveries"),
        (lambda c: c.inbound.list(), "GET", "/v1/inbound"),
        (lambda c: c.inbound.reply("i", text="x"), "POST", "/v1/inbound/i/reply"),
        (lambda c: c.numbers.list(), "GET", "/v1/numbers"),
        (lambda c: c.numbers.available(country="KE", kind="long_code"), "GET", "/v1/numbers/available"),
        (lambda c: c.numbers.assign(country="KE", kind="long_code"), "POST", "/v1/numbers"),
        (lambda c: c.numbers.release("n"), "DELETE", "/v1/numbers/n"),
        (lambda c: c.numbers.list_rules("n"), "GET", "/v1/numbers/n/rules"),
        (lambda c: c.numbers.create_rule("n", match="any", action="webhook", target="https://x"), "POST", "/v1/numbers/n/rules"),
        (lambda c: c.numbers.update_rule("n", "r", match="any", action="webhook", target="https://x"), "PUT", "/v1/numbers/n/rules/r"),
        (lambda c: c.numbers.delete_rule("n", "r"), "DELETE", "/v1/numbers/n/rules/r"),
        (lambda c: c.sender_ids.list(), "GET", "/v1/sender-ids"),
        (lambda c: c.sender_ids.get("s"), "GET", "/v1/sender-ids/s"),
        (lambda c: c.sender_ids.update("s", use_case="otp", countries=["KE"], documents=[]), "PATCH", "/v1/sender-ids/s"),
        (lambda c: c.sender_ids.delete("s"), "DELETE", "/v1/sender-ids/s"),
        (lambda c: c.sender_ids.check(value="ACME", country="KE"), "GET", "/v1/sender-ids/check"),
        (lambda c: c.sender_ids.list_documents(), "GET", "/v1/sender-documents"),
        (lambda c: c.sender_ids.list_drafts(), "GET", "/v1/sender-id-drafts"),
        (lambda c: c.sender_ids.get_draft("d"), "GET", "/v1/sender-id-drafts/d"),
        (lambda c: c.sender_ids.delete_draft("d"), "DELETE", "/v1/sender-id-drafts/d"),
        (lambda c: c.suppressions.list(), "GET", "/v1/compliance/suppressions"),
        (lambda c: c.suppressions.delete(7), "DELETE", "/v1/compliance/suppressions/7"),
        (lambda c: c.compliance.list_countries(), "GET", "/v1/compliance/countries"),
        (lambda c: c.compliance.get_country("KE"), "GET", "/v1/compliance/countries/KE"),
        (lambda c: c.compliance.list_content_rules(), "GET", "/v1/content-rules"),
        (lambda c: c.wallet.create_topup(amount="100", currency="KES", channel="card", email="a@b.c"), "POST", "/v1/wallet/topups"),
        (lambda c: c.pricing.get(product="sms"), "GET", "/v1/pricing"),
        (lambda c: c.analytics.by_country(), "GET", "/v1/analytics/by-country"),
        (lambda c: c.analytics.by_carrier(), "GET", "/v1/analytics/by-carrier"),
        (lambda c: c.analytics.by_sender_id(), "GET", "/v1/analytics/by-sender-id"),
        (lambda c: c.analytics.timeseries(bucket="day"), "GET", "/v1/analytics/timeseries"),
        (lambda c: c.sandbox.list_messages(), "GET", "/v1/sandbox/messages"),
        (lambda c: c.countries.list(), "GET", "/v1/countries"),
        (lambda c: c.countries.carriers("KE"), "GET", "/v1/countries/KE/carriers"),
        (lambda c: c.countries.routes("KE"), "GET", "/v1/countries/KE/routes"),
        (lambda c: c.countries.compliance("KE"), "GET", "/v1/countries/KE/compliance"),
    ],
)
def test_routes(call, method, path):
    client, t, _ = make(resp(200, {}))
    call(client)
    assert t.last.method == method
    assert urlsplit(t.last.url).path == path
