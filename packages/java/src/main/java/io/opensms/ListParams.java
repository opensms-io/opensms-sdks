package io.opensms;

/** Plain {@code limit} + {@code cursor} list parameters. */
public final class ListParams extends CursorParams<ListParams> {

    /** Empty parameters (server defaults). */
    public ListParams() {
    }

    /**
     * @param limit page size.
     * @return new parameters with {@code limit} set.
     */
    public static ListParams ofLimit(int limit) {
        return new ListParams().limit(limit);
    }
}
