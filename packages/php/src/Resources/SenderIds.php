<?php

declare(strict_types=1);

namespace Opensms\Resources;

use Opensms\Models;
use Opensms\Page;
use Opensms\Transport;

/**
 * The `senderIds` resource: sender ID registrations, availability checks, fee quotes, documents and application drafts.
 * Accessed as `$client->senderIds`.
 */
final class SenderIds
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
        return Models::page($this->transport->request('GET', '/v1/sender-ids', Models::map($params, Models::PAGE_QUERY, [], true)));
    }

    /**
     * @return array<string, mixed>
     */
    public function get(string $id): array
    {
        return Models::object($this->transport->request('GET', '/v1/sender-ids/' . Models::pathParam($id)));
    }

    /**
     * Register a sender ID. May charge fees (see {@see quote()}), so it is
     * never retried automatically. Params: `value`, `kind`, `countries`,
     * `documents` (required), `use_case`, `sample_message`, `draft_id`,
     * `draft_version`, `quote_id`.
     *
     * @param array<string, mixed> $params
     * @return array<string, mixed>
     */
    public function create(array $params): array
    {
        $body = Models::map($params, Models::SENDER_ID_CREATE, ['value', 'kind', 'countries', 'documents']);

        return Models::object($this->transport->request('POST', '/v1/sender-ids', [], $body, ['retry' => false]));
    }

    /**
     * Amend a registration: `use_case`, `countries`, `documents`, `sample_message`.
     *
     * @param array<string, mixed> $params
     * @return array<string, mixed>
     */
    public function update(string $id, array $params): array
    {
        $body = Models::map($params, Models::SENDER_ID_UPDATE);

        return Models::object($this->transport->request('PATCH', '/v1/sender-ids/' . Models::pathParam($id), [], $body));
    }

    public function delete(string $id): void
    {
        $this->transport->request('DELETE', '/v1/sender-ids/' . Models::pathParam($id));
    }

    /**
     * Check a value. Returns `{valid, available, reserved, reason}`.
     *
     * @param array{value: string, country?: string} $params
     * @return array<string, mixed>
     */
    public function check(array $params): array
    {
        $query = Models::map($params, Models::SENDER_ID_CHECK_QUERY, ['value'], true);

        return Models::object($this->transport->request('GET', '/v1/sender-ids/check', $query));
    }

    /**
     * Registration fee quote. `countries` is a list, sent as `KE,NG`.
     *
     * @param array{countries: list<string>|string} $params
     * @return array<string, mixed>
     */
    public function quote(array $params): array
    {
        $query = Models::map($params, Models::SENDER_ID_QUOTE_QUERY, ['countries'], true);

        return Models::object($this->transport->request('GET', '/v1/sender-ids/quote', $query));
    }

    /**
     * Uploaded registration documents (upload and download are console only).
     *
     * @return list<array<string, mixed>>
     */
    public function listDocuments(): array
    {
        $response = Models::object($this->transport->request('GET', '/v1/sender-documents'));

        return Models::list($response['items'] ?? []);
    }

    /**
     * @param array<string, mixed> $params `limit`, `cursor`
     */
    public function listDrafts(array $params = []): Page
    {
        return Models::page($this->transport->request('GET', '/v1/sender-id-drafts', Models::map($params, Models::PAGE_QUERY, [], true)));
    }

    /**
     * Params: `source`, `value`, `kind`, `countries`, `use_case`,
     * `sample_message`, `documents`. Not retried automatically.
     *
     * @param array<string, mixed> $params
     * @return array<string, mixed>
     */
    public function createDraft(array $params = []): array
    {
        $body = Models::map($params, Models::SENDER_ID_DRAFT);

        return Models::object($this->transport->request('POST', '/v1/sender-id-drafts', [], $body, ['retry' => false]));
    }

    /**
     * @return array<string, mixed>
     */
    public function getDraft(string $id): array
    {
        return Models::object($this->transport->request('GET', '/v1/sender-id-drafts/' . Models::pathParam($id)));
    }

    /**
     * Update a draft. `version` (the current version) is required; a stale
     * version returns 409.
     *
     * @param array<string, mixed> $params
     * @return array<string, mixed>
     */
    public function updateDraft(string $id, array $params): array
    {
        $body = Models::map($params, Models::SENDER_ID_DRAFT_UPDATE, ['version']);

        return Models::object($this->transport->request('PATCH', '/v1/sender-id-drafts/' . Models::pathParam($id), [], $body));
    }

    public function deleteDraft(string $id): void
    {
        $this->transport->request('DELETE', '/v1/sender-id-drafts/' . Models::pathParam($id));
    }
}
