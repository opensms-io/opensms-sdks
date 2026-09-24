<?php

declare(strict_types=1);

namespace Opensms;

use RuntimeException;

/**
 * The default HTTP handler, built on ext-curl. This is the only code in the
 * SDK that touches the network. Any callable with the same signature can be
 * injected through the `handler` client option (the unit tests use a mock).
 *
 * Request:  ['method' => string, 'url' => string, 'headers' => array<string, string>,
 *            'body' => ?string, 'timeout' => float]
 * Response: ['status' => int, 'headers' => array<string, string> (lowercase names),
 *            'body' => string]
 *
 * A network failure or timeout throws a {@see RuntimeException}.
 */
final class CurlHandler
{
    /**
     * @param array{method: string, url: string, headers: array<string, string>, body: ?string, timeout: float} $request
     * @return array{status: int, headers: array<string, string>, body: string}
     */
    public function __invoke(array $request): array
    {
        $ch = curl_init();
        if ($ch === false) {
            throw new RuntimeException('curl_init failed');
        }

        $headerLines = [];
        foreach ($request['headers'] as $name => $value) {
            $headerLines[] = $name . ': ' . $value;
        }
        // Stop curl from adding "Expect: 100-continue" to larger bodies.
        $headerLines[] = 'Expect:';

        $responseHeaders = [];
        $timeoutMs = (int) round($request['timeout'] * 1000);

        curl_setopt_array($ch, [
            CURLOPT_URL => $request['url'],
            CURLOPT_CUSTOMREQUEST => $request['method'],
            CURLOPT_HTTPHEADER => $headerLines,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_FOLLOWLOCATION => false,
            CURLOPT_TIMEOUT_MS => $timeoutMs,
            CURLOPT_CONNECTTIMEOUT_MS => $timeoutMs,
            CURLOPT_HEADERFUNCTION => static function ($handle, string $line) use (&$responseHeaders): int {
                $trimmed = trim($line);
                if (str_starts_with($trimmed, 'HTTP/')) {
                    // A new status line (for example after a 100 Continue) resets headers.
                    $responseHeaders = [];
                } elseif ($trimmed !== '' && str_contains($trimmed, ':')) {
                    [$name, $value] = explode(':', $trimmed, 2);
                    $responseHeaders[strtolower(trim($name))] = trim($value);
                }

                return strlen($line);
            },
        ]);

        if ($request['body'] !== null) {
            curl_setopt($ch, CURLOPT_POSTFIELDS, $request['body']);
        }

        $body = curl_exec($ch);
        if ($body === false) {
            $message = curl_error($ch);
            $errno = curl_errno($ch);
            throw new RuntimeException("curl error {$errno}: {$message}");
        }

        $status = (int) curl_getinfo($ch, CURLINFO_RESPONSE_CODE);

        return [
            'status' => $status,
            'headers' => $responseHeaders,
            'body' => is_string($body) ? $body : '',
        ];
    }
}
