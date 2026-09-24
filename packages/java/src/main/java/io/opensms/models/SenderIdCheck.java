package io.opensms.models;

/** Availability check for a sender ID value. Fields the API omits decode as null. */
public final class SenderIdCheck {
    public Boolean valid;
    public Boolean available;
    public Boolean reserved;
    public String reason;
}
