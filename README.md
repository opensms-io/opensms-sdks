# opensms SDKs

Official client libraries for [opensms](https://opensms.io): prepaid SMS for Africa. Send messages and
batches, run OTP, look up numbers, manage contacts, templates, webhooks, numbers and sender IDs, and
read your wallet and analytics, all with one API key.

This is a spec-driven monorepo: every client wraps the same API-key surface, defined once in
[`spec/SURFACE.md`](spec/SURFACE.md) and [`spec/DESIGN.md`](spec/DESIGN.md), extracted from the live
backend and checked by calling every operation with a real key. All nine clients cover the same
18 resources and 83 methods, and all pass the same live scenario in
[`spec/CONFORMANCE.md`](spec/CONFORMANCE.md).

| Language | Package | Registry | Status |
|---|---|---|---|
| TypeScript / JavaScript | [`@opensms/sdk`](packages/typescript) | npm | built and tested, not yet published |
| Python | [`opensms`](packages/python) | PyPI | built and tested, not yet published |
| Go | [`github.com/opensms-io/opensms-go`](packages/go) | git tag | built and tested, not yet tagged |
| .NET (C#) | [`Opensms`](packages/dotnet) | NuGet | built and tested, not yet published |
| Java | [`io.opensms:opensms-java`](packages/java) | Maven Central | built and tested, not yet published |
| Rust | [`opensms`](packages/rust) | crates.io | built and tested, not yet published |
| Ruby | [`opensms`](packages/ruby) | RubyGems | built and tested, not yet published |
| PHP | [`opensms/opensms-php`](packages/php) | Packagist | built and tested, not yet published |
| Swift | [`OpensmsSDK`](packages/swift) | SwiftPM (git tag) | built and tested, not yet tagged |

Until a package is published, install it from this repository: each package README has the local
install command.

## Quickstart

**TypeScript**
```ts
import { Opensms } from '@opensms/sdk';

const opensms = new Opensms({ apiKey: process.env.OPENSMS_API_KEY! });
const message = await opensms.messages.send({ to: '+254712345678', text: 'Your code is 482913' });
console.log(message.id, message.status);
```

**Python**
```python
import os

from opensms import Opensms

opensms = Opensms(api_key=os.environ["OPENSMS_API_KEY"])
message = opensms.messages.send(to="+254712345678", text="Your code is 482913")
print(message.id, message.status)
```

Every other language follows the same shape in its own idiom; see each package README.

## What every client does the same way

- **Keys**: `sk_test_...` keys talk to your sandbox, `sk_live_...` keys to live traffic. The key alone
  selects the workspace and environment.
- **Retries**: on 429 and 5xx, honouring `Retry-After`, only for requests that are safe to repeat.
  POSTs carry an `Idempotency-Key` (generated once per call and reused on every retry). OTP verify
  and sender ID creation are never retried.
- **Errors**: RFC 9457 problem responses become one `OpensmsError` type with `status`, `title`,
  `detail`, `type` and `code` when the API sends one.
- **Pagination**: cursor lists expose `items` and `next_cursor`, plus an iterator that walks every page.
- **Webhooks**: a helper verifies `X-OpenSMS-Signature` (`t=<unix>,v1=<hex>`, HMAC-SHA256 of
  `"<t>.<raw body>"` keyed with your `whsec_...` secret, 300 s tolerance by default). The test vector
  in DESIGN.md is shared by all nine clients.

## Layout

```
spec/
  SURFACE.md       the API-key surface: resources, methods, wire fields, live status, drift
  DESIGN.md        the client contract every language implements
  CONFORMANCE.md   the live scenario and the mock-transport test list
  openapi.json     the customer API contract this was extracted from
packages/<lang>/   one client per language, each with unit tests and a live conformance suite
```

## Testing

Each package has two suites: mock-transport unit tests that need no network, and a live
conformance suite that runs the CONFORMANCE.md scenario against a real API. The live suite is
skipped, never failed, when `OPENSMS_BASE_URL` or `OPENSMS_API_KEY` is unset. Point it at a
sandbox workspace with an all-scope `sk_test_` key; the
[local stack guide](https://github.com/opensms-io/opensms-docs/blob/main/operations/local-development.md)
shows how to run one on your machine.

## Known API behaviour the clients follow

The clients follow what the API actually does, even where it differs from the OpenAPI document.
The full list is in [SURFACE.md](spec/SURFACE.md#drift-spec-vs-live-code); the ones you are most likely to meet:
insufficient scope answers 401 on messages and OTP but 403 elsewhere, most errors have no `code`
field, and a raw `text/csv` batch upload cannot carry the `dedupe` flag (clients switch to multipart).

## License

MIT, see [LICENSE](LICENSE).
