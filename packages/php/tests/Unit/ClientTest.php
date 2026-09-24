<?php

declare(strict_types=1);

namespace Opensms\Tests\Unit;

use DateTimeImmutable;
use DateTimeZone;
use InvalidArgumentException;
use Opensms\Client;
use Opensms\OpensmsException;
use Opensms\Page;
use Opensms\Webhook;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\TestCase;

/**
 * Mock-transport unit tests (CONFORMANCE.md "Mock-transport unit tests").
 * No network: an injected handler records requests and replays canned
 * responses; an injected sleeper records requested delays.
 */
final class ClientTest extends TestCase
{
    private const KEY = 'sk_test_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
    private const UUID_RE = '/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/';

    private MockHandler $mock;
    /** @var list<float> */
    private array $sleeps = [];

    /** @param list<array<string, mixed>|\Throwable> $responses */
    private function client(array $responses, array $options = []): Client
    {
        $this->mock = new MockHandler($responses);
        $this->sleeps = [];

        return new Client(self::KEY, $options + [
            'baseUrl' => 'http://mock.test',
            'handler' => $this->mock,
            'sleep' => function (float $s): void {
                $this->sleeps[] = $s;
            },
        ]);
    }

    private static function message(array $extra = []): array
    {
        return $extra + ['id' => '11111111-1111-4111-8111-111111111111', 'to' => '+254700000012', 'status' => 'queued'];
    }

    private function catchError(callable $fn): OpensmsException
    {
        try {
            $fn();
        } catch (OpensmsException $e) {
            return $e;
        }
        $this->fail('expected OpensmsException');
    }

    // 1. Header injection
    public function testHeaderInjection(): void
    {
        $c = $this->client([MockHandler::json(201, self::message()), MockHandler::json(200, ['items' => [], 'next_cursor' => null])]);
        $c->messages->send(['to' => '+254700000012', 'text' => 'hi']);
        $c->messages->list();

        foreach ($this->mock->requests as $i => $r) {
            $h = $r['headers'];
            $this->assertSame('Bearer ' . self::KEY, $h['Authorization']);
            $this->assertSame('application/json', $h['Accept']);
            $this->assertSame('opensms-php/0.1.0', $h['User-Agent']);
            $lower = array_change_key_case($h);
            $this->assertArrayNotHasKey('x-workspace-id', $lower);
            $this->assertArrayNotHasKey('x-environment', $lower);
            if ($i === 0) {
                $this->assertSame('application/json', $h['Content-Type']);
            } else {
                $this->assertArrayNotHasKey('Content-Type', $h);
                $this->assertNull($r['body']);
            }
        }
    }

    // 2. Base URL
    public function testDefaultBaseUrl(): void
    {
        $this->assertSame('https://api.opensms.io', (new Client(self::KEY))->baseUrl());
    }

    public function testCustomBaseUrlTrailingSlash(): void
    {
        $c = $this->client([MockHandler::json(201, self::message())], ['baseUrl' => 'http://host/']);
        $c->messages->send(['to' => '+254700000012', 'text' => 'hi']);
        $this->assertSame('http://host/v1/messages', $this->mock->last()['url']);
    }

    // 3. Key validation
    /** @return array<string, array{string}> */
    public static function badKeys(): array
    {
        return ['empty' => [''], 'wrong prefix' => ['pk_test_x'], 'short' => ['sk_test_short'], 'twelve' => ['sk_test_' . str_repeat('A', 12)]];
    }

    #[DataProvider('badKeys')]
    public function testBadKeysFailAtConstruction(string $key): void
    {
        $this->expectException(InvalidArgumentException::class);
        new Client($key);
    }

    public function testGoodKeysAndEnvironment(): void
    {
        $this->assertSame('live', (new Client('sk_live_' . str_repeat('A', 32)))->environment);
        $this->assertSame('sandbox', (new Client('sk_test_' . str_repeat('A', 32)))->environment);
        $this->assertSame('sandbox', (new Client('sk_test_' . str_repeat('A', 13)))->environment);
    }

    // 4. Body mapping
    public function testSendBodyMapping(): void
    {
        $c = $this->client([MockHandler::json(201, self::message()), MockHandler::json(201, self::message())]);
        $at = new DateTimeImmutable('2026-09-24T12:00:00+03:00');
        $c->messages->send([
            'to' => '+254700000012',
            'text' => 'hi',
            'senderId' => 'ACME',
            'trafficType' => 'otp',
            'scheduledAt' => $at,
            'callbackUrl' => 'https://x.test/cb',
            'metadata' => ['a' => 1],
        ]);
        $body = json_decode($this->mock->last()['body'], true);
        $this->assertSame(['to', 'text', 'sender_id', 'traffic_type', 'scheduled_at', 'callback_url', 'metadata'], array_keys($body));
        $this->assertSame('2026-09-24T09:00:00Z', $body['scheduled_at']);
        $this->assertSame(['a' => 1], $body['metadata']);

        $c->messages->send(['to' => '+254700000012', 'text' => 'hi', 'sender_id' => null, 'metadata' => []]);
        $raw = $this->mock->last()['body'];
        $this->assertSame('{"to":"+254700000012","text":"hi","metadata":{}}', $raw);
    }

    public function testUnknownParamRejectedWithoutRequest(): void
    {
        $c = $this->client([]);
        $this->expectException(InvalidArgumentException::class);
        try {
            $c->messages->send(['to' => '+254700000012', 'text' => 'hi', 'bogus' => 1]);
        } finally {
            $this->assertSame([], $this->mock->requests);
        }
    }

    // 5. Idempotency-Key auto
    public function testIdempotencyKey(): void
    {
        $c = $this->client([
            MockHandler::json(201, self::message()),
            MockHandler::json(201, self::message()),
            MockHandler::json(200, self::message()),
        ]);
        $c->messages->send(['to' => '+254700000012', 'text' => 'hi']);
        $key = $this->mock->requests[0]['headers']['Idempotency-Key'];
        $this->assertSame(36, strlen($key));
        $this->assertMatchesRegularExpression(self::UUID_RE, $key);

        $c->messages->send(['to' => '+254700000012', 'text' => 'hi'], ['idempotencyKey' => 'my-key-1']);
        $this->assertSame('my-key-1', $this->mock->requests[1]['headers']['Idempotency-Key']);

        $c->messages->get('abc');
        $this->assertArrayNotHasKey('Idempotency-Key', $this->mock->requests[2]['headers']);
    }

    // 6. Retry on 429 with Retry-After
    public function testRetryOn429HonoursRetryAfterAndReusesKey(): void
    {
        $c = $this->client([
            MockHandler::problem(429, 'rate limited', ['retry-after' => '2']),
            MockHandler::json(201, self::message()),
        ]);
        $m = $c->messages->send(['to' => '+254700000012', 'text' => 'hi']);
        $this->assertSame('queued', $m['status']);
        $this->assertCount(2, $this->mock->requests);
        $this->assertSame([2.0], $this->sleeps);
        $this->assertSame(
            $this->mock->requests[0]['headers']['Idempotency-Key'],
            $this->mock->requests[1]['headers']['Idempotency-Key'],
        );
    }

    public function testRetryAfterHttpDate(): void
    {
        $date = gmdate('D, d M Y H:i:s', time() + 3) . ' GMT';
        $c = $this->client([MockHandler::problem(503, 'busy', ['Retry-After' => $date]), MockHandler::json(200, self::message())]);
        $c->messages->get('x');
        $this->assertCount(1, $this->sleeps);
        $this->assertGreaterThanOrEqual(1.0, $this->sleeps[0]);
        $this->assertLessThanOrEqual(3.0, $this->sleeps[0]);
    }

    // 7. Retry on 503 without Retry-After
    public function testRetryOn503WithBackoff(): void
    {
        $c = $this->client([MockHandler::problem(503, 'unavailable'), MockHandler::json(200, self::message())]);
        $c->messages->get('x');
        $this->assertCount(2, $this->mock->requests);
        $this->assertCount(1, $this->sleeps);
        $this->assertGreaterThanOrEqual(0.0, $this->sleeps[0]);
        $this->assertLessThanOrEqual(0.5, $this->sleeps[0]);
    }

    // 8. Retries exhausted
    public function testRetriesExhausted(): void
    {
        $c = $this->client([
            MockHandler::problem(500, 'boom'),
            MockHandler::problem(500, 'boom'),
            MockHandler::problem(500, 'boom'),
        ], ['maxRetries' => 2]);
        $e = $this->catchError(fn () => $c->messages->get('x'));
        $this->assertSame(500, $e->getStatus());
        $this->assertCount(3, $this->mock->requests);
        $this->assertCount(2, $this->sleeps);
        $this->assertLessThanOrEqual(1.0, $this->sleeps[1]);
    }

    public function testMaxRetriesZeroDisablesRetries(): void
    {
        $c = $this->client([MockHandler::problem(503, 'x')], ['maxRetries' => 0]);
        $e = $this->catchError(fn () => $c->messages->get('x'));
        $this->assertSame(503, $e->getStatus());
        $this->assertCount(1, $this->mock->requests);
    }

    // 9. Retry-After too large
    public function testRetryAfterTooLarge(): void
    {
        $c = $this->client([MockHandler::problem(429, 'slow down', ['retry-after' => '120'])]);
        $e = $this->catchError(fn () => $c->messages->send(['to' => '+254700000012', 'text' => 'hi']));
        $this->assertSame(429, $e->getStatus());
        $this->assertSame(120.0, $e->getRetryAfter());
        $this->assertCount(1, $this->mock->requests);
        $this->assertSame([], $this->sleeps);
    }

    // 10. No retry on 4xx
    /** @return array<string, array{int}> */
    public static function nonRetryable(): array
    {
        return ['400' => [400], '401' => [401], '404' => [404], '409' => [409], '422' => [422]];
    }

    #[DataProvider('nonRetryable')]
    public function testNoRetryOn4xx(int $status): void
    {
        $c = $this->client([MockHandler::problem($status, 'nope')]);
        $e = $this->catchError(fn () => $c->messages->send(['to' => '+254700000012', 'text' => 'hi']));
        $this->assertSame($status, $e->getStatus());
        $this->assertCount(1, $this->mock->requests);
    }

    // 11. No retry for non-idempotent POST
    public function testNoRetryForNonIdempotentPosts(): void
    {
        $calls = [
            'otp.verify' => fn (Client $c) => $c->otp->verify(['otpId' => 'o', 'code' => '123456']),
            'messages.cancel' => fn (Client $c) => $c->messages->cancel('m'),
            'senderIds.create' => fn (Client $c) => $c->senderIds->create(['value' => 'A', 'kind' => 'alphanumeric', 'countries' => ['KE'], 'documents' => []]),
            'senderIds.createDraft' => fn (Client $c) => $c->senderIds->createDraft([]),
            'suppressions.create' => fn (Client $c) => $c->suppressions->create(['e164' => '+254700000001', 'reason' => 'manual']),
            'suppressions.import' => fn (Client $c) => $c->suppressions->import([['e164' => '+254700000001', 'reason' => 'manual']]),
        ];
        foreach ($calls as $name => $call) {
            $c = $this->client([MockHandler::problem(503, 'down'), MockHandler::json(200, [])]);
            $e = $this->catchError(fn () => $call($c));
            $this->assertSame(503, $e->getStatus(), $name);
            $this->assertCount(1, $this->mock->requests, $name);
            $this->assertArrayNotHasKey('Idempotency-Key', $this->mock->requests[0]['headers'], $name);
        }
    }

    // 12. Network error
    public function testNetworkErrorRetriedThenSucceeds(): void
    {
        $c = $this->client([MockHandler::networkError(), MockHandler::networkError(), MockHandler::json(200, self::message())]);
        $m = $c->messages->get('x');
        $this->assertSame('queued', $m['status']);
        $this->assertCount(3, $this->mock->requests);
    }

    public function testNetworkErrorExhaustedIsStatusZero(): void
    {
        $c = $this->client([MockHandler::networkError(), MockHandler::networkError(), MockHandler::networkError()]);
        $e = $this->catchError(fn () => $c->messages->get('x'));
        $this->assertSame(0, $e->getStatus());
        $this->assertStringContainsString('Failed to connect', $e->getMessage());
        $this->assertCount(3, $this->mock->requests);
    }

    // 13. Error mapping
    public function testProblemMapping(): void
    {
        $body = '{"type":"https://api.opensms.io/problems/invalid_message_id","title":"Bad Request","status":400,"detail":"Message ID must be a valid UUID.","code":"invalid_message_id","trace_id":"t1","errors":{"to":["bad"]}}';
        $c = $this->client([['status' => 400, 'headers' => ['Content-Type' => 'application/problem+json'], 'body' => $body]]);
        $e = $this->catchError(fn () => $c->messages->get('not-a-uuid'));
        $this->assertSame(400, $e->getStatus());
        $this->assertSame('https://api.opensms.io/problems/invalid_message_id', $e->getType());
        $this->assertSame('Bad Request', $e->getTitle());
        $this->assertSame('Message ID must be a valid UUID.', $e->getDetail());
        $this->assertSame('invalid_message_id', $e->getErrorCode());
        $this->assertSame('invalid_message_id', $e->getCode());
        $this->assertSame('t1', $e->getTraceId());
        $this->assertSame(['to' => ['bad']], $e->getErrors());
        $this->assertSame('Message ID must be a valid UUID.', $e->getMessage());
        $this->assertSame(json_decode($body, true), $e->getBody());
    }

    public function testAboutBlankHasNoCode(): void
    {
        $c = $this->client([MockHandler::problem(400, 'to must be an E.164 phone number')]);
        $e = $this->catchError(fn () => $c->messages->send(['to' => '1', 'text' => 'x']));
        $this->assertNull($e->getErrorCode());
        $this->assertSame('about:blank', $e->getType());
        $this->assertNull($e->getRequestId());
    }

    public function testRequestIdHeader(): void
    {
        $c = $this->client([MockHandler::problem(422, 'destination is suppressed', ['X-Request-ID' => 'r1'])]);
        $e = $this->catchError(fn () => $c->messages->send(['to' => '+254700000012', 'text' => 'x']));
        $this->assertSame(422, $e->getStatus());
        $this->assertSame('r1', $e->getRequestId());
    }

    public function testHtmlErrorBody(): void
    {
        $html = '<html><body>Bad Gateway</body></html>';
        $c = $this->client([['status' => 502, 'headers' => ['content-type' => 'text/html'], 'body' => $html]], ['maxRetries' => 0]);
        $e = $this->catchError(fn () => $c->messages->get('x'));
        $this->assertSame(502, $e->getStatus());
        $this->assertNull($e->getDetail());
        $this->assertNull($e->getTitle());
        $this->assertSame($html, $e->getBody());
        $this->assertSame('OpenSMS request failed with status 502', $e->getMessage());
    }

    public function testMessageFallsBackToTitle(): void
    {
        $c = $this->client([MockHandler::json(403, ['type' => 'about:blank', 'title' => 'Forbidden', 'status' => 403])]);
        $e = $this->catchError(fn () => $c->contacts->list());
        $this->assertSame('Forbidden', $e->getMessage());
    }

    // 14. 204 handling
    public function testDeleteReturnsVoidOn204(): void
    {
        $c = $this->client([MockHandler::empty()]);
        $this->assertNull($c->contacts->delete('c1'));
        $this->assertSame('DELETE', $this->mock->last()['method']);
        $this->assertSame('http://mock.test/v1/contacts/c1', $this->mock->last()['url']);
    }

    // 15. Pagination
    public function testPaginateHelper(): void
    {
        $c = $this->client([
            MockHandler::json(200, ['items' => [['id' => 'a'], ['id' => 'b']], 'next_cursor' => 'c1']),
            MockHandler::json(200, ['items' => [['id' => 'c']], 'next_cursor' => null]),
        ]);
        $ids = [];
        foreach ($c->paginate([$c->messages, 'list'], ['limit' => 2]) as $m) {
            $ids[] = $m['id'];
        }
        $this->assertSame(['a', 'b', 'c'], $ids);
        $this->assertCount(2, $this->mock->requests);
        $this->assertSame('http://mock.test/v1/messages?limit=2', $this->mock->requests[0]['url']);
        $this->assertSame('http://mock.test/v1/messages?limit=2&cursor=c1', $this->mock->requests[1]['url']);
    }

    public function testListReturnsPage(): void
    {
        $c = $this->client([MockHandler::json(200, ['items' => [['id' => 'a']], 'next_cursor' => 'n1'])]);
        $page = $c->contacts->list(['limit' => 1]);
        $this->assertInstanceOf(Page::class, $page);
        $this->assertSame('n1', $page->nextCursor);
        $this->assertTrue($page->hasMore());
        $this->assertCount(1, $page);
    }

    // 16. Query encoding
    public function testQueryEncoding(): void
    {
        $c = $this->client([
            MockHandler::json(200, ['quote_id' => 'sq_1']),
            MockHandler::json(200, ['items' => [], 'next_cursor' => null]),
            MockHandler::json(200, ['items' => [], 'next_cursor' => null]),
        ]);
        $c->senderIds->quote(['countries' => ['KE', 'NG']]);
        $this->assertSame('http://mock.test/v1/sender-ids/quote?countries=KE,NG', $this->mock->requests[0]['url']);

        $c->messages->list(['status' => 'delivered', 'to' => '+2547', 'cursor' => null]);
        $this->assertSame('http://mock.test/v1/messages?status=delivered&to=%2B2547', $this->mock->requests[1]['url']);

        $c->messages->list(['dateFrom' => new DateTimeImmutable('2026-01-01T00:00:00', new DateTimeZone('UTC')), 'date_to' => '2026-01-31']);
        $this->assertSame('http://mock.test/v1/messages?date_from=2026-01-01T00%3A00%3A00Z&date_to=2026-01-31', $this->mock->requests[2]['url']);
    }

    // 17. Path escaping
    public function testPathEscaping(): void
    {
        $c = $this->client([MockHandler::json(200, self::message())]);
        $c->messages->get('a/b');
        $this->assertSame('http://mock.test/v1/messages/a%2Fb', $this->mock->last()['url']);
    }

    public function testEmptyIdRejected(): void
    {
        $c = $this->client([]);
        $this->expectException(InvalidArgumentException::class);
        $c->messages->get('');
    }

    // 18. Webhook signature vector
    private const WH_SECRET = 'whsec_c2RrLWNvbmZvcm1hbmNlLXRlc3QtdmVjdG9yLTAwMDE';
    private const WH_T = 1790208000;
    private const WH_BODY = '{"id":"evt_01","type":"message.delivered","workspace_id":"00000000-0000-0000-0000-000000000001","environment":"sandbox","created_at":"2026-09-24T00:00:00Z","data":{"id":"00000000-0000-0000-0000-000000000002","status":"delivered"}}';
    private const WH_SIG = 'eeb2ec420dd348b253dae35c1f3bce03d261109eb8788e3ad836072e894fac23';

    /** @return array<string, array{string, string, string, int, bool}> */
    public static function signatureVector(): array
    {
        $h = 't=1790208000,v1=' . self::WH_SIG;
        $t = self::WH_T;

        return [
            'valid' => [self::WH_BODY, $h, self::WH_SECRET, $t, true],
            'boundary +300' => [self::WH_BODY, $h, self::WH_SECRET, $t + 300, true],
            'expired +301' => [self::WH_BODY, $h, self::WH_SECRET, $t + 301, false],
            'expired -301' => [self::WH_BODY, $h, self::WH_SECRET, $t - 301, false],
            'tampered body' => [str_replace('"delivered"}', '"failed"}', self::WH_BODY), $h, self::WH_SECRET, $t, false],
            'secret without prefix' => [self::WH_BODY, $h, substr(self::WH_SECRET, 6), $t, false],
            'order swapped' => [self::WH_BODY, 'v1=' . self::WH_SIG . ',t=1790208000', self::WH_SECRET, $t, true],
            'extra v0' => [self::WH_BODY, $h . ',v0=abc', self::WH_SECRET, $t, false],
            't only' => [self::WH_BODY, 't=1790208000', self::WH_SECRET, $t, false],
            'uppercase hex' => [self::WH_BODY, 't=1790208000,v1=' . strtoupper(self::WH_SIG), self::WH_SECRET, $t, true],
            'empty secret' => [self::WH_BODY, $h, '', $t, false],
        ];
    }

    #[DataProvider('signatureVector')]
    public function testWebhookSignatureVector(string $body, string $header, string $secret, int $now, bool $valid): void
    {
        $this->assertSame(230, strlen(self::WH_BODY));
        $this->assertSame($valid, Webhook::verifySignature($body, $header, $secret, ['now' => $now]));
        $c = new Client(self::KEY);
        $this->assertSame($valid, $c->webhooks->verifySignature($body, $header, $secret, ['now' => $now]));
    }

    public function testConstructEvent(): void
    {
        $h = 't=1790208000,v1=' . self::WH_SIG;
        $event = Webhook::constructEvent(self::WH_BODY, $h, self::WH_SECRET, ['now' => self::WH_T]);
        $this->assertSame('message.delivered', $event['type']);
        $this->assertSame('delivered', $event['data']['status']);

        $tampered = str_replace('"delivered"}', '"failed"}', self::WH_BODY);
        $e = $this->catchError(fn () => Webhook::constructEvent($tampered, $h, self::WH_SECRET, ['now' => self::WH_T]));
        $this->assertSame(0, $e->getStatus());
        $this->assertSame('invalid_signature', $e->getErrorCode());

        $e = $this->catchError(fn () => Webhook::constructEvent(self::WH_BODY, $h, self::WH_SECRET, ['now' => self::WH_T + 301]));
        $this->assertSame('expired_signature', $e->getErrorCode());
    }

    // 19. Batch CSV
    public function testCreateFromCsv(): void
    {
        $csv = "to,text\n+254700000014,csv\n";
        $c = $this->client([MockHandler::json(202, ['id' => 'b1', 'status' => 'ready', 'total' => 1])]);
        $b = $c->batches->createFromCsv($csv);
        $this->assertSame('ready', $b['status']);
        $r = $this->mock->last();
        $this->assertSame('POST', $r['method']);
        $this->assertSame('http://mock.test/v1/messages/batch', $r['url']);
        $this->assertSame('text/csv', $r['headers']['Content-Type']);
        $this->assertSame($csv, $r['body']);
        $this->assertMatchesRegularExpression(self::UUID_RE, $r['headers']['Idempotency-Key']);
    }

    public function testCreateFromCsvNoDedupeUsesMultipart(): void
    {
        $c = $this->client([MockHandler::json(202, ['id' => 'b1'])]);
        $c->batches->createFromCsv("to,text\n", ['dedupe' => false]);
        $r = $this->mock->last();
        $this->assertStringStartsWith('multipart/form-data; boundary=', $r['headers']['Content-Type']);
        $this->assertStringContainsString("name=\"dedupe\"\r\n\r\nfalse", $r['body']);
    }

    // 20. Decimal strings, unknown fields
    public function testDecimalStringsAndUnknownFields(): void
    {
        $raw = '{"id":"m1","price":"0.000000","currency":"KES","brand_new_field":{"x":1}}';
        $c = $this->client([['status' => 200, 'headers' => ['content-type' => 'application/json'], 'body' => $raw]]);
        $m = $c->messages->get('m1');
        $this->assertSame('0.000000', $m['price']);
        $this->assertSame('m1', $m['id']);
    }

    // Surface: every method hits the documented verb and path.
    /** @return array<string, array{callable, string, string, int, bool}> */
    public static function surface(): array
    {
        $id = 'id1';
        $page = ['items' => [], 'next_cursor' => null];

        // name => [call, method, path+query, response status, idempotency key expected]
        return [
            'messages.send' => [fn (Client $c) => $c->messages->send(['to' => '+254700000012', 'text' => 't']), 'POST', '/v1/messages', 201, true],
            'messages.list' => [fn (Client $c) => $c->messages->list(['limit' => 5]), 'GET', '/v1/messages?limit=5', 200, false],
            'messages.get' => [fn (Client $c) => $c->messages->get($id), 'GET', '/v1/messages/id1', 200, false],
            'messages.attempts' => [fn (Client $c) => $c->messages->attempts($id), 'GET', '/v1/messages/id1/attempts', 200, false],
            'messages.cancel' => [fn (Client $c) => $c->messages->cancel($id), 'POST', '/v1/messages/id1/cancel', 200, false],
            'batches.create' => [fn (Client $c) => $c->batches->create(['items' => [['to' => '+254700000012', 'text' => 't']], 'dedupe' => false]), 'POST', '/v1/messages/batch', 202, true],
            'batches.createFromCsv' => [fn (Client $c) => $c->batches->createFromCsv("to,text\n"), 'POST', '/v1/messages/batch', 202, true],
            'batches.get' => [fn (Client $c) => $c->batches->get($id), 'GET', '/v1/batches/id1', 200, false],
            'batches.validation' => [fn (Client $c) => $c->batches->validation($id), 'GET', '/v1/batches/id1/validation', 200, false],
            'batches.start' => [fn (Client $c) => $c->batches->start($id), 'POST', '/v1/batches/id1/start', 200, true],
            'batches.stop' => [fn (Client $c) => $c->batches->stop($id), 'POST', '/v1/batches/id1/stop', 200, true],
            'batches.listItems' => [fn (Client $c) => $c->batches->listItems($id, ['status' => 'sent']), 'GET', '/v1/batches/id1/items?status=sent', 200, false],
            'otp.send' => [fn (Client $c) => $c->otp->send(['to' => '+254700000012', 'ttlSeconds' => 300]), 'POST', '/v1/otp/send', 201, true],
            'otp.verify' => [fn (Client $c) => $c->otp->verify(['otpId' => 'o', 'code' => '1234']), 'POST', '/v1/otp/verify', 200, false],
            'lookups.create' => [fn (Client $c) => $c->lookups->create(['to' => '+254700000012']), 'POST', '/v1/lookup', 200, true],
            'lookups.get' => [fn (Client $c) => $c->lookups->get($id), 'GET', '/v1/lookup/id1', 200, false],
            'contacts.list' => [fn (Client $c) => $c->contacts->list(), 'GET', '/v1/contacts', 200, false],
            'contacts.create' => [fn (Client $c) => $c->contacts->create(['e164' => '+254700000012']), 'POST', '/v1/contacts', 201, true],
            'contacts.get' => [fn (Client $c) => $c->contacts->get($id), 'GET', '/v1/contacts/id1', 200, false],
            'contacts.update' => [fn (Client $c) => $c->contacts->update($id, ['name' => 'n']), 'PATCH', '/v1/contacts/id1', 200, false],
            'contacts.delete' => [fn (Client $c) => $c->contacts->delete($id), 'DELETE', '/v1/contacts/id1', 204, false],
            'contactGroups.list' => [fn (Client $c) => $c->contactGroups->list(), 'GET', '/v1/contact-groups', 200, false],
            'contactGroups.create' => [fn (Client $c) => $c->contactGroups->create(['name' => 'g', 'contactIds' => ['a']]), 'POST', '/v1/contact-groups', 201, true],
            'contactGroups.get' => [fn (Client $c) => $c->contactGroups->get($id), 'GET', '/v1/contact-groups/id1', 200, false],
            'contactGroups.update' => [fn (Client $c) => $c->contactGroups->update($id, ['name' => 'g2']), 'PATCH', '/v1/contact-groups/id1', 200, false],
            'contactGroups.delete' => [fn (Client $c) => $c->contactGroups->delete($id), 'DELETE', '/v1/contact-groups/id1', 204, false],
            'contactGroups.send' => [fn (Client $c) => $c->contactGroups->send($id, ['templateId' => 't', 'variables' => ['name' => 'A']]), 'POST', '/v1/contact-groups/id1/send', 200, true],
            'templates.list' => [fn (Client $c) => $c->templates->list(), 'GET', '/v1/templates', 200, false],
            'templates.create' => [fn (Client $c) => $c->templates->create(['name' => 'n', 'body' => 'b']), 'POST', '/v1/templates', 201, true],
            'templates.get' => [fn (Client $c) => $c->templates->get($id), 'GET', '/v1/templates/id1', 200, false],
            'templates.update' => [fn (Client $c) => $c->templates->update($id, ['body' => 'b2']), 'PATCH', '/v1/templates/id1', 200, false],
            'templates.delete' => [fn (Client $c) => $c->templates->delete($id), 'DELETE', '/v1/templates/id1', 204, false],
            'webhooks.list' => [fn (Client $c) => $c->webhooks->list(), 'GET', '/v1/webhooks', 200, false],
            'webhooks.create' => [fn (Client $c) => $c->webhooks->create(['url' => 'https://x', 'events' => ['a']]), 'POST', '/v1/webhooks', 201, true],
            'webhooks.get' => [fn (Client $c) => $c->webhooks->get($id), 'GET', '/v1/webhooks/id1', 200, false],
            'webhooks.update' => [fn (Client $c) => $c->webhooks->update($id, ['url' => 'https://x', 'events' => ['a'], 'enabled' => false]), 'PUT', '/v1/webhooks/id1', 200, true],
            'webhooks.delete' => [fn (Client $c) => $c->webhooks->delete($id), 'DELETE', '/v1/webhooks/id1', 204, true],
            'webhooks.test' => [fn (Client $c) => $c->webhooks->test($id), 'POST', '/v1/webhooks/id1/test', 202, true],
            'webhooks.listDeliveries' => [fn (Client $c) => $c->webhooks->listDeliveries($id, ['limit' => 3]), 'GET', '/v1/webhooks/id1/deliveries?limit=3', 200, false],
            'webhooks.replayDelivery' => [fn (Client $c) => $c->webhooks->replayDelivery($id, 42, ['generation' => 1, 'reason' => 'retry it']), 'POST', '/v1/webhooks/id1/deliveries/42/replay', 202, true],
            'inbound.list' => [fn (Client $c) => $c->inbound->list(), 'GET', '/v1/inbound', 200, false],
            'inbound.reply' => [fn (Client $c) => $c->inbound->reply($id, ['text' => 'hi']), 'POST', '/v1/inbound/id1/reply', 201, true],
            'numbers.list' => [fn (Client $c) => $c->numbers->list(), 'GET', '/v1/numbers', 200, false],
            'numbers.available' => [fn (Client $c) => $c->numbers->available(['country' => 'KE', 'kind' => 'long_code']), 'GET', '/v1/numbers/available?country=KE&kind=long_code', 200, false],
            'numbers.assign' => [fn (Client $c) => $c->numbers->assign(['country' => 'KE', 'kind' => 'long_code']), 'POST', '/v1/numbers', 201, true],
            'numbers.release' => [fn (Client $c) => $c->numbers->release($id), 'DELETE', '/v1/numbers/id1', 204, false],
            'numbers.listRules' => [fn (Client $c) => $c->numbers->listRules($id), 'GET', '/v1/numbers/id1/rules', 200, false],
            'numbers.createRule' => [fn (Client $c) => $c->numbers->createRule($id, ['match' => 'any', 'action' => 'webhook', 'target' => 'https://x']), 'POST', '/v1/numbers/id1/rules', 201, true],
            'numbers.updateRule' => [fn (Client $c) => $c->numbers->updateRule($id, 'r1', ['match' => 'any', 'action' => 'webhook', 'target' => 'https://x']), 'PUT', '/v1/numbers/id1/rules/r1', 200, false],
            'numbers.deleteRule' => [fn (Client $c) => $c->numbers->deleteRule($id, 'r1'), 'DELETE', '/v1/numbers/id1/rules/r1', 204, false],
            'senderIds.list' => [fn (Client $c) => $c->senderIds->list(), 'GET', '/v1/sender-ids', 200, false],
            'senderIds.get' => [fn (Client $c) => $c->senderIds->get($id), 'GET', '/v1/sender-ids/id1', 200, false],
            'senderIds.create' => [fn (Client $c) => $c->senderIds->create(['value' => 'ACME', 'kind' => 'alphanumeric', 'countries' => ['KE'], 'documents' => ['d']]), 'POST', '/v1/sender-ids', 201, false],
            'senderIds.update' => [fn (Client $c) => $c->senderIds->update($id, ['useCase' => 'x', 'countries' => ['KE'], 'documents' => []]), 'PATCH', '/v1/sender-ids/id1', 200, false],
            'senderIds.delete' => [fn (Client $c) => $c->senderIds->delete($id), 'DELETE', '/v1/sender-ids/id1', 204, false],
            'senderIds.check' => [fn (Client $c) => $c->senderIds->check(['value' => 'ACME', 'country' => 'KE']), 'GET', '/v1/sender-ids/check?value=ACME&country=KE', 200, false],
            'senderIds.quote' => [fn (Client $c) => $c->senderIds->quote(['countries' => 'KE']), 'GET', '/v1/sender-ids/quote?countries=KE', 200, false],
            'senderIds.listDocuments' => [fn (Client $c) => $c->senderIds->listDocuments(), 'GET', '/v1/sender-documents', 200, false],
            'senderIds.listDrafts' => [fn (Client $c) => $c->senderIds->listDrafts(), 'GET', '/v1/sender-id-drafts', 200, false],
            'senderIds.createDraft' => [fn (Client $c) => $c->senderIds->createDraft(['value' => 'X']), 'POST', '/v1/sender-id-drafts', 201, false],
            'senderIds.getDraft' => [fn (Client $c) => $c->senderIds->getDraft($id), 'GET', '/v1/sender-id-drafts/id1', 200, false],
            'senderIds.updateDraft' => [fn (Client $c) => $c->senderIds->updateDraft($id, ['version' => 1, 'sampleMessage' => 's']), 'PATCH', '/v1/sender-id-drafts/id1', 200, false],
            'senderIds.deleteDraft' => [fn (Client $c) => $c->senderIds->deleteDraft($id), 'DELETE', '/v1/sender-id-drafts/id1', 204, false],
            'suppressions.list' => [fn (Client $c) => $c->suppressions->list(), 'GET', '/v1/compliance/suppressions', 200, false],
            'suppressions.create' => [fn (Client $c) => $c->suppressions->create(['e164' => '+254700000012', 'reason' => 'manual']), 'POST', '/v1/compliance/suppressions', 201, false],
            'suppressions.import' => [fn (Client $c) => $c->suppressions->import([['e164' => '+254700000012', 'reason' => 'manual']]), 'POST', '/v1/compliance/suppressions/import', 201, false],
            'suppressions.delete' => [fn (Client $c) => $c->suppressions->delete(7), 'DELETE', '/v1/compliance/suppressions/7', 204, false],
            'compliance.listCountries' => [fn (Client $c) => $c->compliance->listCountries(), 'GET', '/v1/compliance/countries', 200, false],
            'compliance.getCountry' => [fn (Client $c) => $c->compliance->getCountry('KE'), 'GET', '/v1/compliance/countries/KE', 200, false],
            'compliance.listContentRules' => [fn (Client $c) => $c->compliance->listContentRules(), 'GET', '/v1/content-rules', 200, false],
            'wallet.balances' => [fn (Client $c) => $c->wallet->balances(), 'GET', '/v1/wallet', 200, false],
            'wallet.ledger' => [fn (Client $c) => $c->wallet->ledger(['limit' => 1, 'before' => 99]), 'GET', '/v1/wallet/ledger?limit=1&before=99', 200, false],
            'wallet.createTopup' => [fn (Client $c) => $c->wallet->createTopup(['amount' => '100', 'currency' => 'KES', 'channel' => 'card', 'email' => 'a@b.c']), 'POST', '/v1/wallet/topups', 201, true],
            'pricing.get' => [fn (Client $c) => $c->pricing->get(['product' => 'sms', 'country' => 'KE']), 'GET', '/v1/pricing?product=sms&country=KE', 200, false],
            'analytics.overview' => [fn (Client $c) => $c->analytics->overview(['range' => '7d']), 'GET', '/v1/analytics/overview?range=7d', 200, false],
            'analytics.byCountry' => [fn (Client $c) => $c->analytics->byCountry(), 'GET', '/v1/analytics/by-country', 200, false],
            'analytics.byCarrier' => [fn (Client $c) => $c->analytics->byCarrier(), 'GET', '/v1/analytics/by-carrier', 200, false],
            'analytics.bySenderId' => [fn (Client $c) => $c->analytics->bySenderId(), 'GET', '/v1/analytics/by-sender-id', 200, false],
            'analytics.timeseries' => [fn (Client $c) => $c->analytics->timeseries(['bucket' => 'day']), 'GET', '/v1/analytics/timeseries?bucket=day', 200, false],
            'sandbox.listMessages' => [fn (Client $c) => $c->sandbox->listMessages(['limit' => 10]), 'GET', '/v1/sandbox/messages?limit=10', 200, false],
            'countries.list' => [fn (Client $c) => $c->countries->list(), 'GET', '/v1/countries', 200, false],
            'countries.carriers' => [fn (Client $c) => $c->countries->carriers('KE'), 'GET', '/v1/countries/KE/carriers', 200, false],
            'countries.routes' => [fn (Client $c) => $c->countries->routes('KE'), 'GET', '/v1/countries/KE/routes', 200, false],
            'countries.compliance' => [fn (Client $c) => $c->countries->compliance('KE'), 'GET', '/v1/countries/KE/compliance', 200, false],
        ];
    }

    #[DataProvider('surface')]
    public function testSurface(callable $call, string $method, string $path, int $status, bool $idem): void
    {
        $response = $status === 204 ? MockHandler::empty() : MockHandler::json($status, ['items' => [], 'next_cursor' => null, 'data' => []]);
        $c = $this->client([$response]);
        $call($c);
        $r = $this->mock->last();
        $this->assertSame($method, $r['method']);
        $this->assertSame('http://mock.test' . $path, $r['url']);
        $this->assertSame($idem, isset($r['headers']['Idempotency-Key']));
        if ($r['body'] !== null && ($r['headers']['Content-Type'] ?? '') === 'application/json') {
            $this->assertIsArray(json_decode($r['body'], true));
        }
    }

    public function testSurfaceCoversEightyThreeMethods(): void
    {
        $names = array_keys(self::surface());
        // createFromCsv is a second entry point to batches.create, not counted.
        $counted = array_filter($names, static fn (string $n): bool => $n !== 'batches.createFromCsv');
        $this->assertCount(83, $counted);
    }

    public function testNestedBatchItemMapping(): void
    {
        $c = $this->client([MockHandler::json(202, ['id' => 'b'])]);
        $c->batches->create(['items' => [['to' => '+254700000012', 'text' => 't', 'senderId' => 'X', 'metadata' => []]]]);
        $this->assertSame('{"items":[{"to":"+254700000012","text":"t","sender_id":"X","metadata":{}}]}', $this->mock->last()['body']);
    }

    public function testWalletUnwrapsDataEnvelope(): void
    {
        $c = $this->client([MockHandler::json(200, ['data' => [['id' => 1, 'balance' => '10.000000']]])]);
        $this->assertSame([['id' => 1, 'balance' => '10.000000']], $c->wallet->balances());
    }
}
