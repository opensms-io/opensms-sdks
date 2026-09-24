<?php

declare(strict_types=1);

namespace Opensms\Resources;

use Opensms\Models;
use Opensms\Page;
use Opensms\Transport;

/**
 * The `countries` resource: the public country catalog.
 * Accessed as `$client->countries`.
 */
final class Countries
{
    /** @internal */
    public function __construct(private readonly Transport $transport)
    {
    }

    /**
     * @return list<array<string, mixed>>
     */
    public function list(): array
    {
        return Models::list($this->transport->request('GET', '/v1/countries'));
    }

    /**
     * @return list<array<string, mixed>>
     */
    public function carriers(string $iso2): array
    {
        return Models::list($this->transport->request('GET', '/v1/countries/' . Models::pathParam($iso2, 'iso2') . '/carriers'));
    }

    /**
     * @return list<array<string, mixed>>
     */
    public function routes(string $iso2): array
    {
        return Models::list($this->transport->request('GET', '/v1/countries/' . Models::pathParam($iso2, 'iso2') . '/routes'));
    }

    /**
     * @return array<string, mixed>
     */
    public function compliance(string $iso2): array
    {
        return Models::object($this->transport->request('GET', '/v1/countries/' . Models::pathParam($iso2, 'iso2') . '/compliance'));
    }
}
