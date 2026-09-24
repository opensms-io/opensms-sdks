package io.opensms.models;

import java.time.OffsetDateTime;

/** A number lookup. Fields the API omits decode as null. */
public final class Lookup {
    public String id;
    /** queued, submitting, unknown, completed or failed. */
    public String state;
    public String country;
    /** Carrier name, or null. */
    public String carrier;
    public Boolean ported;
    public Boolean valid;
    /** prefix, hlr or mock. */
    public String source;
    /** Decimal string. */
    public String price;
    public String currency;
    public OffsetDateTime checkedAt;
}
