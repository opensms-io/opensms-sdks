package io.opensms.models;

import com.fasterxml.jackson.databind.JsonNode;

import java.time.OffsetDateTime;

/** A verified webhook event envelope. Fields the API omits decode as null. */
public final class WebhookEvent {
    public String id;
    /** For example message.delivered. */
    public String type;
    public String workspaceId;
    public String environment;
    public OffsetDateTime createdAt;
    /** Event payload. */
    public JsonNode data;
}
