<?php

declare(strict_types=1);

namespace Opensms;

use InvalidArgumentException;

/**
 * Request pipeline shared by every resource: headers, JSON encoding,
 * Idempotency-Key handling, retries with backoff (honouring Retry-After),
 * and mapping non-2xx responses to {@see OpensmsException}. The actual
 * network call is delegated to the handler ({@see CurlHandler} by default).
 *
 * @internal
 */
final class Transport
{
    public const VERSION = '0.1.0';
    public const USER_AGENT = 'opensms-php/' . self::VERSION;
    public const DEFAULT_BASE_URL = 'https://api.opensms.io';

    /** Retry-After values above this many seconds are not waited for. */
    private const MAX_RETRY_AFTER = 60.0;

    private readonly string $apiKey;
    private readonly string $baseUrl;
    private readonly float $timeout;
    private readonly int $maxRetries;
    /** @var callable(array<string, mixed>): array<string, mixed> */
    private $handler;
    /** @var callable(float): void */
    private $sleeper;

    /**
     * @param array{baseUrl?: string, timeout?: float|int, maxRetries?: int, handler?: callable, sleep?: callable} $options
     */
    public function __construct(string $apiKey, array $options = [])
    {
        $this->apiKey = $apiKey;
        $this->baseUrl = rtrim((string) ($options['baseUrl'] ?? self::DEFAULT_BASE_URL), '/');
        $this->timeout = (float) ($options['timeout'] ?? 30.0);
        $maxRetries = (int) ($options['maxRetries'] ?? 2);
        if ($maxRetries < 0) {
            throw new InvalidArgumentException('OpenSMS: `maxRetries` must be 0 or more.');
        }
        $this->maxRetries = $maxRetries;
        $this->handler = $options['handler'] ?? new CurlHandler();
        $this->sleeper = $options['sleep'] ?? static function (float $seconds): void {
            if ($seconds > 0) {
                usleep((int) round($seconds * 1_000_000));
            }
        };
    }

    public function baseUrl(): string
    {
        return $this->baseUrl;
    }

    /**
     * Perform one API call.
     *
     * @param array<string, mixed> $query Already-mapped query parameters (null values are skipped).
     * @param array<string, mixed>|null $json JSON body, or null for none.
     * @param array{
     *     idempotent?: bool,
     *     idempotencyKey?: ?string,
     *     retry?: bool,
     *     rawBody?: string,
     *     contentType?: string
     * } $opts `idempotent` sends an Idempotency-Key (the given one or a fresh
     *     UUIDv4, reused on every retry). `retry` false disables retries for
     *     a POST that is not idempotent. `rawBody` + `contentType` send a
     *     non-JSON body (CSV batches).
     */
    public function request(string $method, string $path, array $query = [], ?array $json = null, array $opts = []): mixed
    {
        $headers = [
            'Authorization' => 'Bearer ' . $this->apiKey,
            'Accept' => 'application/json',
            'User-Agent' => self::USER_AGENT,
        ];

        $body = null;
        if (isset($opts['rawBody'])) {
            $body = $opts['rawBody'];
            $headers['Content-Type'] = $opts['contentType'] ?? 'application/octet-stream';
        } elseif ($json !== null) {
            $body = json_encode($json, JSON_THROW_ON_ERROR | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
            $headers['Content-Type'] = 'application/json';
        }

        $idempotent = (bool) ($opts['idempotent'] ?? false);
        if ($idempotent) {
            $key = $opts['idempotencyKey'] ?? null;
            $headers['Idempotency-Key'] = ($key !== null && $key !== '') ? (string) $key : self::uuid4();
        }

        // GET/PUT/PATCH/DELETE are always safe to repeat; POST only with a key.
        $retryable = ($opts['retry'] ?? true) && ($method !== 'POST' || $idempotent);
        $maxAttempts = $retryable ? $this->maxRetries + 1 : 1;

        $request = [
            'method' => $method,
            'url' => $this->baseUrl . $path . Models::queryString($query),
            'headers' => $headers,
            'body' => $body,
            'timeout' => $this->timeout,
        ];

        $lastNetworkError = null;
        for ($attempt = 1; $attempt <= $maxAttempts; $attempt++) {
            try {
                $response = ($this->handler)($request);
            } catch (\Exception $e) {
                if ($e instanceof OpensmsException) {
                    throw $e;
                }
                $lastNetworkError = $e;
                if ($attempt < $maxAttempts) {
                    ($this->sleeper)($this->backoff($attempt));
                    continue;
                }
                break;
            }

            $status = (int) $response['status'];
            $respHeaders = array_change_key_case($response['headers'] ?? [], CASE_LOWER);
            $raw = (string) ($response['body'] ?? '');

            if ($status >= 200 && $status < 300) {
                return self::decodeSuccess($status, $raw);
            }

            $retryAfter = self::parseRetryAfter($respHeaders['retry-after'] ?? null);
            if ($attempt < $maxAttempts && self::isRetryableStatus($status)
                && ($retryAfter === null || $retryAfter <= self::MAX_RETRY_AFTER)) {
                ($this->sleeper)($retryAfter ?? $this->backoff($attempt));
                continue;
            }

            throw self::toError($status, $respHeaders, $raw, $retryAfter);
        }

        $reason = $lastNetworkError?->getMessage() ?? 'unknown error';

        throw new OpensmsException(0, 'OpenSMS request failed: ' . $reason, previous: $lastNetworkError);
    }

    private static function isRetryableStatus(int $status): bool
    {
        return in_array($status, [429, 500, 502, 503, 504], true);
    }

    /** Full-jitter exponential backoff: random(0, min(8, 0.5 * 2^(n-1))). */
    private function backoff(int $attempt): float
    {
        $cap = min(8.0, 0.5 * (2 ** ($attempt - 1)));

        return $cap * (mt_rand() / mt_getrandmax());
    }

    /** Integer seconds or an HTTP date, in seconds from now; null if absent or unparseable. */
    public static function parseRetryAfter(?string $value): ?float
    {
        if ($value === null) {
            return null;
        }
        $value = trim($value);
        if ($value === '') {
            return null;
        }
        if (preg_match('/^\d+(\.\d+)?$/', $value) === 1) {
            return (float) $value;
        }
        $when = strtotime($value);
        if ($when === false) {
            return null;
        }

        return (float) max(0, $when - time());
    }

    private static function decodeSuccess(int $status, string $raw): mixed
    {
        if ($status === 204 || $raw === '') {
            return null;
        }
        try {
            return json_decode($raw, true, 512, JSON_THROW_ON_ERROR | JSON_BIGINT_AS_STRING);
        } catch (\JsonException) {
            return $raw;
        }
    }

    /**
     * @param array<string, string> $headers lowercase header names
     */
    private static function toError(int $status, array $headers, string $raw, ?float $retryAfter): OpensmsException
    {
        $decoded = null;
        if ($raw !== '') {
            try {
                $decoded = json_decode($raw, true, 512, JSON_THROW_ON_ERROR);
            } catch (\JsonException) {
                $decoded = null;
            }
        }

        $problem = is_array($decoded) && !array_is_list($decoded) ? $decoded : null;
        $str = static fn (string $k): ?string => ($problem !== null && isset($problem[$k]) && is_string($problem[$k])) ? $problem[$k] : null;

        $detail = $str('detail');
        $title = $str('title');
        $errors = ($problem !== null && isset($problem['errors']) && is_array($problem['errors'])) ? $problem['errors'] : null;
        $requestId = $headers['x-request-id'] ?? null;

        $message = $detail ?? $title ?? "OpenSMS request failed with status {$status}";

        return new OpensmsException(
            status: $status,
            message: $message,
            type: $str('type'),
            title: $title,
            detail: $detail,
            errorCode: $str('code'),
            traceId: $str('trace_id'),
            errors: $errors,
            requestId: ($requestId !== null && $requestId !== '') ? $requestId : null,
            retryAfter: $retryAfter,
            body: $decoded ?? ($raw === '' ? null : $raw),
        );
    }

    /** RFC 4122 version 4 UUID (36 characters). */
    public static function uuid4(): string
    {
        $bytes = random_bytes(16);
        $bytes[6] = chr((ord($bytes[6]) & 0x0f) | 0x40);
        $bytes[8] = chr((ord($bytes[8]) & 0x3f) | 0x80);
        $hex = bin2hex($bytes);

        return sprintf(
            '%s-%s-%s-%s-%s',
            substr($hex, 0, 8),
            substr($hex, 8, 4),
            substr($hex, 12, 4),
            substr($hex, 16, 4),
            substr($hex, 20, 12),
        );
    }
}
