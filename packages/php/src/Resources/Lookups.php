<?php

declare(strict_types=1);

namespace Opensms\Resources;

use Opensms\Models;
use Opensms\Page;
use Opensms\Transport;

/**
 * The `lookups` resource: number validity, carrier and porting lookups.
 * Accessed as `$client->lookups`.
 */
final class Lookups
{
    /** @internal */
    public function __construct(private readonly Transport $transport)
    {
    }

    /**
     * Look up a number. Returns the Lookup (`state` completed, or pending).
     *
     * @param array{to: string} $params
     * @param array{idempotencyKey?: string} $options
     * @return array<string, mixed>
     */
    public function create(array $params, array $options = []): array
    {
        $body = Models::map($params, Models::LOOKUP_CREATE, ['to']);

        return Models::object($this->transport->request('POST', '/v1/lookup', [], $body, [
            'idempotent' => true,
            'idempotencyKey' => Models::idempotencyKey($options),
        ]));
    }

    /**
     * @return array<string, mixed>
     */
    public function get(string $id): array
    {
        return Models::object($this->transport->request('GET', '/v1/lookup/' . Models::pathParam($id)));
    }
}
