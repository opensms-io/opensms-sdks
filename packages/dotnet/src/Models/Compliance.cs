using System;
using System.Collections.Generic;
using System.Text.Json.Serialization;

namespace Opensms
{
    /// <summary>A suppressed (do-not-send) destination.</summary>
    public sealed class Suppression
    {
        [JsonPropertyName("id")] public long Id { get; set; }
        [JsonPropertyName("e164")] public string? E164 { get; set; }
        /// <summary><c>stop_keyword|manual|complaint|invalid_number</c>.</summary>
        [JsonPropertyName("reason")] public string? Reason { get; set; }
        [JsonPropertyName("created_at")] public DateTimeOffset? CreatedAt { get; set; }
    }

    /// <summary>One suppression to add.</summary>
    public sealed class SuppressionParams
    {
        [JsonPropertyName("e164")] public required string E164 { get; set; }
        [JsonPropertyName("reason")] public required string Reason { get; set; }
    }

    /// <summary>Result of <see cref="SuppressionsResource.ImportAsync"/>.</summary>
    public sealed class SuppressionImportResult
    {
        [JsonPropertyName("created")] public int Created { get; set; }
        [JsonPropertyName("received")] public int Received { get; set; }
    }

    /// <summary>Messaging rules for one country.</summary>
    public sealed class CountryRules
    {
        [JsonPropertyName("iso2")] public string? Iso2 { get; set; }
        [JsonPropertyName("name")] public string? Name { get; set; }
        [JsonPropertyName("status")] public string? Status { get; set; }
        [JsonPropertyName("dial_code")] public string? DialCode { get; set; }
        [JsonPropertyName("stop_keywords")] public List<string>? StopKeywords { get; set; }
        [JsonPropertyName("quiet_hours")] public List<QuietHours>? QuietHours { get; set; }
        [JsonPropertyName("content_rules")] public List<CountryContentRule>? ContentRules { get; set; }
    }

    /// <summary>A quiet-hours window.</summary>
    public sealed class QuietHours
    {
        [JsonPropertyName("traffic_type")] public string? TrafficType { get; set; }
        /// <summary>Local time, for example <c>21:00:00</c>.</summary>
        [JsonPropertyName("start_local")] public string? StartLocal { get; set; }
        [JsonPropertyName("end_local")] public string? EndLocal { get; set; }
        /// <summary>Enforcement mode as sent by the API (for example <c>defer</c>).</summary>
        [JsonPropertyName("enforce")] public string? Enforce { get; set; }
    }

    /// <summary>A content rule embedded in <see cref="CountryRules"/>.</summary>
    public sealed class CountryContentRule
    {
        [JsonPropertyName("kind")] public string? Kind { get; set; }
        [JsonPropertyName("pattern")] public string? Pattern { get; set; }
        [JsonPropertyName("action")] public string? Action { get; set; }
        [JsonPropertyName("traffic_types")] public List<string>? TrafficTypes { get; set; }
        [JsonPropertyName("enabled")] public bool? Enabled { get; set; }
    }

    /// <summary>A platform content rule.</summary>
    public sealed class ContentRule
    {
        [JsonPropertyName("id")] public long Id { get; set; }
        [JsonPropertyName("country_iso2")] public string? CountryIso2 { get; set; }
        /// <summary><c>blocked_keyword|regex</c>.</summary>
        [JsonPropertyName("kind")] public string? Kind { get; set; }
        [JsonPropertyName("pattern")] public string? Pattern { get; set; }
        /// <summary><c>reject|hold_for_review</c>.</summary>
        [JsonPropertyName("action")] public string? Action { get; set; }
        [JsonPropertyName("traffic_types")] public List<string>? TrafficTypes { get; set; }
        [JsonPropertyName("enabled")] public bool? Enabled { get; set; }
    }

    /// <summary>A country in the public catalog.</summary>
    public sealed class Country
    {
        [JsonPropertyName("iso2")] public string? Iso2 { get; set; }
        [JsonPropertyName("name")] public string? Name { get; set; }
        [JsonPropertyName("dial_code")] public string? DialCode { get; set; }
        [JsonPropertyName("currency")] public string? Currency { get; set; }
        [JsonPropertyName("status")] public string? Status { get; set; }
        [JsonPropertyName("price_per_message")] public Money? PricePerMessage { get; set; }
        [JsonPropertyName("sender_kinds")] public List<string>? SenderKinds { get; set; }
        [JsonPropertyName("providers_available")] public int? ProvidersAvailable { get; set; }
    }

    /// <summary>An amount (decimal string) and currency.</summary>
    public sealed class Money
    {
        [JsonPropertyName("amount")] public string? Amount { get; set; }
        [JsonPropertyName("currency")] public string? Currency { get; set; }
    }

    /// <summary>A mobile carrier in a country.</summary>
    public sealed class Carrier
    {
        [JsonPropertyName("id")] public string Id { get; set; } = "";
        [JsonPropertyName("name")] public string? Name { get; set; }
        [JsonPropertyName("mcc_mnc")] public List<string>? MccMnc { get; set; }
        [JsonPropertyName("prefixes")] public List<string>? Prefixes { get; set; }
    }

    /// <summary>A delivery route into a country.</summary>
    public sealed class Route
    {
        [JsonPropertyName("provider")] public string? Provider { get; set; }
        [JsonPropertyName("carrier")] public string? Carrier { get; set; }
        [JsonPropertyName("health")] public string? Health { get; set; }
        [JsonPropertyName("cost")] public string? Cost { get; set; }
        [JsonPropertyName("currency")] public string? Currency { get; set; }
        [JsonPropertyName("priority")] public int? Priority { get; set; }
        [JsonPropertyName("sell_price")] public Money? SellPrice { get; set; }
        [JsonPropertyName("p50_ms")] public long? P50Ms { get; set; }
    }
}
