package io.opensms.models;

/** Delivery metrics shared by every analytics result. Fields the API omits decode as null. */
public class AnalyticsMetrics {
    public Long sent;
    public Long delivered;
    public Long failed;
    public Long parts;
    /** Percentage. */
    public Double deliveryRate;
    /** Decimal string. */
    public String spend;
    public Long p50Ms;
    public Long p95Ms;
}
