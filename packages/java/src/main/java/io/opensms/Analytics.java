package io.opensms;

import io.opensms.models.AnalyticsBreakdown;
import io.opensms.models.AnalyticsOverview;
import io.opensms.models.AnalyticsPoint;

import java.util.List;

/** Delivery and spend analytics. Accessed as {@code client.analytics()}. */
public final class Analytics {

    private final ApiTransport t;

    Analytics(ApiTransport t) {
        this.t = t;
    }

    /** @return totals for the last 30 days. */
    public AnalyticsOverview overview() {
        return overview(new AnalyticsParams());
    }

    /**
     * @param q range, currency and bucket.
     * @return totals.
     */
    public AnalyticsOverview overview(AnalyticsParams q) {
        return t.get("/v1/analytics/overview", q.toQuery(), ApiTransport.type(AnalyticsOverview.class));
    }

    /** @return metrics per country for the last 30 days. */
    public List<AnalyticsBreakdown> byCountry() {
        return byCountry(new AnalyticsParams());
    }

    /**
     * @param q range, currency and bucket.
     * @return metrics per country.
     */
    public List<AnalyticsBreakdown> byCountry(AnalyticsParams q) {
        return t.get("/v1/analytics/by-country", q.toQuery(), ApiTransport.listOf(AnalyticsBreakdown.class));
    }

    /** @return metrics per carrier for the last 30 days. */
    public List<AnalyticsBreakdown> byCarrier() {
        return byCarrier(new AnalyticsParams());
    }

    /**
     * @param q range, currency and bucket.
     * @return metrics per carrier.
     */
    public List<AnalyticsBreakdown> byCarrier(AnalyticsParams q) {
        return t.get("/v1/analytics/by-carrier", q.toQuery(), ApiTransport.listOf(AnalyticsBreakdown.class));
    }

    /** @return metrics per sender ID for the last 30 days. */
    public List<AnalyticsBreakdown> bySenderId() {
        return bySenderId(new AnalyticsParams());
    }

    /**
     * @param q range, currency and bucket.
     * @return metrics per sender ID.
     */
    public List<AnalyticsBreakdown> bySenderId(AnalyticsParams q) {
        return t.get("/v1/analytics/by-sender-id", q.toQuery(), ApiTransport.listOf(AnalyticsBreakdown.class));
    }

    /** @return metrics per day for the last 30 days. */
    public List<AnalyticsPoint> timeseries() {
        return timeseries(new AnalyticsParams());
    }

    /**
     * @param q range, currency and bucket.
     * @return metrics per bucket.
     */
    public List<AnalyticsPoint> timeseries(AnalyticsParams q) {
        return t.get("/v1/analytics/timeseries", q.toQuery(), ApiTransport.listOf(AnalyticsPoint.class));
    }
}
