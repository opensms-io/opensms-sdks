package io.opensms;

import java.time.Instant;
import java.time.LocalDate;

/** Query for the analytics methods. Use either {@code range} or {@code from}/{@code to}. */
public final class AnalyticsParams {

    private String currency;
    private String range;
    private String from;
    private String to;
    private String bucket;

    /** Empty parameters (last 30 days, workspace currency). */
    public AnalyticsParams() {
    }

    /** @param currency 3-letter currency. @return this. */
    public AnalyticsParams currency(String currency) { this.currency = currency; return this; }

    /** @param range {@code Nd} with N 1..366, for example {@code 7d}. @return this. */
    public AnalyticsParams range(String range) { this.range = range; return this; }

    /** @param from RFC 3339 or {@code YYYY-MM-DD}. @return this. */
    public AnalyticsParams from(String from) { this.from = from; return this; }

    /** @param from start instant, sent as RFC 3339 UTC. @return this. */
    public AnalyticsParams from(Instant from) { this.from = Wire.rfc3339(from); return this; }

    /** @param from start day. @return this. */
    public AnalyticsParams from(LocalDate from) { this.from = from == null ? null : from.toString(); return this; }

    /** @param to RFC 3339 or {@code YYYY-MM-DD}. @return this. */
    public AnalyticsParams to(String to) { this.to = to; return this; }

    /** @param to end instant, sent as RFC 3339 UTC. @return this. */
    public AnalyticsParams to(Instant to) { this.to = Wire.rfc3339(to); return this; }

    /** @param to end day. @return this. */
    public AnalyticsParams to(LocalDate to) { this.to = to == null ? null : to.toString(); return this; }

    /** @param bucket {@code day} or {@code hour}. @return this. */
    public AnalyticsParams bucket(String bucket) { this.bucket = bucket; return this; }

    Query toQuery() {
        return Query.of().add("currency", currency).add("range", range).add("from", from)
                .add("to", to).add("bucket", bucket);
    }
}
