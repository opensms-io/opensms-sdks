package io.opensms;

import io.opensms.models.Page;

import java.util.Collections;
import java.util.Iterator;
import java.util.NoSuchElementException;
import java.util.function.Function;

/**
 * Lazy iterable over every item of a cursor-paginated list. Each page is
 * fetched only when the previous one is exhausted; {@code next_cursor} is fed
 * back as {@code cursor} until it is {@code null}. Not part of the public API;
 * use {@link OpensmsClient#paginate}.
 */
final class Paginator<P extends CursorParams<P>, T> implements Iterable<T> {

    private final Function<P, Page<T>> list;
    private final P params;

    Paginator(Function<P, Page<T>> list, P params) {
        if (list == null || params == null) {
            throw new IllegalArgumentException("list and params are required");
        }
        this.list = list;
        this.params = params;
    }

    @Override
    public Iterator<T> iterator() {
        return new Iterator<>() {
            private P next = params.copy();
            private Iterator<T> current = Collections.emptyIterator();
            private boolean done = false;

            @Override
            public boolean hasNext() {
                while (!current.hasNext()) {
                    if (done) {
                        return false;
                    }
                    Page<T> page = list.apply(next);
                    current = page.items == null ? Collections.emptyIterator() : page.items.iterator();
                    if (page.nextCursor == null || page.nextCursor.isEmpty()) {
                        done = true;
                    } else {
                        next = next.copy().cursor(page.nextCursor);
                    }
                }
                return true;
            }

            @Override
            public T next() {
                if (!hasNext()) {
                    throw new NoSuchElementException();
                }
                return current.next();
            }
        };
    }
}
