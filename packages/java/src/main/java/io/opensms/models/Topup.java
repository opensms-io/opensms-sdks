package io.opensms.models;

/** An initialised wallet top-up payment. Fields the API omits decode as null. */
public final class Topup {
    public String id;
    public String reference;
    /** Send the payer here. */
    public String authorizationUrl;
    public String accessCode;
    public String amount;
    public String currency;
    public String status;
}
