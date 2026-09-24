<?php

declare(strict_types=1);

namespace Opensms\Resources;

use Opensms\Models;
use Opensms\Page;
use Opensms\Transport;

/**
 * The `otp` resource: send and verify one-time passcodes.
 * Accessed as `$client->otp`.
 */
final class Otp
{
    /** @internal */
    public function __construct(private readonly Transport $transport)
    {
    }

    /**
     * Send a code. Params: `to` (required), `sender_id`, `template` (must
     * contain `{{code}}`), `length` (4..10), `ttl_seconds` (30..86400).
     * Returns `{otp_id}`.
     *
     * @param array<string, mixed> $params
     * @param array{idempotencyKey?: string} $options
     * @return array<string, mixed>
     */
    public function send(array $params, array $options = []): array
    {
        $body = Models::map($params, Models::OTP_SEND, ['to']);

        return Models::object($this->transport->request('POST', '/v1/otp/send', [], $body, [
            'idempotent' => true,
            'idempotencyKey' => Models::idempotencyKey($options),
        ]));
    }

    /**
     * Check a code. Returns `{valid, attempts_left}`. A wrong code uses up an
     * attempt, so this call is never retried automatically.
     *
     * @param array{otp_id?: string, otpId?: string, code: string} $params
     * @return array<string, mixed>
     */
    public function verify(array $params): array
    {
        $body = Models::map($params, Models::OTP_VERIFY, ['otp_id', 'code']);

        return Models::object($this->transport->request('POST', '/v1/otp/verify', [], $body, ['retry' => false]));
    }
}
