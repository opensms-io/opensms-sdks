<?php

declare(strict_types=1);

namespace Opensms;

/**
 * Webhook signature verification. Static, so a receiver can verify
 * deliveries without constructing a client or holding an API key.
 *
 * OpenSMS signs each delivery with the header
 * `X-OpenSMS-Signature: t=<unix seconds>,v1=<hex>`, where
 * `v1 = hex(HMAC-SHA256(secret, "<t>.<raw body>"))` and `secret` is the full
 * `whsec_...` value returned once by `webhooks->create()`. Parsing mirrors the
 * server (`internal/webhooks/signature.go`) exactly.
 */
final class Webhook
{
    public const SIGNATURE_HEADER = 'X-OpenSMS-Signature';
    public const DEFAULT_TOLERANCE = 300;

    private function __construct()
    {
    }

    /**
     * True when `$header` is a valid, unexpired signature of `$payload`.
     *
     * @param string $payload The exact raw request body bytes (verify before parsing JSON).
     * @param string $header The X-OpenSMS-Signature header value.
     * @param string $secret The endpoint secret, `whsec_...`, used verbatim.
     * @param array{toleranceSeconds?: int, now?: int} $options
     */
    public static function verifySignature(string $payload, string $header, string $secret, array $options = []): bool
    {
        return self::check($payload, $header, $secret, $options) === null;
    }

    /**
     * Verify the signature and decode the event envelope
     * `{id, type, workspace_id, environment, created_at, data}`.
     *
     * @param array{toleranceSeconds?: int, now?: int} $options
     * @return array<string, mixed>
     * @throws OpensmsException status 0 with code "invalid_signature" or "expired_signature"
     */
    public static function constructEvent(string $payload, string $header, string $secret, array $options = []): array
    {
        $failure = self::check($payload, $header, $secret, $options);
        if ($failure !== null) {
            $message = $failure === 'expired_signature'
                ? 'OpenSMS webhook signature timestamp is outside the tolerance.'
                : 'OpenSMS webhook signature is invalid.';

            throw new OpensmsException(0, $message, errorCode: $failure);
        }

        try {
            $event = json_decode($payload, true, 512, JSON_THROW_ON_ERROR);
        } catch (\JsonException $e) {
            throw new OpensmsException(0, 'OpenSMS webhook payload is not valid JSON.', errorCode: 'invalid_payload', previous: $e);
        }
        if (!is_array($event)) {
            throw new OpensmsException(0, 'OpenSMS webhook payload is not a JSON object.', errorCode: 'invalid_payload');
        }

        return $event;
    }

    /**
     * @param array{toleranceSeconds?: int, now?: int} $options
     * @return string|null null when valid, else "invalid_signature" or "expired_signature"
     */
    private static function check(string $payload, string $header, string $secret, array $options): ?string
    {
        $tolerance = (int) ($options['toleranceSeconds'] ?? self::DEFAULT_TOLERANCE);
        $now = (int) ($options['now'] ?? time());

        if (trim($secret) === '' || $tolerance < 0) {
            return 'invalid_signature';
        }

        $values = self::parseHeader($header);
        if ($values === null) {
            return 'invalid_signature';
        }

        $t = $values['t'];
        if (preg_match('/^[+-]?\d{1,19}$/', $t) !== 1) {
            return 'invalid_signature';
        }
        $timestamp = (int) $t;
        if (abs($now - $timestamp) > $tolerance) {
            return 'expired_signature';
        }

        $v1 = $values['v1'];
        if (strlen($v1) !== 64 || !ctype_xdigit($v1)) {
            return 'invalid_signature';
        }

        $expected = hash_hmac('sha256', $t . '.' . $payload, $secret);
        if (!hash_equals($expected, strtolower($v1))) {
            return 'invalid_signature';
        }

        return null;
    }

    /**
     * Split on ",", trim, split on the first "="; reject empty parts,
     * duplicates, and anything other than exactly `t` and `v1`.
     *
     * @return array{t: string, v1: string}|null
     */
    private static function parseHeader(string $header): ?array
    {
        $values = [];
        foreach (explode(',', $header) as $part) {
            $pair = explode('=', trim($part), 2);
            if (count($pair) !== 2 || $pair[0] === '' || $pair[1] === '' || isset($values[$pair[0]])) {
                return null;
            }
            $values[$pair[0]] = $pair[1];
        }
        if (count($values) !== 2 || !isset($values['t'], $values['v1'])) {
            return null;
        }

        return ['t' => $values['t'], 'v1' => $values['v1']];
    }
}
