package io.opensms;

import io.opensms.models.Page;
import io.opensms.models.Suppression;
import io.opensms.models.SuppressionImportResult;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/** The do-not-send list. Accessed as {@code client.suppressions()}. */
public final class Suppressions {

    private final ApiTransport t;

    Suppressions(ApiTransport t) {
        this.t = t;
    }

    /** @return the first page of suppressions. */
    public Page<Suppression> list() {
        return list(new ListParams());
    }

    /**
     * @param params paging.
     * @return one page.
     */
    public Page<Suppression> list(ListParams params) {
        return t.get("/v1/compliance/suppressions", params.toQuery(), ApiTransport.pageOf(Suppression.class));
    }

    /**
     * Suppress one number. Not retried automatically.
     *
     * @param e164   phone number.
     * @param reason {@code stop_keyword}, {@code manual}, {@code complaint} or {@code invalid_number}.
     * @return the suppression.
     */
    public Suppression create(String e164, String reason) {
        return t.json("POST", "/v1/compliance/suppressions", new SuppressionInput(e164, reason).toWire(), null,
                ApiTransport.type(Suppression.class));
    }

    /**
     * Bulk import ({@code import} in the canonical surface, a reserved word in Java).
     * Not retried automatically.
     *
     * @param items numbers and reasons.
     * @return {@code {created, received}}.
     */
    public SuppressionImportResult importItems(List<SuppressionInput> items) {
        if (items == null || items.isEmpty()) {
            throw new IllegalArgumentException("items is required");
        }
        List<Map<String, Object>> wire = new ArrayList<>();
        for (SuppressionInput i : items) wire.add(i.toWire());
        Map<String, Object> body = Wire.map();
        body.put("items", wire);
        return t.json("POST", "/v1/compliance/suppressions/import", body, null,
                ApiTransport.type(SuppressionImportResult.class));
    }

    /** @param id suppression id. */
    public void delete(long id) {
        t.json("DELETE", "/v1/compliance/suppressions/" + id, null, null, ApiTransport.VOID);
    }
}
