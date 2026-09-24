# @opensms/sdk (TypeScript)

Official TypeScript client for [opensms](https://opensms.io): prepaid SMS for Africa.

Zero runtime dependencies. Requires Node 18+ (or Bun, Deno, or any edge runtime with `fetch`).
Ships ESM and CommonJS builds with type definitions.

See the [monorepo root](../../README.md) for the other eight language clients, and
[`spec/SURFACE.md`](../../spec/SURFACE.md) for the full API surface this SDK wraps.

## Install

```bash
npm install @opensms/sdk
```

Not yet published; until then install from this repository: `npm install && npm run build` in
`packages/typescript`, then install the folder or a packed tarball (`npm pack`).

## Usage

```ts
import { Opensms } from '@opensms/sdk';

const opensms = new Opensms({ apiKey: process.env.OPENSMS_API_KEY! });

const msg = await opensms.messages.send({ to: '+254712345678', text: 'Your order has shipped' });
console.log(msg.id, msg.status);
```

The key selects the environment: `sk_test_` keys run in the sandbox (nothing reaches a handset,
sends cost `0.000000`), `sk_live_` keys send for real. `opensms.environment` is `"sandbox"` or
`"live"`. Field names are camelCase in the SDK; money is always a decimal string.

```ts
new Opensms({
  apiKey: 'sk_test_...',              // required, starts with sk_test_ or sk_live_
  baseUrl: 'https://api.opensms.io',  // default
  timeoutMs: 30_000,                  // per attempt, default
  maxRetries: 2,                      // retries after the first attempt, default
  fetch: customFetch,                 // custom fetch (tests, polyfills)
});
```

## More

Every method takes an optional last argument `{ idempotencyKey?, signal? }`.

### messages

```ts
const m = await opensms.messages.send({ to: '+254712345678', text: 'Hello' });
await opensms.messages.list({ limit: 20, status: 'delivered' });
await opensms.messages.get(m.id);
await opensms.messages.attempts(m.id);
await opensms.messages.cancel(m.id); // only queued or scheduled messages
```

### batches

```ts
const batch = await opensms.batches.create({
  items: [{ to: '+254712345678', text: 'Hi Ada' }],
});
await opensms.batches.start(batch.id); // batches are created "ready", started explicitly
await opensms.batches.listItems(batch.id, { limit: 50 });
```

### otp

```ts
const { otpId } = await opensms.otp.send({ to: '+254712345678', length: 6, ttlSeconds: 300 });
const { valid } = await opensms.otp.verify({ otpId, code: '123456' });
```

### lookups

```ts
const lookup = await opensms.lookups.create({ to: '+254712345678' });
await opensms.lookups.get(lookup.id);
```

### contacts

```ts
const c = await opensms.contacts.create({ e164: '+254712345678', name: 'Ada' });
await opensms.contacts.update(c.id, { name: 'Ada L' }); // partial
await opensms.contacts.list({ limit: 100 });
```

### contact groups

```ts
const g = await opensms.contactGroups.create({ name: 'VIP', contactIds: [c.id] });
await opensms.contactGroups.send(g.id, { text: 'Doors open at 9' }); // returns a running Batch
```

### templates

```ts
const t = await opensms.templates.create({ name: 'welcome', body: 'Hi {{name}}', trafficType: 'transactional' });
t.variables; // ["name"]
await opensms.contactGroups.send(g.id, { templateId: t.id, variables: { name: 'Ada' } });
```

### webhooks

```ts
const hook = await opensms.webhooks.create({
  url: 'https://example.com/opensms',
  events: ['message.delivered', 'message.failed'],
});
hook.secret; // "whsec_..." shown once: store it
await opensms.webhooks.listDeliveries(hook.id);
```

### inbound

```ts
const inbox = await opensms.inbound.list();
await opensms.inbound.reply(inbox.items[0]!.id, { text: 'Thanks!' }); // live keys only
```

### numbers

```ts
const available = await opensms.numbers.available({ country: 'KE', kind: 'long_code' });
const num = await opensms.numbers.assign({ country: 'KE', kind: 'long_code' }); // live only, charges the wallet
await opensms.numbers.createRule(num.id, { match: 'keyword', pattern: 'JOIN', action: 'auto_reply', target: 'Welcome!' });
```

### sender IDs

```ts
await opensms.senderIds.check({ value: 'ACME', country: 'KE' });
const sid = await opensms.senderIds.create({
  value: 'ACME', kind: 'alphanumeric', countries: ['KE'], documents: [],
}); // may charge fees, never retried
```

### suppressions

```ts
await opensms.suppressions.create({ e164: '+254712345678', reason: 'manual' });
await opensms.suppressions.list();
```

### compliance

```ts
const ke = await opensms.compliance.getCountry('KE'); // stopKeywords, quietHours, contentRules
await opensms.compliance.listContentRules();
```

### wallet

```ts
const balances = await opensms.wallet.balances(); // [{ currency: "KES", balance: "…", environment }]
const entries = await opensms.wallet.ledger({ limit: 100 });
// Ledger pages by id: pass the smallest id seen as `before`.
```

### pricing

```ts
await opensms.pricing.get({ product: 'sms', country: 'KE' });
```

### analytics

```ts
await opensms.analytics.overview({ range: '7d' });
await opensms.analytics.byCountry();
```

### sandbox

```ts
// Rendered text of sandbox sends, including OTP codes.
await opensms.sandbox.listMessages({ limit: 10 });
```

### countries

```ts
await opensms.countries.list();
await opensms.countries.carriers('KE');
```

### Pagination

Cursor lists return `{ items, nextCursor }`. Use the `paginate` helper to fetch every page lazily:

```ts
for await (const m of opensms.paginate(opensms.messages.list, { limit: 100 })) {
  console.log(m.id);
}
```

`paginate` is also exported as a standalone function, for lists that take an id first:
`paginate((p) => opensms.batches.listItems(batchId, p))`.

## Errors and retries

Every non-2xx response throws `OpensmsError`, built from the API's RFC 9457 problem body:

| Field | Meaning |
| --- | --- |
| `status` | HTTP status; `0` means no response (network error or timeout) |
| `type`, `title` | problem type and title (`about:blank` for most errors) |
| `detail` | human-readable reason (also the error `message`) |
| `code` | machine code, only on some errors (absent on most) |
| `traceId` | trace id, when the API sets one |
| `errors` | field validation errors (`field -> messages`), when present |
| `requestId` | `X-Request-ID`, set on message and OTP admission rejections |
| `retryAfter` | `Retry-After` in seconds, when the response sent one |
| `body` | the raw decoded response body |

```ts
import { Opensms, OpensmsError } from '@opensms/sdk';

try {
  await opensms.messages.send({ to: '+254712345678', text: 'Hi' });
} catch (e) {
  if (e instanceof OpensmsError) {
    if (e.status === 422) console.warn('rejected:', e.detail, e.requestId);
    else if (e.status === 429) console.warn('slow down, retry in', e.retryAfter, 's');
    else throw e;
  }
}
```

Branch on `status`, not `code`: most errors carry no `code`. Insufficient key scope is `401` on
`messages` and `otp` but `403` on every other resource.

The SDK retries `429`, `500`, `502`, `503`, `504`, and network errors or timeouts, only when the
request is safe to repeat: `GET`, `PUT`, `PATCH` and `DELETE` are always retryable, a `POST` only
when it carries an `Idempotency-Key`. The SDK generates one UUIDv4 per call and reuses it unchanged
across retries of that call; pass your own with `{ idempotencyKey }` to make retries safe across
processes. `Retry-After` is honoured (seconds or an HTTP date); if it asks for more than 60 seconds
the SDK does not wait, it throws with `retryAfter` set. Otherwise the delay is exponential backoff
with full jitter, capped at 8 seconds.

Never retried: `messages.cancel`, `otp.verify`, `senderIds.create`, `senderIds.createDraft`,
`suppressions.create`, `suppressions.import`, and any other `4xx`.

## Webhooks

Deliveries carry `X-OpenSMS-Signature: t=<unix>,v1=<hex>`, an HMAC-SHA256 of `"<t>.<raw body>"`
keyed with the endpoint's `whsec_...` secret used verbatim. Verify the raw body before parsing it.

```ts
import { constructEvent, OpensmsError } from '@opensms/sdk';

// Express: app.post('/opensms', express.raw({ type: 'application/json' }), handler)
function handler(req, res) {
  try {
    const event = constructEvent(req.body, req.header('X-OpenSMS-Signature'), process.env.OPENSMS_WEBHOOK_SECRET!);
    if (event.type === 'message.delivered') console.log(event.data.id);
    res.sendStatus(204);
  } catch (e) {
    if (e instanceof OpensmsError) return res.sendStatus(400); // code: invalid_signature | expired_signature
    throw e;
  }
}
```

`verifySignature(payload, header, secret, { toleranceSeconds })` returns a boolean instead, with a
default tolerance of 300 seconds. Both helpers need no API key and are also available as
`opensms.webhooks.constructEvent` and `opensms.webhooks.verifySignature`.

## Testing

```bash
npm test          # offline unit tests, no network
npm run test:live # live conformance suite; skipped unless OPENSMS_BASE_URL and OPENSMS_API_KEY are set
```

## License

MIT
