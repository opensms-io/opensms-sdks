# Opensms (Swift)

Official Swift client for [opensms](https://opensms.io): prepaid SMS for Africa.

Foundation `URLSession` with async/await, no third-party dependencies. Swift
tools version 5.9, macOS 12+, iOS 15+ (Linux works through FoundationNetworking).

> **Not yet published.** This package has not been tagged or released yet.
> Until the first `swift-v*` tag exists, depend on it by local path or branch.

## Install

Add the future git-tag dependency to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/opensms-io/opensms-swift", from: "0.1.0")
],
targets: [
    .target(name: "YourApp", dependencies: [
        .product(name: "Opensms", package: "opensms-swift")
    ])
]
```

Until then, depend on it from within this repo with a local path instead:
`.package(path: "../../packages/swift")`.

## Usage

```swift
import Opensms

let opensms = try OpensmsClient(apiKey: "sk_test_...")

let message = try await opensms.messages.send(.init(to: "+254712345678", text: "Your order has shipped"))
print(message.id, message.status ?? "")
```

The key alone selects the workspace and environment: `sk_test_...` keys are
sandbox, `sk_live_...` keys are live (`opensms.environment`, `"sandbox"` or
`"live"`). A key with neither prefix throws `OpensmsArgumentError` at
construction, before any request. Construct the client once and reuse it.

See [`../../spec/SURFACE.md`](../../spec/SURFACE.md) for the full API surface
and [`../../README.md`](../../README.md) for the other language SDKs.

## More

Every method is `async throws`. List methods return `Page<T>` (`items`,
`nextCursor`) unless noted. Money, prices and balances are decimal
**strings** (`"0.000000"`), never floats. Timestamps decode to `Date`.

### messages

```swift
let m = try await opensms.messages.send(.init(
    to: "+254712345678", text: "Hi",
    senderId: "ACME", trafficType: "transactional",
    scheduledAt: .date(Date().addingTimeInterval(3600)),   // or "2026-10-01T09:00:00Z"
    callbackUrl: "https://example.com/dlr", metadata: ["ref": "a1"]
))
let page = try await opensms.messages.list(.init(limit: 50, status: "delivered", country: "KE"))
let attempts = try await opensms.messages.attempts(m.id)   // [MessageAttempt]
let cancelled = try await opensms.messages.cancel(m.id)    // queued or scheduled only, never retried
```

### batches

```swift
let batch = try await opensms.batches.create(.init(items: [
    .init(to: "+254712345678", text: "Hello"),
    .init(to: "+254712345679", text: "Hello", senderId: "ACME")
], dedupe: true))
let report = try await opensms.batches.validation(batch.id)   // per-row errors
_ = try await opensms.batches.start(batch.id)                 // nothing is sent until start
let items = try await opensms.batches.listItems(batch.id, .init(status: "delivered"))
let stopped = try await opensms.batches.stop(batch.id)        // { id, status, cancelled }
```

### otp

```swift
let otp = try await opensms.otp.send(.init(to: "+254712345678", length: 6, ttlSeconds: 300))
let check = try await opensms.otp.verify(otpId: otp.otpId, code: "123456")   // never retried
print(check.valid ?? false, check.attemptsLeft ?? 0)
```

### lookups

```swift
let lookup = try await opensms.lookups.create(to: "+254712345678")
_ = try await opensms.lookups.get(lookup.id)
```

### contacts

```swift
let contact = try await opensms.contacts.create(e164: "+254712345678", name: "Ada", attributes: ["tier": "gold"])
_ = try await opensms.contacts.list(.init(limit: 100))
_ = try await opensms.contacts.update(contact.id, name: "Ada L")   // PATCH: other fields kept
try await opensms.contacts.delete(contact.id)
```

### contactGroups

```swift
let group = try await opensms.contactGroups.create(name: "VIP", contactIds: [contact.id])
_ = try await opensms.contactGroups.send(group.id, .init(text: "Hi all"))   // returns a running Batch
try await opensms.contactGroups.delete(group.id)
```

### templates

```swift
let template = try await opensms.templates.create(name: "welcome", body: "Hi {{name}}", trafficType: "transactional")
_ = try await opensms.templates.update(template.id, body: "Hello {{name}}")
try await opensms.templates.delete(template.id)
```

### webhooks

```swift
let hook = try await opensms.webhooks.create(url: "https://example.com/opensms", events: ["message.delivered", "message.failed"])
let secret = hook.secret!   // whsec_..., shown only once
_ = try await opensms.webhooks.update(hook.id, url: hook.url!, events: hook.events!, enabled: true)   // PUT, full replacement
let deliveries = try await opensms.webhooks.listDeliveries(hook.id)
if let d = deliveries.items.first {
    _ = try await opensms.webhooks.replayDelivery(hook.id, deliveryId: d.id, generation: d.generation ?? 0, reason: "receiver was down")
}
```

### inbound

```swift
let inbox = try await opensms.inbound.list()
_ = try await opensms.inbound.reply(inbox.items[0].id, text: "Thanks!")   // live keys only
```

### numbers

```swift
let available = try await opensms.numbers.available(country: "KE", kind: "long_code")
let number = try await opensms.numbers.assign(country: "KE", kind: "long_code")   // live keys, charges the wallet
let rule = try await opensms.numbers.createRule(number.id, .init(match: "keyword", pattern: "STOP", action: "webhook", target: "https://example.com/in"))
try await opensms.numbers.release(number.id)
```

Everything except `list` and `available` needs a live key.

### senderIds

```swift
let quote = try await opensms.senderIds.quote(countries: ["KE", "NG"])
let docs = try await opensms.senderIds.listDocuments()   // upload and download are console only
let sender = try await opensms.senderIds.create(.init(   // may charge a fee, never retried
    value: "ACME", kind: "alphanumeric", countries: ["KE"],
    documents: docs.map(\.id), quoteId: quote.quoteId
))
try await opensms.senderIds.delete(sender.id)
```

### suppressions

```swift
let s = try await opensms.suppressions.create(e164: "+254712345678", reason: "manual")   // never retried
_ = try await opensms.suppressions.import([.init(e164: "+254712345670", reason: "complaint")])   // never retried
try await opensms.suppressions.delete(s.id)
```

### compliance

```swift
_ = try await opensms.compliance.listCountries()      // [CountryRules]
let ke = try await opensms.compliance.getCountry("KE")
_ = try await opensms.compliance.listContentRules()    // [ContentRule]
```

### wallet

```swift
let balances = try await opensms.wallet.balances()          // [WalletBalance]
var entries = try await opensms.wallet.ledger(limit: 100)   // [LedgerEntry], newest first
if let oldest = entries.last?.id { entries = try await opensms.wallet.ledger(limit: 100, before: oldest) }
let topup = try await opensms.wallet.createTopup(.init(amount: "1000", currency: "KES", channel: "mobile_money", email: "billing@example.com"))   // live keys
```

The ledger has no cursor: pass the smallest `id` seen as `before` and stop
when fewer than `limit` rows come back.

### pricing

```swift
let prices = try await opensms.pricing.get(product: "sms", country: "KE")
```

### analytics

```swift
let overview = try await opensms.analytics.overview(.init(range: "7d"))
_ = try await opensms.analytics.byCountry(.init(from: "2026-09-01", to: "2026-09-24"))
_ = try await opensms.analytics.timeseries(.init(range: "2d", bucket: "hour"))
```

### sandbox

```swift
let sandboxSends = try await opensms.sandbox.listMessages(.init(limit: 10))   // rendered text, including OTP codes
```

### countries

```swift
_ = try await opensms.countries.list()
_ = try await opensms.countries.carriers("KE")
_ = try await opensms.countries.compliance("KE")
```

### Pagination

Every cursor list works with the auto-pagination helper. It fetches pages
only as you iterate, so breaking out early never triggers another request:

```swift
for try await message in opensms.paginate(opensms.messages.list, ListMessagesParams(limit: 50)) {
    print(message.id)
}

// Methods with a path parameter: wrap them in a closure.
for try await item in opensms.paginate({ try await opensms.batches.listItems(batchId, $0) }, ListBatchItemsParams()) {
    print(item.status ?? "")
}
```

## Errors and retries

Every non-2xx response, and any network failure that survives retries,
throws `OpensmsError`, mapped from the RFC 9457 problem body:

| Field | Type | Notes |
|---|---|---|
| `status` | `Int` | HTTP status, or `0` when no response was received |
| `type` | `String?` | problem `type` |
| `title` | `String?` | problem `title` |
| `detail` | `String?` | human-readable explanation |
| `code` | `String?` | absent on most errors |
| `traceId` | `String?` | when present |
| `errors` | `[String: [String]]?` | field validation errors |
| `requestId` | `String?` | set on message and OTP admission rejections |
| `retryAfter` | `Int?` | seconds, on 429 and some 503 |
| `body` | `JSONValue?` | the raw decoded body |

A malformed key or an empty id throws `OpensmsArgumentError` instead, before
any request. Insufficient scope is **401** on `messages` and `otp`, but
**403** everywhere else; branch on `status`, not `code`.

Retries: `429`, `500`, `502`, `503`, `504`, network errors and timeouts,
only when the request is safe to repeat. `GET`, `PUT`, `PATCH` and `DELETE`
are always retryable. A `POST` is retried only when it carries an
`Idempotency-Key`; the SDK generates a UUIDv4 per call and reuses it
unchanged on every retry, so a retried send never sends twice:

```swift
_ = try await opensms.messages.send(params, idempotencyKey: "order-1042-sms")
```

The `Retry-After` header (seconds or an HTTP date) is honoured when present;
if it asks for more than 60s, the SDK does not wait and throws instead with
`retryAfter` set. Otherwise exponential backoff with full jitter, capped at
8s. Never retried: `messages.cancel`, `otp.verify` (a replay uses up an
attempt), `senderIds.create` (may charge a fee), `senderIds.createDraft`,
`suppressions.create`, `suppressions.import`, and any other 4xx.

## Webhooks

Deliveries carry `X-OpenSMS-Signature: t=<unix>,v1=<hex>`, an HMAC-SHA256 of
`"<t>.<raw body>"` keyed with the full `whsec_...` secret. Verify the exact
raw bytes before parsing. No API key is needed:

```swift
import Opensms

func handle(body: Data, signature: String) throws {
    let event = try OpensmsWebhooks.constructEvent(
        payload: body,
        header: signature,     // the X-OpenSMS-Signature header
        secret: "whsec_..."    // from webhooks.create, used verbatim
    )
    switch event.type {
    case "message.delivered": print(event.data?["id"]?.stringValue ?? "")
    default: break
    }
}

// Or just a Bool:
let ok = OpensmsWebhooks.verifySignature(payload: body, header: signature, secret: "whsec_...")
```

The default tolerance is 300s (`toleranceSeconds:`); `now:` is injectable.
`constructEvent` throws `OpensmsError` with `status == 0` and `code`
`invalid_signature` or `expired_signature`. The same helpers are also
available as `opensms.webhooks.verifySignature` and
`opensms.webhooks.constructEvent`.

## Testing

```sh
swift build
swift test                                  # offline, mock-transport tests
swift test --filter LiveConformanceTests    # live scenario against a sandbox; skipped unless
                                             # OPENSMS_BASE_URL and OPENSMS_API_KEY are set
```

## License

MIT.
