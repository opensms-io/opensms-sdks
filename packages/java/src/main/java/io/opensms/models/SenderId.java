package io.opensms.models;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;

/** A registered sender ID. Fields the API omits decode as null. */
public final class SenderId {
    public String id;
    public String value;
    /** alphanumeric or numeric. */
    public String kind;
    public List<String> countries;
    public String useCase;
    public String sampleMessage;
    public String status;
    public String rejectionReason;
    public Boolean restricted;
    public String restrictionReason;
    public OffsetDateTime createdAt;
    /** Per-country registrations (get and create). */
    public List<Map<String, Object>> registrations;
}
