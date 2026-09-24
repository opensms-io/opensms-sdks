<?php

declare(strict_types=1);

namespace Opensms\Resources;

use Opensms\Models;
use Opensms\Page;
use Opensms\Transport;

/**
 * The `contacts` resource: phone contacts with free-form `attributes`. Fields: `e164`, `name`, `attributes`.
 * Accessed as `$client->contacts`.
 */
final class Contacts
{
    /** @internal */
    public function __construct(private readonly Transport $transport)
    {
    }

    /**
     * Query: `limit` (1..200), `cursor`.
     *
     * @param array<string, mixed> $params
     */
    public function list(array $params = []): Page
    {
        $query = Models::map($params, Models::PAGE_QUERY, [], true);

        return Models::page($this->transport->request('GET', '/v1/contacts', $query));
    }

    /**
     * @param array<string, mixed> $params
     * @param array{idempotencyKey?: string} $options
     * @return array<string, mixed>
     */
    public function create(array $params, array $options = []): array
    {
        $body = Models::map($params, Models::CONTACT, ['e164']);

        return Models::object($this->transport->request('POST', '/v1/contacts', [], $body, [
            'idempotent' => true,
            'idempotencyKey' => Models::idempotencyKey($options),
        ]));
    }

    /**
     * @return array<string, mixed>
     */
    public function get(string $id): array
    {
        return Models::object($this->transport->request('GET', '/v1/contacts/' . Models::pathParam($id)));
    }

    /**
     * Partial update (PATCH): only the given fields change.
     *
     * @param array<string, mixed> $params
     * @return array<string, mixed>
     */
    public function update(string $id, array $params): array
    {
        $body = Models::map($params, Models::CONTACT);

        return Models::object($this->transport->request('PATCH', '/v1/contacts/' . Models::pathParam($id), [], $body));
    }

    public function delete(string $id): void
    {
        $this->transport->request('DELETE', '/v1/contacts/' . Models::pathParam($id));
    }
}
