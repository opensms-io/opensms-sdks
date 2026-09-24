<?php

declare(strict_types=1);

namespace Opensms;

use ArrayIterator;
use Countable;
use Generator;
use IteratorAggregate;
use Traversable;

/**
 * One page of a cursor-paginated list: `items` plus `nextCursor` (null on the
 * last page). Pass `nextCursor` back as the `cursor` param to get the next
 * page, or use {@see Client::paginate()} to walk every page lazily.
 *
 * @implements IteratorAggregate<int, array<string, mixed>>
 */
final class Page implements IteratorAggregate, Countable
{
    /**
     * @param list<array<string, mixed>> $items
     */
    public function __construct(
        public readonly array $items,
        public readonly ?string $nextCursor,
    ) {
    }

    public function hasMore(): bool
    {
        return $this->nextCursor !== null;
    }

    public function count(): int
    {
        return count($this->items);
    }

    /** @return Traversable<int, array<string, mixed>> */
    public function getIterator(): Traversable
    {
        return new ArrayIterator($this->items);
    }

    /**
     * Call a list method repeatedly, feeding `nextCursor` back as `cursor`
     * (with the same other params) until it is null, yielding items lazily.
     *
     * @param callable(array<string, mixed>): Page $list
     * @param array<string, mixed> $params
     * @return Generator<int, array<string, mixed>>
     */
    public static function iterate(callable $list, array $params = []): Generator
    {
        while (true) {
            $page = $list($params);
            foreach ($page->items as $item) {
                yield $item;
            }
            if ($page->nextCursor === null) {
                return;
            }
            unset($params['cursor']);
            $params['cursor'] = $page->nextCursor;
        }
    }
}
