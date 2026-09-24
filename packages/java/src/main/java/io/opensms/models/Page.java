package io.opensms.models;

import java.util.List;

/**
 * One page of a cursor-paginated list: {@code {items, next_cursor}}. Pass
 * {@link #nextCursor} back as {@code cursor} until it is {@code null}, or use
 * {@code OpensmsClient.paginate}.
 *
 * @param <T> the item type.
 */
public final class Page<T> {
    /** The items on this page. */
    public List<T> items;
    /** Cursor for the next page, {@code null} on the last page. */
    public String nextCursor;
}
