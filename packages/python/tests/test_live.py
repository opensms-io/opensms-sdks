"""Live conformance scenario (CONFORMANCE.md "Live scenario"), run in file
order against a real OpenSMS API. Skipped unless OPENSMS_BASE_URL and
OPENSMS_API_KEY are set. Never creates accounts or keys.

    source ../../spec/fixtures/credentials.sh && pytest tests/test_live.py -v
"""

from __future__ import annotations

import os
import random
import re
import secrets
import string
import time
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any, Callable, Dict, Optional

import pytest

from opensms import Opensms, OpensmsError

BASE_URL = os.environ.get("OPENSMS_BASE_URL")
API_KEY = os.environ.get("OPENSMS_API_KEY")
READONLY_KEY = os.environ.get("OPENSMS_READONLY_API_KEY")

pytestmark = [
    pytest.mark.live,
    pytest.mark.skipif(
        not (BASE_URL and API_KEY), reason="OPENSMS_BASE_URL and OPENSMS_API_KEY are not set"
    ),
]

RUN = secrets.token_hex(4)
LANG = "python"
# CONFORMANCE.md uses the fixed destination +254700000012. The API limits
# sends per destination number per workspace (5 per hour, 20 per day, 3 OTPs
# per 10 minutes, internal/messages/rate_limits.go), and every SDK's live run
# shares one workspace, so a fixed number is rate limited after the first
# run. Each run therefore uses its own Safaricom (+25470...) numbers.
def _safaricom() -> str:
    return "+25470" + "".join(random.choice(string.digits) for _ in range(7))


TO = _safaricom()
TO_B = _safaricom()
TO_C = _safaricom()
TO_OTP = _safaricom()
ZERO_UUID = "00000000-0000-0000-0000-000000000000"
TIMEOUT = 60.0  # the isolated stack can be slow under load (Argon2 per request)
POLL_DEADLINE = 60.0
UUID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")

S: Dict[str, Any] = {}


def rand_phone() -> str:
    return "+2547" + "".join(random.choice(string.digits) for _ in range(8))


def mk(key: Optional[str] = None, **kw: Any) -> Opensms:
    return Opensms(key or API_KEY, base_url=BASE_URL, timeout=TIMEOUT, **kw)  # type: ignore[arg-type]


@pytest.fixture(scope="module")
def c() -> Opensms:
    return mk()


def expect_err(fn: Callable[[], Any], status: int, detail: Optional[str] = None) -> OpensmsError:
    with pytest.raises(OpensmsError) as info:
        fn()
    err = info.value
    assert err.status == status, f"expected {status}, got {err.status}: {err.detail!r}"
    if detail is not None:
        assert err.detail == detail
    return err


def poll(fn: Callable[[], Any], until: Callable[[Any], bool], deadline: float = POLL_DEADLINE) -> Any:
    end = time.monotonic() + deadline
    last = None
    while time.monotonic() < end:
        last = fn()
        if until(last):
            return last
        time.sleep(1.0)
    raise AssertionError(f"condition not met within {deadline}s; last={last!r}")


# 1
def test_01_constructor_validation():
    with pytest.raises(ValueError):
        Opensms("not_a_key", base_url=BASE_URL)
    with pytest.raises(ValueError):
        Opensms("sk_test_short", base_url=BASE_URL)


# 2
def test_02_auth_error_not_retried():
    calls = []

    from opensms import urllib_transport

    def counting(req):
        calls.append(req)
        return urllib_transport(req)

    bad = Opensms("sk_test_" + "A" * 32, base_url=BASE_URL, timeout=TIMEOUT, transport=counting)
    err = expect_err(lambda: bad.messages.list(limit=1), 401, "missing or invalid API key")
    assert err.type == "about:blank"
    assert err.title == "Unauthorized"
    assert err.code is None
    assert len(calls) == 1


# 3
def test_03_send(c):
    m = c.messages.send(to=TO, text=f"conformance {LANG} {RUN}", metadata={"sdk": LANG, "run": RUN})
    assert UUID_RE.match(m["id"])
    assert m["to"] == TO
    assert m["sender_id"] == "OPENSMS"
    assert m["traffic_type"] == "transactional"
    assert m["status"] in {"queued", "sending", "sent", "delivered"}
    assert m["parts"] == 1
    assert m["encoding"] == "gsm7"
    assert m["country_iso2"] == "KE"
    assert m["currency"] == "KES"
    assert m["price"] == "0.000000"
    assert m["metadata"]["run"] == RUN
    S["M"] = m["id"]
    S["M_text"] = f"conformance {LANG} {RUN}"


# 4
def test_04_idempotent_replay(c):
    key = str(uuid.uuid4())
    to = _safaricom()
    params = {"to": to, "text": f"idem {LANG} {RUN}"}
    first = c.messages.send(**params, idempotency_key=key)
    second = c.messages.send(**params, idempotency_key=key)
    assert first["id"] == second["id"]
    expect_err(
        lambda: c.messages.send(to=to, text=f"idem changed {RUN}", idempotency_key=key),
        409,
        "Idempotency-Key was already used with a different request",
    )


# 5
def test_05_get_and_wait(c):
    m = poll(lambda: c.messages.get(S["M"]), lambda m: m.get("status") == "delivered")
    assert m.get("delivered_at")
    assert m.get("sent_at")
    assert m["text"] == S["M_text"]


# 6
def test_06_list_and_cursor(c):
    page = c.messages.list(limit=1)
    assert len(page.items) == 1
    assert page.next_cursor
    page2 = c.messages.list(limit=1, cursor=page.next_cursor)
    assert len(page2.items) == 1
    assert page2.items[0]["id"] != page.items[0]["id"]
    expect_err(lambda: c.messages.list(limit=1, cursor="garbage"), 400, "invalid cursor")
    expect_err(lambda: c.messages.list(status="bogus"), 400, "invalid status")
    seen = []
    for item in c.paginate(c.messages.list, limit=2):
        seen.append(item["id"])
        if len(seen) == 3:
            break
    assert len(seen) == 3 and len(set(seen)) == 3


# 7
def test_07_attempts(c):
    attempts = c.messages.attempts(S["M"])
    assert isinstance(attempts, list) and attempts
    first = attempts[0]
    assert first["sequence"] == 1
    assert first["route_name"].startswith("Mock provider (sandbox)")
    assert first["status"] == "delivered"
    assert first["price"] == "0.000000"


# 8
def test_08_validation_error(c):
    calls = []
    from opensms import urllib_transport

    def counting(req):
        calls.append(req)
        return urllib_transport(req)

    client = mk(transport=counting)
    err = expect_err(lambda: client.messages.send(to="12345", text="x"), 400, "to must be an E.164 phone number")
    assert err.title == "Bad Request"
    assert err.type == "about:blank"
    assert len(calls) == 1


# 9
def test_09_coded_error(c):
    err = expect_err(lambda: c.messages.get("not-a-uuid"), 400, "Message ID must be a valid UUID.")
    assert err.code == "invalid_message_id"
    assert err.type == "https://api.opensms.io/problems/invalid_message_id"


# 10
def test_10_not_found(c):
    expect_err(lambda: c.messages.get(ZERO_UUID), 404, "message not found")


# 11
def test_11_schedule_and_cancel(c):
    when = datetime.now(timezone.utc) + timedelta(hours=2)
    m = c.messages.send(to=_safaricom(), text=f"scheduled {RUN}", scheduled_at=when)
    assert m["status"] == "scheduled"
    cancelled = c.messages.cancel(m["id"])
    assert cancelled["status"] == "cancelled"
    assert cancelled.get("cancelled_at")
    msg = "message cannot be cancelled in its current state"
    expect_err(lambda: c.messages.cancel(m["id"]), 409, msg)
    expect_err(lambda: c.messages.cancel(S["M"]), 409, msg)


# 12
def test_12_batch(c):
    b = c.batches.create(
        items=[
            {"to": TO, "text": f"b1 {RUN}"},
            {"to": TO_B, "text": f"b2 {RUN}"},
            {"to": "bad", "text": "x"},
        ]
    )
    assert b["status"] == "ready"
    assert b["total"] == 3
    assert b["invalid"] == 1
    assert b["sent"] == 0
    report = c.batches.validation(b["id"])
    assert len(report["rows"]) == 3
    assert report["valid"] == 2
    assert report["rows"][2]["valid"] is False
    assert report["rows"][2]["error"] == "to must be an E.164 phone number"
    got = c.batches.get(b["id"])
    assert (got["total"], got["invalid"], got["sent"]) == (3, 1, 0)
    started = c.batches.start(b["id"])
    assert started["status"] == "running"
    page = poll(lambda: c.batches.list_items(b["id"]), lambda p: len(p.items) == 2)
    for item in page.items:
        assert item.get("to") and item.get("status")


# 13
def test_13_batch_stop(c):
    b = c.batches.create(items=[{"to": _safaricom(), "text": f"stop {RUN}"}])
    stopped = c.batches.stop(b["id"])
    assert stopped == {"id": b["id"], "status": "stopped", "cancelled": 0}
    expect_err(lambda: c.batches.start(b["id"]), 409, "batch is not ready to start")
    expect_err(lambda: c.batches.get(ZERO_UUID), 404, "batch not found")


# 14
def test_14_csv_batch(c):
    b = c.batches.create_from_csv(f"to,text\n{TO_C},csv {RUN}\n")
    assert b["status"] == "ready"
    assert b["total"] == 1
    assert b["invalid"] == 0


# 15
def test_15_otp(c):
    started = datetime.now(timezone.utc) - timedelta(seconds=5)
    sent = c.otp.send(to=TO_OTP, length=6, ttl_seconds=300)
    otp_id = sent["otp_id"]
    assert UUID_RE.match(otp_id)
    pattern = re.compile(r"Your OpenSMS verification code is (\d{6})")

    def find_code(page):
        for item in page.items:
            if item.get("traffic_type") != "otp" or item.get("to") != TO_OTP:
                continue
            match = pattern.search(item.get("text") or "")
            created = item.get("created_at")
            if match and created and datetime.fromisoformat(created.replace("Z", "+00:00")) >= started:
                return match.group(1)
        return None

    page = poll(lambda: c.sandbox.list_messages(limit=10), lambda p: find_code(p) is not None)
    code = find_code(page)
    wrong = code
    while wrong == code:
        wrong = "".join(random.choice(string.digits) for _ in range(6))
    assert c.otp.verify(otp_id=otp_id, code=wrong) == {"valid": False, "attempts_left": 4}
    assert c.otp.verify(otp_id=otp_id, code=code) == {"valid": True, "attempts_left": 3}
    expect_err(lambda: c.otp.send(to=TO_OTP, template="no placeholder"), 400, "template must contain {{code}}")
    expect_err(lambda: c.otp.verify(otp_id=ZERO_UUID, code="123456"), 404, "OTP not found")


# 16
def test_16_lookup(c):
    lk = c.lookups.create(to=TO)
    assert lk["state"] == "completed"
    assert lk["country"] == "KE"
    assert lk["source"] == "mock"
    assert lk["price"] == "0.000000"
    again = c.lookups.get(lk["id"])
    assert again["id"] == lk["id"] and again["state"] == lk["state"]
    err = expect_err(lambda: c.lookups.get(ZERO_UUID), 404, "Lookup not found.")
    assert err.code == "not_found"


# 17
def test_17_contacts(c):
    r1 = rand_phone()
    ct = c.contacts.create(e164=r1, name=f"Ada {RUN}", attributes={"tier": "gold"})
    assert ct["e164"] == r1
    assert c.contacts.get(ct["id"]) == ct
    up = c.contacts.update(ct["id"], name=f"Ada L {RUN}")
    assert up["name"] == f"Ada L {RUN}"
    assert up["attributes"]["tier"] == "gold"
    found = False
    for item in c.paginate(c.contacts.list, limit=200):
        if item["id"] == ct["id"]:
            found = True
            break
    assert found
    expect_err(lambda: c.contacts.create(e164=r1), 409, "A record with this phone number or name already exists.")
    S["contact"] = ct["id"]


# 18
def test_18_contact_groups(c):
    g = c.contact_groups.create(name=f"grp {RUN}", contact_ids=[S["contact"]])
    assert g["contact_ids"] == [S["contact"]]
    g2 = c.contact_groups.update(g["id"], name=f"grp2 {RUN}")
    assert g2["name"] == f"grp2 {RUN}"
    batch = c.contact_groups.send(g["id"], text=f"Hi {RUN}")
    assert batch["status"] == "running"
    assert batch["total"] == 1
    empty = c.contact_groups.create(name=f"empty {RUN}")
    try:
        expect_err(
            lambda: c.contact_groups.send(empty["id"], text="x"),
            422,
            "Group must contain between 1 and 1000 contacts.",
        )
    finally:
        c.contact_groups.delete(empty["id"])
    S["group"] = g["id"]


# 19
def test_19_templates(c):
    t = c.templates.create(name=f"tpl-{RUN}", body="Hi {{name}}", traffic_type="transactional")
    assert t["variables"] == ["name"]
    t2 = c.templates.update(t["id"], body="Hello {{name}}")
    assert t2["body"] == "Hello {{name}}"
    assert t2["variables"] == ["name"]
    batch = c.contact_groups.send(S["group"], template_id=t["id"], variables={"name": "Ada"})
    assert batch["status"] == "running"
    assert c.templates.delete(t["id"]) is None
    assert c.contact_groups.delete(S["group"]) is None
    assert c.contacts.delete(S["contact"]) is None
    expect_err(lambda: c.contacts.get(S["contact"]), 404, "Record not found.")


# 20
def test_20_webhooks(c):
    w = c.webhooks.create(url=f"https://example.com/opensms/{RUN}", events=["message.delivered", "message.failed"])
    try:
        assert w["secret"].startswith("whsec_")
        assert w["enabled"] is True
        assert "secret" not in c.webhooks.get(w["id"])
        expect_err(
            lambda: c.webhooks.create(url="http://example.com/x", events=["message.delivered"]),
            400,
            "url must be an HTTPS URL without credentials or fragment",
        )
        up = c.webhooks.update(
            w["id"], url=f"https://example.com/opensms/{RUN}/v2", events=["message.delivered"], enabled=True
        )
        assert up["url"] == f"https://example.com/opensms/{RUN}/v2"
        assert up["events"] == ["message.delivered"]
        assert c.webhooks.test(w["id"]) == {"status": "pending"}
        page = poll(lambda: c.webhooks.list_deliveries(w["id"]), lambda p: len(p.items) >= 1)
        delivery = next(d for d in page.items if d["event"] == "webhook.test")
        assert isinstance(delivery["id"], int) and isinstance(delivery["generation"], int)
        try:
            out = c.webhooks.replay_delivery(
                w["id"], delivery["id"], generation=delivery["generation"], reason="sdk conformance replay"
            )
            assert "status" in out
        except OpensmsError as err:
            assert err.status == 409
            assert err.detail == "Delivery state, lease or generation does not permit replay."
    finally:
        assert c.webhooks.delete(w["id"]) is None
    expect_err(lambda: c.webhooks.get(w["id"]), 404, "webhook not found")


# 21
def test_21_suppressions(c):
    r2, r3 = rand_phone(), rand_phone()
    s = c.suppressions.create(e164=r2, reason="manual")
    assert isinstance(s["id"], int)
    assert s["reason"] == "manual"
    err = expect_err(lambda: c.messages.send(to=r2, text="x"), 422, "destination is suppressed")
    assert isinstance(err.request_id, str) and err.request_id
    found = any(item["e164"] == r2 for item in c.paginate(c.suppressions.list, limit=200))
    assert found
    assert c.suppressions.import_([{"e164": r3, "reason": "complaint"}]) == {"created": 1, "received": 1}
    assert c.suppressions.delete(s["id"]) is None
    expect_err(lambda: c.suppressions.delete(s["id"]), 404, "suppression not found")


# 22
def test_22_compliance(c):
    ke = c.compliance.get_country("KE")
    assert ke["iso2"] == "KE"
    assert ke["dial_code"] == "+254"
    assert "STOP" in ke["stop_keywords"]
    expect_err(lambda: c.compliance.get_country("ZZ"), 404, "country not found")
    assert any(x["iso2"] == "KE" for x in c.compliance.list_countries())
    rules = c.compliance.list_content_rules()
    assert isinstance(rules, list)
    for rule in rules:
        assert isinstance(rule["id"], int)


# 23
def test_23_wallet(c):
    balances = c.wallet.balances()
    assert balances
    first = balances[0]
    assert first["environment"] == "sandbox"
    assert first["currency"] == "KES"
    assert isinstance(first["balance"], str) and re.match(r"^-?\d+(\.\d+)?$", first["balance"])
    entries = c.wallet.ledger(limit=1)
    assert len(entries) == 1 and isinstance(entries[0]["id"], int)
    expect_err(lambda: c.wallet.ledger(limit=0), 400, "limit must be between 1 and 200")
    expect_err(
        lambda: c.wallet.create_topup(amount="100", currency="KES", channel="card", email="dev@opensms.test"),
        422,
        "sandbox wallets cannot use payment providers",
    )


# 24
def test_24_pricing(c):
    p = c.pricing.get(product="sms", country="KE")
    assert p["currency"] == "KES"
    assert p["product"] == "sms"
    for entry in p["entries"]:
        assert entry["country_iso2"] == "KE"
    expect_err(lambda: c.pricing.get(product="bogus"), 400, "product must be sms, lookup, or number_monthly")


# 25
def test_25_analytics(c):
    ov = c.analytics.overview()
    assert ov["environment"] == "sandbox"
    assert ov["currency"] == "KES"
    assert isinstance(ov["sent"], int)
    c.analytics.overview(range="7d")
    for fn in (c.analytics.by_country, c.analytics.by_carrier, c.analytics.by_sender_id, c.analytics.timeseries):
        assert isinstance(fn(), list)


# 26
def test_26_numbers_and_inbound(c):
    page = c.numbers.list()
    assert isinstance(page.items, list)
    assert isinstance(c.numbers.available(country="KE", kind="long_code"), list)
    expect_err(
        lambda: c.numbers.assign(country="KE", kind="long_code"),
        422,
        "This operation requires the live environment.",
    )
    assert c.inbound.list().items == []


# 27
def test_27_sender_ids(c):
    assert any(
        s["value"] == "OPENSMS" and s["status"] == "approved"
        for s in c.paginate(c.sender_ids.list, limit=200)
    )
    assert c.sender_ids.check(value="ACME", country="KE")["valid"] is True
    assert c.sender_ids.quote(countries=["KE"])["quote_id"].startswith("sq_")
    assert isinstance(c.sender_ids.list_documents(), list)
    value = "SDK" + "".join(random.choice(string.ascii_uppercase) for _ in range(4))
    d = c.sender_ids.create_draft(
        source="application",
        value=value,
        kind="alphanumeric",
        countries=["KE"],
        use_case="transactional",
        sample_message="Your order shipped",
    )
    try:
        assert d["version"] == 1
        assert d["status"] == "active"
        d2 = c.sender_ids.update_draft(d["id"], version=1, sample_message="Your order has shipped")
        assert d2["version"] == 2
        assert c.sender_ids.get_draft(d["id"])["id"] == d["id"]
    finally:
        assert c.sender_ids.delete_draft(d["id"]) is None
    expect_err(lambda: c.sender_ids.get(ZERO_UUID), 404, "sender ID not found")


# 28
def test_28_countries(c):
    countries = c.countries.list()
    ke = next(x for x in countries if x["iso2"] == "KE")
    assert ke["dial_code"] == "+254"
    assert c.countries.carriers("KE")
    assert isinstance(c.countries.routes("KE"), list)
    assert c.countries.compliance("KE")["iso2"] == "KE"


# 29
@pytest.mark.skipif(not READONLY_KEY, reason="OPENSMS_READONLY_API_KEY is not set")
def test_29_scope_errors():
    ro = mk(READONLY_KEY)
    expect_err(lambda: ro.messages.send(to=_safaricom(), text=f"scope {RUN}"), 401, "insufficient scope")
    expect_err(lambda: ro.contacts.list(), 403, "Insufficient API key scope.")
    assert len(ro.messages.list(limit=1).items) == 1
