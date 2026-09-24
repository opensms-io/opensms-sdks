package io.opensms;

import io.opensms.models.Carrier;
import io.opensms.models.Country;
import io.opensms.models.CountryRules;
import io.opensms.models.Route;

import java.util.List;

/** The public country catalog. Accessed as {@code client.countries()}. */
public final class Countries {

    private final ApiTransport t;

    Countries(ApiTransport t) {
        this.t = t;
    }

    /** @return every supported country. */
    public List<Country> list() {
        return t.get("/v1/countries", null, ApiTransport.listOf(Country.class));
    }

    /**
     * @param iso2 ISO2 country.
     * @return carriers in that country.
     */
    public List<Carrier> carriers(String iso2) {
        return t.get("/v1/countries/" + Wire.id(iso2, "iso2") + "/carriers", null, ApiTransport.listOf(Carrier.class));
    }

    /**
     * @param iso2 ISO2 country.
     * @return routable providers in that country.
     */
    public List<Route> routes(String iso2) {
        return t.get("/v1/countries/" + Wire.id(iso2, "iso2") + "/routes", null, ApiTransport.listOf(Route.class));
    }

    /**
     * @param iso2 ISO2 country.
     * @return that country's compliance rules.
     */
    public CountryRules compliance(String iso2) {
        return t.get("/v1/countries/" + Wire.id(iso2, "iso2") + "/compliance", null, ApiTransport.type(CountryRules.class));
    }
}
