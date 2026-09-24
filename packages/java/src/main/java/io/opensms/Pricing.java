package io.opensms;

import io.opensms.models.PriceList;

/** Your effective prices. Accessed as {@code client.pricing()}. */
public final class Pricing {

    private final ApiTransport t;

    Pricing(ApiTransport t) {
        this.t = t;
    }

    /** @return the SMS price list for every country. */
    public PriceList get() {
        return get(null, null);
    }

    /**
     * @param product {@code sms} (default), {@code lookup} or {@code number_monthly}, or {@code null}.
     * @param country ISO2 country, or {@code null} for all.
     * @return the price list.
     */
    public PriceList get(String product, String country) {
        return t.get("/v1/pricing", Query.of().add("product", product).add("country", country),
                ApiTransport.type(PriceList.class));
    }
}
