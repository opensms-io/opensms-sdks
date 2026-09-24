package io.opensms.models;

import java.util.List;

/** Registration fee quote. Fields the API omits decode as null. */
public final class SenderIdQuote {
    /** Pass to senderIds.create when a fee applies. */
    public String quoteId;
    public List<Entry> entries;
    public List<Total> totals;

    /** One country and provider fee. */
    public static final class Entry {
        public String country;
        public String provider;
        /** Decimal string. */
        public String feeAmount;
        public String feeCurrency;
    }

    /** Total per currency. */
    public static final class Total {
        public String currency;
        /** Decimal string. */
        public String amount;
    }
}
