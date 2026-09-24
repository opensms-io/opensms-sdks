<?php

declare(strict_types=1);

namespace Opensms\Tests\Live;

use DateTimeImmutable;
use InvalidArgumentException;
use Opensms\Client;
use Opensms\OpensmsException;
use Opensms\Page;
use PHPUnit\Framework\TestCase;

/**
 * Live conformance scenario (CONFORMANCE.md "Live scenario"). Runs only when
 * OPENSMS_BASE_URL and OPENSMS_API_KEY are set; skipped otherwise. Steps run
 * in declaration order and share state through static properties.
 */
final class ConformanceTest extends TestCase
{
    private const UUID_RE = '/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/';
    private const ZERO_UUID = '00000000-0000-0000-0000-000000000000';
    /**
     * CONFORMANCE.md uses the fixed +254700000012, but the API caps sends per
     * destination (5/hour, 20/day, 3 OTPs per 10 min) and every SDK shares
     * that number, so each run uses its own random Safaricom-prefixed number.
     */
    private static string $to = '';

    private static ?Client $client = null;
    private static string $run = '';
    private static ?string $messageId = null;
    private static ?string $contactId = null;
    private static ?string $groupId = null;

    public static function setUpBeforeClass(): void
    {
        $base = getenv('OPENSMS_BASE_URL');
        $key = getenv('OPENSMS_API_KEY');
        if (is_string($base) && $base !== '' && is_string($key) && $key !== '') {
            self::$client = new Client($key, ['baseUrl' => $base, 'timeout' => 60]);
            self::$run = bin2hex(random_bytes(4));
            self::$to = self::ke();
        }
    }

    protected function setUp(): void
    {
        if (self::$client === null) {
            $this->markTestSkipped('OPENSMS_BASE_URL and OPENSMS_API_KEY are not set.');
        }
    }

    private function c(): Client
    {
        return self::$client;
    }

    private static function randomPhone(): string
    {
        return '+2547' . str_pad((string) random_int(0, 99_999_999), 8, '0', STR_PAD_LEFT);
    }

    /** A random +25470xxxxxxx number (KE, Safaricom prefix, like +254700000012). */
    private static function ke(): string
    {
        return '+25470' . str_pad((string) random_int(0, 9_999_999), 7, '0', STR_PAD_LEFT);
    }

    private function assertErr(int $status, string $detail, callable $fn): OpensmsException
    {
        try {
            $fn();
        } catch (OpensmsException $e) {
            $this->assertSame($status, $e->getStatus(), 'status for: ' . $e->getMessage());
            $this->assertSame($detail, $e->getDetail());

            return $e;
        }
        $this->fail("expected OpensmsException {$status} {$detail}");
    }

    /**
     * @template T
     * @param callable(): T $fn
     * @param callable(T): bool $done
     * @return T
     */
    private function poll(callable $fn, callable $done, float $deadline = 20.0): mixed
    {
        $end = microtime(true) + $deadline;
        do {
            $value = $fn();
            if ($done($value)) {
                return $value;
            }
            usleep(500_000);
        } while (microtime(true) < $end);
        $this->fail('poll deadline exceeded');
    }

    public function test01Constructor(): void
    {
        foreach (['not_a_key', 'sk_test_short'] as $bad) {
            try {
                new Client($bad);
                $this->fail("{$bad} accepted");
            } catch (InvalidArgumentException) {
                $this->addToAssertionCount(1);
            }
        }
    }

    public function test02AuthError(): void
    {
        $attempts = 0;
        $curl = new \Opensms\CurlHandler();
        $bad = new Client('sk_test_' . str_repeat('A', 32), [
            'baseUrl' => getenv('OPENSMS_BASE_URL'),
            'timeout' => 60,
            'handler' => function (array $r) use (&$attempts, $curl): array {
                $attempts++;

                return $curl($r);
            },
        ]);
        $e = $this->assertErr(401, 'missing or invalid API key', fn () => $bad->messages->list(['limit' => 1]));
        $this->assertSame('about:blank', $e->getType());
        $this->assertSame('Unauthorized', $e->getTitle());
        $this->assertNull($e->getErrorCode());
        $this->assertSame(1, $attempts);
    }

    public function test03Send(): void
    {
        $m = $this->c()->messages->send([
            'to' => self::$to,
            'text' => 'conformance php ' . self::$run,
            'metadata' => ['sdk' => 'php', 'run' => self::$run],
        ]);
        $this->assertMatchesRegularExpression(self::UUID_RE, $m['id']);
        $this->assertSame(self::$to, $m['to']);
        $this->assertSame('OPENSMS', $m['sender_id']);
        $this->assertSame('transactional', $m['traffic_type']);
        $this->assertContains($m['status'], ['queued', 'sending', 'sent', 'delivered']);
        $this->assertSame(1, $m['parts']);
        $this->assertSame('gsm7', $m['encoding']);
        $this->assertSame('KE', $m['country_iso2']);
        $this->assertSame('KES', $m['currency']);
        $this->assertSame('0.000000', $m['price']);
        $this->assertSame(self::$run, $m['metadata']['run']);
        self::$messageId = $m['id'];
    }

    public function test04IdempotentReplay(): void
    {
        $key = 'php-' . self::$run . '-' . bin2hex(random_bytes(6));
        $p = ['to' => self::$to, 'text' => 'idem php ' . self::$run];
        $a = $this->c()->messages->send($p, ['idempotencyKey' => $key]);
        $b = $this->c()->messages->send($p, ['idempotencyKey' => $key]);
        $this->assertSame($a['id'], $b['id']);
        $this->assertErr(409, 'Idempotency-Key was already used with a different request', fn () => $this->c()->messages->send(
            ['to' => self::$to, 'text' => 'idem php changed ' . self::$run],
            ['idempotencyKey' => $key],
        ));
    }

    public function test05GetAndWait(): void
    {
        $m = $this->poll(fn () => $this->c()->messages->get(self::$messageId), fn ($m) => $m['status'] === 'delivered');
        $this->assertNotEmpty($m['delivered_at']);
        $this->assertNotEmpty($m['sent_at']);
        $this->assertSame('conformance php ' . self::$run, $m['text']);
    }

    public function test06ListAndCursor(): void
    {
        $p1 = $this->c()->messages->list(['limit' => 1]);
        $this->assertInstanceOf(Page::class, $p1);
        $this->assertCount(1, $p1->items);
        $this->assertNotNull($p1->nextCursor);
        $p2 = $this->c()->messages->list(['limit' => 1, 'cursor' => $p1->nextCursor]);
        $this->assertCount(1, $p2->items);
        $this->assertNotSame($p1->items[0]['id'], $p2->items[0]['id']);
        $this->assertErr(400, 'invalid cursor', fn () => $this->c()->messages->list(['limit' => 1, 'cursor' => 'garbage']));
        $this->assertErr(400, 'invalid status', fn () => $this->c()->messages->list(['status' => 'bogus']));

        $seen = 0;
        foreach ($this->c()->paginate([$this->c()->messages, 'list'], ['limit' => 2]) as $m) {
            $this->assertArrayHasKey('id', $m);
            if (++$seen >= 3) {
                break;
            }
        }
        $this->assertSame(3, $seen);
    }

    public function test07Attempts(): void
    {
        $attempts = $this->c()->messages->attempts(self::$messageId);
        $this->assertNotEmpty($attempts);
        $this->assertSame(1, $attempts[0]['sequence']);
        $this->assertStringStartsWith('Mock provider (sandbox)', $attempts[0]['route_name']);
        $this->assertSame('delivered', $attempts[0]['status']);
        $this->assertSame('0.000000', $attempts[0]['price']);
    }

    public function test08ValidationError(): void
    {
        $e = $this->assertErr(400, 'to must be an E.164 phone number', fn () => $this->c()->messages->send(['to' => '12345', 'text' => 'x']));
        $this->assertSame('Bad Request', $e->getTitle());
        $this->assertSame('about:blank', $e->getType());
    }

    public function test09CodedError(): void
    {
        $e = $this->assertErr(400, 'Message ID must be a valid UUID.', fn () => $this->c()->messages->get('not-a-uuid'));
        $this->assertSame('invalid_message_id', $e->getErrorCode());
        $this->assertSame('https://api.opensms.io/problems/invalid_message_id', $e->getType());
    }

    public function test10NotFound(): void
    {
        $this->assertErr(404, 'message not found', fn () => $this->c()->messages->get(self::ZERO_UUID));
    }

    public function test11ScheduleAndCancel(): void
    {
        $m = $this->c()->messages->send([
            'to' => self::ke(),
            'text' => 'scheduled ' . self::$run,
            'scheduledAt' => new DateTimeImmutable('+2 hours'),
        ]);
        $this->assertSame('scheduled', $m['status']);
        $cancelled = $this->c()->messages->cancel($m['id']);
        $this->assertSame('cancelled', $cancelled['status']);
        $this->assertNotEmpty($cancelled['cancelled_at']);
        $detail = 'message cannot be cancelled in its current state';
        $this->assertErr(409, $detail, fn () => $this->c()->messages->cancel($m['id']));
        $this->assertErr(409, $detail, fn () => $this->c()->messages->cancel(self::$messageId));
    }

    public function test12Batch(): void
    {
        $b = $this->c()->batches->create(['items' => [
            ['to' => self::ke(), 'text' => 'b1 ' . self::$run],
            ['to' => self::ke(), 'text' => 'b2 ' . self::$run],
            ['to' => 'bad', 'text' => 'x'],
        ]]);
        $this->assertSame('ready', $b['status']);
        $this->assertSame(3, $b['total']);
        $this->assertSame(1, $b['invalid']);
        $this->assertSame(0, $b['sent']);

        $report = $this->c()->batches->validation($b['id']);
        $this->assertCount(3, $report['rows']);
        $this->assertSame(2, $report['valid']);
        $this->assertFalse($report['rows'][2]['valid']);
        $this->assertSame('to must be an E.164 phone number', $report['rows'][2]['error']);

        $got = $this->c()->batches->get($b['id']);
        $this->assertSame(3, $got['total']);
        $this->assertSame(1, $got['invalid']);

        $started = $this->c()->batches->start($b['id']);
        $this->assertSame('running', $started['status']);

        $page = $this->poll(fn () => $this->c()->batches->listItems($b['id']), fn (Page $p) => count($p->items) === 2);
        foreach ($page->items as $item) {
            $this->assertArrayHasKey('to', $item);
            $this->assertArrayHasKey('status', $item);
        }
    }

    public function test13BatchStop(): void
    {
        $b = $this->c()->batches->create(['items' => [['to' => self::ke(), 'text' => 'stop ' . self::$run]]]);
        $stopped = $this->c()->batches->stop($b['id']);
        $this->assertSame($b['id'], $stopped['id']);
        $this->assertSame('stopped', $stopped['status']);
        $this->assertSame(0, $stopped['cancelled']);
        $this->assertErr(409, 'batch is not ready to start', fn () => $this->c()->batches->start($b['id']));
        $this->assertErr(404, 'batch not found', fn () => $this->c()->batches->get(self::ZERO_UUID));
    }

    public function test14CsvBatch(): void
    {
        $b = $this->c()->batches->createFromCsv("to,text\n" . self::ke() . ",csv " . self::$run . "\n");
        $this->assertSame('ready', $b['status']);
        $this->assertSame(1, $b['total']);
        $this->assertSame(0, $b['invalid']);
    }

    public function test15Otp(): void
    {
        $since = new DateTimeImmutable('-5 seconds');
        $sent = $this->c()->otp->send(['to' => self::$to, 'length' => 6, 'ttlSeconds' => 300]);
        $this->assertMatchesRegularExpression(self::UUID_RE, $sent['otp_id']);

        $code = null;
        $this->poll(function () use ($since, &$code) {
            foreach ($this->c()->sandbox->listMessages(['limit' => 10])->items as $m) {
                if (($m['traffic_type'] ?? null) === 'otp' && ($m['to'] ?? null) === self::$to
                    && new DateTimeImmutable($m['created_at']) >= $since
                    && preg_match('/Your OpenSMS verification code is (\d{6})/', $m['text'] ?? '', $mm) === 1) {
                    $code = $mm[1];

                    return true;
                }
            }

            return false;
        }, fn ($found) => $found);

        $wrong = $code === '000000' ? '111111' : '000000';
        $r = $this->c()->otp->verify(['otpId' => $sent['otp_id'], 'code' => $wrong]);
        $this->assertFalse($r['valid']);
        $this->assertSame(4, $r['attempts_left']);
        $r = $this->c()->otp->verify(['otpId' => $sent['otp_id'], 'code' => $code]);
        $this->assertTrue($r['valid']);
        $this->assertSame(3, $r['attempts_left']);

        $this->assertErr(400, 'template must contain {{code}}', fn () => $this->c()->otp->send(['to' => self::$to, 'template' => 'no placeholder']));
        $this->assertErr(404, 'OTP not found', fn () => $this->c()->otp->verify(['otpId' => self::ZERO_UUID, 'code' => '123456']));
    }

    public function test16Lookup(): void
    {
        $l = $this->c()->lookups->create(['to' => self::$to]);
        $this->assertSame('completed', $l['state']);
        $this->assertSame('KE', $l['country']);
        $this->assertSame('mock', $l['source']);
        $this->assertSame('0.000000', $l['price']);
        $again = $this->c()->lookups->get($l['id']);
        $this->assertSame($l['id'], $again['id']);
        $this->assertSame($l['state'], $again['state']);
        $e = $this->assertErr(404, 'Lookup not found.', fn () => $this->c()->lookups->get(self::ZERO_UUID));
        $this->assertSame('not_found', $e->getErrorCode());
    }

    public function test17Contacts(): void
    {
        $r1 = self::randomPhone();
        $c = $this->c()->contacts->create(['e164' => $r1, 'name' => 'Ada ' . self::$run, 'attributes' => ['tier' => 'gold']]);
        $this->assertSame($r1, $c['e164']);
        self::$contactId = $c['id'];
        $this->assertSame($c['id'], $this->c()->contacts->get($c['id'])['id']);
        $u = $this->c()->contacts->update($c['id'], ['name' => 'Ada L ' . self::$run]);
        $this->assertSame('Ada L ' . self::$run, $u['name']);
        $this->assertSame('gold', $u['attributes']['tier']);

        $found = false;
        foreach ($this->c()->paginate([$this->c()->contacts, 'list'], ['limit' => 200]) as $item) {
            if ($item['id'] === $c['id']) {
                $found = true;
                break;
            }
        }
        $this->assertTrue($found);
        $this->assertErr(409, 'A record with this phone number or name already exists.', fn () => $this->c()->contacts->create(['e164' => $r1]));
    }

    public function test18ContactGroups(): void
    {
        $g = $this->c()->contactGroups->create(['name' => 'grp ' . self::$run, 'contactIds' => [self::$contactId]]);
        $this->assertSame([self::$contactId], $g['contact_ids']);
        self::$groupId = $g['id'];
        $u = $this->c()->contactGroups->update($g['id'], ['name' => 'grp2 ' . self::$run]);
        $this->assertSame('grp2 ' . self::$run, $u['name']);
        $this->assertSame($g['id'], $this->c()->contactGroups->get($g['id'])['id']);
        $batch = $this->c()->contactGroups->send($g['id'], ['text' => 'Hi ' . self::$run]);
        $this->assertSame('running', $batch['status']);
        $this->assertSame(1, $batch['total']);

        $empty = $this->c()->contactGroups->create(['name' => 'empty ' . self::$run]);
        $this->assertErr(422, 'Group must contain between 1 and 1000 contacts.', fn () => $this->c()->contactGroups->send($empty['id'], ['text' => 'x']));
        $this->c()->contactGroups->delete($empty['id']);
        $this->assertInstanceOf(Page::class, $this->c()->contactGroups->list(['limit' => 5]));
    }

    public function test19Templates(): void
    {
        $t = $this->c()->templates->create(['name' => 'tpl-' . self::$run, 'body' => 'Hi {{name}}', 'trafficType' => 'transactional']);
        $this->assertSame(['name'], $t['variables']);
        $u = $this->c()->templates->update($t['id'], ['body' => 'Hello {{name}}']);
        $this->assertSame('Hello {{name}}', $u['body']);
        $this->assertSame(['name'], $u['variables']);
        $this->assertSame($t['id'], $this->c()->templates->get($t['id'])['id']);
        $this->assertInstanceOf(Page::class, $this->c()->templates->list(['limit' => 5]));
        $batch = $this->c()->contactGroups->send(self::$groupId, ['templateId' => $t['id'], 'variables' => ['name' => 'Ada']]);
        $this->assertSame('running', $batch['status']);

        $this->assertNull($this->c()->templates->delete($t['id']));
        $this->assertNull($this->c()->contactGroups->delete(self::$groupId));
        $this->assertNull($this->c()->contacts->delete(self::$contactId));
        $this->assertErr(404, 'Record not found.', fn () => $this->c()->contacts->get(self::$contactId));
    }

    public function test20Webhooks(): void
    {
        $w = $this->c()->webhooks->create(['url' => 'https://example.com/opensms/' . self::$run, 'events' => ['message.delivered', 'message.failed']]);
        $this->assertStringStartsWith('whsec_', $w['secret']);
        $this->assertTrue($w['enabled']);
        $got = $this->c()->webhooks->get($w['id']);
        $this->assertArrayNotHasKey('secret', $got);
        $this->assertInstanceOf(Page::class, $this->c()->webhooks->list(['limit' => 5]));
        $this->assertErr(400, 'url must be an HTTPS URL without credentials or fragment', fn () => $this->c()->webhooks->create(['url' => 'http://example.com/x', 'events' => ['message.delivered']]));

        $u = $this->c()->webhooks->update($w['id'], ['url' => 'https://example.com/opensms/' . self::$run . '/v2', 'events' => ['message.delivered'], 'enabled' => true]);
        $this->assertSame('https://example.com/opensms/' . self::$run . '/v2', $u['url']);
        $this->assertSame(['message.delivered'], $u['events']);

        $this->assertSame('pending', $this->c()->webhooks->test($w['id'])['status']);
        $deliveries = $this->poll(fn () => $this->c()->webhooks->listDeliveries($w['id']), fn (Page $p) => count($p->items) > 0);
        $d = null;
        foreach ($deliveries->items as $item) {
            if ($item['event'] === 'webhook.test') {
                $d = $item;
            }
        }
        $this->assertNotNull($d);
        $this->assertIsInt($d['id']);
        $this->assertIsInt($d['generation']);

        try {
            $r = $this->c()->webhooks->replayDelivery($w['id'], $d['id'], ['generation' => $d['generation'], 'reason' => 'sdk conformance replay']);
            $this->assertArrayHasKey('status', $r);
        } catch (OpensmsException $e) {
            $this->assertSame(409, $e->getStatus());
            $this->assertSame('Delivery state, lease or generation does not permit replay.', $e->getDetail());
        }

        $this->assertNull($this->c()->webhooks->delete($w['id']));
        $this->assertErr(404, 'webhook not found', fn () => $this->c()->webhooks->get($w['id']));
    }

    public function test21Suppressions(): void
    {
        $r2 = self::randomPhone();
        $s = $this->c()->suppressions->create(['e164' => $r2, 'reason' => 'manual']);
        $this->assertIsInt($s['id']);
        $this->assertSame('manual', $s['reason']);
        $e = $this->assertErr(422, 'destination is suppressed', fn () => $this->c()->messages->send(['to' => $r2, 'text' => 'x']));
        $this->assertIsString($e->getRequestId());
        $this->assertNotSame('', $e->getRequestId());

        $found = false;
        foreach ($this->c()->paginate([$this->c()->suppressions, 'list'], ['limit' => 200]) as $item) {
            if ($item['e164'] === $r2) {
                $found = true;
                break;
            }
        }
        $this->assertTrue($found);

        $imp = $this->c()->suppressions->import([['e164' => self::randomPhone(), 'reason' => 'complaint']]);
        $this->assertSame(1, $imp['created']);
        $this->assertSame(1, $imp['received']);
        $this->assertNull($this->c()->suppressions->delete($s['id']));
        $this->assertErr(404, 'suppression not found', fn () => $this->c()->suppressions->delete($s['id']));
    }

    public function test22Compliance(): void
    {
        $ke = $this->c()->compliance->getCountry('KE');
        $this->assertSame('KE', $ke['iso2']);
        $this->assertSame('+254', $ke['dial_code']);
        $this->assertContains('STOP', $ke['stop_keywords']);
        $this->assertErr(404, 'country not found', fn () => $this->c()->compliance->getCountry('ZZ'));
        $this->assertContains('KE', array_column($this->c()->compliance->listCountries(), 'iso2'));
        $rules = $this->c()->compliance->listContentRules();
        $this->assertIsArray($rules);
        foreach ($rules as $rule) {
            $this->assertIsInt($rule['id']);
        }
    }

    public function test23Wallet(): void
    {
        $balances = $this->c()->wallet->balances();
        $this->assertNotEmpty($balances);
        $this->assertSame('sandbox', $balances[0]['environment']);
        $this->assertSame('KES', $balances[0]['currency']);
        $this->assertMatchesRegularExpression('/^-?\d+(\.\d+)?$/', $balances[0]['balance']);
        $ledger = $this->c()->wallet->ledger(['limit' => 1]);
        $this->assertCount(1, $ledger);
        $this->assertIsInt($ledger[0]['id']);
        $this->assertErr(400, 'limit must be between 1 and 200', fn () => $this->c()->wallet->ledger(['limit' => 0]));
        $this->assertErr(422, 'sandbox wallets cannot use payment providers', fn () => $this->c()->wallet->createTopup([
            'amount' => '100', 'currency' => 'KES', 'channel' => 'card', 'email' => 'dev@opensms.test',
        ]));
    }

    public function test24Pricing(): void
    {
        $p = $this->c()->pricing->get(['product' => 'sms', 'country' => 'KE']);
        $this->assertSame('KES', $p['currency']);
        $this->assertSame('sms', $p['product']);
        foreach ($p['entries'] as $entry) {
            $this->assertSame('KE', $entry['country_iso2']);
        }
        $this->assertErr(400, 'product must be sms, lookup, or number_monthly', fn () => $this->c()->pricing->get(['product' => 'bogus']));
    }

    public function test25Analytics(): void
    {
        $o = $this->c()->analytics->overview();
        $this->assertSame('sandbox', $o['environment']);
        $this->assertSame('KES', $o['currency']);
        $this->assertIsInt($o['sent']);
        $this->assertIsArray($this->c()->analytics->overview(['range' => '7d']));
        $this->assertIsList($this->c()->analytics->byCountry());
        $this->assertIsList($this->c()->analytics->byCarrier());
        $this->assertIsList($this->c()->analytics->bySenderId());
        $this->assertIsList($this->c()->analytics->timeseries());
    }

    public function test26NumbersAndInbound(): void
    {
        $this->assertInstanceOf(Page::class, $this->c()->numbers->list());
        $this->assertIsList($this->c()->numbers->available(['country' => 'KE', 'kind' => 'long_code']));
        $this->assertErr(422, 'This operation requires the live environment.', fn () => $this->c()->numbers->assign(['country' => 'KE', 'kind' => 'long_code']));
        $this->assertSame([], $this->c()->inbound->list()->items);
    }

    public function test27SenderIds(): void
    {
        $found = false;
        foreach ($this->c()->senderIds->list()->items as $s) {
            if ($s['value'] === 'OPENSMS' && $s['status'] === 'approved') {
                $found = true;
            }
        }
        $this->assertTrue($found);
        $this->assertTrue($this->c()->senderIds->check(['value' => 'ACME', 'country' => 'KE'])['valid']);
        $this->assertStringStartsWith('sq_', $this->c()->senderIds->quote(['countries' => ['KE']])['quote_id']);
        $this->assertIsList($this->c()->senderIds->listDocuments());

        $letters = '';
        for ($i = 0; $i < 4; $i++) {
            $letters .= chr(random_int(65, 90));
        }
        $d = $this->c()->senderIds->createDraft([
            'source' => 'application', 'value' => 'SDK' . $letters, 'kind' => 'alphanumeric',
            'countries' => ['KE'], 'useCase' => 'transactional', 'sampleMessage' => 'Your order shipped',
        ]);
        $this->assertSame(1, $d['version']);
        $this->assertSame('active', $d['status']);
        $u = $this->c()->senderIds->updateDraft($d['id'], ['version' => 1, 'sampleMessage' => 'Your order has shipped']);
        $this->assertSame(2, $u['version']);
        $this->assertSame($d['id'], $this->c()->senderIds->getDraft($d['id'])['id']);
        $this->assertInstanceOf(Page::class, $this->c()->senderIds->listDrafts(['limit' => 5]));
        $this->assertNull($this->c()->senderIds->deleteDraft($d['id']));
        $this->assertErr(404, 'sender ID not found', fn () => $this->c()->senderIds->get(self::ZERO_UUID));
    }

    public function test28Countries(): void
    {
        $ke = null;
        foreach ($this->c()->countries->list() as $country) {
            if ($country['iso2'] === 'KE') {
                $ke = $country;
            }
        }
        $this->assertNotNull($ke);
        $this->assertSame('+254', $ke['dial_code']);
        $this->assertNotEmpty($this->c()->countries->carriers('KE'));
        $this->assertIsList($this->c()->countries->routes('KE'));
        $this->assertSame('KE', $this->c()->countries->compliance('KE')['iso2']);
    }

    public function test29ScopeErrors(): void
    {
        $ro = getenv('OPENSMS_READONLY_API_KEY');
        if (!is_string($ro) || $ro === '') {
            $this->markTestSkipped('OPENSMS_READONLY_API_KEY is not set.');
        }
        $client = new Client($ro, ['baseUrl' => getenv('OPENSMS_BASE_URL'), 'timeout' => 60]);
        $this->assertErr(401, 'insufficient scope', fn () => $client->messages->send(['to' => self::$to, 'text' => 'x']));
        $this->assertErr(403, 'Insufficient API key scope.', fn () => $client->contacts->list());
        $this->assertInstanceOf(Page::class, $client->messages->list(['limit' => 1]));
    }
}
