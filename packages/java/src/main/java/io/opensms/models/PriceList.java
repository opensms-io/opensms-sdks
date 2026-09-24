package io.opensms.models;

import java.time.OffsetDateTime;
import java.util.List;

/** The workspace's price list. Fields the API omits decode as null. */
public final class PriceList {
    public String workspaceId;
    public String currency;
    public String product;
    public List<Entry> entries;

    /** One price row. */
    public static final class Entry {
        public String countryIso2;
        public String countryName;
        public String carrierId;
        public String carrierName;
        public String product;
        public Long minMonthlyVolume;
        public String markupType;
        public String markupValue;
        public String sellCurrency;
        public String sellAmount;
        public String convertedAmount;
        public String convertedCurrency;
        public Boolean workspaceOverride;
        public OffsetDateTime effectiveFrom;
        public String fxRate;
    }
}
