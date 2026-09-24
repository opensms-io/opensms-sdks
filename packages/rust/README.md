# opensms (Rust)

Official Rust client for [opensms](https://opensms.io): prepaid SMS for Africa. Send messages and
batches, run OTP, look up numbers, manage contacts, templates, webhooks, numbers and sender IDs, and
read your wallet and analytics.

Async (built on `reqwest` and `serde`, needs a Tokio runtime), edition 2021, four dependencies. One
transport layer handles bearer auth, Idempotency-Keys, retries with backoff, and error mapping.

## Install

```toml
[dependencies]
opensms = "0.1"   # once published; for now: opensms = { path = "../../packages/rust" }
tokio = { version = "1", features = ["full"] }
```

Not yet published to crates.io. Until then, depend on it by path from elsewhere in this repository,
or clone the monorepo and point `path` at `packages/rust`.

## Usage

```rust,no_run
use opensms::{Client, SendMessage};

#[tokio::main]
async fn main() -> Result<(), opensms::OpensmsError> {
    let client = Client::new(std::env::var("OPENSMS_API_KEY").unwrap())?;

    let message = client
        .messages()
        .send(&SendMessage::new("+254712345678", "Your order has shipped"))
        .await?;
    println!("{} is {:?}", message.id, message.status);
    Ok(())
}
```

The key must start with `sk_test_` (sandbox) or `sk_live_` (live) and have more than 12 characters
after the prefix; anything else fails in `Client::new` with no network call. `client.environment()`
returns `"sandbox"` or `"live"`. Override the base URL, timeout and retry count with the builder:

```rust,no_run
use std::time::Duration;
use opensms::Client;

let client = Client::builder("sk_test_...")
    .base_url("https://sandbox.opensms.io")
    .timeout(Duration::from_secs(60))
    .max_retries(4)
    .build()?;
# Ok::<(), opensms::OpensmsError>(())
```

Request structs use public fields: set the required ones with `new(...)` or a struct literal and fill
the rest with `..Default::default()`. Unset optional fields are left out of the request body. Money
and prices are decimal strings, timestamps are RFC 3339 strings, and `opensms::rfc3339(SystemTime)`
formats inputs such as `scheduled_at`.

## More

Every resource is an accessor on the client. Methods that send an Idempotency-Key have a `_with`
variant that takes `&RequestOptions`.

### messages

```rust,no_run
# async fn demo(client: &opensms::Client) -> Result<(), opensms::OpensmsError> {
use opensms::{ListMessages, RequestOptions, SendMessage};

let m = client.messages().send(&SendMessage::new("+254712345678", "Your order has shipped")).await?;
client.messages().send_with(
    &SendMessage::new("+254712345678", "Hi"),
    &RequestOptions::idempotency_key("order-1234"),
).await?;
client.messages().list(ListMessages { status: Some("delivered".into()), limit: Some(50), ..Default::default() }).await?;
client.messages().get(&m.id).await?;
client.messages().cancel(&m.id).await?;   // queued or scheduled only, never retried
# Ok(())
# }
```

### batches

```rust,no_run
# async fn demo(client: &opensms::Client) -> Result<(), opensms::OpensmsError> {
use opensms::{BatchItemInput, CreateBatch};

let batch = client.batches().create(&CreateBatch {
    items: vec![BatchItemInput::new("+254712345678", "Hello Ada")],
    dedupe: None,
}).await?;                              // created "ready"; sends nothing until start
client.batches().start(&batch.id).await?;
client.batches().get(&batch.id).await?;
client.batches().stop(&batch.id).await?;
# Ok(())
# }
```

### otp

```rust,no_run
# async fn demo(client: &opensms::Client) -> Result<(), opensms::OpensmsError> {
use opensms::{SendOtp, VerifyOtp};

let sent = client.otp().send(&SendOtp::new("+254712345678")).await?;
let result = client.otp().verify(&VerifyOtp::new(&sent.otp_id, "123456")).await?;
println!("valid={:?}", result.valid);   // verify is never retried
# Ok(())
# }
```

### lookups

```rust,no_run
# async fn demo(client: &opensms::Client) -> Result<(), opensms::OpensmsError> {
use opensms::CreateLookup;

let lookup = client.lookups().create(&CreateLookup { to: "+254712345678".into() }).await?;
client.lookups().get(&lookup.id).await?;
# Ok(())
# }
```

### contacts and contact_groups

```rust,no_run
# async fn demo(client: &opensms::Client) -> Result<(), opensms::OpensmsError> {
use opensms::{CreateContact, CreateContactGroup, ListParams, SendToGroup};

let contact = client.contacts().create(&CreateContact { e164: "+254712345678".into(), ..Default::default() }).await?;
client.contacts().list(ListParams::limit(100)).await?;

let group = client.contact_groups().create(&CreateContactGroup {
    name: "VIP".into(),
    contact_ids: Some(vec![contact.id.clone()]),
}).await?;
client.contact_groups().send(&group.id, &SendToGroup { text: Some("Doors open at 9".into()), ..Default::default() }).await?;
# Ok(())
# }
```

### templates

```rust,no_run
# async fn demo(client: &opensms::Client) -> Result<(), opensms::OpensmsError> {
use opensms::CreateTemplate;

let tpl = client.templates().create(&CreateTemplate {
    name: "welcome".into(),
    body: "Hi {{name}}".into(),
    traffic_type: None,
}).await?;
client.templates().list(Default::default()).await?;
# let _ = tpl;
# Ok(())
# }
```

### webhooks

```rust,no_run
# async fn demo(client: &opensms::Client) -> Result<(), opensms::OpensmsError> {
use opensms::CreateWebhook;

let wh = client.webhooks().create(&CreateWebhook {
    url: "https://example.com/opensms".into(),
    events: vec!["message.delivered".into()],
    enabled: None,
}).await?;
let secret = wh.secret.clone().unwrap();   // whsec_..., shown only once: store it
client.webhooks().test(&wh.id).await?;
# let _ = secret;
# Ok(())
# }
```

### inbound

```rust,no_run
# async fn demo(client: &opensms::Client) -> Result<(), opensms::OpensmsError> {
use opensms::{ListParams, ReplyInbound};

let inbox = client.inbound().list(ListParams::default()).await?;
if let Some(msg) = inbox.items.first() {
    client.inbound().reply(&msg.id, &ReplyInbound { text: "Thanks!".into() }).await?;  // live keys only
}
# Ok(())
# }
```

### numbers

```rust,no_run
# async fn demo(client: &opensms::Client) -> Result<(), opensms::OpensmsError> {
use opensms::NumberQuery;

let query = NumberQuery { country: "KE".into(), kind: "long_code".into() };
client.numbers().available(&query).await?;
let number = client.numbers().assign(&query).await?;   // live keys only, charges the wallet
client.numbers().release(&number.id).await?;
# Ok(())
# }
```

### sender_ids

```rust,no_run
# async fn demo(client: &opensms::Client) -> Result<(), opensms::OpensmsError> {
use opensms::{CheckSenderId, CreateSenderId};

client.sender_ids().check(&CheckSenderId { value: "ACME".into(), country: Some("KE".into()) }).await?;
let sender = client.sender_ids().create(&CreateSenderId {   // never retried: may charge fees
    value: "ACME".into(),
    kind: "alphanumeric".into(),
    countries: vec!["KE".into()],
    documents: vec![],
    ..Default::default()
}).await?;
client.sender_ids().get(&sender.id).await?;
# Ok(())
# }
```

### suppressions

```rust,no_run
# async fn demo(client: &opensms::Client) -> Result<(), opensms::OpensmsError> {
use opensms::CreateSuppression;

let s = client.suppressions().create(&CreateSuppression { e164: "+254712345678".into(), reason: "manual".into() }).await?;
client.suppressions().list(Default::default()).await?;
client.suppressions().delete(s.id).await?;
# Ok(())
# }
```

### compliance

```rust,no_run
# async fn demo(client: &opensms::Client) -> Result<(), opensms::OpensmsError> {
client.compliance().get_country("KE").await?;
client.compliance().list_content_rules().await?;
# Ok(())
# }
```

### wallet and pricing

```rust,no_run
# async fn demo(client: &opensms::Client) -> Result<(), opensms::OpensmsError> {
use opensms::PricingParams;

client.wallet().balances().await?;
client.wallet().ledger(Default::default()).await?;   // pages by `before`, not by cursor
client.pricing().get(PricingParams { product: Some("sms".into()), country: Some("KE".into()) }).await?;
# Ok(())
# }
```

### analytics and sandbox

```rust,no_run
# async fn demo(client: &opensms::Client) -> Result<(), opensms::OpensmsError> {
use opensms::AnalyticsQuery;

client.analytics().overview(AnalyticsQuery { range: Some("7d".into()), ..Default::default() }).await?;
client.sandbox().list_messages(Default::default()).await?;   // sandbox keys: rendered text, OTP codes included
# Ok(())
# }
```

### countries

```rust,no_run
# async fn demo(client: &opensms::Client) -> Result<(), opensms::OpensmsError> {
client.countries().list().await?;
client.countries().carriers("KE").await?;
# Ok(())
# }
```

### pagination

Cursor lists return `Page<T>` with `items` and `next_cursor`. `client.paginate` walks every page
lazily:

```rust,no_run
# async fn demo(client: &opensms::Client) -> Result<(), opensms::OpensmsError> {
use opensms::ListMessages;

let mut it = client.paginate(|cursor| {
    client.messages().list(ListMessages { limit: Some(100), cursor, ..Default::default() })
});
while let Some(message) = it.next().await {
    println!("{}", message?.id);
}
# Ok(())
# }
```

Bare-array endpoints (`messages().attempts`, `numbers().available`, `compliance()`, `countries()`,
the analytics breakdowns) return a plain `Vec<T>`, and `wallet().ledger` pages by `before` instead of
a cursor.

## Errors and retries

Every method returns `Result<T, OpensmsError>`. The error carries the RFC 9457 problem fields and the
useful headers:

| Field | Meaning |
| --- | --- |
| `status` | HTTP status; `0` means no HTTP response (network failure or timeout) |
| `type`, `title`, `detail` | problem body fields |
| `code` | machine code, absent on most errors |
| `trace_id`, `errors` | optional trace id and field errors |
| `request_id` | `X-Request-ID`, set on message and OTP admission rejections |
| `retry_after` | `Retry-After` in seconds, when the server sent one |
| `body` | raw decoded body (text wrapped as a JSON string when it was not JSON) |

```rust,no_run
# async fn demo(client: &opensms::Client) {
use opensms::SendMessage;

match client.messages().send(&SendMessage::new("+254712345678", "hi")).await {
    Ok(m) => println!("sent {}", m.id),
    Err(e) if e.status == 422 => eprintln!("rejected: {} (request {:?})", e.message, e.request_id),
    Err(e) if e.status == 429 => eprintln!("rate limited, retry in {:?} s", e.retry_after),
    Err(e) => eprintln!("error {}: {}", e.status, e.message),
}
# }
```

Branch on `status`, not `code`: most validation errors have no `code`, and insufficient scope is
`401` on `messages` and `otp` but `403` everywhere else.

Retries, up to `max_retries` (default 2, so 3 attempts):

- Retried on `429`, `500`, `502`, `503`, `504`, network errors and timeouts.
- `GET`, `PUT`, `PATCH` and `DELETE` are always retryable. A `POST` is retried only when it carries an
  Idempotency-Key; the SDK generates a UUIDv4 per call and reuses it unchanged on every retry, so a
  retried send is never duplicated.
- Never retried: `messages().cancel`, `otp().verify`, `sender_ids().create`,
  `sender_ids().create_draft`, `suppressions().create`, `suppressions().import`, and any other 4xx.
- `Retry-After` (seconds or an HTTP date) is honoured. If it asks for more than 60 s the call fails at
  once with `retry_after` set instead of waiting. Otherwise the delay is exponential backoff with full
  jitter, capped at 8 s: `random(0, min(8 s, 0.5 s * 2^(n-1)))`.

## Webhooks

Deliveries carry `X-OpenSMS-Signature: t=<unix>,v1=<hex>`. Verify the exact raw body bytes before
parsing, with the full `whsec_...` secret. No client or API key is needed:

```rust,no_run
use opensms::webhook::{construct_event, verify_signature, VerifyOptions, SIGNATURE_HEADER};

fn handle(raw_body: &[u8], signature_header: &str, secret: &str) -> Result<(), opensms::OpensmsError> {
    if !verify_signature(raw_body, signature_header, secret, VerifyOptions::default()) {
        return Ok(()); // reply 400
    }
    // Or verify and parse in one step; fails with code "invalid_signature" or "expired_signature".
    let event = construct_event(raw_body, signature_header, secret, VerifyOptions::default())?;
    println!("{} {:?}", SIGNATURE_HEADER, event.r#type);
    Ok(())
}
```

The default tolerance is 300 s (`VerifyOptions`). The same functions are available as
`client.webhooks().verify_signature(...)` and `client.webhooks().construct_event(...)`.

## Testing

```sh
cargo test                              # unit tests: mock transport, offline
cargo test --test live -- --nocapture   # live conformance scenario
```

The live suite runs against a sandbox and is skipped unless `OPENSMS_BASE_URL` and `OPENSMS_API_KEY`
are set. See the monorepo [README](../../README.md) and [`spec/SURFACE.md`](../../spec/SURFACE.md)
for the full API surface this SDK implements.

## License

MIT
