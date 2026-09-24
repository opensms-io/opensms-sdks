<?php

declare(strict_types=1);

namespace Opensms\Resources;

use Opensms\Models;
use Opensms\Page;
use Opensms\Transport;

/**
 * The `messages` resource: send SMS, list and inspect messages, cancel scheduled ones.
 * Accessed as `$client->messages`.
 */
final class Messages
{
    /** @internal */
    public function __construct(private readonly Transport $transport)
    {
    }

    /**
     * Send one SMS. Returns the Message (201).
     *
     * Params: `to` (E.164, required), `text` (required), `sender_id`,
     * `traffic_type` (otp|transactional|marketing), `scheduled_at`
     * (DateTimeInterface or RFC 3339 string), `callback_url`, `metadata`.
     * camelCase aliases (`senderId`, ...) are accepted.
     *
     * @param array<string, mixed> $params
     * @param array{idempotencyKey?: string} $options
     * @return array<string, mixed>
     */
    public function send(array $params, array $options = []): array
    {
        $body = Models::map($params, Models::MESSAGE_SEND, ['to', 'text']);

        return Models::object($this->transport->request('POST', '/v1/messages', [], $body, [
            'idempotent' => true,
            'idempotencyKey' => Models::idempotencyKey($options),
        ]));
    }

    /**
     * List messages, newest first. Query: `limit` (1..100), `cursor`,
     * `status`, `to`, `country`, `date_from`, `date_to`.
     *
     * @param array<string, mixed> $params
     */
    public function list(array $params = []): Page
    {
        $query = Models::map($params, Models::MESSAGE_LIST_QUERY, [], true);

        return Models::page($this->transport->request('GET', '/v1/messages', $query));
    }

    /**
     * Fetch one message.
     *
     * @return array<string, mixed>
     */
    public function get(string $id): array
    {
        return Models::object($this->transport->request('GET', '/v1/messages/' . Models::pathParam($id)));
    }

    /**
     * List provider submission attempts for a message.
     *
     * @return list<array<string, mixed>>
     */
    public function attempts(string $id): array
    {
        return Models::list($this->transport->request('GET', '/v1/messages/' . Models::pathParam($id) . '/attempts'));
    }

    /**
     * Cancel a queued or scheduled message. Not retried automatically.
     *
     * @return array<string, mixed>
     */
    public function cancel(string $id): array
    {
        return Models::object($this->transport->request('POST', '/v1/messages/' . Models::pathParam($id) . '/cancel', [], null, [
            'retry' => false,
        ]));
    }
}
