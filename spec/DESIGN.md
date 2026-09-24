# OpenSMS SDK - Design Contract

Every SDK (typescript, python, go, ruby, php, java, dotnet, rust, swift)
exposes the SAME resources and methods over the SURFACE.md contract, with the
same transport behaviour. Names below are canonical camelCase; each language
applies its own idiom (snake_case for python, ruby and rust; PascalCase
exported identifiers for go and dotnet). The structure follows the Axene
Mailer SDKs, adjusted for what the OpenSMS
API actually does.

## Package names

No opensms repository claims these names. The only
existing package is the private, generated `@opensms/api-client` in
`api/sdk/typescript` (not published, `"private": true`), which these names do
not collide with.

| Language | Registry | Package / coordinates | Import / namespace | Client type | Error type |
| --- | --- | --- | --- | --- | --- |
| typescript | npm | `@opensms/sdk` | `import { Opensms } from '@opensms/sdk'` | `Opensms` | `OpensmsError` |
| python | PyPI | `opensms` | `import opensms` / `from opensms import Opensms` | `Opensms` | `OpensmsError` |
| go | Go modules (git tag) | `github.com/opensms-io/opensms-go` | `package opensms` | `*opensms.Client` | `*opensms.Error` |
| ruby | RubyGems | `opensms` | `require "opensms"`, module `Opensms` | `Opensms::Client` | `Opensms::Error` |
| php | Packagist | `opensms/opensms-php` | namespace `Opensms\` | `Opensms\Client` | `Opensms\OpensmsException` |
| java | Maven Central | `io.opensms:opensms-java` | package `io.opensms` | `OpensmsClient` | `OpensmsException` (unchecked) |
| dotnet | NuGet | `Opensms` | namespace `Opensms` | `OpensmsClient` | `OpensmsException` |
| rust | crates.io | `opensms` | `use opensms::Client` | `opensms::Client` | `opensms::OpensmsError` |
| swift | SwiftPM (git tag) | `opensms-swift`, library `Opensms` | `import Opensms` | `OpensmsClient` | `OpensmsError` |

"OpensmsError" below means the language's error type from this table.
User-Agent is `opensms-<lang>/<version>` (for example `opensms-python/0.1.0`).
Initial version for every package: `0.1.0`. Packages live in
`packages/<lang>/` of this monorepo; Go and Swift are released by git tag
from their own repos, like Axene.

## Client

Constructor options:

| Option | Default | Rule |
| --- | --- | --- |
| `apiKey` | required | Must start with `sk_test_` or `sk_live_` and have more than 12 characters after the prefix (mirrors `auth.ValidSecret`). Anything else fails fast with the language's argument error (`TypeError`, `ValueError`, `ArgumentException`, `IllegalArgumentException`, `InvalidArgumentException`, Go returns an `error` from `NewClient`, Rust returns `Err`). No network call. |
| `baseUrl` | `https://opensms.io` | Trailing slashes stripped. The OpenAPI `servers` block only lists `http://localhost:8080`, so the default comes from the live API: `GET https://opensms.io/v1/me` answers 401. The problem `type` base (`https://api.opensms.io/problems/<code>`, from `internal/httpx/problempb`) is a separate RFC 9457 type-URI namespace that does not resolve as a host and must not be used as the default base URL. |
| `timeout` | 30 s | Per attempt, covers connect and read. |
| `maxRetries` | 2 | Number of retries after the first attempt (so 3 attempts total). `0` disables retries. |
| transport hook | platform default | Injectable HTTP client/fetch/handler so unit tests can use a mock transport (TS `fetch`, Python a transport callable over the stdlib `urllib` default with no runtime dependencies, Go `*http.Client`, Java `HttpClient`, .NET `HttpMessageHandler`, etc.). |

The client exposes `environment` (read-only): `"sandbox"` for `sk_test_`,
`"live"` for `sk_live_`. SDKs do not read environment variables implicitly;
tests read `OPENSMS_BASE_URL` and `OPENSMS_API_KEY` themselves.

Resources hang off the client as properties/fields: `messages`, `batches`,
`otp`, `lookups`, `contacts`, `contactGroups`, `templates`, `webhooks`,
`inbound`, `numbers`, `senderIds`, `suppressions`, `compliance`, `wallet`,
`pricing`, `analytics`, `sandbox`, `countries`. Method names are exactly those
in SURFACE.md.

## Separation of concerns

One file/module each for: client (construction, wiring resources), transport
(the only code that touches the network), errors, models/types, pagination,
webhook signature verification, and one file per resource. Resources are thin:
build path, query and body, call the transport, decode the model.

## Transport

Every request:

- `Authorization: Bearer <apiKey>`
- `Accept: application/json`
- `User-Agent: opensms-<lang>/<version>`
- `Content-Type: application/json` when there is a JSON body (the CSV batch
  entry point sends `text/csv`).
- Never `X-Workspace-ID` or `X-Environment` (the key selects both; batch and
  analytics answer `403` if they disagree).
- Path parameters are URL-escaped. Query parameters that are unset are
  omitted; list-valued query parameters (`senderIds.quote` `countries`) are
  joined with commas.
- Request bodies omit unset optional fields entirely. Handlers reject unknown
  fields, and some treat `null` differently from absent.
- Responses: decode JSON for 2xx with a body; `204` returns nothing (`void`,
  `None`, `nil`, unit).

### Idempotency-Key

The API supports it and requires it on most POSTs (SURFACE.md "Idem"
column). Rules:

1. Every method marked **req** or **opt** accepts a per-call
   `idempotencyKey` option. If the caller does not pass one, the SDK generates
   a UUIDv4 (36 characters, within both server limits of 200 and 255).
2. The key is generated once per method call and reused unchanged on every
   retry of that call. This is what makes POST retries safe: the server
   replays the stored response for the same key and body.
3. Methods marked **-** never send the header.
4. The same key with a different body yields `409`; the SDK surfaces it as an
   OpensmsError, it never regenerates a key on its own.

### Retries

Retry when the attempt ends in `429`, `500`, `502`, `503`, `504`, or a
network error or timeout, only if the request is safe to repeat:

- `GET`, `PUT`, `PATCH`, `DELETE`: always retryable.
- `POST`: retryable only when the request carries an Idempotency-Key (the
  **req**/**opt** methods). The POSTs without idempotency support are never
  retried: `messages.cancel`, `otp.verify` (a replay burns an attempt),
  `senderIds.create` (may charge a fee), `senderIds.createDraft`,
  `suppressions.create`, `suppressions.import`.
- Never retry other 4xx (400, 401, 402, 403, 404, 409, 410, 413, 422).

Delay before retry `n` (1-based):

- If the response has `Retry-After`, honour it: integer seconds or an HTTP
  date. If it asks for more than 60 s, do not retry; raise the OpensmsError
  (with `retryAfter` set) so the caller can decide.
- Otherwise exponential backoff with full jitter:
  `random(0, min(8 s, 0.5 s * 2^(n-1)))`. Tests inject a zero-delay sleeper
  or clock rather than waiting.

After the last attempt, the final HTTP error becomes an OpensmsError; a final
network failure becomes an OpensmsError with `status = 0`.

## Errors

`OpensmsError` is raised for every non-2xx response and for transport
failures that survive retries. It is mapped from the RFC 9457
problem+json body (`internal/httpx/problempb.Problem`):

| Field | Source | Notes |
| --- | --- | --- |
| `status` | HTTP status (int) | `0` = no response (network, timeout). |
| `type` | body `type` | usually `about:blank`, else `https://api.opensms.io/problems/<code>` |
| `title` | body `title` | `Bad Request`, `Unauthorized`, ... |
| `detail` | body `detail` | human text; the observed strings are in SURFACE.md |
| `code` | body `code`, optional | absent on most errors; only a few handlers set it (`invalid_message_id`, `not_found`, `spend_cap_reached`, ...) |
| `traceId` | body `trace_id`, optional | |
| `errors` | body `errors`, optional | `map<string, string[]>` field errors |
| `requestId` | `X-Request-ID` header, optional | set on message and OTP admission rejections (e.g. `422 destination is suppressed`) |
| `retryAfter` | `Retry-After` header in seconds, optional | on 429 and some 503 |
| `body` | raw decoded body (or raw text if not JSON) | for debugging and forward compatibility |

Message: `detail`, else `title`, else `OpenSMS request failed with status <n>`.
When the body is not JSON (a proxy HTML page), all body fields are null and
`body` holds the text. Unknown extra problem fields are preserved in `body`.
Languages with exception hierarchies may add subclasses per status class, but
`OpensmsError` must be catchable for all of them and v1 does not require any.

Caution for callers (document in each README): insufficient scope is `401`
on messages and otp but `403` everywhere else, and most validation errors have
no `code`, so branch on `status` and use `detail` for display.

## Models

- Wire names are snake_case; each SDK exposes idiomatic names (camelCase in
  TS/Java/.NET/Swift/Go fields, snake_case in Python/Ruby/Rust/PHP arrays)
  and maps them in one place (models file), for example `otpId` <-> `otp_id`,
  `contactIds` <-> `contact_ids`, `trafficType` <-> `traffic_type`,
  `scheduledAt` <-> `scheduled_at`, `callbackUrl` <-> `callback_url`,
  `templateId` <-> `template_id`, `ttlSeconds` <-> `ttl_seconds`,
  `nextCursor` <-> `next_cursor`, `attemptsLeft` <-> `attempts_left`.
- Money, prices, balances and FX rates stay **strings** (decimal text).
- Enums are open: model them as strings (or an enum with an unknown case) so a
  new server value never breaks decoding.
- Unknown response fields are ignored; missing optional fields decode as
  null/absent. Typed languages mark every response field optional except
  `id`, because live payloads omit empty fields (`omitempty` in Go handlers).
- `metadata`, `attributes`, webhook `payload`, and `variables` are free-form
  JSON objects / maps.
- Datetimes: parse to the platform instant type when the language makes that
  cheap and lossless (Go `time.Time`, Java `OffsetDateTime`, .NET
  `DateTimeOffset`, Swift `Date` with fractional-seconds ISO 8601), otherwise
  keep the RFC 3339 string. Inputs (`scheduledAt`, analytics `from`/`to`,
  message `dateFrom`/`dateTo`) accept the native type and serialize as
  RFC 3339 UTC.

## Pagination

The API uses opaque cursors: request `limit` + `cursor`, response
`{ items, next_cursor }`. Every cursor list method returns a `Page<T>` with
`items` and `nextCursor` (null on the last page). Each SDK also ships one
generic auto-pagination helper that repeatedly calls a list method, feeding
`nextCursor` back as `cursor` until it is null, yielding items lazily:

| Language | Helper |
| --- | --- |
| typescript | `for await (const m of client.paginate(client.messages.list, { limit: 50 }))` (async iterator) |
| python | `for m in client.paginate(client.messages.list, limit=50)` (generator) |
| go | `it := opensms.Paginate(ctx, client.Messages.List, params)`; `for it.Next() { it.Item() }`; `it.Err()` |
| ruby | `client.paginate(:messages, :list, limit: 50).each` (Enumerator) |
| php | `foreach ($client->paginate([$client->messages, 'list'], ['limit' => 50]) as $m)` (Generator) |
| java | `client.paginate(client.messages()::list, params)` returns `Iterable<T>` |
| dotnet | `await foreach (var m in client.PaginateAsync(client.Messages.ListAsync, p))` (`IAsyncEnumerable<T>`) |
| rust | `client.paginate(...)` returning an iterator/stream of `Result<T>` |
| swift | `for try await m in client.paginate(client.messages.list, params)` (`AsyncThrowingStream`) |

Lists that do not use cursors are not paginated by the helper: bare-array
endpoints (`messages.attempts`, `numbers.available`, `compliance.*`,
`analytics.by*`, `analytics.timeseries`, `countries.*`), `senderIds.listDocuments`
(`{items}` without cursor), and `wallet.ledger`, which pages by
`before=<smallest id seen>` and returns `{data: [...]}`; its method returns the
entries list and callers page manually.

## Webhook signature verification

The API signs every webhook delivery (`internal/webhooks/signature.go`,
`internal/webhooks/worker.go`):

- Header: `X-OpenSMS-Signature: t=<unix seconds>,v1=<hex>`.
- `v1 = hex(HMAC-SHA256(key = secret, message = "<t>" + "." + <raw body bytes>))`.
- `secret` is the endpoint secret exactly as returned once by
  `webhooks.create` (`whsec_<base64url>`), used verbatim as UTF-8 bytes. Do
  not strip the `whsec_` prefix and do not base64-decode it.
- The body is the exact bytes received. Verify before parsing JSON.
- Deliveries are `POST` with `Content-Type: application/json`; the envelope is
  `{ id, type, workspace_id, environment, created_at, data }`
  (`internal/webhooks/fanout.go`).

Canonical helper (on the client and as a free function so a receiver does not
need an API key):

```
webhooks.verifySignature(payload, header, secret, { toleranceSeconds = 300, now? }) -> bool
webhooks.constructEvent(payload, header, secret, { toleranceSeconds = 300, now? }) -> WebhookEvent   // throws OpensmsError(status 0, code "invalid_signature" | "expired_signature")
```

Parsing mirrors the server exactly: split the header on `,`, trim each part,
split on the first `=`; reject empty keys or values, duplicate keys, and any
header that does not contain exactly the two keys `t` and `v1`. `t` must parse
as an integer; reject when `|now - t| > tolerance` (expired). `v1` must be 64
hex characters; compare with a constant-time function. An empty secret is
always invalid. `now` is injectable for tests.

### Test vector

Computed with Python `hmac` and `openssl dgst -sha256 -hmac`, then every row
of the table below was checked by compiling the server's
`internal/webhooks/signature.go` unchanged and calling its `Sign` and
`Verify`.

```
secret    = whsec_c2RrLWNvbmZvcm1hbmNlLXRlc3QtdmVjdG9yLTAwMDE
timestamp = 1790208000
body      = {"id":"evt_01","type":"message.delivered","workspace_id":"00000000-0000-0000-0000-000000000001","environment":"sandbox","created_at":"2026-09-24T00:00:00Z","data":{"id":"00000000-0000-0000-0000-000000000002","status":"delivered"}}
            (230 bytes, no trailing newline)
header    = t=1790208000,v1=eeb2ec420dd348b253dae35c1f3bce03d261109eb8788e3ad836072e894fac23
```

Expected results with `now = 1790208000`:

| Case | Result |
| --- | --- |
| header above | valid |
| same, `now = 1790208000 + 300` | valid (boundary is inclusive) |
| same, `now = 1790208000 + 301` | invalid, expired |
| same, `now = 1790208000 - 301` | invalid, expired |
| body with `"delivered"` in `data.status` changed to `"failed"` | invalid |
| secret without the `whsec_` prefix | invalid |
| header `v1=...,t=1790208000` (order swapped) | valid |
| header with an extra `,v0=abc` | invalid |
| header `t=1790208000` only | invalid |
| header with uppercase hex digest | valid (hex decoding is case-insensitive in the server) |

## Resource conventions

- Methods that take an id validate that it is non-empty before calling
  (argument error, no request).
- `messages.send` accepts `scheduledAt` as a native datetime or string.
- `batches.create` takes `{ items, dedupe? }`; `batches.createFromCsv` takes
  the CSV text/bytes and posts `text/csv`.
- `webhooks.update` requires `url`, `events` and `enabled` (full
  replacement, `PUT`).
- `senderIds.quote({ countries: ["KE", "NG"] })` sends `countries=KE,NG`.
- `wallet.ledger({ limit?, before? })` returns `LedgerEntry[]` from the `data`
  envelope; `wallet.balances()` returns the `data` array.

## Tests (every SDK)

1. **Unit tests with a mock transport** (no network): the list in
   CONFORMANCE.md "Mock-transport unit tests". Must pass offline.
2. **Live integration test**: the ordered scenario in CONFORMANCE.md, run only
   when `OPENSMS_BASE_URL` and `OPENSMS_API_KEY` are set, skipped (not failed)
   otherwise.
3. The language's standard test framework only (the Axene package for that
   language is the guide). No new runtime dependencies beyond the standard
   library, except where the Axene package already uses one.

## CI / release

- One CI job per package, gated like Axene (`[test]` in the commit message or
  PR title).
- Release tag prefixes: `ts-v*`, `py-v*`, `go-v*` (mirror repo), `ruby-v*`,
  `php-v*`, `java-v*`, `dotnet-v*`, `rust-v*`, `swift-v*`.
- Tests always run before publish. Nothing is published until explicitly
  requested.
