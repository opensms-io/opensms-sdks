package io.opensms.models;

import java.time.OffsetDateTime;

/** One delivery attempt of a message through a route. Fields the API omits decode as null. */
public final class MessageAttempt {
    public Long id;
    /** 1 for the first attempt. */
    public Integer sequence;
    public String routeId;
    public String routeName;
    /** Decimal string or null. */
    public String price;
    public String currency;
    public String provider;
    public String providerMessageId;
    /** submitting, submission_unknown, submitted, not_accepted, delivered, failed or expired. */
    public String status;
    public String errorCode;
    public OffsetDateTime submittedAt;
    public OffsetDateTime dlrAt;
    public Long submitLatencyMs;
    public Long dlrLatencyMs;
}
