package io.opensms.models;

import java.util.List;

/** Compliance rules for a country. Fields the API omits decode as null. */
public final class CountryRules {
    public String iso2;
    public String name;
    public String status;
    public String dialCode;
    public List<String> stopKeywords;
    public List<QuietHours> quietHours;
    public List<Rule> contentRules;

    /** A quiet-hours window. */
    public static final class QuietHours {
        public String trafficType;
        public String startLocal;
        public String endLocal;
        public String enforce;
    }

    /** A content rule applying to this country. */
    public static final class Rule {
        public String kind;
        public String pattern;
        public String action;
        public List<String> trafficTypes;
        public Boolean enabled;
    }
}
