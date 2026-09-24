<?php

declare(strict_types=1);

namespace Opensms\Resources;

use Opensms\Models;
use Opensms\Page;
use Opensms\Transport;

/**
 * The `numbers` resource: virtual numbers and their inbound routing rules. Everything except `list` and `available` needs a live key.
 * Accessed as `$client->numbers`.
 */
final class Numbers
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
        return Models::page($this->transport->request('GET', '/v1/numbers', Models::map($params, Models::PAGE_QUERY, [], true)));
    }

    /**
     * Numbers available to assign.
     *
     * @param array{country: string, kind: string} $params
     * @return list<array<string, mixed>>
     */
    public function available(array $params): array
    {
        $query = Models::map($params, Models::NUMBER_QUERY, [], true);

        return Models::list($this->transport->request('GET', '/v1/numbers/available', $query));
    }

    /**
     * Assign (rent) a number. Charges the wallet.
     *
     * @param array{country: string, kind: string} $params
     * @param array{idempotencyKey?: string} $options
     * @return array<string, mixed>
     */
    public function assign(array $params, array $options = []): array
    {
        $body = Models::map($params, Models::NUMBER_QUERY, ['country', 'kind']);

        return Models::object($this->transport->request('POST', '/v1/numbers', [], $body, [
            'idempotent' => true,
            'idempotencyKey' => Models::idempotencyKey($options),
        ]));
    }

    public function release(string $id): void
    {
        $this->transport->request('DELETE', '/v1/numbers/' . Models::pathParam($id));
    }

    /**
     * @param array<string, mixed> $params `limit`, `cursor`
     */
    public function listRules(string $id, array $params = []): Page
    {
        $query = Models::map($params, Models::PAGE_QUERY, [], true);

        return Models::page($this->transport->request('GET', '/v1/numbers/' . Models::pathParam($id) . '/rules', $query));
    }

    /**
     * Rule: `match` (keyword|prefix|regex|any), `pattern`, `action`
     * (webhook|auto_reply|forward_email), `target`, `position`.
     *
     * @param array<string, mixed> $rule
     * @param array{idempotencyKey?: string} $options
     * @return array<string, mixed>
     */
    public function createRule(string $id, array $rule, array $options = []): array
    {
        $body = Models::map($rule, Models::NUMBER_RULE);

        return Models::object($this->transport->request('POST', '/v1/numbers/' . Models::pathParam($id) . '/rules', [], $body, [
            'idempotent' => true,
            'idempotencyKey' => Models::idempotencyKey($options),
        ]));
    }

    /**
     * Replace a rule (PUT).
     *
     * @param array<string, mixed> $rule
     * @return array<string, mixed>
     */
    public function updateRule(string $id, string|int $ruleId, array $rule): array
    {
        $body = Models::map($rule, Models::NUMBER_RULE);
        $path = '/v1/numbers/' . Models::pathParam($id) . '/rules/' . Models::pathParam($ruleId, 'ruleId');

        return Models::object($this->transport->request('PUT', $path, [], $body));
    }

    public function deleteRule(string $id, string|int $ruleId): void
    {
        $this->transport->request('DELETE', '/v1/numbers/' . Models::pathParam($id) . '/rules/' . Models::pathParam($ruleId, 'ruleId'));
    }
}
