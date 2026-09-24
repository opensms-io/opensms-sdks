package io.opensms.models;

import com.fasterxml.jackson.databind.JsonNode;

import java.time.OffsetDateTime;

/** One webhook delivery. Fields the API omits decode as null. */
public final class WebhookDelivery {
    public Long id;
    /** Pass to replayDelivery. */
    public Long generation;
    public String event;
    public JsonNode payload;
    public Integer attempts;
    public OffsetDateTime nextRetryAt;
    public String status;
    public Integer lastResponseCode;
    public String lastError;
    public OffsetDateTime createdAt;
    public OffsetDateTime deliveredAt;
}
