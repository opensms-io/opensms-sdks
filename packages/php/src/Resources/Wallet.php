<?php

declare(strict_types=1);

namespace Opensms\Resources;

use Opensms\Models;
use Opensms\Page;
use Opensms\Transport;

/**
 * The `wallet` resource: balances, the ledger, and top-ups (live keys only).
 * Accessed as `$client->wallet`.
 */
final class Wallet
{
    /** @internal */
    public function __construct(private readonly Transport $transport)
    {
    }

    /**
     * Balances, one per currency and environment.
     *
     * @return list<array<string, mixed>>
     */
    public function balances(): array
    {
        return Models::data($this->transport->request('GET', '/v1/wallet'));
    }

    /**
     * Ledger entries, newest first. Not cursor based: pass `before` = the
     * smallest `id` already seen; stop when fewer than `limit` come back.
     *
     * @param array{limit?: int, before?: int} $params
     * @return list<array<string, mixed>>
     */
    public function ledger(array $params = []): array
    {
        $query = Models::map($params, Models::LEDGER_QUERY, [], true);

        return Models::data($this->transport->request('GET', '/v1/wallet/ledger', $query));
    }

    /**
     * Start a top-up. Returns `{id, reference, authorization_url, access_code, amount, currency, status}`.
     *
     * @param array{amount: string, currency: string, channel: string, email: string} $params
     * @param array{idempotencyKey?: string} $options
     * @return array<string, mixed>
     */
    public function createTopup(array $params, array $options = []): array
    {
        $body = Models::map($params, Models::TOPUP, ['amount', 'currency', 'channel']);

        return Models::object($this->transport->request('POST', '/v1/wallet/topups', [], $body, [
            'idempotent' => true,
            'idempotencyKey' => Models::idempotencyKey($options),
        ]));
    }
}
