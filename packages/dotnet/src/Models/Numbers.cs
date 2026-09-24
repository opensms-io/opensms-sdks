using System;
using System.Text.Json.Serialization;

namespace Opensms
{
    /// <summary>A virtual phone number.</summary>
    public sealed class PhoneNumber
    {
        [JsonPropertyName("id")] public string Id { get; set; } = "";
        [JsonPropertyName("country")] public string? Country { get; set; }
        [JsonPropertyName("number")] public string? Number { get; set; }
        /// <summary><c>long_code|short_code|toll_free</c>.</summary>
        [JsonPropertyName("kind")] public string? Kind { get; set; }
        [JsonPropertyName("monthly_fee")] public string? MonthlyFee { get; set; }
        [JsonPropertyName("fee_currency")] public string? FeeCurrency { get; set; }
        /// <summary><c>available|assigned|releasing</c>.</summary>
        [JsonPropertyName("status")] public string? Status { get; set; }
        [JsonPropertyName("inbound")] public bool? Inbound { get; set; }
        [JsonPropertyName("outbound")] public bool? Outbound { get; set; }
        [JsonPropertyName("assigned_at")] public DateTimeOffset? AssignedAt { get; set; }
        [JsonPropertyName("renews_at")] public DateTimeOffset? RenewsAt { get; set; }
    }

    /// <summary>Country and kind, for <see cref="NumbersResource.AvailableAsync"/> and <see cref="NumbersResource.AssignAsync"/>.</summary>
    public sealed class NumberSearchParams
    {
        [JsonPropertyName("country")] public required string Country { get; set; }
        /// <summary><c>long_code|short_code|toll_free</c>.</summary>
        [JsonPropertyName("kind")] public required string Kind { get; set; }
    }

    /// <summary>An inbound routing rule on a number.</summary>
    public sealed class NumberRule
    {
        [JsonPropertyName("id")] public string Id { get; set; } = "";
        /// <summary><c>keyword|prefix|regex|any</c>.</summary>
        [JsonPropertyName("match")] public string? Match { get; set; }
        [JsonPropertyName("pattern")] public string? Pattern { get; set; }
        /// <summary><c>webhook|auto_reply|forward_email</c>.</summary>
        [JsonPropertyName("action")] public string? Action { get; set; }
        [JsonPropertyName("target")] public string? Target { get; set; }
        [JsonPropertyName("position")] public int? Position { get; set; }
    }

    /// <summary>Body for <see cref="NumbersResource.CreateRuleAsync"/> and <see cref="NumbersResource.UpdateRuleAsync"/>.</summary>
    public sealed class NumberRuleParams
    {
        [JsonPropertyName("match")] public required string Match { get; set; }
        /// <summary>Required unless <see cref="Match"/> is <c>any</c>.</summary>
        [JsonPropertyName("pattern")] public string? Pattern { get; set; }
        [JsonPropertyName("action")] public required string Action { get; set; }
        [JsonPropertyName("target")] public required string Target { get; set; }
        /// <summary>0..10000.</summary>
        [JsonPropertyName("position")] public int? Position { get; set; }
    }
}
