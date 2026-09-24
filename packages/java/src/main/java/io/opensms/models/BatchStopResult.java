package io.opensms.models;

/** Result of stopping a batch. Fields the API omits decode as null. */
public final class BatchStopResult {
    public String id;
    /** Always stopped. */
    public String status;
    /** Items cancelled. */
    public Integer cancelled;
}
