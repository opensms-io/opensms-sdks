<?php

declare(strict_types=1);

namespace Opensms\Resources;

use Opensms\Models;
use Opensms\Page;
use Opensms\Transport;

/**
 * The `batches` resource: bulk sends created in `ready` and started explicitly.
 * Accessed as `$client->batches`.
 */
final class Batches
{
    /** @internal */
    public function __construct(private readonly Transport $transport)
    {
    }

    /**
     * Create a batch from items. Params: `items` (list of
     * `{to, text, sender_id?, traffic_type?, callback_url?, metadata?}`),
     * `dedupe` (bool, default true). Returns the Batch (202, status ready).
     *
     * @param array{items: list<array<string, mixed>>, dedupe?: bool} $params
     * @param array{idempotencyKey?: string} $options
     * @return array<string, mixed>
     */
    public function create(array $params, array $options = []): array
    {
        $body = Models::map($params, ['items' => Models::SCALAR, 'dedupe' => Models::SCALAR], ['items']);
        if (!is_array($body['items'])) {
            throw new \InvalidArgumentException('OpenSMS: `items` must be a list.');
        }
        $body['items'] = array_map(
            static fn (array $item): array => Models::map($item, Models::BATCH_ITEM),
            array_values($body['items']),
        );

        return Models::object($this->transport->request('POST', '/v1/messages/batch', [], $body, [
            'idempotent' => true,
            'idempotencyKey' => Models::idempotencyKey($options),
        ]));
    }

    /**
     * Create a batch from CSV text (header row `to,text[,sender_id,...]`),
     * sent as `text/csv`. The server always dedupes a raw CSV body, so
     * `dedupe: false` switches the upload to multipart/form-data, the only
     * CSV form in which the API honours that flag.
     *
     * @param array{dedupe?: bool} $params
     * @param array{idempotencyKey?: string} $options
     * @return array<string, mixed>
     */
    public function createFromCsv(string $csv, array $params = [], array $options = []): array
    {
        $mapped = Models::map($params, ['dedupe' => Models::SCALAR]);
        $body = $csv;
        $contentType = 'text/csv';
        if (($mapped['dedupe'] ?? true) === false) {
            $boundary = 'opensms' . bin2hex(random_bytes(12));
            $body = "--{$boundary}\r\n"
                . "Content-Disposition: form-data; name=\"dedupe\"\r\n\r\n"
                . "false\r\n"
                . "--{$boundary}\r\n"
                . "Content-Disposition: form-data; name=\"file\"; filename=\"batch.csv\"\r\n"
                . "Content-Type: text/csv\r\n\r\n"
                . $csv . "\r\n"
                . "--{$boundary}--\r\n";
            $contentType = 'multipart/form-data; boundary=' . $boundary;
        }

        return Models::object($this->transport->request('POST', '/v1/messages/batch', [], null, [
            'idempotent' => true,
            'idempotencyKey' => Models::idempotencyKey($options),
            'rawBody' => $body,
            'contentType' => $contentType,
        ]));
    }

    /**
     * @return array<string, mixed>
     */
    public function get(string $id): array
    {
        return Models::object($this->transport->request('GET', '/v1/batches/' . Models::pathParam($id)));
    }

    /**
     * Per-row validation report: `{rows, total, valid, invalid, duplicates, suppressed}`.
     *
     * @return array<string, mixed>
     */
    public function validation(string $id): array
    {
        return Models::object($this->transport->request('GET', '/v1/batches/' . Models::pathParam($id) . '/validation'));
    }

    /**
     * Start sending a ready batch.
     *
     * @param array{idempotencyKey?: string} $options
     * @return array<string, mixed>
     */
    public function start(string $id, array $options = []): array
    {
        return Models::object($this->transport->request('POST', '/v1/batches/' . Models::pathParam($id) . '/start', [], null, [
            'idempotent' => true,
            'idempotencyKey' => Models::idempotencyKey($options),
        ]));
    }

    /**
     * Stop a batch. Returns `{id, status: "stopped", cancelled}`.
     *
     * @param array{idempotencyKey?: string} $options
     * @return array<string, mixed>
     */
    public function stop(string $id, array $options = []): array
    {
        return Models::object($this->transport->request('POST', '/v1/batches/' . Models::pathParam($id) . '/stop', [], null, [
            'idempotent' => true,
            'idempotencyKey' => Models::idempotencyKey($options),
        ]));
    }

    /**
     * List the messages a batch produced. Query: `status`, `limit`, `cursor`.
     *
     * @param array<string, mixed> $params
     */
    public function listItems(string $id, array $params = []): Page
    {
        $query = Models::map($params, Models::BATCH_ITEMS_QUERY, [], true);

        return Models::page($this->transport->request('GET', '/v1/batches/' . Models::pathParam($id) . '/items', $query));
    }
}
