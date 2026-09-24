package io.opensms.models;

import java.time.OffsetDateTime;
import java.util.List;

/** A message template. Fields the API omits decode as null. */
public final class Template {
    public String id;
    public String workspaceId;
    public String name;
    public String body;
    public String trafficType;
    public OffsetDateTime createdAt;
    public OffsetDateTime updatedAt;
    /** Placeholder names parsed from the body. */
    public List<String> variables;
}
