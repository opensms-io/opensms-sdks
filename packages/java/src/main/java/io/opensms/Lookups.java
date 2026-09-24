package io.opensms;

import io.opensms.models.Lookup;

import java.util.Map;

/** Number lookups (carrier, portability, validity). Accessed as {@code client.lookups()}. */
public final class Lookups {

    private final ApiTransport t;

    Lookups(ApiTransport t) {
        this.t = t;
    }

    /**
     * @param to number in E.164.
     * @return the lookup ({@code completed}, or pending: poll {@link #get}).
     */
    public Lookup create(String to) {
        return create(to, null);
    }

    /**
     * @param to      number in E.164.
     * @param options per-call options.
     * @return the lookup.
     */
    public Lookup create(String to, RequestOptions options) {
        Map<String, Object> body = Wire.map();
        body.put("to", Wire.require(to, "to"));
        return t.json("POST", "/v1/lookup", body, ApiTransport.idempotencyKey(options),
                ApiTransport.type(Lookup.class));
    }

    /**
     * @param id lookup id.
     * @return the lookup.
     */
    public Lookup get(String id) {
        return t.get("/v1/lookup/" + Wire.id(id, "id"), null, ApiTransport.type(Lookup.class));
    }
}
