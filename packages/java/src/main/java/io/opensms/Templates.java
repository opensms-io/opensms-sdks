package io.opensms;

import io.opensms.models.Page;
import io.opensms.models.Template;

/** Manage message templates. Accessed as {@code client.templates()}. */
public final class Templates {

    private final ApiTransport t;

    Templates(ApiTransport t) {
        this.t = t;
    }

    /** @return the first page of templates. */
    public Page<Template> list() {
        return list(new ListParams());
    }

    /**
     * @param params paging.
     * @return one page.
     */
    public Page<Template> list(ListParams params) {
        return t.get("/v1/templates", params.toQuery(), ApiTransport.pageOf(Template.class));
    }

    /**
     * @param params {@code name} and {@code body} required.
     * @return the created template.
     */
    public Template create(TemplateParams params) {
        return create(params, null);
    }

    /**
     * @param params  {@code name} and {@code body} required.
     * @param options per-call options.
     * @return the created template.
     */
    public Template create(TemplateParams params, RequestOptions options) {
        Wire.require(params.name(), "name");
        Wire.require(params.body(), "body");
        return t.json("POST", "/v1/templates", params.toWire(), ApiTransport.idempotencyKey(options),
                ApiTransport.type(Template.class));
    }

    /**
     * @param id template id.
     * @return the template.
     */
    public Template get(String id) {
        return t.get("/v1/templates/" + Wire.id(id, "id"), null, ApiTransport.type(Template.class));
    }

    /**
     * @param id     template id.
     * @param params fields to change.
     * @return the updated template.
     */
    public Template update(String id, TemplateParams params) {
        return t.json("PATCH", "/v1/templates/" + Wire.id(id, "id"), params.toWire(), null,
                ApiTransport.type(Template.class));
    }

    /** @param id template id. */
    public void delete(String id) {
        t.json("DELETE", "/v1/templates/" + Wire.id(id, "id"), null, null, ApiTransport.VOID);
    }
}
