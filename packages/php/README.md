# opensms-php (PHP)

Official PHP client for [opensms](https://opensms.io): prepaid SMS for Africa.

PHP 8.1+, zero runtime dependencies beyond `ext-curl` and `ext-json`. See the
[monorepo README](../../README.md) for the other eight SDKs and the
[API surface](../../spec/SURFACE.md) they all implement.

## Install

```bash
composer require opensms/opensms-php
```

`opensms/opensms-php` is not on Packagist yet. Until it is, install it from a
checkout of this monorepo with a Composer path repository:

```json
{
    "repositories": [{ "type": "path", "url": "../opensms-sdks/packages/php" }],
    "require": { "opensms/opensms-php": "*@dev" }
}
```

## Usage

```php
<?php

require 'vendor/autoload.php';

use Opensms\Client;
use Opensms\OpensmsException;

$opensms = new Client(getenv('OPENSMS_API_KEY'));

try {
    $message = $opensms->messages->send([
        'to' => '+254712345678',
        'text' => 'Your order has shipped.',
    ]);

    echo $message['id'], ' ', $message['status'], "\n";
} catch (OpensmsException $e) {
    fwrite(STDERR, $e->getStatus() . ' ' . $e->getMessage() . "\n");
}
```

The API key selects the environment: `sk_test_...` keys run against the
sandbox, `sk_live_...` against live traffic (`$opensms->environment`, `"sandbox"`
or `"live"`). A malformed key throws `InvalidArgumentException` at
construction, before any request.

## More

### Messages

```php
$opensms->messages->send(['to' => '+254712345678', 'text' => 'Hello', 'sender_id' => 'ACME']);
$opensms->messages->list(['status' => 'delivered', 'country' => 'KE']);
$opensms->messages->get($id);
$opensms->messages->attempts($id);   // provider submission attempts
$opensms->messages->cancel($id);     // queued or scheduled only
```

### Batches

```php
$batch = $opensms->batches->create([
    'items' => [
        ['to' => '+254712345678', 'text' => 'Hi Ada'],
        ['to' => '+254712345679', 'text' => 'Hi Bo'],
    ],
]);
$opensms->batches->start($batch['id']);   // batches are created "ready"
$opensms->batches->listItems($batch['id'], ['status' => 'delivered']);
```

### OTP

```php
$otp = $opensms->otp->send(['to' => '+254712345678', 'length' => 6, 'ttl_seconds' => 300]);
$result = $opensms->otp->verify(['otp_id' => $otp['otp_id'], 'code' => $codeFromUser]);
```

### Lookups

```php
$lookup = $opensms->lookups->create(['to' => '+254712345678']);
$opensms->lookups->get($lookup['id']);
```

### Contacts

```php
$contact = $opensms->contacts->create(['e164' => '+254712345678', 'name' => 'Ada']);
$opensms->contacts->list(['limit' => 100]);
$opensms->contacts->update($contact['id'], ['name' => 'Ada L']);   // PATCH
$opensms->contacts->delete($contact['id']);
```

### Contact groups

```php
$group = $opensms->contactGroups->create(['name' => 'VIP', 'contact_ids' => [$contact['id']]]);
$opensms->contactGroups->send($group['id'], ['text' => 'Sale starts today']);
$opensms->contactGroups->delete($group['id']);
```

### Templates

```php
$tpl = $opensms->templates->create(['name' => 'welcome', 'body' => 'Hi {{name}}', 'traffic_type' => 'transactional']);
$opensms->templates->update($tpl['id'], ['body' => 'Hello {{name}}']);
$opensms->templates->delete($tpl['id']);
```

### Webhooks

```php
$hook = $opensms->webhooks->create([
    'url' => 'https://example.com/opensms',
    'events' => ['message.delivered', 'message.failed'],
]);
$secret = $hook['secret'];   // whsec_..., shown only once: store it
$opensms->webhooks->listDeliveries($hook['id']);
$opensms->webhooks->delete($hook['id']);
```

See [Webhooks](#webhooks) below for verifying deliveries.

### Inbound

```php
$opensms->inbound->list();
$opensms->inbound->reply($inboundId, ['text' => 'Thanks!']);   // live keys only
```

### Numbers

```php
// Everything except list() and available() needs a live key.
$number = $opensms->numbers->assign(['country' => 'KE', 'kind' => 'long_code']);
$opensms->numbers->createRule($number['id'], [
    'match' => 'keyword', 'pattern' => 'JOIN', 'action' => 'webhook', 'target' => 'https://example.com/in',
]);
$opensms->numbers->release($number['id']);
```

### Sender IDs

```php
$opensms->senderIds->check(['value' => 'ACME', 'country' => 'KE']);
$sender = $opensms->senderIds->create([
    'value' => 'ACME', 'kind' => 'alphanumeric', 'countries' => ['KE'],
    'use_case' => 'transactional', 'documents' => $documentIds,
]);
$opensms->senderIds->createDraft(['source' => 'application', 'value' => 'ACME', 'kind' => 'alphanumeric']);
```

Document upload and download are console-only and not in the SDK.

### Suppressions

```php
$s = $opensms->suppressions->create(['e164' => '+254712345678', 'reason' => 'manual']);
$opensms->suppressions->import([['e164' => '+254712345679', 'reason' => 'complaint']]);
$opensms->suppressions->delete($s['id']);
```

### Compliance

```php
$opensms->compliance->listCountries();
$opensms->compliance->getCountry('KE');
```

### Wallet

```php
$opensms->wallet->balances();
$opensms->wallet->ledger(['limit' => 100]);
$opensms->wallet->createTopup(['amount' => '1000', 'currency' => 'KES', 'channel' => 'mobile_money', 'email' => 'billing@example.com']);
```

### Pricing

```php
$opensms->pricing->get(['product' => 'sms', 'country' => 'KE']);
```

### Analytics

```php
$opensms->analytics->overview(['range' => '7d']);
$opensms->analytics->byCountry(['from' => '2026-09-01', 'to' => '2026-09-24']);
```

### Sandbox

```php
// Rendered text of sandbox sends, including OTP codes (sk_test_ keys).
$opensms->sandbox->listMessages(['limit' => 10]);
```

### Countries

```php
$opensms->countries->list();
$opensms->countries->carriers('KE');
```

### Pagination

Cursor lists return an `Opensms\Page` with `->items` and `->nextCursor` (null
on the last page). `Client::paginate()` walks every page lazily:

```php
foreach ($opensms->paginate([$opensms->messages, 'list'], ['limit' => 50]) as $message) {
    echo $message['id'], "\n";
}
```

## Errors and retries

Every non-2xx response, and any network failure that survives retries, throws
`Opensms\OpensmsException`:

| Accessor | Meaning |
| --- | --- |
| `getStatus(): int` | HTTP status; `0` means no response (network error or timeout) |
| `getType(): ?string` | problem `type`, usually `about:blank` |
| `getTitle(): ?string` | problem `title`, e.g. `Bad Request` |
| `getDetail(): ?string` | human-readable detail |
| `getErrorCode(): ?string` | machine code, when the API sets one (most errors have none) |
| `getErrors(): ?array` | field errors, `field => [messages]` |
| `getTraceId(): ?string` | trace id, when present |
| `getRequestId(): ?string` | `X-Request-ID`, set on message and OTP admission rejections |
| `getRetryAfter(): ?float` | `Retry-After` seconds, when present |
| `getBody(): mixed` | raw decoded body, or raw text when it was not JSON |

Most errors carry no code, so branch on `getStatus()` and show `getDetail()`.
Insufficient key scope is `401` on `messages` and `otp` but `403` everywhere
else.

Requests are retried automatically on `429`, `500`, `502`, `503`, `504` and
network errors or timeouts, up to `maxRetries` (default 2). `GET`, `PUT`,
`PATCH` and `DELETE` are always retried; `POST` only when it carries an
`Idempotency-Key`, which the SDK generates once per call and reuses on every
retry of that call. `Retry-After` is honoured; if it asks for more than 60
seconds the SDK throws instead of waiting. Otherwise the delay is exponential
backoff with full jitter, capped at 8 seconds. `messages->cancel`,
`otp->verify`, `senderIds->create`, `senderIds->createDraft`,
`suppressions->create`, `suppressions->import`, and any other `4xx`, are
never retried.

## Webhooks

Each delivery carries `X-OpenSMS-Signature: t=<unix>,v1=<hex>`, an
HMAC-SHA256 of `"<t>.<raw body>"` keyed with the endpoint's `whsec_...`
secret. Verify against the **raw** body before parsing it as JSON. No client
or API key is needed:

```php
use Opensms\OpensmsException;
use Opensms\Webhook;

$payload = file_get_contents('php://input');
$header = $_SERVER['HTTP_X_OPENSMS_SIGNATURE'] ?? '';

try {
    $event = Webhook::constructEvent($payload, $header, getenv('OPENSMS_WEBHOOK_SECRET'));
} catch (OpensmsException $e) {
    // getErrorCode() is "invalid_signature" or "expired_signature"
    http_response_code(400);
    exit;
}

if ($event['type'] === 'message.delivered') {
    markDelivered($event['data']['id']);
}
http_response_code(204);
```

`Webhook::verifySignature($payload, $header, $secret)` returns a bool
instead. Both accept `['toleranceSeconds' => 300, 'now' => time()]` (default
tolerance 300 seconds) and are also available as
`$opensms->webhooks->verifySignature(...)` and
`$opensms->webhooks->constructEvent(...)`.

## Testing

```bash
composer install
./vendor/bin/phpunit --testsuite unit     # offline, mock transport
```

The live suite runs the conformance scenario against a sandbox and is
skipped unless `OPENSMS_BASE_URL` and `OPENSMS_API_KEY` are set:

```bash
OPENSMS_BASE_URL=... OPENSMS_API_KEY=sk_test_... ./vendor/bin/phpunit --testsuite live
```

## License

MIT
