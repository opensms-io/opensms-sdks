package io.opensms;

import java.time.Instant;
import java.time.LocalDate;
import java.time.OffsetDateTime;

/** Filters for {@code messages.list}. Each filter is optional. */
public final class MessageListParams extends CursorParams<MessageListParams> {

    private String status;
    private String to;
    private String country;
    private String dateFrom;
    private String dateTo;

    /** Empty parameters. */
    public MessageListParams() {
    }

    /** @param status message status, for example {@code delivered}. @return this. */
    public MessageListParams status(String status) { this.status = status; return this; }

    /** @param to digits or {@code +digits} fragment of the destination. @return this. */
    public MessageListParams to(String to) { this.to = to; return this; }

    /** @param country uppercase ISO 3166-1 alpha-2. @return this. */
    public MessageListParams country(String country) { this.country = country; return this; }

    /** @param dateFrom {@code YYYY-MM-DD} or RFC 3339. @return this. */
    public MessageListParams dateFrom(String dateFrom) { this.dateFrom = dateFrom; return this; }

    /** @param dateFrom a calendar day. @return this. */
    public MessageListParams dateFrom(LocalDate dateFrom) { this.dateFrom = dateFrom == null ? null : dateFrom.toString(); return this; }

    /** @param dateFrom an instant, sent as RFC 3339 UTC. @return this. */
    public MessageListParams dateFrom(Instant dateFrom) { this.dateFrom = Wire.rfc3339(dateFrom); return this; }

    /** @param dateFrom a timestamp, sent as RFC 3339 UTC. @return this. */
    public MessageListParams dateFrom(OffsetDateTime dateFrom) { this.dateFrom = Wire.rfc3339(dateFrom); return this; }

    /** @param dateTo {@code YYYY-MM-DD} (inclusive) or RFC 3339. @return this. */
    public MessageListParams dateTo(String dateTo) { this.dateTo = dateTo; return this; }

    /** @param dateTo a calendar day (inclusive). @return this. */
    public MessageListParams dateTo(LocalDate dateTo) { this.dateTo = dateTo == null ? null : dateTo.toString(); return this; }

    /** @param dateTo an instant, sent as RFC 3339 UTC. @return this. */
    public MessageListParams dateTo(Instant dateTo) { this.dateTo = Wire.rfc3339(dateTo); return this; }

    /** @param dateTo a timestamp, sent as RFC 3339 UTC. @return this. */
    public MessageListParams dateTo(OffsetDateTime dateTo) { this.dateTo = Wire.rfc3339(dateTo); return this; }

    @Override
    Query toQuery() {
        return super.toQuery().add("status", status).add("to", to).add("country", country)
                .add("date_from", dateFrom).add("date_to", dateTo);
    }
}
