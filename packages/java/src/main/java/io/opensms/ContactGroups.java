package io.opensms;

import io.opensms.models.Batch;
import io.opensms.models.ContactGroup;
import io.opensms.models.Page;

/** Manage contact groups and send to them. Accessed as {@code client.contactGroups()}. */
public final class ContactGroups {

    private final ApiTransport t;

    ContactGroups(ApiTransport t) {
        this.t = t;
    }

    /** @return the first page of groups. */
    public Page<ContactGroup> list() {
        return list(new ListParams());
    }

    /**
     * @param params paging.
     * @return one page.
     */
    public Page<ContactGroup> list(ListParams params) {
        return t.get("/v1/contact-groups", params.toQuery(), ApiTransport.pageOf(ContactGroup.class));
    }

    /**
     * @param params {@code name} required.
     * @return the created group.
     */
    public ContactGroup create(ContactGroupParams params) {
        return create(params, null);
    }

    /**
     * @param params  {@code name} required.
     * @param options per-call options.
     * @return the created group.
     */
    public ContactGroup create(ContactGroupParams params, RequestOptions options) {
        Wire.require(params.name(), "name");
        return t.json("POST", "/v1/contact-groups", params.toWire(), ApiTransport.idempotencyKey(options),
                ApiTransport.type(ContactGroup.class));
    }

    /**
     * @param id group id.
     * @return the group.
     */
    public ContactGroup get(String id) {
        return t.get("/v1/contact-groups/" + Wire.id(id, "id"), null, ApiTransport.type(ContactGroup.class));
    }

    /**
     * @param id     group id.
     * @param params fields to change.
     * @return the updated group.
     */
    public ContactGroup update(String id, ContactGroupParams params) {
        return t.json("PATCH", "/v1/contact-groups/" + Wire.id(id, "id"), params.toWire(), null,
                ApiTransport.type(ContactGroup.class));
    }

    /** @param id group id. */
    public void delete(String id) {
        t.json("DELETE", "/v1/contact-groups/" + Wire.id(id, "id"), null, null, ApiTransport.VOID);
    }

    /**
     * Send to every contact in the group; returns a batch already {@code running}.
     *
     * @param id     group id.
     * @param params text or template.
     * @return the batch.
     */
    public Batch send(String id, GroupSendParams params) {
        return send(id, params, null);
    }

    /**
     * @param id      group id.
     * @param params  text or template.
     * @param options per-call options.
     * @return the batch.
     */
    public Batch send(String id, GroupSendParams params, RequestOptions options) {
        return t.json("POST", "/v1/contact-groups/" + Wire.id(id, "id") + "/send", params.toWire(),
                ApiTransport.idempotencyKey(options), ApiTransport.type(Batch.class));
    }
}
