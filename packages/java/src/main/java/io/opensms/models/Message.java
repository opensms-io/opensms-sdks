package io.opensms.models;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;

/** An SMS message. Also used for batch items, which carry fewer fields. Fields the API omits decode as null. */
public final class Message {
    /** Message id (UUID). */
    public String id;
    /** When the message was accepted. */
    public OffsetDateTime createdAt;
    /** Destination in E.164. */
    public String to;
    /** Sender ID the message left with. */
    public String senderId;
    /** Message body (omitted when empty). */
    public String text;
    /** Number of SMS parts. */
    public Integer parts;
    /** queued, scheduled, held, sending, sent, delivered, failed, cancelled or expired (open set). */
    public String status;
    /** Why the message is in its status, if known. */
    public String statusReason;
    public OffsetDateTime sentAt;
    public OffsetDateTime deliveredAt;
    public OffsetDateTime failedAt;
    public OffsetDateTime cancelledAt;
    public OffsetDateTime scheduledAt;
    /** Decimal string, for example 0.000000. */
    public String price;
    /** ISO 4217 currency of price. */
    public String currency;
    /** otp, transactional or marketing. */
    public String trafficType;
    /** Free-form metadata sent with the message. */
    public Map<String, Object> metadata;
    /** gsm7 or ucs2. */
    public String encoding;
    public String countryId;
    public String countryIso2;
    public String countryName;
    public String carrierId;
    public String carrierName;
    /** prefix, hlr or unknown. */
    public String destinationSource;
    /** Billing lines (present on get and list, absent on send). */
    public List<Map<String, Object>> billing;
}
