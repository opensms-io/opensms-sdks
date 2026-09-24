using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Opensms
{
    /// <summary>An outbound SMS. Also used for batch items, which carry fewer fields.</summary>
    public sealed class Message
    {
        [JsonPropertyName("id")] public string Id { get; set; } = "";
        [JsonPropertyName("created_at")] public DateTimeOffset? CreatedAt { get; set; }
        /// <summary>Destination in E.164.</summary>
        [JsonPropertyName("to")] public string? To { get; set; }
        [JsonPropertyName("sender_id")] public string? SenderId { get; set; }
        [JsonPropertyName("text")] public string? Text { get; set; }
        [JsonPropertyName("parts")] public int? Parts { get; set; }
        /// <summary><c>queued|scheduled|held|sending|sent|delivered|failed|cancelled|expired</c> (open set).</summary>
        [JsonPropertyName("status")] public string? Status { get; set; }
        [JsonPropertyName("status_reason")] public string? StatusReason { get; set; }
        [JsonPropertyName("sent_at")] public DateTimeOffset? SentAt { get; set; }
        [JsonPropertyName("delivered_at")] public DateTimeOffset? DeliveredAt { get; set; }
        [JsonPropertyName("failed_at")] public DateTimeOffset? FailedAt { get; set; }
        [JsonPropertyName("cancelled_at")] public DateTimeOffset? CancelledAt { get; set; }
        [JsonPropertyName("scheduled_at")] public DateTimeOffset? ScheduledAt { get; set; }
        /// <summary>Decimal string, for example <c>"0.000000"</c>.</summary>
        [JsonPropertyName("price")] public string? Price { get; set; }
        [JsonPropertyName("currency")] public string? Currency { get; set; }
        /// <summary><c>otp|transactional|marketing</c>.</summary>
        [JsonPropertyName("traffic_type")] public string? TrafficType { get; set; }
        [JsonPropertyName("metadata")] public Dictionary<string, JsonElement>? Metadata { get; set; }
        /// <summary><c>gsm7|ucs2</c>.</summary>
        [JsonPropertyName("encoding")] public string? Encoding { get; set; }
        [JsonPropertyName("country_id")] public string? CountryId { get; set; }
        [JsonPropertyName("country_iso2")] public string? CountryIso2 { get; set; }
        [JsonPropertyName("country_name")] public string? CountryName { get; set; }
        [JsonPropertyName("carrier_id")] public string? CarrierId { get; set; }
        [JsonPropertyName("carrier_name")] public string? CarrierName { get; set; }
        /// <summary><c>prefix|hlr|unknown</c>.</summary>
        [JsonPropertyName("destination_source")] public string? DestinationSource { get; set; }
        /// <summary>Billing lines (present on get and list, absent on send).</summary>
        [JsonPropertyName("billing")] public List<JsonElement>? Billing { get; set; }
    }

    /// <summary>Parameters for <see cref="MessagesResource.SendAsync"/>.</summary>
    public sealed class SendMessageParams
    {
        /// <summary>Destination in E.164 (<c>+254700000012</c>).</summary>
        [JsonPropertyName("to")] public required string To { get; set; }
        /// <summary>1..1600 characters.</summary>
        [JsonPropertyName("text")] public required string Text { get; set; }
        [JsonPropertyName("sender_id")] public string? SenderId { get; set; }
        [JsonPropertyName("traffic_type")] public string? TrafficType { get; set; }
        [JsonPropertyName("scheduled_at")] public DateTimeInput? ScheduledAt { get; set; }
        [JsonPropertyName("callback_url")] public string? CallbackUrl { get; set; }
        [JsonPropertyName("metadata")] public IDictionary<string, object?>? Metadata { get; set; }
    }

    /// <summary>Filters for <see cref="MessagesResource.ListAsync"/>.</summary>
    public sealed class MessageListParams : ListParams
    {
        public string? Status { get; set; }
        /// <summary>Digits or <c>+digits</c> fragment of the destination.</summary>
        public string? To { get; set; }
        /// <summary>Uppercase ISO2 country code.</summary>
        public string? Country { get; set; }
        /// <summary><c>YYYY-MM-DD</c> or an instant.</summary>
        public DateTimeInput? DateFrom { get; set; }
        /// <summary><c>YYYY-MM-DD</c> (inclusive) or an instant.</summary>
        public DateTimeInput? DateTo { get; set; }
    }

    /// <summary>One provider submission attempt for a message.</summary>
    public sealed class Attempt
    {
        [JsonPropertyName("id")] public long Id { get; set; }
        [JsonPropertyName("sequence")] public int? Sequence { get; set; }
        [JsonPropertyName("route_id")] public string? RouteId { get; set; }
        [JsonPropertyName("route_name")] public string? RouteName { get; set; }
        [JsonPropertyName("price")] public string? Price { get; set; }
        [JsonPropertyName("currency")] public string? Currency { get; set; }
        [JsonPropertyName("provider")] public string? Provider { get; set; }
        [JsonPropertyName("provider_message_id")] public string? ProviderMessageId { get; set; }
        [JsonPropertyName("status")] public string? Status { get; set; }
        [JsonPropertyName("error_code")] public string? ErrorCode { get; set; }
        [JsonPropertyName("submitted_at")] public DateTimeOffset? SubmittedAt { get; set; }
        [JsonPropertyName("dlr_at")] public DateTimeOffset? DlrAt { get; set; }
        [JsonPropertyName("submit_latency_ms")] public long? SubmitLatencyMs { get; set; }
        [JsonPropertyName("dlr_latency_ms")] public long? DlrLatencyMs { get; set; }
    }

    /// <summary>A message as seen by the sandbox (rendered text, including OTP codes).</summary>
    public sealed class SandboxMessage
    {
        [JsonPropertyName("id")] public string Id { get; set; } = "";
        [JsonPropertyName("to")] public string? To { get; set; }
        [JsonPropertyName("sender_id")] public string? SenderId { get; set; }
        [JsonPropertyName("text")] public string? Text { get; set; }
        [JsonPropertyName("parts")] public int? Parts { get; set; }
        [JsonPropertyName("status")] public string? Status { get; set; }
        [JsonPropertyName("traffic_type")] public string? TrafficType { get; set; }
        [JsonPropertyName("created_at")] public DateTimeOffset? CreatedAt { get; set; }
        [JsonPropertyName("sent_at")] public DateTimeOffset? SentAt { get; set; }
    }

    /// <summary>Parameters for <see cref="OtpResource.SendAsync"/>.</summary>
    public sealed class SendOtpParams
    {
        [JsonPropertyName("to")] public required string To { get; set; }
        [JsonPropertyName("sender_id")] public string? SenderId { get; set; }
        /// <summary>Must contain <c>{{code}}</c>.</summary>
        [JsonPropertyName("template")] public string? Template { get; set; }
        /// <summary>4..10 digits (default 6).</summary>
        [JsonPropertyName("length")] public int? Length { get; set; }
        /// <summary>30..86400 (default 600).</summary>
        [JsonPropertyName("ttl_seconds")] public int? TtlSeconds { get; set; }
    }

    /// <summary>Result of <see cref="OtpResource.SendAsync"/>.</summary>
    public sealed class OtpSendResult
    {
        [JsonPropertyName("otp_id")] public string OtpId { get; set; } = "";
    }

    /// <summary>Parameters for <see cref="OtpResource.VerifyAsync"/>.</summary>
    public sealed class VerifyOtpParams
    {
        [JsonPropertyName("otp_id")] public required string OtpId { get; set; }
        [JsonPropertyName("code")] public required string Code { get; set; }
    }

    /// <summary>Result of <see cref="OtpResource.VerifyAsync"/>.</summary>
    public sealed class OtpVerifyResult
    {
        [JsonPropertyName("valid")] public bool Valid { get; set; }
        [JsonPropertyName("attempts_left")] public int? AttemptsLeft { get; set; }
    }

    /// <summary>A number lookup (carrier, validity, porting).</summary>
    public sealed class Lookup
    {
        [JsonPropertyName("id")] public string Id { get; set; } = "";
        /// <summary><c>queued|submitting|unknown|completed|failed</c>.</summary>
        [JsonPropertyName("state")] public string? State { get; set; }
        [JsonPropertyName("country")] public string? Country { get; set; }
        [JsonPropertyName("carrier")] public string? Carrier { get; set; }
        [JsonPropertyName("ported")] public bool? Ported { get; set; }
        [JsonPropertyName("valid")] public bool? Valid { get; set; }
        /// <summary><c>prefix|hlr|mock</c>.</summary>
        [JsonPropertyName("source")] public string? Source { get; set; }
        [JsonPropertyName("price")] public string? Price { get; set; }
        [JsonPropertyName("currency")] public string? Currency { get; set; }
        [JsonPropertyName("checked_at")] public DateTimeOffset? CheckedAt { get; set; }
    }

    /// <summary>Parameters for <see cref="LookupsResource.CreateAsync"/>.</summary>
    public sealed class CreateLookupParams
    {
        [JsonPropertyName("to")] public required string To { get; set; }
    }

    /// <summary>An inbound SMS received on one of your numbers.</summary>
    public sealed class InboundMessage
    {
        [JsonPropertyName("id")] public string Id { get; set; } = "";
        [JsonPropertyName("from")] public string? From { get; set; }
        [JsonPropertyName("to")] public string? To { get; set; }
        [JsonPropertyName("text")] public string? Text { get; set; }
        [JsonPropertyName("received_at")] public DateTimeOffset? ReceivedAt { get; set; }
        [JsonPropertyName("virtual_number_id")] public string? VirtualNumberId { get; set; }
    }

    /// <summary>Parameters for <see cref="InboundResource.ReplyAsync"/>.</summary>
    public sealed class InboundReplyParams
    {
        [JsonPropertyName("text")] public required string Text { get; set; }
    }
}
