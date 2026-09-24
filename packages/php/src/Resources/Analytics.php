<?php

declare(strict_types=1);

namespace Opensms\Resources;

use Opensms\Models;
use Opensms\Page;
use Opensms\Transport;

/**
 * The `analytics` resource: delivery and spend metrics. Query: `currency`, `range` (`30d`) or `from`/`to`, `bucket` (day|hour).
 * Accessed as `$client->analytics`.
 */
final class Analytics
{
    /** @internal */
    public function __construct(private readonly Transport $transport)
    {
    }

    /**
     * @param array<string, mixed> $params
     * @return array<string, mixed>
     */
    public function overview(array $params = []): array
    {
        return Models::object($this->transport->request('GET', '/v1/analytics/overview', $this->query($params)));
    }

    /**
     * @param array<string, mixed> $params
     * @return list<array<string, mixed>>
     */
    public function byCountry(array $params = []): array
    {
        return Models::list($this->transport->request('GET', '/v1/analytics/by-country', $this->query($params)));
    }

    /**
     * @param array<string, mixed> $params
     * @return list<array<string, mixed>>
     */
    public function byCarrier(array $params = []): array
    {
        return Models::list($this->transport->request('GET', '/v1/analytics/by-carrier', $this->query($params)));
    }

    /**
     * @param array<string, mixed> $params
     * @return list<array<string, mixed>>
     */
    public function bySenderId(array $params = []): array
    {
        return Models::list($this->transport->request('GET', '/v1/analytics/by-sender-id', $this->query($params)));
    }

    /**
     * @param array<string, mixed> $params
     * @return list<array<string, mixed>>
     */
    public function timeseries(array $params = []): array
    {
        return Models::list($this->transport->request('GET', '/v1/analytics/timeseries', $this->query($params)));
    }

    /**
     * @param array<string, mixed> $params
     * @return array<string, mixed>
     */
    private function query(array $params): array
    {
        return Models::map($params, Models::ANALYTICS_QUERY, [], true);
    }
}
