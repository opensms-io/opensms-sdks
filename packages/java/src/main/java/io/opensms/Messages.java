package io.opensms;

import io.opensms.models.Message;
import io.opensms.models.MessageAttempt;
import io.opensms.models.Page;

import java.util.List;

/** Send and inspect SMS messages. Accessed as {@code client.messages()}. */
public final class Messages {

    private final ApiTransport t;

    Messages(ApiTransport t) {
        this.t = t;
    }

    /**
     * Send one SMS ({@code POST /v1/messages}). An {@code Idempotency-Key} is
     * generated when you do not pass one, and reused on retries.
     *
     * @param params the message.
     * @return the accepted message.
     */
    public Message send(SendMessageParams params) {
        return send(params, null);
    }

    /**
     * Send one SMS with per-call options.
     *
     * @param params  the message.
     * @param options for example an explicit idempotency key.
     * @return the accepted message.
     */
    public Message send(SendMessageParams params, RequestOptions options) {
        return t.json("POST", "/v1/messages", params.toWire(), ApiTransport.idempotencyKey(options),
                ApiTransport.type(Message.class));
    }

    /** @return the first page of messages, newest first. */
    public Page<Message> list() {
        return list(new MessageListParams());
    }

    /**
     * List messages ({@code GET /v1/messages}).
     *
     * @param params filters and paging.
     * @return one page.
     */
    public Page<Message> list(MessageListParams params) {
        return t.get("/v1/messages", params.toQuery(), ApiTransport.pageOf(Message.class));
    }

    /**
     * @param id message id.
     * @return the message.
     */
    public Message get(String id) {
        return t.get("/v1/messages/" + Wire.id(id, "id"), null, ApiTransport.type(Message.class));
    }

    /**
     * @param id message id.
     * @return delivery attempts, oldest first.
     */
    public List<MessageAttempt> attempts(String id) {
        return t.get("/v1/messages/" + Wire.id(id, "id") + "/attempts", null,
                ApiTransport.listOf(MessageAttempt.class));
    }

    /**
     * Cancel a queued or scheduled message. Never retried automatically.
     *
     * @param id message id.
     * @return the cancelled message.
     */
    public Message cancel(String id) {
        return t.json("POST", "/v1/messages/" + Wire.id(id, "id") + "/cancel", null, null,
                ApiTransport.type(Message.class));
    }
}
