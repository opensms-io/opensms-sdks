<?php

declare(strict_types=1);

namespace Opensms;

use Generator;
use InvalidArgumentException;
use Opensms\Resources\Analytics;
use Opensms\Resources\Batches;
use Opensms\Resources\Compliance;
use Opensms\Resources\ContactGroups;
use Opensms\Resources\Contacts;
use Opensms\Resources\Countries;
use Opensms\Resources\Inbound;
use Opensms\Resources\Lookups;
use Opensms\Resources\Messages;
use Opensms\Resources\Numbers;
use Opensms\Resources\Otp;
use Opensms\Resources\Pricing;
use Opensms\Resources\Sandbox;
use Opensms\Resources\SenderIds;
use Opensms\Resources\Suppressions;
use Opensms\Resources\Templates;
use Opensms\Resources\Wallet;
use Opensms\Resources\Webhooks;

/**
 * OpenSMS API client. Wires the transport to the resource groups.
 *
 * @example
 * ```php
 * $opensms = new \Opensms\Client(getenv('OPENSMS_API_KEY'));
 * $message = $opensms->messages->send(['to' => '+254700000012', 'text' => 'Hello']);
 * ```
 */
final class Client
{
    public const VERSION = Transport::VERSION;

    /** "sandbox" for sk_test_ keys, "live" for sk_live_ keys. */
    public readonly string $environment;

    public readonly Messages $messages;
    public readonly Batches $batches;
    public readonly Otp $otp;
    public readonly Lookups $lookups;
    public readonly Contacts $contacts;
    public readonly ContactGroups $contactGroups;
    public readonly Templates $templates;
    public readonly Webhooks $webhooks;
    public readonly Inbound $inbound;
    public readonly Numbers $numbers;
    public readonly SenderIds $senderIds;
    public readonly Suppressions $suppressions;
    public readonly Compliance $compliance;
    public readonly Wallet $wallet;
    public readonly Pricing $pricing;
    public readonly Analytics $analytics;
    public readonly Sandbox $sandbox;
    public readonly Countries $countries;

    private readonly Transport $transport;

    /**
     * @param string $apiKey `sk_test_...` or `sk_live_...` (more than 12 characters after the prefix).
     * @param array{
     *     baseUrl?: string,
     *     timeout?: float|int,
     *     maxRetries?: int,
     *     handler?: callable,
     *     sleep?: callable
     * } $options baseUrl (default https://opensms.io), timeout in seconds
     *     per attempt (default 30), maxRetries after the first attempt
     *     (default 2), handler (replaces the cURL handler, see
     *     {@see CurlHandler}), sleep (callable(float $seconds), for tests).
     * @throws InvalidArgumentException on a malformed key or unknown option
     */
    public function __construct(string $apiKey, array $options = [])
    {
        $this->environment = self::environmentOf($apiKey);

        $known = ['baseUrl', 'timeout', 'maxRetries', 'handler', 'sleep'];
        foreach (array_keys($options) as $k) {
            if (!in_array($k, $known, true)) {
                throw new InvalidArgumentException("OpenSMS: unknown client option `{$k}`.");
            }
        }

        $this->transport = new Transport($apiKey, $options);

        $this->messages = new Messages($this->transport);
        $this->batches = new Batches($this->transport);
        $this->otp = new Otp($this->transport);
        $this->lookups = new Lookups($this->transport);
        $this->contacts = new Contacts($this->transport);
        $this->contactGroups = new ContactGroups($this->transport);
        $this->templates = new Templates($this->transport);
        $this->webhooks = new Webhooks($this->transport);
        $this->inbound = new Inbound($this->transport);
        $this->numbers = new Numbers($this->transport);
        $this->senderIds = new SenderIds($this->transport);
        $this->suppressions = new Suppressions($this->transport);
        $this->compliance = new Compliance($this->transport);
        $this->wallet = new Wallet($this->transport);
        $this->pricing = new Pricing($this->transport);
        $this->analytics = new Analytics($this->transport);
        $this->sandbox = new Sandbox($this->transport);
        $this->countries = new Countries($this->transport);
    }

    /**
     * Walk every page of a cursor list lazily.
     *
     * ```php
     * foreach ($client->paginate([$client->messages, 'list'], ['limit' => 50]) as $m) { ... }
     * foreach ($client->paginate(fn ($p) => $client->batches->listItems($id, $p)) as $item) { ... }
     * ```
     *
     * @param callable(array<string, mixed>): Page $list
     * @param array<string, mixed> $params
     * @return Generator<int, array<string, mixed>>
     */
    public function paginate(callable $list, array $params = []): Generator
    {
        return Page::iterate($list, $params);
    }

    /** The configured base URL (no trailing slash). */
    public function baseUrl(): string
    {
        return $this->transport->baseUrl();
    }

    private static function environmentOf(string $apiKey): string
    {
        foreach (['sk_test_' => 'sandbox', 'sk_live_' => 'live'] as $prefix => $env) {
            if (str_starts_with($apiKey, $prefix) && strlen($apiKey) - strlen($prefix) > 12) {
                return $env;
            }
        }

        throw new InvalidArgumentException(
            'OpenSMS: `apiKey` must start with sk_test_ or sk_live_ and have more than 12 characters after the prefix.',
        );
    }
}
