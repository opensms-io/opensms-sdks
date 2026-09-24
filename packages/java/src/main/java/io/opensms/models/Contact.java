package io.opensms.models;

import java.time.OffsetDateTime;
import java.util.Map;

/** A contact. Fields the API omits decode as null. */
public final class Contact {
    public String id;
    public String workspaceId;
    public String e164;
    public String name;
    /** Free-form attributes. */
    public Map<String, Object> attributes;
    public OffsetDateTime createdAt;
}
