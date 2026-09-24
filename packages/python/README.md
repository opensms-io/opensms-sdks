# opensms (Python)

Official Python client for [opensms](https://opensms.io): prepaid SMS for Africa.

Pure standard library: no runtime dependencies. Python 3.8+. Fully typed (`py.typed`).
See the [monorepo README](https://github.com/opensms-io/opensms-sdks) for the other SDKs and
[spec/SURFACE.md](https://github.com/opensms-io/opensms-sdks/blob/main/spec/SURFACE.md) for the full API surface.

## Install

```bash
pip install opensms
```

## Usage

```python
from opensms import Opensms

client = Opensms(api_key="sk_test_...")

message = client.messages.send(to="+254712345678", text="Your order has shipped")
print(message["id"], message["status"], message["price"])   # price is a decimal string
```

A key starting `sk_test_` selects the sandbox, `sk_live_` the live environment; `client.environment`
reports which one is active, and a malformed key raises `ValueError` before any request is made.
Other constructor options: `base_url` (default `https://api.opensms.io`), `timeout` (seconds per
attempt, default 30), `max_retries` (default 2), and `transport` (swap the network layer for tests).

## More

One short example per resource, in the order they're listed on `client`.

### messages

```python
m = client.messages.send(to="+254712345678", text="Hello", sender_id="ACME")
client.messages.get(m["id"])
client.messages.cancel(m["id"])                       # only queued or scheduled messages
page = client.messages.list(limit=50, status="delivered", country="KE")
```

### batches

```python
b = client.batches.create(items=[
    {"to": "+254712345678", "text": "Hi Ada"},
])
client.batches.start(b["id"])                         # batches are created "ready"
client.batches.get(b["id"])
```

### otp

```python
otp = client.otp.send(to="+254712345678", length=6, ttl_seconds=300)
result = client.otp.verify(otp_id=otp["otp_id"], code="123456")
print(result["valid"], result["attempts_left"])
```

### lookups

```python
lk = client.lookups.create(to="+254712345678")
client.lookups.get(lk["id"])
```

### contacts

```python
ct = client.contacts.create(e164="+254712345678", name="Ada")
client.contacts.update(ct["id"], name="Ada L")        # PATCH: other fields kept
client.contacts.list(limit=200)
```

### contact_groups

```python
g = client.contact_groups.create(name="VIP", contact_ids=[ct["id"]])
client.contact_groups.send(g["id"], text="Sale starts today")
```

### templates

```python
tpl = client.templates.create(name="welcome", body="Hi {{name}}", traffic_type="transactional")
client.templates.update(tpl["id"], body="Hello {{name}}")
```

### webhooks

```python
wh = client.webhooks.create(url="https://example.com/opensms", events=["message.delivered"])
secret = wh["secret"]                                 # whsec_..., shown only once
client.webhooks.update(wh["id"], url=wh["url"], events=wh["events"], enabled=True)  # full replacement
```

### inbound

```python
client.inbound.list()
client.inbound.reply(inbound_id, text="Thanks!")      # live keys only
```

### numbers

```python
n = client.numbers.assign(country="KE", kind="long_code")   # live keys only, charges the wallet
client.numbers.create_rule(n["id"], match="keyword", pattern="STOP", action="webhook", target="https://example.com/in")
```

### sender_ids

```python
draft = client.sender_ids.create_draft(source="application", value="ACME", kind="alphanumeric", countries=["KE"])
sid = client.sender_ids.create(value="ACME", kind="alphanumeric", countries=["KE"],
                                documents=[], use_case="transactional")  # may charge fees; never auto-retried
```

### suppressions

```python
s = client.suppressions.create(e164="+254712345678", reason="manual")
client.suppressions.import_([{"e164": "+254712345679", "reason": "complaint"}])
```

`import` is a Python keyword, so the method is `import_` (`getattr(client.suppressions, "import")` also works).

### compliance

```python
client.compliance.list_countries()
client.compliance.get_country("KE")
```

### wallet

```python
client.wallet.balances()
client.wallet.ledger(limit=50)                        # not cursor based; page with before=<smallest id seen>
```

### pricing

```python
client.pricing.get(product="sms", country="KE")
```

### analytics

```python
client.analytics.overview(range="7d")
client.analytics.by_country(from_="2026-09-01", to="2026-09-24")   # from is a keyword, so from_
```

### sandbox

```python
client.sandbox.list_messages(limit=10)                # rendered texts of sandbox sends, including OTP codes
```

### countries

```python
client.countries.list()
client.countries.carriers("KE")
```

### Pagination

```python
for message in client.paginate(client.messages.list, limit=50):
    print(message["id"])
```

`client.paginate(list_method, *args, **params)` feeds each page's `next_cursor` back as `cursor` until
it is `None`. Bare-array endpoints and `wallet.ledger` are not paginated by it.

## Errors and retries

Every non-2xx response, and any network failure or timeout that survives all retries, raises
`OpensmsError`:

| Field | Notes |
|---|---|
| `status` | HTTP status; `0` means a network error, timeout, or webhook signature failure |
| `message` | `detail`, else `title`, else a generic message |
| `type` | problem `type` URI, usually `about:blank` |
| `title` | problem `title`, e.g. `"Bad Request"` |
| `detail` | the specific human readable reason |
| `code` | machine readable code; absent on most errors |
| `trace_id` | present when the server sets one |
| `errors` | field validation errors, `{field: [messages]}`, when present |
| `request_id` | `X-Request-ID`; set on message and OTP admission rejections |
| `retry_after` | seconds, from `Retry-After`, when the server sent it |
| `body` | raw decoded body (dict), or text when the body was not JSON |

Most errors carry no `code`, so branch on `status` and show `detail`. Insufficient scope is `401` on
`messages` and `otp` but `403` everywhere else, so branch on `status`, not `code`, there too.

The client retries `429`, `500`, `502`, `503`, `504`, and network errors or timeouts, up to
`max_retries` (default 2, so 3 attempts), only when the request is safe to repeat. `GET`, `PUT`,
`PATCH` and `DELETE` are always retried. A `POST` is retried only when it carries an
`Idempotency-Key`: every method that supports one generates a UUIDv4 per call (or uses your
`idempotency_key=`) and sends the same key on every retry, so the server replays instead of sending
twice. `messages.cancel`, `otp.verify`, `sender_ids.create`, `sender_ids.create_draft`,
`suppressions.create`, `suppressions.import_`, and any other 4xx are never retried. The client
honours `Retry-After` (seconds or an HTTP date); when that asks for more than 60s it raises instead,
with `retry_after` set. Otherwise it waits a random delay up to `min(8s, 0.5s * 2^(n-1))` (exponential
backoff with full jitter).

```python
from opensms import OpensmsError

try:
    client.messages.send(to="+254712345679", text="hi")
except OpensmsError as e:
    print(e.status, e.detail)
```

## Webhooks

Deliveries carry `X-OpenSMS-Signature: t=<unix>,v1=<hex>`, an HMAC-SHA256 of `"<t>.<raw body>"` keyed
with the endpoint's `whsec_...` secret used verbatim. Always verify the raw body before parsing it;
no API key is needed:

```python
from opensms import construct_event, verify_signature, OpensmsError

# e.g. in a Flask view
raw = request.get_data()                              # exact bytes received
header = request.headers.get("X-OpenSMS-Signature")
try:
    event = construct_event(raw, header, secret)       # secret = "whsec_..." from webhooks.create
except OpensmsError as e:
    abort(400)                                          # e.code: invalid_signature | expired_signature
print(event["type"], event["data"])

ok = verify_signature(raw, header, secret, tolerance_seconds=300)   # boolean form
```

The default tolerance is 300 seconds; both functions accept `now` to inject a fixed clock in tests.

## Testing

```bash
pip install -e ".[dev]"
pytest tests/test_unit.py tests/test_urllib_transport.py
```

The unit tests need no network. The live suite (`tests/test_live.py`, marked `live`) runs against a
sandbox when `OPENSMS_BASE_URL` and `OPENSMS_API_KEY` are set, and is skipped otherwise:

```bash
OPENSMS_BASE_URL=... OPENSMS_API_KEY=... pytest tests/test_live.py -v
```

## License

MIT (c) OpenSMS
