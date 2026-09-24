package io.opensms.models;

import java.time.OffsetDateTime;
import java.util.List;

/** A saved sender ID application draft. Fields the API omits decode as null. */
public final class SenderIdDraft {
    public String id;
    /** onboarding or application. */
    public String source;
    public String value;
    public String kind;
    public List<String> countries;
    public String useCase;
    public String sampleMessage;
    public List<String> documents;
    /** Optimistic lock; pass the current value to updateDraft. */
    public Integer version;
    /** active or submitted. */
    public String status;
    public String submittedSenderId;
    public OffsetDateTime createdAt;
    public OffsetDateTime updatedAt;
}
