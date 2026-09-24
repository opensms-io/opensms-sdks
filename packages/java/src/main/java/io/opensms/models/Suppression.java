package io.opensms.models;

import java.time.OffsetDateTime;

/** A suppressed destination. Fields the API omits decode as null. */
public final class Suppression {
    public Long id;
    public String e164;
    /** stop_keyword, manual, complaint or invalid_number. */
    public String reason;
    public OffsetDateTime createdAt;
}
