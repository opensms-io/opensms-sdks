package io.opensms.models;

import java.util.List;
import java.util.Map;

/** Per-row validation of a batch. Fields the API omits decode as null. */
public final class BatchValidationReport {
    public List<Row> rows;
    public Integer total;
    public Integer valid;
    public Integer invalid;
    public Integer duplicates;
    public Integer suppressed;

    /** One validated input row. */
    public static final class Row {
        /** Row number as reported by the API. */
        public Integer row;
        /** The input as parsed. */
        public Item item;
        public Boolean valid;
        public Boolean duplicate;
        public Boolean suppressed;
        /** Why the row is invalid. */
        public String error;
    }

    /** A parsed batch input row. */
    public static final class Item {
        public String to;
        public String text;
        public String senderId;
        public String trafficType;
        public String callbackUrl;
        public Map<String, Object> metadata;
    }
}
