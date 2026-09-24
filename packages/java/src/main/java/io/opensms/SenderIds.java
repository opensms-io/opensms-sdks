package io.opensms;

import com.fasterxml.jackson.databind.JsonNode;
import io.opensms.models.Page;
import io.opensms.models.SenderDocument;
import io.opensms.models.SenderId;
import io.opensms.models.SenderIdCheck;
import io.opensms.models.SenderIdDraft;
import io.opensms.models.SenderIdQuote;

import java.util.Collections;
import java.util.List;

/** Sender ID registrations, drafts and documents. Accessed as {@code client.senderIds()}. */
public final class SenderIds {

    private final ApiTransport t;

    SenderIds(ApiTransport t) {
        this.t = t;
    }

    /** @return the first page of sender IDs. */
    public Page<SenderId> list() {
        return list(new ListParams());
    }

    /**
     * @param params paging.
     * @return one page.
     */
    public Page<SenderId> list(ListParams params) {
        return t.get("/v1/sender-ids", params.toQuery(), ApiTransport.pageOf(SenderId.class));
    }

    /**
     * @param id sender ID id.
     * @return the sender ID with its registrations.
     */
    public SenderId get(String id) {
        return t.get("/v1/sender-ids/" + Wire.id(id, "id"), null, ApiTransport.type(SenderId.class));
    }

    /**
     * Register a sender ID. May charge a fee, so it is never retried automatically.
     *
     * @param params the registration.
     * @return the sender ID.
     */
    public SenderId create(SenderIdCreateParams params) {
        return t.json("POST", "/v1/sender-ids", params.toWire(), null, ApiTransport.type(SenderId.class));
    }

    /**
     * Amend a registration.
     *
     * @param id     sender ID id.
     * @param params the amendment.
     * @return the sender ID.
     */
    public SenderId update(String id, SenderIdUpdateParams params) {
        return t.json("PATCH", "/v1/sender-ids/" + Wire.id(id, "id"), params.toWire(), null,
                ApiTransport.type(SenderId.class));
    }

    /** @param id sender ID id. */
    public void delete(String id) {
        t.json("DELETE", "/v1/sender-ids/" + Wire.id(id, "id"), null, null, ApiTransport.VOID);
    }

    /**
     * @param value   the sender ID text.
     * @param country ISO2 country, or {@code null}.
     * @return {@code {valid, available, reserved, reason}}.
     */
    public SenderIdCheck check(String value, String country) {
        Wire.require(value, "value");
        return t.get("/v1/sender-ids/check", Query.of().add("value", value).add("country", country),
                ApiTransport.type(SenderIdCheck.class));
    }

    /**
     * @param countries ISO2 markets, sent as {@code countries=KE,NG}.
     * @return the fee quote.
     */
    public SenderIdQuote quote(List<String> countries) {
        if (countries == null || countries.isEmpty()) {
            throw new IllegalArgumentException("countries is required");
        }
        return t.get("/v1/sender-ids/quote", Query.of().add("countries", countries),
                ApiTransport.type(SenderIdQuote.class));
    }

    /** @return uploaded supporting documents (not paginated). */
    public List<SenderDocument> listDocuments() {
        JsonNode root = t.get("/v1/sender-documents", null, ApiTransport.type(JsonNode.class));
        if (root == null || root.get("items") == null || root.get("items").isNull()) {
            return Collections.emptyList();
        }
        return Json.MAPPER.convertValue(root.get("items"), ApiTransport.listOf(SenderDocument.class));
    }

    /** @return the first page of drafts. */
    public Page<SenderIdDraft> listDrafts() {
        return listDrafts(new ListParams());
    }

    /**
     * @param params paging.
     * @return one page.
     */
    public Page<SenderIdDraft> listDrafts(ListParams params) {
        return t.get("/v1/sender-id-drafts", params.toQuery(), ApiTransport.pageOf(SenderIdDraft.class));
    }

    /**
     * Create a draft. Not retried automatically (no idempotency support).
     *
     * @param params draft fields.
     * @return the draft ({@code version} 1).
     */
    public SenderIdDraft createDraft(SenderIdDraftParams params) {
        return t.json("POST", "/v1/sender-id-drafts", params.toWire(), null, ApiTransport.type(SenderIdDraft.class));
    }

    /**
     * @param id draft id.
     * @return the draft.
     */
    public SenderIdDraft getDraft(String id) {
        return t.get("/v1/sender-id-drafts/" + Wire.id(id, "id"), null, ApiTransport.type(SenderIdDraft.class));
    }

    /**
     * @param id     draft id.
     * @param params {@code version} (current) required, plus fields to change.
     * @return the draft with an incremented version.
     */
    public SenderIdDraft updateDraft(String id, SenderIdDraftParams params) {
        Wire.require(params.version(), "version");
        return t.json("PATCH", "/v1/sender-id-drafts/" + Wire.id(id, "id"), params.toWire(), null,
                ApiTransport.type(SenderIdDraft.class));
    }

    /** @param id draft id. */
    public void deleteDraft(String id) {
        t.json("DELETE", "/v1/sender-id-drafts/" + Wire.id(id, "id"), null, null, ApiTransport.VOID);
    }
}
