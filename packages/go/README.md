# opensms-go (Go)

Official Go client for [opensms](https://opensms.io): prepaid SMS for Africa.

Requires Go 1.21+. Standard library only, no dependencies. See the
[monorepo overview](https://github.com/opensms-io/opensms-sdks) for what every language client shares, and
[spec/SURFACE.md](https://github.com/opensms-io/opensms-sdks/blob/main/spec/SURFACE.md) for the full method and field list this client wraps.

## Install

```sh
go get github.com/opensms-io/opensms-go
```

## Usage

```go
package main

import (
	"context"
	"log"

	opensms "github.com/opensms-io/opensms-go"
)

func main() {
	client, err := opensms.NewClient("sk_test_...")
	if err != nil {
		log.Fatal(err) // the key is malformed; no request was made
	}

	msg, err := client.Messages.Send(context.Background(), opensms.SendMessageParams{
		To:   "+254712345678",
		Text: "Your order has shipped",
	})
	if err != nil {
		log.Fatal(err)
	}
	log.Printf("sent %s (%s)", msg.ID, msg.Status)
}
```

`sk_test_` keys run against the sandbox (free, mock delivery); `sk_live_` keys send real traffic.
The key alone selects the workspace and environment; `client.Environment()` returns `sandbox` or
`live`.

## More

Money, prices and balances decode as decimal strings, never floats. Timestamps decode to
`time.Time`. Optional pointer fields take the `opensms.Bool` and `opensms.Int` helpers.

### Messages

```go
msg, err := client.Messages.Send(ctx, opensms.SendMessageParams{To: "+254712345678", Text: "Your code is ready"})
page, err := client.Messages.List(ctx, opensms.ListMessagesParams{Limit: 50, Status: "delivered"})
msg, err = client.Messages.Get(ctx, msg.ID)
attempts, err := client.Messages.Attempts(ctx, msg.ID)
msg, err = client.Messages.Cancel(ctx, msg.ID) // queued or scheduled only, never retried
```

### Batches

```go
b, err := client.Batches.Create(ctx, opensms.CreateBatchParams{Items: []opensms.BatchItemInput{
	{To: "+254712345678", Text: "Hello Ada"},
}})
b, err = client.Batches.Start(ctx, b.ID) // batches send nothing until started
items, err := client.Batches.ListItems(ctx, b.ID, opensms.ListBatchItemsParams{})
```

### OTP

```go
res, err := client.OTP.Send(ctx, opensms.SendOTPParams{To: "+254712345678", Length: 6, TTLSeconds: 300})
v, err := client.OTP.Verify(ctx, opensms.VerifyOTPParams{OTPID: res.OTPID, Code: "123456"})
if v.Valid { /* ... */ } // a wrong code returns Valid false and uses an attempt, never retried
```

### Lookups

```go
l, err := client.Lookups.Create(ctx, opensms.CreateLookupParams{To: "+254712345678"})
l, err = client.Lookups.Get(ctx, l.ID) // 202 on create means still pending: poll Get
```

### Contacts

```go
c, err := client.Contacts.Create(ctx, opensms.CreateContactParams{E164: "+254712345678", Name: "Ada"})
c, err = client.Contacts.Update(ctx, c.ID, opensms.UpdateContactParams{Name: "Ada L"})
page, err := client.Contacts.List(ctx, opensms.ListParams{Limit: 100})
err = client.Contacts.Delete(ctx, c.ID)
```

### Contact groups

```go
g, err := client.ContactGroups.Create(ctx, opensms.CreateContactGroupParams{Name: "VIP", ContactIDs: []string{c.ID}})
batch, err := client.ContactGroups.Send(ctx, g.ID, opensms.GroupSendParams{Text: "Hi from OpenSMS"})
err = client.ContactGroups.Delete(ctx, g.ID)
```

### Templates

```go
tpl, err := client.Templates.Create(ctx, opensms.CreateTemplateParams{Name: "welcome", Body: "Hi {{name}}"})
batch, err := client.ContactGroups.Send(ctx, g.ID, opensms.GroupSendParams{
	TemplateID: tpl.ID, Variables: map[string]string{"name": "Ada"},
})
```

### Webhooks

```go
wh, err := client.Webhooks.Create(ctx, opensms.CreateWebhookParams{
	URL:    "https://example.com/opensms",
	Events: []string{"message.delivered", "message.failed"},
})
secret := wh.Secret // whsec_..., returned only once: store it
deliveries, err := client.Webhooks.ListDeliveries(ctx, wh.ID, opensms.ListParams{})
```

See [Webhooks](#webhooks) below for verifying incoming deliveries.

### Inbound

```go
page, err := client.Inbound.List(ctx, opensms.ListParams{})
reply, err := client.Inbound.Reply(ctx, page.Items[0].ID, opensms.InboundReplyParams{Text: "Thanks!"}) // live keys only
```

### Numbers

`List` and `Available` work with any key; the rest need a live key.

```go
avail, err := client.Numbers.Available(ctx, opensms.AvailableNumbersParams{Country: "KE", Kind: "long_code"})
n, err := client.Numbers.Assign(ctx, opensms.AssignNumberParams{Country: "KE", Kind: "long_code"}) // charges the wallet
rule, err := client.Numbers.CreateRule(ctx, n.ID, opensms.NumberRuleParams{
	Match: "keyword", Pattern: "HELP", Action: "auto_reply", Target: "Reply STOP to opt out",
})
```

### Sender IDs

```go
quote, err := client.SenderIDs.Quote(ctx, opensms.QuoteSenderIDParams{Countries: []string{"KE", "NG"}})
s, err := client.SenderIDs.Create(ctx, opensms.CreateSenderIDParams{
	Value: "ACME", Kind: "alphanumeric", Countries: []string{"KE"},
	UseCase: "transactional", QuoteID: quote.QuoteID,
}) // may charge fees (see Quote), never retried
```

### Suppressions

```go
s, err := client.Suppressions.Create(ctx, opensms.CreateSuppressionParams{E164: "+254712345678", Reason: "manual"}) // never retried
res, err := client.Suppressions.Import(ctx, []opensms.SuppressionInput{{E164: "+254712345699", Reason: "complaint"}}) // never retried
err = client.Suppressions.Delete(ctx, s.ID)
```

### Compliance

```go
ke, err := client.Compliance.GetCountry(ctx, "KE") // stop keywords, quiet hours, content rules
all, err := client.Compliance.ListCountries(ctx)
```

### Wallet

```go
balances, err := client.Wallet.Balances(ctx)
entries, err := client.Wallet.Ledger(ctx, opensms.LedgerParams{Limit: opensms.Int(50)})
// Ledger pages with Before (the smallest id seen), not cursors.
older, err := client.Wallet.Ledger(ctx, opensms.LedgerParams{Limit: opensms.Int(50), Before: entries[len(entries)-1].ID})
```

### Pricing

```go
prices, err := client.Pricing.Get(ctx, opensms.PricingParams{Product: "sms", Country: "KE"})
```

### Analytics

```go
ov, err := client.Analytics.Overview(ctx, opensms.AnalyticsParams{Range: "7d"})
byCountry, err := client.Analytics.ByCountry(ctx, opensms.AnalyticsParams{})
series, err := client.Analytics.Timeseries(ctx, opensms.AnalyticsParams{Bucket: "day"})
```

### Sandbox

```go
page, err := client.Sandbox.ListMessages(ctx, opensms.ListParams{Limit: 10}) // rendered text, including OTP codes
```

### Countries

```go
countries, err := client.Countries.List(ctx)
carriers, err := client.Countries.Carriers(ctx, "KE")
```

### Pagination

Cursor lists return `*opensms.Page[T]` with `Items` and `NextCursor` (empty on the last page).
`Paginate` walks every page lazily:

```go
it := opensms.Paginate(ctx, client.Messages.List, opensms.ListMessagesParams{Limit: 100})
for it.Next() {
	m := it.Item()
	_ = m
}
if err := it.Err(); err != nil {
	log.Fatal(err)
}
```

For a list method that takes an id (`Batches.ListItems`, `Webhooks.ListDeliveries`,
`Numbers.ListRules`), wrap the call in a closure that captures it.

## Errors and retries

Every non-2xx response, and every transport failure that survives all retries, is a
`*opensms.Error`, mapped from the RFC 9457 problem+json body:

```go
_, err := client.Messages.Send(ctx, params)
var oe *opensms.Error
if errors.As(err, &oe) {
	log.Printf("status=%d detail=%q code=%q request=%q", oe.Status, oe.Detail, oe.Code, oe.RequestID)
}
```

| Field | Meaning |
| --- | --- |
| `Status` | HTTP status; `0` means no response (network failure or timeout) |
| `Type`, `Title`, `Detail` | problem fields; `Detail` is the human text |
| `Code` | machine code, when present |
| `TraceID`, `Errors` | trace id and field validation errors, when present |
| `RequestID` | `X-Request-ID`, set on message and OTP admission rejections |
| `RetryAfter` | the `Retry-After` header, when present |
| `Body` | raw response body |

Most errors carry no `Code`, so branch on `Status` and show `Detail`. Insufficient scope is
**401** on `Messages` and `OTP` but **403** on every other resource.

Errors raised before any request (a malformed API key in `NewClient`, an empty id) wrap
`opensms.ErrInvalidArgument`; test them with `errors.Is`.

Retries: `429`, `500`, `502`, `503`, `504`, network errors and timeouts are retried with
exponential backoff and full jitter, capped at 8s. `GET`, `PUT`, `PATCH` and `DELETE` are always
retryable; `POST` only when it carries an `Idempotency-Key`, which the SDK generates once per call
(a UUIDv4) and reuses unchanged on every retry of that call. A `Retry-After` header (seconds or an
HTTP date) is honoured; if it asks for more than 60s the SDK does not wait, it returns the error
with `RetryAfter` set instead. Other `4xx` responses are never retried, and neither are
`Messages.Cancel`, `OTP.Verify`, `SenderIDs.Create`, `SenderIDs.CreateDraft`,
`Suppressions.Create` and `Suppressions.Import`.

## Webhooks

Each delivery carries `X-OpenSMS-Signature: t=<unix>,v1=<hex>`, HMAC-SHA256 of `"<t>.<raw body>"`
keyed with the endpoint's `whsec_...` secret, used verbatim. Verify the raw body before parsing it;
no client or API key is needed:

```go
func handler(w http.ResponseWriter, r *http.Request) {
	body, _ := io.ReadAll(r.Body)
	event, err := opensms.ConstructEvent(body, r.Header.Get(opensms.SignatureHeader), os.Getenv("OPENSMS_WEBHOOK_SECRET"))
	if err != nil {
		http.Error(w, "bad signature", http.StatusBadRequest) // Code is invalid_signature or expired_signature
		return
	}
	log.Printf("%s %v", event.Type, event.Data["status"])
	w.WriteHeader(http.StatusNoContent)
}
```

`opensms.VerifySignature(body, header, secret)` returns a plain bool instead. The default
tolerance is 300 seconds; override it with `opensms.VerifyOptions{Tolerance: 10 * time.Minute}`.

## Not covered

Account, team and key management, workspace settings, billing documents, onboarding and sender
document upload are console-only (session auth) and are not in this SDK. The realtime WebSocket
stream is not wrapped either.

## Testing

Unit tests need no network:

```sh
go test ./...
```

The live suite runs the CONFORMANCE.md scenario against a sandbox. It runs only when
`OPENSMS_BASE_URL` and `OPENSMS_API_KEY` are set, and is skipped otherwise:

```sh
go test -run TestLiveConformance -v ./...
```

## License

MIT
