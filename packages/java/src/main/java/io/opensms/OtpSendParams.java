package io.opensms;

import java.util.Map;

/** Body of {@code otp.send}. {@code to} is required. */
public final class OtpSendParams {

    private final String to;
    private String senderId;
    private String template;
    private Integer length;
    private Integer ttlSeconds;

    /** @param to destination in E.164. */
    public OtpSendParams(String to) {
        this.to = to;
    }

    /** @param senderId sender ID. @return this. */
    public OtpSendParams senderId(String senderId) { this.senderId = senderId; return this; }

    /** @param template text containing {@code {{code}}}. @return this. */
    public OtpSendParams template(String template) { this.template = template; return this; }

    /** @param length code length 4..10 (default 6). @return this. */
    public OtpSendParams length(Integer length) { this.length = length; return this; }

    /** @param ttlSeconds validity 30..86400 seconds (default 600). @return this. */
    public OtpSendParams ttlSeconds(Integer ttlSeconds) { this.ttlSeconds = ttlSeconds; return this; }

    Map<String, Object> toWire() {
        Map<String, Object> m = Wire.map();
        m.put("to", Wire.require(to, "to"));
        Wire.put(m, "sender_id", senderId);
        Wire.put(m, "template", template);
        Wire.put(m, "length", length);
        Wire.put(m, "ttl_seconds", ttlSeconds);
        return m;
    }
}
