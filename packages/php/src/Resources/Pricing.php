<?php

declare(strict_types=1);

namespace Opensms\Resources;

use Opensms\Models;
use Opensms\Page;
use Opensms\Transport;

/**
 * The `pricing` resource: your price list.
 * Accessed as `$client->pricing`.
 */
final class Pricing
{
    /** @internal */
    public function __construct(private readonly Transport $transport)
    {
    }

    /**
     * @param array{product?: string, country?: string} $params product: sms|lookup|number_monthly
     * @return array<string, mixed>
     */
    public function get(array $params = []): array
    {
        return Models::object($this->transport->request('GET', '/v1/pricing', Models::map($params, Models::PRICING_QUERY, [], true)));
    }
}
