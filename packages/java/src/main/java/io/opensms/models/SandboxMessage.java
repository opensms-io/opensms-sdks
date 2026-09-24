package io.opensms.models;

import java.time.OffsetDateTime;

/** A message captured by the sandbox, with its rendered text. Fields the API omits decode as null. */
public final class SandboxMessage {
    public String id;
    public String to;
    public String senderId;
    public String text;
    public Integer parts;
    public String status;
    public String trafficType;
    public OffsetDateTime createdAt;
    public OffsetDateTime sentAt;
}
