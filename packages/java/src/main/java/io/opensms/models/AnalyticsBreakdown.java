package io.opensms.models;

/** Metrics for one country, carrier or sender ID. Fields the API omits decode as null. */
public final class AnalyticsBreakdown extends AnalyticsMetrics {
    public String key;
    public String name;
}
