package io.opensms.models;

import java.time.OffsetDateTime;
import java.util.List;

/** A webhook endpoint. Fields the API omits decode as null. */
public final class WebhookEndpoint {
    public String id;
    public String url;
    public List<String> events;
    public Boolean enabled;
    public Integer consecutiveFailures;
    public OffsetDateTime disabledAt;
    public OffsetDateTime createdAt;
    /** Signing secret (whsec_...), only present in the create response. */
    public String secret;
}
