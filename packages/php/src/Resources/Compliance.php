<?php

declare(strict_types=1);

namespace Opensms\Resources;

use Opensms\Models;
use Opensms\Page;
use Opensms\Transport;

/**
 * The `compliance` resource: per-country rules and content rules.
 * Accessed as `$client->compliance`.
 */
final class Compliance
{
    /** @internal */
    public function __construct(private readonly Transport $transport)
    {
    }

    /**
     * @return list<array<string, mixed>>
     */
    public function listCountries(): array
    {
        return Models::list($this->transport->request('GET', '/v1/compliance/countries'));
    }

    /**
     * @return array<string, mixed>
     */
    public function getCountry(string $iso2): array
    {
        return Models::object($this->transport->request('GET', '/v1/compliance/countries/' . Models::pathParam($iso2, 'iso2')));
    }

    /**
     * @return list<array<string, mixed>>
     */
    public function listContentRules(): array
    {
        return Models::list($this->transport->request('GET', '/v1/content-rules'));
    }
}
