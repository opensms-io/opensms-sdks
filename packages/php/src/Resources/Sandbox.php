<?php

declare(strict_types=1);

namespace Opensms\Resources;

use Opensms\Models;
use Opensms\Page;
use Opensms\Transport;

/**
 * The `sandbox` resource: the rendered text of sandbox sends (including OTP codes).
 * Accessed as `$client->sandbox`.
 */
final class Sandbox
{
    /** @internal */
    public function __construct(private readonly Transport $transport)
    {
    }

    /**
     * @param array<string, mixed> $params `limit`, `cursor`
     */
    public function listMessages(array $params = []): Page
    {
        return Models::page($this->transport->request('GET', '/v1/sandbox/messages', Models::map($params, Models::PAGE_QUERY, [], true)));
    }
}
