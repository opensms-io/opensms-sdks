package io.opensms.models;

import java.util.List;

/** A country in the public catalog. Fields the API omits decode as null. */
public final class Country {
    public String iso2;
    public String name;
    public String dialCode;
    public String currency;
    public String status;
    /** Null when not priced. */
    public Money pricePerMessage;
    public List<String> senderKinds;
    public Integer providersAvailable;
}
