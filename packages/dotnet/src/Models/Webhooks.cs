using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Opensms
{
    /// <summary>A webhook endpoint.</summary>
    public sealed class WebhookEndpoint
    {
        [JsonPropertyName("id")] public string Id { get; set; } = "";
        [JsonPropertyName("url")] public string? Url { get; set; }
        [JsonPropertyName("events")] public List<string>? Events { get; set; }
        [JsonPropertyName("enabled")] public bool? Enabled { get; set; }
        [JsonPropertyName("consecutive_failures")] public int? ConsecutiveFailures { get; set; }
        [JsonPropertyName("disabled_at")] public DateTimeOffset? DisabledAt { get; set; }
        [JsonPropertyName("created_at")] public DateTimeOffset? CreatedAt { get; set; }
        /// <summary>The signing secret (<c>whsec_...</c>). Only present in the create response; store it.</summary>
        [JsonPropertyName("secret")] public string? Secret { get; set; }
    }

    /// <summary>One delivery of an event to an endpoint.</summary>
    public sealed class WebhookDelivery
    {
        [JsonPropertyName("id")] public long Id { get; set; }
        [JsonPropertyName("generation")] public long? Generation { get; set; }
        [JsonPropertyName("event")] public string? Event { get; set; }
        [JsonPropertyName("payload")] public JsonElement? Payload { get; set; }
        [JsonPropertyName("attempts")] public int? Attempts { get; set; }
        [JsonPropertyName("next_retry_at")] public DateTimeOffset? NextRetryAt { get; set; }
        [JsonPropertyName("status")] public string? Status { get; set; }
        [JsonPropertyName("last_response_code")] public int? LastResponseCode { get; set; }
        [JsonPropertyName("last_error")] public string? LastError { get; set; }
        [JsonPropertyName("created_at")] public DateTimeOffset? CreatedAt { get; set; }
        [JsonPropertyName("delivered_at")] public DateTimeOffset? DeliveredAt { get; set; }
    }

    /// <summary>Parameters for <see cref="WebhooksResource.CreateAsync"/>.</summary>
    public sealed class CreateWebhookParams
    {
        /// <summary>An <c>https://</c> URL without credentials or fragment.</summary>
        [JsonPropertyName("url")] public required string Url { get; set; }
        [JsonPropertyName("events")] public required IList<string> Events { get; set; }
        [JsonPropertyName("enabled")] public bool? Enabled { get; set; }
    }

    /// <summary>Full replacement for <see cref="WebhooksResource.UpdateAsync"/>: every field is required.</summary>
    public sealed class UpdateWebhookParams
    {
        [JsonPropertyName("url")] public required string Url { get; set; }
        [JsonPropertyName("events")] public required IList<string> Events { get; set; }
        [JsonPropertyName("enabled")] public required bool Enabled { get; set; }
    }

    /// <summary>Parameters for <see cref="WebhooksResource.ReplayDeliveryAsync"/>.</summary>
    public sealed class ReplayDeliveryParams
    {
        /// <summary>The delivery's current <c>generation</c>.</summary>
        [JsonPropertyName("generation")] public required long Generation { get; set; }
        /// <summary>5..1000 characters.</summary>
        [JsonPropertyName("reason")] public required string Reason { get; set; }
    }

    /// <summary>A verified webhook event envelope.</summary>
    public sealed class WebhookEvent
    {
        [JsonPropertyName("id")] public string Id { get; set; } = "";
        /// <summary>For example <c>message.delivered</c>.</summary>
        [JsonPropertyName("type")] public string? Type { get; set; }
        [JsonPropertyName("workspace_id")] public string? WorkspaceId { get; set; }
        [JsonPropertyName("environment")] public string? Environment { get; set; }
        [JsonPropertyName("created_at")] public DateTimeOffset? CreatedAt { get; set; }
        /// <summary>The event object (a Message for <c>message.*</c> events).</summary>
        [JsonPropertyName("data")] public JsonElement? Data { get; set; }
    }
}
