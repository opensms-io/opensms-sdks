package io.opensms;

import io.opensms.models.Page;
import io.opensms.models.StatusResult;
import io.opensms.models.WebhookDelivery;
import io.opensms.models.WebhookEndpoint;
import io.opensms.models.WebhookEvent;

import java.util.Map;

/**
 * Manage webhook endpoints and deliveries, and verify incoming signatures.
 * Accessed as {@code client.webhooks()}. Signature helpers are also available
 * without a client on {@link WebhookSignature}.
 */
public final class Webhooks {

    private final ApiTransport t;

    Webhooks(ApiTransport t) {
        this.t = t;
    }

    /** @return the first page of endpoints. */
    public Page<WebhookEndpoint> list() {
        return list(new ListParams());
    }

    /**
     * @param params paging.
     * @return one page.
     */
    public Page<WebhookEndpoint> list(ListParams params) {
        return t.get("/v1/webhooks", params.toQuery(), ApiTransport.pageOf(WebhookEndpoint.class));
    }

    /**
     * Create an endpoint. The response carries the signing {@code secret} once.
     *
     * @param params url and events.
     * @return the endpoint, including {@code secret}.
     */
    public WebhookEndpoint create(WebhookParams params) {
        return create(params, null);
    }

    /**
     * @param params  url and events.
     * @param options per-call options.
     * @return the endpoint, including {@code secret}.
     */
    public WebhookEndpoint create(WebhookParams params, RequestOptions options) {
        return t.json("POST", "/v1/webhooks", params.toWire(), ApiTransport.idempotencyKey(options),
                ApiTransport.type(WebhookEndpoint.class));
    }

    /**
     * @param id endpoint id.
     * @return the endpoint (no secret).
     */
    public WebhookEndpoint get(String id) {
        return t.get("/v1/webhooks/" + Wire.id(id, "id"), null, ApiTransport.type(WebhookEndpoint.class));
    }

    /**
     * Replace an endpoint ({@code PUT}): {@code url}, {@code events} and {@code enabled} are all required.
     *
     * @param id     endpoint id.
     * @param params the full replacement.
     * @return the updated endpoint.
     */
    public WebhookEndpoint update(String id, WebhookParams params) {
        return update(id, params, null);
    }

    /**
     * @param id      endpoint id.
     * @param params  the full replacement.
     * @param options per-call options.
     * @return the updated endpoint.
     */
    public WebhookEndpoint update(String id, WebhookParams params, RequestOptions options) {
        if (params.enabled() == null) {
            throw new IllegalArgumentException("enabled is required for update (full replacement)");
        }
        return t.json("PUT", "/v1/webhooks/" + Wire.id(id, "id"), params.toWire(),
                ApiTransport.idempotencyKey(options), ApiTransport.type(WebhookEndpoint.class));
    }

    /** @param id endpoint id. */
    public void delete(String id) {
        delete(id, null);
    }

    /**
     * @param id      endpoint id.
     * @param options per-call options.
     */
    public void delete(String id, RequestOptions options) {
        t.json("DELETE", "/v1/webhooks/" + Wire.id(id, "id"), null, ApiTransport.idempotencyKey(options),
                ApiTransport.VOID);
    }

    /**
     * Queue a {@code webhook.test} delivery.
     *
     * @param id endpoint id.
     * @return {@code {status}}.
     */
    public StatusResult test(String id) {
        return test(id, null);
    }

    /**
     * @param id      endpoint id.
     * @param options per-call options.
     * @return {@code {status}}.
     */
    public StatusResult test(String id, RequestOptions options) {
        return t.json("POST", "/v1/webhooks/" + Wire.id(id, "id") + "/test", null,
                ApiTransport.idempotencyKey(options), ApiTransport.type(StatusResult.class));
    }

    /**
     * @param id endpoint id.
     * @return the first page of deliveries.
     */
    public Page<WebhookDelivery> listDeliveries(String id) {
        return listDeliveries(id, new ListParams());
    }

    /**
     * @param id     endpoint id.
     * @param params paging.
     * @return one page.
     */
    public Page<WebhookDelivery> listDeliveries(String id, ListParams params) {
        return t.get("/v1/webhooks/" + Wire.id(id, "id") + "/deliveries", params.toQuery(),
                ApiTransport.pageOf(WebhookDelivery.class));
    }

    /**
     * Replay a delivery.
     *
     * @param id         endpoint id.
     * @param deliveryId delivery id.
     * @param generation the delivery's current {@code generation}.
     * @param reason     5 to 1000 characters, recorded for audit.
     * @return {@code {status}}.
     */
    public StatusResult replayDelivery(String id, long deliveryId, long generation, String reason) {
        return replayDelivery(id, deliveryId, generation, reason, null);
    }

    /**
     * @param id         endpoint id.
     * @param deliveryId delivery id.
     * @param generation the delivery's current {@code generation}.
     * @param reason     5 to 1000 characters.
     * @param options    per-call options.
     * @return {@code {status}}.
     */
    public StatusResult replayDelivery(String id, long deliveryId, long generation, String reason,
                                       RequestOptions options) {
        Map<String, Object> body = Wire.map();
        body.put("generation", generation);
        body.put("reason", Wire.require(reason, "reason"));
        return t.json("POST", "/v1/webhooks/" + Wire.id(id, "id") + "/deliveries/" + deliveryId + "/replay",
                body, ApiTransport.idempotencyKey(options), ApiTransport.type(StatusResult.class));
    }

    /**
     * Verify an {@code X-OpenSMS-Signature} header with the default 300 s tolerance.
     *
     * @param payload raw request body bytes.
     * @param header  the header value.
     * @param secret  endpoint secret ({@code whsec_...}), used verbatim.
     * @return whether the signature is valid and fresh.
     */
    public boolean verifySignature(byte[] payload, String header, String secret) {
        return WebhookSignature.verify(payload, header, secret);
    }

    /**
     * @param payload raw request body as a string (UTF-8).
     * @param header  the header value.
     * @param secret  endpoint secret.
     * @return whether the signature is valid and fresh.
     */
    public boolean verifySignature(String payload, String header, String secret) {
        return WebhookSignature.verify(payload, header, secret);
    }

    /**
     * Verify and parse a delivery.
     *
     * @param payload raw request body bytes.
     * @param header  the header value.
     * @param secret  endpoint secret.
     * @return the parsed event.
     * @throws OpensmsException status 0 with code {@code invalid_signature} or {@code expired_signature}.
     */
    public WebhookEvent constructEvent(byte[] payload, String header, String secret) {
        return WebhookSignature.constructEvent(payload, header, secret);
    }

    /**
     * @param payload raw request body as a string (UTF-8).
     * @param header  the header value.
     * @param secret  endpoint secret.
     * @return the parsed event.
     */
    public WebhookEvent constructEvent(String payload, String header, String secret) {
        return WebhookSignature.constructEvent(payload, header, secret);
    }
}
