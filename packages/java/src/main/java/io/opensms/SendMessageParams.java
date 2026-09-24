package io.opensms;

import java.time.Instant;
import java.time.OffsetDateTime;
import java.util.Map;

/** Body of {@code messages.send}. {@code to} and {@code text} are required. */
public final class SendMessageParams {

    private final String to;
    private final String text;
    private String senderId;
    private String trafficType;
    private String scheduledAt;
    private String callbackUrl;
    private Map<String, Object> metadata;

    /**
     * @param to   destination in E.164, for example {@code +254700000012}.
     * @param text message body, 1 to 1600 characters.
     */
    public SendMessageParams(String to, String text) {
        this.to = to;
        this.text = text;
    }

    /** @param senderId approved sender ID (sandbox always uses OPENSMS). @return this. */
    public SendMessageParams senderId(String senderId) { this.senderId = senderId; return this; }

    /** @param trafficType {@code otp}, {@code transactional} (default) or {@code marketing}. @return this. */
    public SendMessageParams trafficType(String trafficType) { this.trafficType = trafficType; return this; }

    /** @param scheduledAt RFC 3339 send time. @return this. */
    public SendMessageParams scheduledAt(String scheduledAt) { this.scheduledAt = scheduledAt; return this; }

    /** @param scheduledAt send time, sent as RFC 3339 UTC. @return this. */
    public SendMessageParams scheduledAt(Instant scheduledAt) { this.scheduledAt = Wire.rfc3339(scheduledAt); return this; }

    /** @param scheduledAt send time, sent as RFC 3339 UTC. @return this. */
    public SendMessageParams scheduledAt(OffsetDateTime scheduledAt) { this.scheduledAt = Wire.rfc3339(scheduledAt); return this; }

    /** @param callbackUrl per-message status callback URL. @return this. */
    public SendMessageParams callbackUrl(String callbackUrl) { this.callbackUrl = callbackUrl; return this; }

    /** @param metadata free-form JSON object stored with the message. @return this. */
    public SendMessageParams metadata(Map<String, Object> metadata) { this.metadata = metadata; return this; }

    Map<String, Object> toWire() {
        Map<String, Object> m = Wire.map();
        m.put("to", Wire.require(to, "to"));
        m.put("text", Wire.require(text, "text"));
        Wire.put(m, "sender_id", senderId);
        Wire.put(m, "traffic_type", trafficType);
        Wire.put(m, "scheduled_at", scheduledAt);
        Wire.put(m, "callback_url", callbackUrl);
        Wire.put(m, "metadata", metadata);
        return m;
    }
}
