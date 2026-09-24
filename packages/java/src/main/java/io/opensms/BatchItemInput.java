package io.opensms;

import java.util.Map;

/** One row of {@code batches.create}. {@code to} and {@code text} are required. */
public final class BatchItemInput {

    private final String to;
    private final String text;
    private String senderId;
    private String trafficType;
    private String callbackUrl;
    private Map<String, Object> metadata;

    /**
     * @param to   destination in E.164 (invalid rows are counted, not rejected).
     * @param text message body.
     */
    public BatchItemInput(String to, String text) {
        this.to = to;
        this.text = text;
    }

    /** @param senderId sender ID. @return this. */
    public BatchItemInput senderId(String senderId) { this.senderId = senderId; return this; }

    /** @param trafficType traffic type. @return this. */
    public BatchItemInput trafficType(String trafficType) { this.trafficType = trafficType; return this; }

    /** @param callbackUrl status callback URL. @return this. */
    public BatchItemInput callbackUrl(String callbackUrl) { this.callbackUrl = callbackUrl; return this; }

    /** @param metadata free-form JSON object. @return this. */
    public BatchItemInput metadata(Map<String, Object> metadata) { this.metadata = metadata; return this; }

    Map<String, Object> toWire() {
        Map<String, Object> m = Wire.map();
        m.put("to", Wire.require(to, "to"));
        m.put("text", Wire.require(text, "text"));
        Wire.put(m, "sender_id", senderId);
        Wire.put(m, "traffic_type", trafficType);
        Wire.put(m, "callback_url", callbackUrl);
        Wire.put(m, "metadata", metadata);
        return m;
    }
}
