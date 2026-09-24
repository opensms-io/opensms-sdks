package io.opensms.models;

/** A wallet balance. Fields the API omits decode as null. */
public final class WalletBalance {
    public String id;
    public String currency;
    /** Decimal string. */
    public String balance;
    /** Decimal string. */
    public String reserved;
    public String environment;
}
