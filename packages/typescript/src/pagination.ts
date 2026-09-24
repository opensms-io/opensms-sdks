/**
 * Auto-pagination over cursor lists.
 * @module
 */
import type { Page } from './models.js';

/** A list method that accepts a cursor and returns a {@link Page}. */
export type PageFetcher = (params: any, ...rest: any[]) => Promise<Page<unknown>>;

/** The item type of a list method's pages. */
export type PageItem<F extends PageFetcher> = Awaited<ReturnType<F>> extends Page<infer T> ? T : never;

/** The params type of a list method (its first argument). */
export type PageParams<F extends PageFetcher> = NonNullable<Parameters<F>[0]>;

/**
 * Iterate every item of a cursor list lazily, feeding `nextCursor` back as
 * `cursor` until it is `null`. Other params (such as `limit`) are kept on
 * every request.
 *
 * @example
 * ```ts
 * for await (const m of paginate(client.messages.list, { limit: 50 })) console.log(m.id);
 * // Lists that take an id first:
 * for await (const item of paginate((p: ListParams) => client.batches.listItems(batchId, p))) {}
 * ```
 */
export async function* paginate<F extends PageFetcher>(
  fetchPage: F,
  params?: PageParams<F>,
): AsyncGenerator<PageItem<F>, void, undefined> {
  const base = (params ?? {}) as { cursor?: string };
  let cursor: string | undefined = base.cursor;
  const seen = new Set<string>();
  for (;;) {
    const page = (await fetchPage({ ...base, cursor })) as Page<PageItem<F>>;
    for (const item of page.items) yield item;
    if (!page.nextCursor || seen.has(page.nextCursor)) return;
    seen.add(page.nextCursor);
    cursor = page.nextCursor;
  }
}
