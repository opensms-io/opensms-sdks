package io.opensms;

import io.opensms.models.Batch;
import io.opensms.models.BatchStopResult;
import io.opensms.models.BatchValidationReport;
import io.opensms.models.Message;
import io.opensms.models.Page;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/** Create, inspect, start and stop message batches. Accessed as {@code client.batches()}. */
public final class Batches {

    private final ApiTransport t;

    Batches(ApiTransport t) {
        this.t = t;
    }

    /**
     * Create a batch in {@code ready} state; nothing is sent until {@link #start}.
     *
     * @param items  the rows (invalid rows are counted in {@code invalid}, not rejected).
     * @param dedupe drop duplicate destinations (server default {@code true}), or {@code null}.
     * @return the batch.
     */
    public Batch create(List<BatchItemInput> items, Boolean dedupe) {
        return create(items, dedupe, null);
    }

    /**
     * @param items   the rows.
     * @return the batch.
     */
    public Batch create(List<BatchItemInput> items) {
        return create(items, null, null);
    }

    /**
     * @param items   the rows.
     * @param dedupe  drop duplicates, or {@code null} for the default.
     * @param options per-call options.
     * @return the batch.
     */
    public Batch create(List<BatchItemInput> items, Boolean dedupe, RequestOptions options) {
        if (items == null || items.isEmpty()) {
            throw new IllegalArgumentException("items is required");
        }
        List<Map<String, Object>> wire = new ArrayList<>();
        for (BatchItemInput i : items) wire.add(i.toWire());
        Map<String, Object> body = Wire.map();
        body.put("items", wire);
        Wire.put(body, "dedupe", dedupe);
        return t.json("POST", "/v1/messages/batch", body, ApiTransport.idempotencyKey(options),
                ApiTransport.type(Batch.class));
    }

    /**
     * Create a batch from CSV text (header row {@code to,text[,sender_id,...]}),
     * posted as {@code text/csv}. The API does not accept a dedupe flag on this
     * entry point; duplicates are always removed.
     *
     * @param csv the CSV document.
     * @return the batch.
     */
    public Batch createFromCsv(String csv) {
        return createFromCsv(csv, null);
    }

    /**
     * @param csv     the CSV document.
     * @param options per-call options.
     * @return the batch.
     */
    public Batch createFromCsv(String csv, RequestOptions options) {
        Wire.require(csv, "csv");
        return t.raw("POST", "/v1/messages/batch", csv.getBytes(StandardCharsets.UTF_8), "text/csv",
                ApiTransport.idempotencyKey(options), ApiTransport.type(Batch.class));
    }

    /**
     * @param id batch id.
     * @return the batch with its counters.
     */
    public Batch get(String id) {
        return t.get("/v1/batches/" + Wire.id(id, "id"), null, ApiTransport.type(Batch.class));
    }

    /**
     * @param id batch id.
     * @return the per-row validation report.
     */
    public BatchValidationReport validation(String id) {
        return t.get("/v1/batches/" + Wire.id(id, "id") + "/validation", null,
                ApiTransport.type(BatchValidationReport.class));
    }

    /**
     * Start sending a {@code ready} batch.
     *
     * @param id batch id.
     * @return the running batch.
     */
    public Batch start(String id) {
        return start(id, null);
    }

    /**
     * @param id      batch id.
     * @param options per-call options.
     * @return the running batch.
     */
    public Batch start(String id, RequestOptions options) {
        return t.json("POST", "/v1/batches/" + Wire.id(id, "id") + "/start", null,
                ApiTransport.idempotencyKey(options), ApiTransport.type(Batch.class));
    }

    /**
     * Stop a batch, cancelling items not yet sent.
     *
     * @param id batch id.
     * @return {@code {id, status: "stopped", cancelled}}.
     */
    public BatchStopResult stop(String id) {
        return stop(id, null);
    }

    /**
     * @param id      batch id.
     * @param options per-call options.
     * @return the stop result.
     */
    public BatchStopResult stop(String id, RequestOptions options) {
        return t.json("POST", "/v1/batches/" + Wire.id(id, "id") + "/stop", null,
                ApiTransport.idempotencyKey(options), ApiTransport.type(BatchStopResult.class));
    }

    /**
     * @param id batch id.
     * @return the first page of items.
     */
    public Page<Message> listItems(String id) {
        return listItems(id, new BatchItemListParams());
    }

    /**
     * List a batch's messages. Items carry fewer fields than a full message.
     *
     * @param id     batch id.
     * @param params status filter and paging.
     * @return one page.
     */
    public Page<Message> listItems(String id, BatchItemListParams params) {
        return t.get("/v1/batches/" + Wire.id(id, "id") + "/items", params.toQuery(),
                ApiTransport.pageOf(Message.class));
    }
}
