<?php

declare(strict_types=1);

namespace Opensms;

use DateTimeImmutable;
use DateTimeInterface;
use DateTimeZone;
use InvalidArgumentException;

/**
 * The one place that maps SDK input to the wire shape and decodes response
 * envelopes. Not part of the public API.
 *
 * Request params are associative arrays keyed by the API's snake_case field
 * names (`sender_id`, `traffic_type`, ...). The camelCase spelling
 * (`senderId`, `trafficType`, ...) is accepted as an alias. Unknown keys are
 * rejected with InvalidArgumentException before any request is made, because
 * the API itself rejects unknown JSON fields. Null values are omitted from
 * the body rather than sent as `null`.
 *
 * Responses are returned as decoded associative arrays with the API's
 * snake_case keys; money stays a decimal string and timestamps stay RFC 3339
 * strings.
 *
 * @internal
 */
final class Models
{
    /** Field kind: passed through as-is. */
    public const SCALAR = 'scalar';
    /** Field kind: free-form JSON object (`{}` even when empty). */
    public const OBJECT = 'object';
    /** Field kind: RFC 3339 datetime, accepts DateTimeInterface or string. */
    public const DATETIME = 'datetime';
    /** Field kind: list of strings; in a query it is joined with commas. */
    public const LIST = 'list';

    // ---- Request field specs (wire name => kind) ----

    /** @var array<string, string> */
    public const MESSAGE_SEND = [
        'to' => self::SCALAR,
        'text' => self::SCALAR,
        'sender_id' => self::SCALAR,
        'traffic_type' => self::SCALAR,
        'scheduled_at' => self::DATETIME,
        'callback_url' => self::SCALAR,
        'metadata' => self::OBJECT,
    ];

    /** @var array<string, string> */
    public const MESSAGE_LIST_QUERY = [
        'limit' => self::SCALAR,
        'cursor' => self::SCALAR,
        'status' => self::SCALAR,
        'to' => self::SCALAR,
        'country' => self::SCALAR,
        'date_from' => self::DATETIME,
        'date_to' => self::DATETIME,
    ];

    /** @var array<string, string> */
    public const BATCH_ITEM = [
        'to' => self::SCALAR,
        'text' => self::SCALAR,
        'sender_id' => self::SCALAR,
        'traffic_type' => self::SCALAR,
        'callback_url' => self::SCALAR,
        'metadata' => self::OBJECT,
    ];

    /** @var array<string, string> */
    public const PAGE_QUERY = [
        'limit' => self::SCALAR,
        'cursor' => self::SCALAR,
    ];

    /** @var array<string, string> */
    public const BATCH_ITEMS_QUERY = [
        'status' => self::SCALAR,
        'limit' => self::SCALAR,
        'cursor' => self::SCALAR,
    ];

    /** @var array<string, string> */
    public const OTP_SEND = [
        'to' => self::SCALAR,
        'sender_id' => self::SCALAR,
        'template' => self::SCALAR,
        'length' => self::SCALAR,
        'ttl_seconds' => self::SCALAR,
    ];

    /** @var array<string, string> */
    public const OTP_VERIFY = [
        'otp_id' => self::SCALAR,
        'code' => self::SCALAR,
    ];

    /** @var array<string, string> */
    public const LOOKUP_CREATE = [
        'to' => self::SCALAR,
    ];

    /** @var array<string, string> */
    public const CONTACT = [
        'e164' => self::SCALAR,
        'name' => self::SCALAR,
        'attributes' => self::OBJECT,
    ];

    /** @var array<string, string> */
    public const CONTACT_GROUP = [
        'name' => self::SCALAR,
        'contact_ids' => self::SCALAR,
    ];

    /** @var array<string, string> */
    public const GROUP_SEND = [
        'text' => self::SCALAR,
        'template_id' => self::SCALAR,
        'variables' => self::OBJECT,
        'sender_id' => self::SCALAR,
        'traffic_type' => self::SCALAR,
        'callback_url' => self::SCALAR,
    ];

    /** @var array<string, string> */
    public const TEMPLATE = [
        'name' => self::SCALAR,
        'body' => self::SCALAR,
        'traffic_type' => self::SCALAR,
    ];

    /** @var array<string, string> */
    public const WEBHOOK = [
        'url' => self::SCALAR,
        'events' => self::SCALAR,
        'enabled' => self::SCALAR,
    ];

    /** @var array<string, string> */
    public const WEBHOOK_REPLAY = [
        'generation' => self::SCALAR,
        'reason' => self::SCALAR,
    ];

    /** @var array<string, string> */
    public const INBOUND_REPLY = [
        'text' => self::SCALAR,
    ];

    /** @var array<string, string> */
    public const NUMBER_QUERY = [
        'country' => self::SCALAR,
        'kind' => self::SCALAR,
    ];

    /** @var array<string, string> */
    public const NUMBER_RULE = [
        'match' => self::SCALAR,
        'pattern' => self::SCALAR,
        'action' => self::SCALAR,
        'target' => self::SCALAR,
        'position' => self::SCALAR,
    ];

    /** @var array<string, string> */
    public const SENDER_ID_CREATE = [
        'value' => self::SCALAR,
        'kind' => self::SCALAR,
        'countries' => self::SCALAR,
        'use_case' => self::SCALAR,
        'sample_message' => self::SCALAR,
        'documents' => self::SCALAR,
        'draft_id' => self::SCALAR,
        'draft_version' => self::SCALAR,
        'quote_id' => self::SCALAR,
    ];

    /** @var array<string, string> */
    public const SENDER_ID_UPDATE = [
        'use_case' => self::SCALAR,
        'countries' => self::SCALAR,
        'documents' => self::SCALAR,
        'sample_message' => self::SCALAR,
    ];

    /** @var array<string, string> */
    public const SENDER_ID_CHECK_QUERY = [
        'value' => self::SCALAR,
        'country' => self::SCALAR,
    ];

    /** @var array<string, string> */
    public const SENDER_ID_QUOTE_QUERY = [
        'countries' => self::LIST,
    ];

    /** @var array<string, string> */
    public const SENDER_ID_DRAFT = [
        'source' => self::SCALAR,
        'value' => self::SCALAR,
        'kind' => self::SCALAR,
        'countries' => self::SCALAR,
        'use_case' => self::SCALAR,
        'sample_message' => self::SCALAR,
        'documents' => self::SCALAR,
    ];

    /** @var array<string, string> */
    public const SENDER_ID_DRAFT_UPDATE = self::SENDER_ID_DRAFT + [
        'version' => self::SCALAR,
    ];

    /** @var array<string, string> */
    public const SUPPRESSION = [
        'e164' => self::SCALAR,
        'reason' => self::SCALAR,
    ];

    /** @var array<string, string> */
    public const LEDGER_QUERY = [
        'limit' => self::SCALAR,
        'before' => self::SCALAR,
    ];

    /** @var array<string, string> */
    public const TOPUP = [
        'amount' => self::SCALAR,
        'currency' => self::SCALAR,
        'channel' => self::SCALAR,
        'email' => self::SCALAR,
    ];

    /** @var array<string, string> */
    public const PRICING_QUERY = [
        'product' => self::SCALAR,
        'country' => self::SCALAR,
    ];

    /** @var array<string, string> */
    public const ANALYTICS_QUERY = [
        'currency' => self::SCALAR,
        'range' => self::SCALAR,
        'from' => self::DATETIME,
        'to' => self::DATETIME,
        'bucket' => self::SCALAR,
    ];

    /**
     * Map caller params to wire fields for a JSON body or query.
     *
     * @param array<string, mixed> $params
     * @param array<string, string> $spec wire name => kind
     * @param list<string> $required wire names that must be present
     * @return array<string, mixed>
     */
    public static function map(array $params, array $spec, array $required = [], bool $forQuery = false): array
    {
        $aliases = [];
        foreach (array_keys($spec) as $wire) {
            $aliases[$wire] = $wire;
            $aliases[self::camel($wire)] = $wire;
        }

        $out = [];
        foreach ($params as $key => $value) {
            if (!is_string($key) || !isset($aliases[$key])) {
                $allowed = implode(', ', array_keys($spec));
                throw new InvalidArgumentException("OpenSMS: unknown parameter `{$key}` (allowed: {$allowed}).");
            }
            $wire = $aliases[$key];
            if ($value === null || array_key_exists($wire, $out)) {
                continue;
            }
            $out[$wire] = self::convert($value, $spec[$wire], $forQuery);
        }

        foreach ($required as $wire) {
            if (!array_key_exists($wire, $out)) {
                throw new InvalidArgumentException("OpenSMS: `{$wire}` is required.");
            }
        }

        return $out;
    }

    private static function convert(mixed $value, string $kind, bool $forQuery): mixed
    {
        if ($value instanceof DateTimeInterface) {
            return self::rfc3339($value);
        }
        if ($kind === self::OBJECT && is_array($value)) {
            // An empty PHP array would encode as `[]`; the API wants an object.
            return (object) $value;
        }
        if ($forQuery && is_array($value)) {
            return implode(',', array_map('strval', $value));
        }

        return $value;
    }

    /** RFC 3339 in UTC, with milliseconds only when present. */
    public static function rfc3339(DateTimeInterface $value): string
    {
        $utc = DateTimeImmutable::createFromInterface($value)->setTimezone(new DateTimeZone('UTC'));
        $format = $utc->format('u') === '000000' ? 'Y-m-d\TH:i:s\Z' : 'Y-m-d\TH:i:s.v\Z';

        return $utc->format($format);
    }

    /**
     * Build "?a=1&b=2" (or "") from wire-named params. Null values are
     * skipped, booleans become "true"/"false", lists are joined with commas.
     * Values are percent-encoded (RFC 3986) so `+` becomes `%2B`; commas in
     * joined lists are kept literal.
     *
     * @param array<string, mixed> $params
     */
    public static function queryString(array $params): string
    {
        $parts = [];
        foreach ($params as $key => $value) {
            if ($value === null) {
                continue;
            }
            if (is_bool($value)) {
                $value = $value ? 'true' : 'false';
            } elseif (is_array($value)) {
                $value = implode(',', array_map('strval', $value));
            }
            $encoded = str_replace('%2C', ',', rawurlencode((string) $value));
            $parts[] = rawurlencode((string) $key) . '=' . $encoded;
        }

        return $parts === [] ? '' : '?' . implode('&', $parts);
    }

    /**
     * Validate and percent-encode a path parameter.
     */
    public static function pathParam(string|int $value, string $name = 'id'): string
    {
        $value = (string) $value;
        if (trim($value) === '') {
            throw new InvalidArgumentException("OpenSMS: `{$name}` must be a non-empty string.");
        }

        return rawurlencode($value);
    }

    /**
     * Read the per-call idempotency key option (`idempotencyKey` or
     * `idempotency_key`). Other option keys are rejected.
     *
     * @param array<string, mixed> $options
     */
    public static function idempotencyKey(array $options): ?string
    {
        foreach (array_keys($options) as $k) {
            if ($k !== 'idempotencyKey' && $k !== 'idempotency_key') {
                throw new InvalidArgumentException("OpenSMS: unknown option `{$k}` (allowed: idempotencyKey).");
            }
        }
        $key = $options['idempotencyKey'] ?? $options['idempotency_key'] ?? null;

        return $key === null ? null : (string) $key;
    }

    /** Decode a cursor page envelope `{items, next_cursor}`. */
    public static function page(mixed $response): Page
    {
        $response = is_array($response) ? $response : [];
        $items = $response['items'] ?? [];
        $next = $response['next_cursor'] ?? null;

        return new Page(is_array($items) ? array_values($items) : [], is_string($next) && $next !== '' ? $next : null);
    }

    /**
     * Unwrap a `{data: [...]}` envelope (wallet).
     *
     * @return list<mixed>
     */
    public static function data(mixed $response): array
    {
        $data = is_array($response) ? ($response['data'] ?? []) : [];

        return is_array($data) ? array_values($data) : [];
    }

    /**
     * A bare JSON array response.
     *
     * @return list<mixed>
     */
    public static function list(mixed $response): array
    {
        return is_array($response) ? array_values($response) : [];
    }

    /**
     * A JSON object response.
     *
     * @return array<string, mixed>
     */
    public static function object(mixed $response): array
    {
        return is_array($response) ? $response : [];
    }

    private static function camel(string $snake): string
    {
        return lcfirst(str_replace(' ', '', ucwords(str_replace('_', ' ', $snake))));
    }
}
