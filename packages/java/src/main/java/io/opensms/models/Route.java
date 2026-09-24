package io.opensms.models;

/** A public routable provider for a country. Fields the API omits decode as null. */
public final class Route {
    public String provider;
    public String carrier;
    public String health;
    public String cost;
    public String currency;
    public Integer priority;
    public Money sellPrice;
    public Long p50Ms;
}
