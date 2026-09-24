package io.opensms.models;

/** An amount and currency. Fields the API omits decode as null. */
public final class Money {
    /** Decimal string. */
    public String amount;
    public String currency;
}
