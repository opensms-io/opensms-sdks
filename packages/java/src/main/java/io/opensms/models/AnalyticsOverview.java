package io.opensms.models;

import java.time.OffsetDateTime;

/** Aggregate analytics. Fields the API omits decode as null. */
public final class AnalyticsOverview extends AnalyticsMetrics {
    public OffsetDateTime from;
    public OffsetDateTime to;
    public String currency;
    public String environment;
}
