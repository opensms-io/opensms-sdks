<?php

declare(strict_types=1);

namespace Opensms\Tests\Unit;

use RuntimeException;

/**
 * Injected in place of the cURL handler: records every request and replays
 * queued responses. A queued Throwable is thrown, simulating a network error.
 */
final class MockHandler
{
    /** @var list<array{method: string, url: string, headers: array<string, string>, body: ?string, timeout: float}> */
    public array $requests = [];

    /** @var list<array{status: int, headers: array<string, string>, body: string}|\Throwable> */
    private array $queue;

    /** @param list<array{status: int, headers: array<string, string>, body: string}|\Throwable> $responses */
    public function __construct(array $responses)
    {
        $this->queue = $responses;
    }

    /**
     * @param array{method: string, url: string, headers: array<string, string>, body: ?string, timeout: float} $request
     * @return array{status: int, headers: array<string, string>, body: string}
     */
    public function __invoke(array $request): array
    {
        $this->requests[] = $request;
        if ($this->queue === []) {
            throw new RuntimeException('MockHandler: no response queued');
        }
        $next = array_shift($this->queue);
        if ($next instanceof \Throwable) {
            throw $next;
        }

        return $next;
    }

    /** @param array<string, mixed>|list<mixed> $body */
    public static function json(int $status, array $body, array $headers = []): array
    {
        return [
            'status' => $status,
            'headers' => $headers + ['content-type' => 'application/json'],
            'body' => json_encode($body),
        ];
    }

    public static function problem(int $status, string $detail, array $headers = [], ?string $code = null): array
    {
        $body = ['type' => 'about:blank', 'title' => 'Error', 'status' => $status, 'detail' => $detail];
        if ($code !== null) {
            $body['code'] = $code;
        }

        return [
            'status' => $status,
            'headers' => $headers + ['content-type' => 'application/problem+json'],
            'body' => json_encode($body),
        ];
    }

    public static function empty(int $status = 204): array
    {
        return ['status' => $status, 'headers' => [], 'body' => ''];
    }

    public static function networkError(): RuntimeException
    {
        return new RuntimeException('curl error 7: Failed to connect');
    }

    public function last(): array
    {
        return $this->requests[array_key_last($this->requests)];
    }
}
