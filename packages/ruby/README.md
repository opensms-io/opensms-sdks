# opensms (Ruby)

Official Ruby client for [opensms](https://opensms.io): prepaid SMS for Africa.

Ruby 3.0+, zero runtime dependencies (standard library only).

## Install

```ruby
# Gemfile, once the gem is published
gem "opensms"
```

Not on RubyGems yet: until then, install from this checkout with
`gem "opensms", path: "path/to/sdks/packages/ruby"` in your Gemfile, or
`gem build opensms.gemspec && gem install ./opensms-0.1.0.gem`.

## Usage

```ruby
require "opensms"

client = Opensms::Client.new(api_key: ENV.fetch("OPENSMS_API_KEY"))

msg = client.messages.send(to: "+254712345678", text: "Your order has shipped")
puts msg[:id], msg[:status]
```

The key selects the environment: `sk_test_...` keys run in the sandbox
(`client.environment == "sandbox"`), `sk_live_...` keys send real traffic
(`"live"`). A malformed key raises `ArgumentError` before any network call.

Methods take keyword arguments (or a Hash with String or Symbol keys) using
the API's snake_case field names. Responses are plain Ruby `Hash`/`Array`
values with symbol keys, exactly as the API returns them: money stays a
decimal string, timestamps stay RFC 3339 strings, and unknown fields are
kept. Unknown request parameters raise `ArgumentError` locally, because the
API rejects unknown fields. Time-like inputs (`scheduled_at`, `date_from`,
`date_to`, analytics `from`/`to`) accept a `Time`, `Date` or string.

## More

One example per resource. See [`../../spec/SURFACE.md`](https://github.com/opensms-io/opensms-sdks/blob/main/spec/SURFACE.md)
for the full surface.

### messages

```ruby
msg = client.messages.send(to: "+254712345678", text: "Hi Ada", sender_id: "ACME")
client.messages.list(limit: 20, status: "delivered", country: "KE")
client.messages.get(msg[:id])
client.messages.attempts(msg[:id])   # delivery attempts (Array)
client.messages.cancel(msg[:id])     # only queued or scheduled messages; never auto-retried
```

### batches

```ruby
batch = client.batches.create(items: [
  { to: "+254712345678", text: "Hello 1" },
  { to: "+254712345679", text: "Hello 2" }
], dedupe: true)
client.batches.validation(batch[:id])   # per-row report
client.batches.start(batch[:id])        # batches are created "ready" and send nothing until started
client.batches.list_items(batch[:id], status: "delivered")
client.batches.stop(batch[:id])
```

### otp

```ruby
otp = client.otp.send(to: "+254712345678", length: 6, ttl_seconds: 300)
res = client.otp.verify(otp_id: otp[:otp_id], code: "123456")
res[:valid]          # true / false
res[:attempts_left]  # a wrong code burns an attempt, so verify is never auto-retried
```

### lookups

```ruby
lookup = client.lookups.create(to: "+254712345678")
client.lookups.get(lookup[:id])
```

### contacts

```ruby
contact = client.contacts.create(e164: "+254712345678", name: "Ada", attributes: { tier: "gold" })
client.contacts.update(contact[:id], name: "Ada L")   # partial update
client.contacts.list(limit: 50)
client.contacts.delete(contact[:id])
```

### contact_groups

```ruby
group = client.contact_groups.create(name: "VIP", contact_ids: [contact[:id]])
client.contact_groups.send(group[:id], text: "Hi all")   # returns a running Batch
client.contact_groups.send(group[:id], template_id: "tpl-id", variables: { name: "Ada" })
client.contact_groups.delete(group[:id])
```

### templates

```ruby
tpl = client.templates.create(name: "welcome", body: "Hi {{name}}", traffic_type: "transactional")
client.templates.update(tpl[:id], body: "Hello {{name}}")
client.templates.list
```

### webhooks

```ruby
hook = client.webhooks.create(url: "https://you.example/opensms", events: ["message.delivered", "message.failed"])
secret = hook[:secret]   # whsec_..., returned only once: store it

client.webhooks.update(hook[:id], url: "https://you.example/v2", events: ["message.delivered"], enabled: true)
client.webhooks.test(hook[:id])   # queues a webhook.test delivery
```

`update` is a full replacement: `url`, `events` and `enabled` are all required.
See [Webhooks](#webhooks) below for signature verification.

### inbound

```ruby
client.inbound.list
client.inbound.reply("inbound-id", text: "Thanks!")   # live keys only
```

### numbers

```ruby
client.numbers.available(country: "KE", kind: "long_code")
number = client.numbers.assign(country: "KE", kind: "long_code")   # charges the wallet; live keys only
client.numbers.create_rule(number[:id], match: "keyword", pattern: "STOP", action: "webhook",
                                        target: "https://you.example/inbound")
client.numbers.release(number[:id])
```

### sender_ids

```ruby
quote = client.sender_ids.quote(countries: ["KE", "NG"])
sender = client.sender_ids.create(value: "ACME", kind: "alphanumeric", countries: ["KE"],
                                  use_case: "transactional", documents: ["doc-id-1"],
                                  quote_id: quote[:quote_id])   # may charge fees: never auto-retried
client.sender_ids.update(sender[:id], use_case: "otp", countries: ["KE"], documents: ["doc-id-1"])

draft = client.sender_ids.create_draft(source: "application", value: "ACME", kind: "alphanumeric", countries: ["KE"])
client.sender_ids.update_draft(draft[:id], version: draft[:version], sample_message: "Your code is 1234")
```

Document upload and download are console-only and not part of the SDK.

### suppressions

```ruby
sup = client.suppressions.create(e164: "+254712345678", reason: "manual")   # never auto-retried
client.suppressions.import([{ e164: "+254712345679", reason: "complaint" }])
client.suppressions.delete(sup[:id])
```

### compliance

```ruby
client.compliance.list_countries
client.compliance.get_country("KE")
client.compliance.list_content_rules
```

### wallet

```ruby
client.wallet.balances               # [{ currency: "KES", balance: "100.000000", ... }]
entries = client.wallet.ledger(limit: 100)
older = client.wallet.ledger(limit: 100, before: entries.map { |e| e[:id] }.min)   # pages with `before`
client.wallet.create_topup(amount: "1000", currency: "KES", channel: "mobile_money", email: "billing@you.example")
```

### pricing

```ruby
client.pricing.get(product: "sms", country: "KE")
```

### analytics

```ruby
client.analytics.overview(range: "7d")
client.analytics.by_country(from: Date.today - 30, to: Date.today)
client.analytics.timeseries(range: "2d", bucket: "hour")
```

### sandbox

```ruby
client.sandbox.list_messages(limit: 10)   # rendered text of sandbox sends, including OTP codes
```

### countries

```ruby
client.countries.list
client.countries.carriers("KE")
```

### Pagination

Cursor lists return an `Opensms::Page` with `items` and `next_cursor` (nil on
the last page). `client.paginate` walks every page lazily:

```ruby
client.paginate(:messages, :list, limit: 50).each { |m| puts m[:id] }
client.paginate(client.contacts.method(:list), limit: 200).to_a
```

## Errors and retries

Every non-2xx response raises `Opensms::Error`, mapped from the API's
RFC 9457 problem body:

| Accessor | Meaning |
| --- | --- |
| `status` | HTTP status (`0` for a network failure or timeout) |
| `type` | problem `type` (`"about:blank"` or a problems URI) |
| `title` | HTTP reason title, e.g. `"Bad Request"` |
| `detail` | human-readable detail (also `e.message`) |
| `code` | machine code, absent on most errors |
| `errors` | field-error map, when present |
| `request_id` | set on message and OTP admission rejections |
| `retry_after` | seconds, when the API asked to wait |
| `trace_id` | present when the API attaches one |
| `body` | raw decoded body (or raw text when not JSON) |

**Branch on `status`, not `code`.** Most opensms errors carry no `code`; use
`detail` for display. Insufficient API key scope is `401` on `messages` and
`otp`, but `403` everywhere else.

Retries: `429`, `500`, `502`, `503`, `504`, network errors and timeouts are
retried up to `max_retries` times (default 2), only when safe. `GET`, `PUT`,
`PATCH` and `DELETE` are always retryable. A `POST` is retried only when it
carries an `Idempotency-Key`; the SDK generates a UUIDv4 per call and reuses
it unchanged across retries of that call, so a retried send is never
duplicated. `Retry-After` is honoured (seconds or HTTP date); if it asks for
more than 60 seconds the SDK does not wait, it raises `Opensms::Error` with
`retry_after` set. Otherwise the delay is exponential backoff with full
jitter, capped at 8 seconds. Never retried: other `4xx` responses, and
`messages.cancel`, `otp.verify`, `sender_ids.create`,
`sender_ids.create_draft`, `suppressions.create` and `suppressions.import`.

```ruby
begin
  client.messages.send(to: "+254712345678", text: "hi")
rescue Opensms::Error => e
  warn "#{e.status} #{e.code}: #{e.detail}"
end
```

## Webhooks

Every delivery carries `X-OpenSMS-Signature: t=<unix>,v1=<hex>`, an
HMAC-SHA256 of `"<t>.<raw body>"` keyed with the endpoint's `whsec_...`
secret used verbatim. Verify the raw body before parsing; no API key is
needed:

```ruby
payload = request.body.read
header = request.get_header("HTTP_X_OPENSMS_SIGNATURE")

begin
  event = Opensms::Webhook.construct_event(payload, header, ENV.fetch("OPENSMS_WEBHOOK_SECRET"))
  case event.type
  when "message.delivered" then mark_delivered(event.data[:id])
  end
rescue Opensms::Error => e
  # e.code is "invalid_signature" or "expired_signature"
  head :bad_request
end

Opensms::Webhook.verify_signature(payload, header, secret)                        # => true / false
Opensms::Webhook.verify_signature(payload, header, secret, tolerance_seconds: 60) # default 300
```

The same helpers are available as `client.webhooks.verify_signature` and
`client.webhooks.construct_event`.

## Testing

```sh
rake test         # offline unit tests, no network
rake integration  # live scenario against a sandbox; skipped unless OPENSMS_BASE_URL and OPENSMS_API_KEY are set
```

See the monorepo [root README](https://github.com/opensms-io/opensms-sdks) and
[`../../spec/SURFACE.md`](https://github.com/opensms-io/opensms-sdks/blob/main/spec/SURFACE.md) for the API surface this
SDK implements.

## License

MIT
