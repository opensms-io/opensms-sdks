package io.opensms;

import io.opensms.models.Contact;
import io.opensms.models.Page;

/** Manage contacts. Accessed as {@code client.contacts()}. */
public final class Contacts {

    private final ApiTransport t;

    Contacts(ApiTransport t) {
        this.t = t;
    }

    /** @return the first page of contacts. */
    public Page<Contact> list() {
        return list(new ListParams());
    }

    /**
     * @param params paging.
     * @return one page.
     */
    public Page<Contact> list(ListParams params) {
        return t.get("/v1/contacts", params.toQuery(), ApiTransport.pageOf(Contact.class));
    }

    /**
     * @param params {@code e164} required.
     * @return the created contact.
     */
    public Contact create(ContactParams params) {
        return create(params, null);
    }

    /**
     * @param params  {@code e164} required.
     * @param options per-call options.
     * @return the created contact.
     */
    public Contact create(ContactParams params, RequestOptions options) {
        Wire.require(params.e164(), "e164");
        return t.json("POST", "/v1/contacts", params.toWire(), ApiTransport.idempotencyKey(options),
                ApiTransport.type(Contact.class));
    }

    /**
     * @param id contact id.
     * @return the contact.
     */
    public Contact get(String id) {
        return t.get("/v1/contacts/" + Wire.id(id, "id"), null, ApiTransport.type(Contact.class));
    }

    /**
     * Partial update; fields you do not set are kept.
     *
     * @param id     contact id.
     * @param params fields to change.
     * @return the updated contact.
     */
    public Contact update(String id, ContactParams params) {
        return t.json("PATCH", "/v1/contacts/" + Wire.id(id, "id"), params.toWire(), null,
                ApiTransport.type(Contact.class));
    }

    /** @param id contact id. */
    public void delete(String id) {
        t.json("DELETE", "/v1/contacts/" + Wire.id(id, "id"), null, null, ApiTransport.VOID);
    }
}
