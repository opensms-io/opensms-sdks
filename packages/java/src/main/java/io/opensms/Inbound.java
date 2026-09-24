package io.opensms;

import io.opensms.models.InboundMessage;
import io.opensms.models.Message;
import io.opensms.models.Page;

import java.util.Map;

/** Messages received on your numbers. Accessed as {@code client.inbound()}. */
public final class Inbound {

    private final ApiTransport t;

    Inbound(ApiTransport t) {
        this.t = t;
    }

    /** @return the first page of inbound messages. */
    public Page<InboundMessage> list() {
        return list(new ListParams());
    }

    /**
     * @param params paging.
     * @return one page.
     */
    public Page<InboundMessage> list(ListParams params) {
        return t.get("/v1/inbound", params.toQuery(), ApiTransport.pageOf(InboundMessage.class));
    }

    /**
     * Reply to an inbound message (live keys only).
     *
     * @param id   inbound message id.
     * @param text reply text.
     * @return the outbound message.
     */
    public Message reply(String id, String text) {
        return reply(id, text, null);
    }

    /**
     * @param id      inbound message id.
     * @param text    reply text.
     * @param options per-call options.
     * @return the outbound message.
     */
    public Message reply(String id, String text, RequestOptions options) {
        Map<String, Object> body = Wire.map();
        body.put("text", Wire.require(text, "text"));
        return t.json("POST", "/v1/inbound/" + Wire.id(id, "id") + "/reply", body,
                ApiTransport.idempotencyKey(options), ApiTransport.type(Message.class));
    }
}
