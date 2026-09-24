# Opensms (.NET)

Official .NET client for [opensms](https://opensms.io): prepaid SMS for Africa.

Targets `net8.0`. No dependencies beyond the .NET base class library.

See the [monorepo README](https://github.com/opensms-io/opensms-sdks) for the other language SDKs, and
[spec/SURFACE.md](https://github.com/opensms-io/opensms-sdks/blob/main/spec/SURFACE.md) for the full API surface this client wraps.

## Install

```bash
dotnet add package Opensms
```

## Usage

```csharp
using Opensms;

using var client = new OpensmsClient("sk_test_...");   // sk_live_... for real traffic

var message = await client.Messages.SendAsync(new SendMessageParams
{
    To = "+254712345678",
    Text = "Your order has shipped",
});

Console.WriteLine($"{message.Id} {message.Status}");
```

The key alone selects the workspace and environment: `sk_test_` keys use the sandbox
(`client.Environment == "sandbox"`), `sk_live_` keys send real SMS (`"live"`). A
malformed key throws `ArgumentException` in the constructor, before any request.

Options (all optional, passed as a second constructor argument):

```csharp
var client = new OpensmsClient(apiKey, new OpensmsClientOptions
{
    BaseUrl = "https://api.opensms.io",   // default
    Timeout = TimeSpan.FromSeconds(30),   // per attempt, default 30 s
    MaxRetries = 2,                       // retries after the first attempt, 0 disables
    HttpMessageHandler = handler,         // optional, for tests or custom networking
});
```

## More

Every example below assumes `client` from Usage.

### Messages

```csharp
var page = await client.Messages.ListAsync(new MessageListParams { Limit = 50, Status = "delivered" });
var one = await client.Messages.GetAsync(message.Id);
var attempts = await client.Messages.AttemptsAsync(message.Id);
await client.Messages.CancelAsync(message.Id);   // queued or scheduled only, never retried
```

### Batches

```csharp
var batch = await client.Batches.CreateAsync(new CreateBatchParams
{
    Items = new[] { new BatchItemInput { To = "+254712345678", Text = "Hi there" } },
});
var report = await client.Batches.ValidationAsync(batch.Id);   // per-row errors
await client.Batches.StartAsync(batch.Id);
var items = await client.Batches.ListItemsAsync(batch.Id);
await client.Batches.StopAsync(batch.Id);
```

### OTP

```csharp
var otp = await client.Otp.SendAsync(new SendOtpParams { To = "+254712345678", Length = 6, TtlSeconds = 300 });
var check = await client.Otp.VerifyAsync(new VerifyOtpParams { OtpId = otp.OtpId, Code = "123456" });
if (check.Valid) { /* signed in */ } else Console.WriteLine($"{check.AttemptsLeft} attempts left");
```

`VerifyAsync` is never retried automatically: a replay would use up an attempt.

### Lookups

```csharp
var lookup = await client.Lookups.CreateAsync(new CreateLookupParams { To = "+254712345678" });
var again = await client.Lookups.GetAsync(lookup.Id);
```

### Contacts

```csharp
var ada = await client.Contacts.CreateAsync(new CreateContactParams { E164 = "+254712345678", Name = "Ada" });
await client.Contacts.UpdateAsync(ada.Id, new UpdateContactParams { Name = "Ada L" });
var contacts = await client.Contacts.ListAsync(new ListParams { Limit = 200 });
await client.Contacts.DeleteAsync(ada.Id);
```

### Contact groups

```csharp
var group = await client.ContactGroups.CreateAsync(new CreateContactGroupParams { Name = "VIP", ContactIds = new[] { ada.Id } });
await client.ContactGroups.UpdateAsync(group.Id, new UpdateContactGroupParams { Name = "VIP 2026" });
var running = await client.ContactGroups.SendAsync(group.Id, new GroupSendParams { Text = "Doors open at 9" });
await client.ContactGroups.DeleteAsync(group.Id);   // members are kept
```

### Templates

```csharp
var tpl = await client.Templates.CreateAsync(new CreateTemplateParams { Name = "welcome", Body = "Hi {{name}}" });
await client.ContactGroups.SendAsync(group.Id, new GroupSendParams
{
    TemplateId = tpl.Id,
    Variables = new Dictionary<string, string> { ["name"] = "Ada" },
});
await client.Templates.DeleteAsync(tpl.Id);
```

### Webhooks

```csharp
var hook = await client.Webhooks.CreateAsync(new CreateWebhookParams
{
    Url = "https://example.com/opensms",
    Events = new[] { "message.delivered", "message.failed" },
});
var secret = hook.Secret;   // whsec_..., shown only once: store it

var deliveries = await client.Webhooks.ListDeliveriesAsync(hook.Id);
var d = deliveries.Items[0];
await client.Webhooks.ReplayDeliveryAsync(hook.Id, d.Id, new ReplayDeliveryParams { Generation = d.Generation!.Value, Reason = "endpoint was down" });
```

See [Webhooks](#webhooks) below for verifying signatures.

### Inbound

```csharp
var inbound = await client.Inbound.ListAsync();
await client.Inbound.ReplyAsync(inbound.Items[0].Id, new InboundReplyParams { Text = "Thanks!" });   // live keys only
```

### Numbers

```csharp
var available = await client.Numbers.AvailableAsync(new NumberSearchParams { Country = "KE", Kind = "long_code" });
var number = await client.Numbers.AssignAsync(new NumberSearchParams { Country = "KE", Kind = "long_code" });   // live, charges the wallet
var rule = await client.Numbers.CreateRuleAsync(number.Id, new NumberRuleParams { Match = "keyword", Pattern = "STOP", Action = "webhook", Target = "https://example.com/in" });
await client.Numbers.ReleaseAsync(number.Id);
```

### Sender IDs

```csharp
var check = await client.SenderIds.CheckAsync(new SenderIdCheckParams { Value = "ACME", Country = "KE" });
var quote = await client.SenderIds.QuoteAsync(new SenderIdQuoteParams { Countries = new[] { "KE", "NG" } });

var sender = await client.SenderIds.CreateAsync(new CreateSenderIdParams
{
    Value = "ACME", Kind = "alphanumeric", Countries = new[] { "KE" },
    Documents = new[] { "doc_123" },   // uploaded via the console
    QuoteId = quote.QuoteId,
});
```

Document upload and download are console only. `CreateAsync`, `CreateDraftAsync` and the
suppression writes below may charge fees or bypass review, so they are never auto-retried.

### Suppressions

```csharp
var s = await client.Suppressions.CreateAsync(new SuppressionParams { E164 = "+254712345678", Reason = "manual" });
var result = await client.Suppressions.ImportAsync(new[] { new SuppressionParams { E164 = "+254712345678", Reason = "complaint" } });
await client.Suppressions.DeleteAsync(s.Id);
```

### Compliance

```csharp
var kenya = await client.Compliance.GetCountryAsync("KE");   // stop keywords, quiet hours, content rules
var rules = await client.Compliance.ListContentRulesAsync();
```

### Wallet

```csharp
var balances = await client.Wallet.BalancesAsync();   // Balance is a decimal string
var ledger = await client.Wallet.LedgerAsync(new LedgerParams { Limit = 50 });
var topup = await client.Wallet.CreateTopupAsync(new CreateTopupParams { Amount = "1000", Currency = "KES", Channel = "mobile_money", Email = "billing@example.com" });
// open topup.AuthorizationUrl to pay (live keys only)
```

The ledger pages with `Before` (the smallest id seen); stop when fewer than `Limit` rows come back.

### Pricing

```csharp
var prices = await client.Pricing.GetAsync(new PricingParams { Product = "sms", Country = "KE" });
```

### Analytics

```csharp
var overview = await client.Analytics.OverviewAsync(new AnalyticsQuery { Range = "7d" });
var byCountry = await client.Analytics.ByCountryAsync();
var series = await client.Analytics.TimeseriesAsync(new AnalyticsQuery { From = "2026-09-01", To = "2026-09-24", Bucket = "day" });
```

### Sandbox

```csharp
var sent = await client.Sandbox.ListMessagesAsync(new ListParams { Limit = 10 });   // rendered text, including OTP codes
```

### Countries

```csharp
var countries = await client.Countries.ListAsync();
var carriers = await client.Countries.CarriersAsync("KE");
```

### Pagination

Cursor lists return `Page<T>` (`Items`, `NextCursor`). `PaginateAsync` walks every page:

```csharp
await foreach (var m in client.PaginateAsync(client.Messages.ListAsync, new MessageListParams { Limit = 100 }))
    Console.WriteLine(m.Id);
```

## Errors and retries

Every non-2xx response throws `OpensmsException`, mapped from the API's
`application/problem+json` body:

| Property | Meaning |
| --- | --- |
| `Status` | HTTP status; `0` when no response arrived (network failure or timeout) |
| `Type`, `Title`, `Detail` | problem fields; `Message` is `Detail`, else `Title` |
| `Code` | optional machine code (absent on most errors) |
| `TraceId`, `Errors` | optional trace id and per-field errors |
| `RequestId` | `X-Request-ID` header, set on message and OTP admission rejections |
| `RetryAfter` | `Retry-After` in seconds, when present |
| `Body` | the raw response body text |

Insufficient key scope is **401** on messages and OTP but **403** everywhere else, so
branch on `Status`, not `Code`.

The client retries `429`, `500`, `502`, `503`, `504`, and network errors or timeouts,
up to `MaxRetries` times (default 2, so 3 attempts in total):

- `GET`, `PUT`, `PATCH` and `DELETE` are always retried.
- `POST`s are retried only when they carry an `Idempotency-Key`. The SDK generates a
  UUIDv4 once per call and reuses it on every retry, so the server replays the first
  result instead of sending twice. `Messages.CancelAsync`, `Otp.VerifyAsync`,
  `SenderIds.CreateAsync`, `SenderIds.CreateDraftAsync`, `Suppressions.CreateAsync`
  and `Suppressions.ImportAsync` are never retried.
- `Retry-After` is honoured. If it asks for more than 60 seconds the SDK throws
  instead, with `RetryAfter` set, so you can decide.
- Otherwise the delay is exponential backoff with full jitter, capped at 8 seconds.
- Other 4xx responses are never retried.

## Webhooks

Deliveries carry `X-OpenSMS-Signature: t=<unix>,v1=<hex>`, an HMAC-SHA256 of
`"<t>.<raw body>"` keyed with the endpoint's full `whsec_...` secret. Verify the exact
raw bytes before parsing. `WebhookSignature` needs no API key:

```csharp
using var ms = new MemoryStream();
await req.Body.CopyToAsync(ms);
try
{
    var evt = WebhookSignature.ConstructEvent(ms.ToArray(), req.Headers[WebhookSignature.HeaderName], secret);
    if (evt.Type == "message.delivered") { /* evt.Data is the Message */ }
}
catch (OpensmsException e) when (e.Code is "invalid_signature" or "expired_signature")
{
    // reject the delivery
}
```

`WebhookSignature.Verify(...)` returns a `bool` instead of throwing. The default
tolerance is 300 seconds; pass `tolerance:` to change it. The same helpers are
available as `client.Webhooks.VerifySignature(...)` and `client.Webhooks.ConstructEvent(...)`.

## Testing

```bash
dotnet build Opensms.csproj
dotnet test tests/Opensms.Tests.csproj
```

Unit tests run offline. The live conformance suite runs only when `OPENSMS_BASE_URL`
and `OPENSMS_API_KEY` are set in the environment, and is skipped otherwise.

## License

MIT
