package io.opensms;

import java.util.Map;

/** Body of {@code contactGroups.send}: set either {@code text} or {@code templateId}. */
public final class GroupSendParams {

    private String text;
    private String templateId;
    private Map<String, String> variables;
    private String senderId;
    private String trafficType;
    private String callbackUrl;

    /** Empty parameters. */
    public GroupSendParams() {
    }

    /** @param text message body. @return this. */
    public GroupSendParams text(String text) { this.text = text; return this; }

    /** @param templateId template to render instead of text. @return this. */
    public GroupSendParams templateId(String templateId) { this.templateId = templateId; return this; }

    /** @param variables template variables. @return this. */
    public GroupSendParams variables(Map<String, String> variables) { this.variables = variables; return this; }

    /** @param senderId sender ID. @return this. */
    public GroupSendParams senderId(String senderId) { this.senderId = senderId; return this; }

    /** @param trafficType traffic type. @return this. */
    public GroupSendParams trafficType(String trafficType) { this.trafficType = trafficType; return this; }

    /** @param callbackUrl status callback URL. @return this. */
    public GroupSendParams callbackUrl(String callbackUrl) { this.callbackUrl = callbackUrl; return this; }

    Map<String, Object> toWire() {
        Map<String, Object> m = Wire.map();
        Wire.put(m, "text", text);
        Wire.put(m, "template_id", templateId);
        Wire.put(m, "variables", variables);
        Wire.put(m, "sender_id", senderId);
        Wire.put(m, "traffic_type", trafficType);
        Wire.put(m, "callback_url", callbackUrl);
        return m;
    }
}
