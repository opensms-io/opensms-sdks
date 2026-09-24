# opensms-java (Java)

Official Java client for [opensms](https://opensms.io): prepaid SMS for Africa.

Targets Java 17+. Uses `java.net.http.HttpClient` for transport, with one dependency (Jackson) for JSON.

## Install

Maven:

```xml
<dependency>
  <groupId>io.opensms</groupId>
  <artifactId>opensms-java</artifactId>
  <version>0.1.0</version>
</dependency>
```

Gradle:

```kotlin
implementation("io.opensms:opensms-java:0.1.0")
```

Not yet published to Maven Central: for now, run `mvn install` in this directory to put `io.opensms:opensms-java:0.1.0` in your local repository, then depend on it as above.

## Usage

```java
import io.opensms.*;
import io.opensms.models.*;

OpensmsClient opensms = new OpensmsClient("sk_test_...");

Message m = opensms.messages().send(new SendMessageParams("+254712345678", "Your order has shipped"));
System.out.println(m.id + " " + m.status); // e.g. queued
```

`sk_test_` keys run in the sandbox (free, mock delivery); `sk_live_` keys send real SMS. A malformed
key throws `IllegalArgumentException` before any network call, and `opensms.environment()` returns
`"sandbox"` or `"live"`. For custom settings (base URL, timeout, retries, a proxied `HttpClient`),
build with `OpensmsClient.builder()...build()`. The client is thread-safe; create one and reuse it.

## More

One short example per resource, in the order the client exposes them. Full parameter lists are in
the Javadoc and [spec/SURFACE.md](../../spec/SURFACE.md).

### messages

```java
Message m = opensms.messages().send(new SendMessageParams("+254712345678", "Hello")
    .senderId("ACME").trafficType("transactional"));
Page<Message> page = opensms.messages().list(new MessageListParams().status("delivered").limit(50));
Message one = opensms.messages().get(m.id);
opensms.messages().cancel(m.id); // only queued or scheduled messages
```

### batches

```java
Batch b = opensms.batches().create(List.of(
    new BatchItemInput("+254712345678", "Hi Ada"),
    new BatchItemInput("+254712345679", "Hi Grace")));
opensms.batches().start(b.id); // nothing is sent until start
Page<Message> items = opensms.batches().listItems(b.id);
```

### otp

```java
OtpSendResult sent = opensms.otp().send(new OtpSendParams("+254712345678").length(6));
OtpVerifyResult r = opensms.otp().verify(sent.otpId, "123456");
if (Boolean.TRUE.equals(r.valid)) { /* signed in */ }
```

### lookups

```java
Lookup l = opensms.lookups().create("+254712345678");
```

### contacts

```java
Contact c = opensms.contacts().create(new ContactParams().e164("+254712345678").name("Ada"));
opensms.contacts().update(c.id, new ContactParams().name("Ada L")); // partial update
Page<Contact> contacts = opensms.contacts().list(ListParams.ofLimit(100));
```

### contactGroups

```java
ContactGroup g = opensms.contactGroups().create(
    new ContactGroupParams().name("VIP").contactIds(List.of(c.id)));
Batch sent = opensms.contactGroups().send(g.id, new GroupSendParams().text("Doors open at 9"));
```

### templates

```java
Template tpl = opensms.templates().create(new TemplateParams().name("welcome").body("Hi {{name}}"));
Page<Template> templates = opensms.templates().list();
```

### webhooks

```java
WebhookEndpoint w = opensms.webhooks().create(new WebhookParams("https://example.com/opensms",
    List.of("message.delivered", "message.failed")));
String secret = w.secret; // whsec_..., shown only once: store it
opensms.webhooks().test(w.id);
```

### inbound

```java
Page<InboundMessage> inbox = opensms.inbound().list();
Message reply = opensms.inbound().reply(inbox.items.get(0).id, "Thanks!"); // live keys only
```

### numbers

```java
List<VirtualNumber> available = opensms.numbers().available("KE", "long_code");
VirtualNumber n = opensms.numbers().assign("KE", "long_code"); // live keys only, charges the wallet
opensms.numbers().createRule(n.id,
    new NumberRuleParams("keyword", "auto_reply", "Thanks, we got it").pattern("INFO"));
```

### senderIds

```java
SenderIdCheck check = opensms.senderIds().check("ACME", "KE");
SenderIdDraft draft = opensms.senderIds().createDraft(new SenderIdDraftParams()
    .value("ACME").kind("alphanumeric").countries(List.of("KE")).useCase("transactional"));
SenderId s = opensms.senderIds().create(new SenderIdCreateParams("ACME", "alphanumeric",
    List.of("KE"), List.of(certificateId, signatoryId, authorizationId)));
```

### suppressions

```java
Suppression s = opensms.suppressions().create("+254712345678", "manual");
opensms.suppressions().importItems(List.of(new SuppressionInput("+254712345679", "complaint")));
```

`importItems` is the canonical `import` method (`import` is a reserved word in Java).

### compliance

```java
CountryRules ke = opensms.compliance().getCountry("KE");
List<ContentRule> rules = opensms.compliance().listContentRules();
```

### wallet

```java
List<WalletBalance> balances = opensms.wallet().balances();
Topup t = opensms.wallet().createTopup(
    new TopupParams("1000.00", "KES", "mobile_money", "billing@example.com"));
// redirect the payer to t.authorizationUrl (live keys only)
```

### pricing

```java
PriceList prices = opensms.pricing().get("sms", "KE");
```

### analytics

```java
AnalyticsOverview o = opensms.analytics().overview(new AnalyticsParams().range("7d"));
List<AnalyticsBreakdown> byCountry = opensms.analytics().byCountry();
```

### sandbox

```java
// Rendered text of sandbox sends, including OTP codes
Page<SandboxMessage> sandbox = opensms.sandbox().listMessages(ListParams.ofLimit(10));
```

### countries

```java
List<Country> countries = opensms.countries().list();
CountryRules rules = opensms.countries().compliance("KE");
```

### Pagination

Cursor lists return `Page<T>` (`items`, `nextCursor`). `paginate` walks every item, fetching pages
lazily:

```java
for (Message m : opensms.paginate(opensms.messages()::list, new MessageListParams().limit(100))) {
    System.out.println(m.id);
}
```

## Errors and retries

Every non-2xx response throws the unchecked `OpensmsException`, mapped from the RFC 9457 problem body:

| Getter | Meaning |
| --- | --- |
| `getStatus()` | HTTP status, `0` when no response was received |
| `getType()`, `getTitle()`, `getDetail()` | problem fields |
| `getCode()` | machine code, absent on most errors |
| `getErrors()` | field validation errors, if any |
| `getTraceId()` | trace id, if any |
| `getRequestId()` | `X-Request-ID`, set on message and OTP admission rejections |
| `getRetryAfter()` | seconds, if the server sent `Retry-After` |
| `getBody()` | decoded JSON (`JsonNode`) or raw text |

Branch on `getStatus()`, not `getCode()`. Note that **insufficient scope is `401` on `messages()`
and `otp()` but `403` everywhere else**.

Retried automatically: `429`, `500`, `502`, `503`, `504`, and network errors or timeouts, with
exponential backoff (full jitter, capped at 8 s), or the server's `Retry-After` when present (if it
asks for more than 60 s, the SDK throws instead of waiting, with `getRetryAfter()` set). `GET`,
`PUT`, `PATCH` and `DELETE` are always retryable; a `POST` is retried only when it carries an
`Idempotency-Key`, which the SDK generates once per call (a UUIDv4) and reuses unchanged on every
retry. Pass your own with `RequestOptions.idempotencyKey("order-42-sms")`.

Never retried: `messages().cancel`, `otp().verify`, `senderIds().create`, `senderIds().createDraft`,
`suppressions().create`, `suppressions().importItems`, and any other 4xx.

## Webhooks

Deliveries carry `X-OpenSMS-Signature: t=<unix>,v1=<hex>`, an HMAC-SHA256 of `"<t>.<raw body>"`
keyed with the endpoint's `whsec_...` secret, used verbatim. Verify the raw body bytes before
parsing:

```java
byte[] raw = request.getInputStream().readAllBytes();
String header = request.getHeader("X-OpenSMS-Signature");
try {
    WebhookEvent event = WebhookSignature.constructEvent(raw, header, secret); // 300 s tolerance
    if ("message.delivered".equals(event.type)) {
        String messageId = event.data.get("id").asText();
    }
} catch (OpensmsException e) {
    // e.getCode() is "invalid_signature" or "expired_signature": respond 400
}
```

`WebhookSignature.verify(raw, header, secret)` returns a plain `boolean`. The same helpers are also
available on the client as `opensms.webhooks().constructEvent(...)` and
`opensms.webhooks().verifySignature(...)`. No API key is needed to verify a signature.

## Testing

```sh
mvn -B test                             # unit tests, no network
mvn -B test -Dtest=LiveConformanceTest  # live suite; skipped unless OPENSMS_BASE_URL and OPENSMS_API_KEY are set
```

See the [monorepo README](../../README.md) and [spec/SURFACE.md](../../spec/SURFACE.md) for the
full API surface.

## License

MIT (c) OpenSMS
