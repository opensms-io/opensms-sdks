package io.opensms.models;

/** An inbound routing rule on a number. Fields the API omits decode as null. */
public final class NumberRule {
    public String id;
    /** keyword, prefix, regex or any. */
    public String match;
    public String pattern;
    /** webhook, auto_reply or forward_email. */
    public String action;
    public String target;
    public Integer position;
}
