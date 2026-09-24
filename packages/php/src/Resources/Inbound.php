<?php

declare(strict_types=1);

namespace Opensms\Resources;

use Opensms\Models;
use Opensms\Page;
use Opensms\Transport;

/**
 * The `inbound` resource: messages received on your numbers, and replies.
 * Accessed as `$client->inbound`.
 */
final class Inbound
{
    /** @internal */
    public function __construct(private readonly Transport $transport)
    {
    }

    /**
     * @param array<string, mixed> $params `limit`, `cursor`
     */
    public function list(array $params = []): Page
    {
        return Models::page($this->transport->request('GET', '/v1/inbound', Models::map($params, Models::PAGE_QUERY, [], true)));
    }

    /**
     * Reply to an inbound message. Returns the sent Message (live keys only).
     *
     * @param array{text: string} $params
     * @param array{idempotencyKey?: string} $options
     * @return array<string, mixed>
     */
    public function reply(string $id, array $params, array $options = []): array
    {
        $body = Models::map($params, Models::INBOUND_REPLY, ['text']);

        return Models::object($this->transport->request('POST', '/v1/inbound/' . Models::pathParam($id) . '/reply', [], $body, [
            'idempotent' => true,
            'idempotencyKey' => Models::idempotencyKey($options),
        ]));
    }
}
