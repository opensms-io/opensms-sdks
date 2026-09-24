package io.opensms.models;

import java.time.OffsetDateTime;

/** A message received on one of your numbers. Fields the API omits decode as null. */
public final class InboundMessage {
    public String id;
    public String from;
    public String to;
    public String text;
    public OffsetDateTime receivedAt;
    public String virtualNumberId;
}
