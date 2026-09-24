package io.opensms;

/**
 * Base for cursor-paginated list parameters ({@code limit} and {@code cursor}).
 * {@link OpensmsClient#paginate} copies the parameters and feeds
 * {@code next_cursor} back as {@code cursor}; your instance is never modified.
 *
 * @param <SELF> the concrete parameter type, for fluent chaining.
 */
public abstract class CursorParams<SELF extends CursorParams<SELF>> implements Cloneable {

    Integer limit;
    String cursor;

    /**
     * @param limit page size (messages 1..100, other lists 1..200).
     * @return this.
     */
    public SELF limit(Integer limit) {
        this.limit = limit;
        return self();
    }

    /**
     * @param cursor {@code nextCursor} from the previous page.
     * @return this.
     */
    public SELF cursor(String cursor) {
        this.cursor = cursor;
        return self();
    }

    /** @return the page size, or {@code null} for the server default. */
    public Integer getLimit() {
        return limit;
    }

    /** @return the cursor, or {@code null} for the first page. */
    public String getCursor() {
        return cursor;
    }

    @SuppressWarnings("unchecked")
    private SELF self() {
        return (SELF) this;
    }

    /** A shallow copy, used by the pagination helper. */
    @SuppressWarnings("unchecked")
    SELF copy() {
        try {
            return (SELF) super.clone();
        } catch (CloneNotSupportedException e) {
            throw new IllegalStateException(e);
        }
    }

    /** The query with {@code limit} and {@code cursor}; subclasses add their filters. */
    Query toQuery() {
        return Query.of().add("limit", limit).add("cursor", cursor);
    }
}
