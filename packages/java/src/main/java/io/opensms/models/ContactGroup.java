package io.opensms.models;

import java.time.OffsetDateTime;
import java.util.List;

/** A contact group. Fields the API omits decode as null. */
public final class ContactGroup {
    public String id;
    public String workspaceId;
    public String name;
    public List<String> contactIds;
    public OffsetDateTime createdAt;
}
