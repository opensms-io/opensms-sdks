package io.opensms.models;

import java.time.OffsetDateTime;

/** A sender ID supporting document. Fields the API omits decode as null. */
public final class SenderDocument {
    public String id;
    /** certificate, signatory-id or authorization. */
    public String kind;
    public String filename;
    public String contentType;
    public Long size;
    public String scanStatus;
    public String reviewStatus;
    public String reviewReason;
    public OffsetDateTime reviewedAt;
    public Integer version;
    public String supersedesId;
    public Boolean isCurrent;
    public OffsetDateTime createdAt;
}
