package io.opensms.models;

import java.time.OffsetDateTime;

/** A virtual phone number (the API's Number object). Fields the API omits decode as null. */
public final class VirtualNumber {
    public String id;
    public String country;
    public String number;
    /** long_code, short_code or toll_free. */
    public String kind;
    /** Decimal string. */
    public String monthlyFee;
    public String feeCurrency;
    /** available, assigned or releasing. */
    public String status;
    public Boolean inbound;
    public Boolean outbound;
    public OffsetDateTime assignedAt;
    public OffsetDateTime renewsAt;
}
