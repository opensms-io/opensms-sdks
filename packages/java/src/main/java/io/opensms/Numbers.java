package io.opensms;

import io.opensms.models.NumberRule;
import io.opensms.models.Page;
import io.opensms.models.VirtualNumber;

import java.util.List;
import java.util.Map;

/**
 * Virtual numbers and their inbound rules. Accessed as {@code client.numbers()}.
 * Everything except {@link #list} and {@link #available} needs a live key.
 */
public final class Numbers {

    private final ApiTransport t;

    Numbers(ApiTransport t) {
        this.t = t;
    }

    /** @return the first page of your numbers. */
    public Page<VirtualNumber> list() {
        return list(new ListParams());
    }

    /**
     * @param params paging.
     * @return one page.
     */
    public Page<VirtualNumber> list(ListParams params) {
        return t.get("/v1/numbers", params.toQuery(), ApiTransport.pageOf(VirtualNumber.class));
    }

    /**
     * @param country ISO2 country.
     * @param kind    {@code long_code}, {@code short_code} or {@code toll_free}.
     * @return numbers available to assign.
     */
    public List<VirtualNumber> available(String country, String kind) {
        return t.get("/v1/numbers/available", Query.of().add("country", country).add("kind", kind),
                ApiTransport.listOf(VirtualNumber.class));
    }

    /**
     * Assign a number (charges the wallet).
     *
     * @param country ISO2 country.
     * @param kind    number kind.
     * @return the assigned number.
     */
    public VirtualNumber assign(String country, String kind) {
        return assign(country, kind, null);
    }

    /**
     * @param country ISO2 country.
     * @param kind    number kind.
     * @param options per-call options.
     * @return the assigned number.
     */
    public VirtualNumber assign(String country, String kind, RequestOptions options) {
        Map<String, Object> body = Wire.map();
        body.put("country", Wire.require(country, "country"));
        body.put("kind", Wire.require(kind, "kind"));
        return t.json("POST", "/v1/numbers", body, ApiTransport.idempotencyKey(options),
                ApiTransport.type(VirtualNumber.class));
    }

    /** @param id number id. */
    public void release(String id) {
        t.json("DELETE", "/v1/numbers/" + Wire.id(id, "id"), null, null, ApiTransport.VOID);
    }

    /**
     * @param id number id.
     * @return the first page of rules.
     */
    public Page<NumberRule> listRules(String id) {
        return listRules(id, new ListParams());
    }

    /**
     * @param id     number id.
     * @param params paging.
     * @return one page.
     */
    public Page<NumberRule> listRules(String id, ListParams params) {
        return t.get("/v1/numbers/" + Wire.id(id, "id") + "/rules", params.toQuery(),
                ApiTransport.pageOf(NumberRule.class));
    }

    /**
     * @param id   number id.
     * @param rule the rule.
     * @return the created rule.
     */
    public NumberRule createRule(String id, NumberRuleParams rule) {
        return createRule(id, rule, null);
    }

    /**
     * @param id      number id.
     * @param rule    the rule.
     * @param options per-call options.
     * @return the created rule.
     */
    public NumberRule createRule(String id, NumberRuleParams rule, RequestOptions options) {
        return t.json("POST", "/v1/numbers/" + Wire.id(id, "id") + "/rules", rule.toWire(),
                ApiTransport.idempotencyKey(options), ApiTransport.type(NumberRule.class));
    }

    /**
     * @param id     number id.
     * @param ruleId rule id.
     * @param rule   the replacement rule.
     * @return the updated rule.
     */
    public NumberRule updateRule(String id, String ruleId, NumberRuleParams rule) {
        return t.json("PUT", "/v1/numbers/" + Wire.id(id, "id") + "/rules/" + Wire.id(ruleId, "ruleId"),
                rule.toWire(), null, ApiTransport.type(NumberRule.class));
    }

    /**
     * @param id     number id.
     * @param ruleId rule id.
     */
    public void deleteRule(String id, String ruleId) {
        t.json("DELETE", "/v1/numbers/" + Wire.id(id, "id") + "/rules/" + Wire.id(ruleId, "ruleId"),
                null, null, ApiTransport.VOID);
    }
}
