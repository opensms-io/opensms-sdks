package io.opensms;

import io.opensms.models.ContentRule;
import io.opensms.models.CountryRules;

import java.util.List;

/** Country compliance rules and content rules. Accessed as {@code client.compliance()}. */
public final class Compliance {

    private final ApiTransport t;

    Compliance(ApiTransport t) {
        this.t = t;
    }

    /** @return rules for every country. */
    public List<CountryRules> listCountries() {
        return t.get("/v1/compliance/countries", null, ApiTransport.listOf(CountryRules.class));
    }

    /**
     * @param iso2 ISO2 country.
     * @return that country's rules.
     */
    public CountryRules getCountry(String iso2) {
        return t.get("/v1/compliance/countries/" + Wire.id(iso2, "iso2"), null, ApiTransport.type(CountryRules.class));
    }

    /** @return every content rule. */
    public List<ContentRule> listContentRules() {
        return t.get("/v1/content-rules", null, ApiTransport.listOf(ContentRule.class));
    }
}
