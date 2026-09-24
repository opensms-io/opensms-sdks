<?php

declare(strict_types=1);

namespace Opensms\Resources;

use Opensms\Models;
use Opensms\Page;
use Opensms\Transport;

/**
 * The `suppressions` resource: numbers that must never be messaged.
 * Accessed as `$client->suppressions`.
 */
final class Suppressions
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
        return Models::page($this->transport->request('GET', '/v1/compliance/suppressions', Models::map($params, Models::PAGE_QUERY, [], true)));
    }

    /**
     * Not retried automatically.
     *
     * @param array{e164: string, reason: string} $params reason: stop_keyword|manual|complaint|invalid_number
     * @return array<string, mixed>
     */
    public function create(array $params): array
    {
        $body = Models::map($params, Models::SUPPRESSION, ['e164', 'reason']);

        return Models::object($this->transport->request('POST', '/v1/compliance/suppressions', [], $body, ['retry' => false]));
    }

    /**
     * Bulk add. Returns `{created, received}`. Not retried automatically.
     *
     * @param list<array{e164: string, reason: string}> $items
     * @return array<string, mixed>
     */
    public function import(array $items): array
    {
        $body = ['items' => array_map(
            static fn (array $item): array => Models::map($item, Models::SUPPRESSION, ['e164', 'reason']),
            array_values($items),
        )];

        return Models::object($this->transport->request('POST', '/v1/compliance/suppressions/import', [], $body, ['retry' => false]));
    }

    public function delete(string|int $id): void
    {
        $this->transport->request('DELETE', '/v1/compliance/suppressions/' . Models::pathParam($id));
    }
}
