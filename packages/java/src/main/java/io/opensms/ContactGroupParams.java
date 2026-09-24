package io.opensms;

import java.util.List;
import java.util.Map;

/** Body of {@code contactGroups.create} ({@code name} required) and {@code contactGroups.update}. */
public final class ContactGroupParams {

    private String name;
    private List<String> contactIds;

    /** Empty parameters (for updates). */
    public ContactGroupParams() {
    }

    /** @param name group name. @return this. */
    public ContactGroupParams name(String name) { this.name = name; return this; }

    /** @param contactIds member contact ids (replaces the membership). @return this. */
    public ContactGroupParams contactIds(List<String> contactIds) { this.contactIds = contactIds; return this; }

    String name() { return name; }

    Map<String, Object> toWire() {
        Map<String, Object> m = Wire.map();
        Wire.put(m, "name", name);
        Wire.put(m, "contact_ids", contactIds);
        return m;
    }
}
