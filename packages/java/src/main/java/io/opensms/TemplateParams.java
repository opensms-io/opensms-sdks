package io.opensms;

import java.util.Map;

/** Body of {@code templates.create} ({@code name} and {@code body} required) and {@code templates.update}. */
public final class TemplateParams {

    private String name;
    private String body;
    private String trafficType;

    /** Empty parameters (for updates). */
    public TemplateParams() {
    }

    /** @param name unique template name. @return this. */
    public TemplateParams name(String name) { this.name = name; return this; }

    /** @param body text with {@code {{variable}}} placeholders. @return this. */
    public TemplateParams body(String body) { this.body = body; return this; }

    /** @param trafficType traffic type. @return this. */
    public TemplateParams trafficType(String trafficType) { this.trafficType = trafficType; return this; }

    String name() { return name; }

    String body() { return body; }

    Map<String, Object> toWire() {
        Map<String, Object> m = Wire.map();
        Wire.put(m, "name", name);
        Wire.put(m, "body", body);
        Wire.put(m, "traffic_type", trafficType);
        return m;
    }
}
