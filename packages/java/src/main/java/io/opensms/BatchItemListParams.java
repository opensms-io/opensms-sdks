package io.opensms;

/** Parameters for {@code batches.listItems}. */
public final class BatchItemListParams extends CursorParams<BatchItemListParams> {

    private String status;

    /** Empty parameters. */
    public BatchItemListParams() {
    }

    /** @param status only items in this message status. @return this. */
    public BatchItemListParams status(String status) { this.status = status; return this; }

    @Override
    Query toQuery() {
        return super.toQuery().add("status", status);
    }
}
