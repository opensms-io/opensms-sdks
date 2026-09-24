package io.opensms;

import java.util.Map;

/** Body of {@code numbers.createRule} and {@code numbers.updateRule}. */
public final class NumberRuleParams {

    private final String match;
    private final String action;
    private final String target;
    private String pattern;
    private Integer position;

    /**
     * @param match  {@code keyword}, {@code prefix}, {@code regex} or {@code any}.
     * @param action {@code webhook}, {@code auto_reply} or {@code forward_email}.
     * @param target webhook URL, reply text or email address (1..2048 chars).
     */
    public NumberRuleParams(String match, String action, String target) {
        this.match = match;
        this.action = action;
        this.target = target;
    }

    /** @param pattern required unless match is {@code any}. @return this. */
    public NumberRuleParams pattern(String pattern) { this.pattern = pattern; return this; }

    /** @param position evaluation order 0..10000 (default 0). @return this. */
    public NumberRuleParams position(Integer position) { this.position = position; return this; }

    Map<String, Object> toWire() {
        Map<String, Object> m = Wire.map();
        m.put("match", Wire.require(match, "match"));
        Wire.put(m, "pattern", pattern);
        m.put("action", Wire.require(action, "action"));
        m.put("target", Wire.require(target, "target"));
        Wire.put(m, "position", position);
        return m;
    }
}
