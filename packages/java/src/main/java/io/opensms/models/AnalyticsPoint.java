package io.opensms.models;

import java.time.OffsetDateTime;

/** Metrics for one time bucket. Fields the API omits decode as null. */
public final class AnalyticsPoint extends AnalyticsMetrics {
    public OffsetDateTime bucket;
}
