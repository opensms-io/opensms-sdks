package io.opensms.models;

import java.util.List;

/** A content rule. Fields the API omits decode as null. */
public final class ContentRule {
    public Long id;
    /** Null applies to every country. */
    public String countryIso2;
    /** blocked_keyword or regex. */
    public String kind;
    public String pattern;
    /** reject or hold_for_review. */
    public String action;
    public List<String> trafficTypes;
    public Boolean enabled;
}
