<?php

declare(strict_types=1);

namespace Opensms\Resources;

use Opensms\Models;
use Opensms\Page;
use Opensms\Transport;

/**
 * The `webhooks` resource: endpoints, test events, deliveries and replays, plus signature verification helpers.
 * Accessed as `$client->webhooks`.
 */
final class Webhooks
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
        return Models::page($this->transport->request('GET', '/v1/webhooks', Models::map($params, Models::PAGE_QUERY, [], true)));
    }

    /**
     * Create an endpoint. `url` must be https. The response includes the
     * signing `secret` (`whsec_...`), shown only once.
     *
     * @param array{url: string, events: list<string>, enabled?: bool} $params
     * @param array{idempotencyKey?: string} $options
     * @return array<string, mixed>
     */
    public function create(array $params, array $options = []): array
    {
        $body = Models::map($params, Models::WEBHOOK, ['url', 'events']);

        return Models::object($this->transport->request('POST', '/v1/webhooks', [], $body, [
            'idempotent' => true,
            'idempotencyKey' => Models::idempotencyKey($options),
        ]));
    }

    /**
     * @return array<string, mixed>
     */
    public function get(string $id): array
    {
        return Models::object($this->transport->request('GET', '/v1/webhooks/' . Models::pathParam($id)));
    }

    /**
     * Full replacement (PUT): `url`, `events` and `enabled` are all required.
     *
     * @param array{url: string, events: list<string>, enabled: bool} $params
     * @param array{idempotencyKey?: string} $options
     * @return array<string, mixed>
     */
    public function update(string $id, array $params, array $options = []): array
    {
        $body = Models::map($params, Models::WEBHOOK, ['url', 'events', 'enabled']);

        return Models::object($this->transport->request('PUT', '/v1/webhooks/' . Models::pathParam($id), [], $body, [
            'idempotent' => true,
            'idempotencyKey' => Models::idempotencyKey($options),
        ]));
    }

    /**
     * @param array{idempotencyKey?: string} $options
     */
    public function delete(string $id, array $options = []): void
    {
        $this->transport->request('DELETE', '/v1/webhooks/' . Models::pathParam($id), [], null, [
            'idempotent' => true,
            'idempotencyKey' => Models::idempotencyKey($options),
        ]);
    }

    /**
     * Queue a `webhook.test` delivery. Returns `{status}`.
     *
     * @param array{idempotencyKey?: string} $options
     * @return array<string, mixed>
     */
    public function test(string $id, array $options = []): array
    {
        return Models::object($this->transport->request('POST', '/v1/webhooks/' . Models::pathParam($id) . '/test', [], null, [
            'idempotent' => true,
            'idempotencyKey' => Models::idempotencyKey($options),
        ]));
    }

    /**
     * @param array<string, mixed> $params `limit`, `cursor`
     */
    public function listDeliveries(string $id, array $params = []): Page
    {
        $query = Models::map($params, Models::PAGE_QUERY, [], true);

        return Models::page($this->transport->request('GET', '/v1/webhooks/' . Models::pathParam($id) . '/deliveries', $query));
    }

    /**
     * Re-queue a delivery. `generation` comes from the delivery; `reason`
     * is 5..1000 characters. Returns `{status}`.
     *
     * @param array{generation: int, reason: string} $params
     * @param array{idempotencyKey?: string} $options
     * @return array<string, mixed>
     */
    public function replayDelivery(string $id, string|int $deliveryId, array $params, array $options = []): array
    {
        $body = Models::map($params, Models::WEBHOOK_REPLAY, ['generation', 'reason']);
        $path = '/v1/webhooks/' . Models::pathParam($id) . '/deliveries/' . Models::pathParam($deliveryId, 'deliveryId') . '/replay';

        return Models::object($this->transport->request('POST', $path, [], $body, [
            'idempotent' => true,
            'idempotencyKey' => Models::idempotencyKey($options),
        ]));
    }

    /**
     * Same as {@see \Opensms\Webhook::verifySignature()}.
     *
     * @param array{toleranceSeconds?: int, now?: int} $options
     */
    public function verifySignature(string $payload, string $header, string $secret, array $options = []): bool
    {
        return \Opensms\Webhook::verifySignature($payload, $header, $secret, $options);
    }

    /**
     * Same as {@see \Opensms\Webhook::constructEvent()}.
     *
     * @param array{toleranceSeconds?: int, now?: int} $options
     * @return array<string, mixed>
     */
    public function constructEvent(string $payload, string $header, string $secret, array $options = []): array
    {
        return \Opensms\Webhook::constructEvent($payload, $header, $secret, $options);
    }
}
