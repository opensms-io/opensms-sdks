package io.opensms;

import java.util.Map;

/** Body of {@code contacts.create} ({@code e164} required) and {@code contacts.update} (all optional). */
public final class ContactParams {

    private String e164;
    private String name;
    private Map<String, Object> attributes;

    /** Empty parameters (for updates). */
    public ContactParams() {
    }

    /** @param e164 phone number in E.164. @return this. */
    public ContactParams e164(String e164) { this.e164 = e164; return this; }

    /** @param name display name. @return this. */
    public ContactParams name(String name) { this.name = name; return this; }

    /** @param attributes free-form JSON object. @return this. */
    public ContactParams attributes(Map<String, Object> attributes) { this.attributes = attributes; return this; }

    String e164() { return e164; }

    Map<String, Object> toWire() {
        Map<String, Object> m = Wire.map();
        Wire.put(m, "e164", e164);
        Wire.put(m, "name", name);
        Wire.put(m, "attributes", attributes);
        return m;
    }
}
