<?php

declare(strict_types=1);

namespace Opensms\Resources;

use Opensms\Models;
use Opensms\Page;
use Opensms\Transport;

/**
 * The `contactGroups` resource: named groups of contacts, and sending to them. Fields: `name`, `contact_ids`.
 * Accessed as `$client->contactGroups`.
 */
final class ContactGroups
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

        return Models::page($this->transport->request('GET', '/v1/contact-groups', $query));
    }

    /**
     * @param array<string, mixed> $params
     * @param array{idempotencyKey?: string} $options
     * @return array<string, mixed>
     */
    public function create(array $params, array $options = []): array
    {
        $body = Models::map($params, Models::CONTACT_GROUP, ['name']);

        return Models::object($this->transport->request('POST', '/v1/contact-groups', [], $body, [
            'idempotent' => true,
            'idempotencyKey' => Models::idempotencyKey($options),
        ]));
    }

    /**
     * @return array<string, mixed>
     */
    public function get(string $id): array
    {
        return Models::object($this->transport->request('GET', '/v1/contact-groups/' . Models::pathParam($id)));
    }

    /**
     * Partial update (PATCH): only the given fields change.
     *
     * @param array<string, mixed> $params
     * @return array<string, mixed>
     */
    public function update(string $id, array $params): array
    {
        $body = Models::map($params, Models::CONTACT_GROUP);

        return Models::object($this->transport->request('PATCH', '/v1/contact-groups/' . Models::pathParam($id), [], $body));
    }

    public function delete(string $id): void
    {
        $this->transport->request('DELETE', '/v1/contact-groups/' . Models::pathParam($id));
    }

    /**
     * Send to every contact in the group. Params: `text` or `template_id`
     * (one of them), `variables` (map), `sender_id`, `traffic_type`,
     * `callback_url`. Returns a Batch that is already running.
     *
     * @param array<string, mixed> $params
     * @param array{idempotencyKey?: string} $options
     * @return array<string, mixed>
     */
    public function send(string $id, array $params, array $options = []): array
    {
        $body = Models::map($params, Models::GROUP_SEND);

        return Models::object($this->transport->request('POST', '/v1/contact-groups/' . Models::pathParam($id) . '/send', [], $body, [
            'idempotent' => true,
            'idempotencyKey' => Models::idempotencyKey($options),
        ]));
    }
}
