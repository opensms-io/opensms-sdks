package io.opensms;

import java.util.List;
import java.util.Map;

/**
 * Body of {@code webhooks.create} ({@code url} and {@code events} required) and
 * {@code webhooks.update} (a full replacement: {@code url}, {@code events} and
 * {@code enabled} all required).
 */
public final class WebhookParams {

    private final String url;
    private final List<String> events;
    private Boolean enabled;

    /**
     * @param url    HTTPS URL without credentials or fragment.
     * @param events non-empty list of event names, for example {@code message.delivered}.
     */
    public WebhookParams(String url, List<String> events) {
        this.url = url;
        this.events = events;
    }

    /** @param enabled whether deliveries are sent. @return this. */
    public WebhookParams enabled(Boolean enabled) { this.enabled = enabled; return this; }

    Boolean enabled() { return enabled; }

    Map<String, Object> toWire() {
        Map<String, Object> m = Wire.map();
        m.put("url", Wire.require(url, "url"));
        if (events == null || events.isEmpty()) {
            throw new IllegalArgumentException("events is required");
        }
        m.put("events", events);
        Wire.put(m, "enabled", enabled);
        return m;
    }
}
