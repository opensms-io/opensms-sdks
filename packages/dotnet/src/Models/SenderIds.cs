using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Opensms
{
    /// <summary>A registered sender ID.</summary>
    public sealed class SenderId
    {
        [JsonPropertyName("id")] public string Id { get; set; } = "";
        [JsonPropertyName("value")] public string? Value { get; set; }
        /// <summary><c>alphanumeric|numeric</c>.</summary>
        [JsonPropertyName("kind")] public string? Kind { get; set; }
        [JsonPropertyName("countries")] public List<string>? Countries { get; set; }
        [JsonPropertyName("use_case")] public string? UseCase { get; set; }
        [JsonPropertyName("sample_message")] public string? SampleMessage { get; set; }
        /// <summary><c>pending|approved|rejected|...</c>.</summary>
        [JsonPropertyName("status")] public string? Status { get; set; }
        [JsonPropertyName("rejection_reason")] public string? RejectionReason { get; set; }
        [JsonPropertyName("restricted")] public bool? Restricted { get; set; }
        [JsonPropertyName("restriction_reason")] public string? RestrictionReason { get; set; }
        [JsonPropertyName("created_at")] public DateTimeOffset? CreatedAt { get; set; }
        /// <summary>Per-country registrations (on get and create).</summary>
        [JsonPropertyName("registrations")] public List<JsonElement>? Registrations { get; set; }
    }

    /// <summary>Parameters for <see cref="SenderIdsResource.CreateAsync"/>. Never auto-retried because registration may charge fees.</summary>
    public sealed class CreateSenderIdParams
    {
        [JsonPropertyName("value")] public required string Value { get; set; }
        [JsonPropertyName("kind")] public required string Kind { get; set; }
        [JsonPropertyName("countries")] public required IList<string> Countries { get; set; }
        [JsonPropertyName("use_case")] public string? UseCase { get; set; }
        [JsonPropertyName("sample_message")] public string? SampleMessage { get; set; }
        /// <summary>Document ids (certificate, signatory-id and authorization are required for a custom sender).</summary>
        [JsonPropertyName("documents")] public required IList<string> Documents { get; set; }
        [JsonPropertyName("draft_id")] public string? DraftId { get; set; }
        [JsonPropertyName("draft_version")] public int? DraftVersion { get; set; }
        [JsonPropertyName("quote_id")] public string? QuoteId { get; set; }
    }

    /// <summary>Amendment for <see cref="SenderIdsResource.UpdateAsync"/>.</summary>
    public sealed class UpdateSenderIdParams
    {
        [JsonPropertyName("use_case")] public required string UseCase { get; set; }
        [JsonPropertyName("countries")] public required IList<string> Countries { get; set; }
        [JsonPropertyName("documents")] public required IList<string> Documents { get; set; }
        [JsonPropertyName("sample_message")] public string? SampleMessage { get; set; }
    }

    /// <summary>Query for <see cref="SenderIdsResource.CheckAsync"/>.</summary>
    public sealed class SenderIdCheckParams
    {
        public required string Value { get; set; }
        public string? Country { get; set; }
    }

    /// <summary>Availability of a sender ID value.</summary>
    public sealed class SenderIdCheckResult
    {
        [JsonPropertyName("valid")] public bool? Valid { get; set; }
        [JsonPropertyName("available")] public bool? Available { get; set; }
        [JsonPropertyName("reserved")] public bool? Reserved { get; set; }
        [JsonPropertyName("reason")] public string? Reason { get; set; }
    }

    /// <summary>Query for <see cref="SenderIdsResource.QuoteAsync"/>.</summary>
    public sealed class SenderIdQuoteParams
    {
        /// <summary>ISO2 codes; sent comma-joined (<c>countries=KE,NG</c>).</summary>
        public required IList<string> Countries { get; set; }
    }

    /// <summary>A registration fee quote.</summary>
    public sealed class SenderIdQuote
    {
        [JsonPropertyName("quote_id")] public string? QuoteId { get; set; }
        [JsonPropertyName("entries")] public List<SenderIdQuoteEntry>? Entries { get; set; }
        [JsonPropertyName("totals")] public List<SenderIdQuoteTotal>? Totals { get; set; }
    }

    /// <summary>One country line of a quote.</summary>
    public sealed class SenderIdQuoteEntry
    {
        [JsonPropertyName("country")] public string? Country { get; set; }
        [JsonPropertyName("provider")] public string? Provider { get; set; }
        [JsonPropertyName("fee_amount")] public string? FeeAmount { get; set; }
        [JsonPropertyName("fee_currency")] public string? FeeCurrency { get; set; }
    }

    /// <summary>Quote total per currency.</summary>
    public sealed class SenderIdQuoteTotal
    {
        [JsonPropertyName("currency")] public string? Currency { get; set; }
        [JsonPropertyName("amount")] public string? Amount { get; set; }
    }

    /// <summary>An uploaded sender registration document.</summary>
    public sealed class SenderDocument
    {
        [JsonPropertyName("id")] public string Id { get; set; } = "";
        /// <summary><c>certificate|signatory-id|authorization</c>.</summary>
        [JsonPropertyName("kind")] public string? Kind { get; set; }
        [JsonPropertyName("filename")] public string? Filename { get; set; }
        [JsonPropertyName("content_type")] public string? ContentType { get; set; }
        [JsonPropertyName("size")] public long? Size { get; set; }
        [JsonPropertyName("scan_status")] public string? ScanStatus { get; set; }
        [JsonPropertyName("review_status")] public string? ReviewStatus { get; set; }
        [JsonPropertyName("review_reason")] public string? ReviewReason { get; set; }
        [JsonPropertyName("reviewed_at")] public DateTimeOffset? ReviewedAt { get; set; }
        [JsonPropertyName("version")] public int? Version { get; set; }
        [JsonPropertyName("supersedes_id")] public string? SupersedesId { get; set; }
        [JsonPropertyName("is_current")] public bool? IsCurrent { get; set; }
        [JsonPropertyName("created_at")] public DateTimeOffset? CreatedAt { get; set; }
    }

    /// <summary>A saved sender ID application draft.</summary>
    public sealed class SenderIdDraft
    {
        [JsonPropertyName("id")] public string Id { get; set; } = "";
        /// <summary><c>onboarding|application</c>.</summary>
        [JsonPropertyName("source")] public string? Source { get; set; }
        [JsonPropertyName("value")] public string? Value { get; set; }
        [JsonPropertyName("kind")] public string? Kind { get; set; }
        [JsonPropertyName("countries")] public List<string>? Countries { get; set; }
        [JsonPropertyName("use_case")] public string? UseCase { get; set; }
        [JsonPropertyName("sample_message")] public string? SampleMessage { get; set; }
        [JsonPropertyName("documents")] public List<string>? Documents { get; set; }
        /// <summary>Optimistic-lock version; pass it to <see cref="SenderIdsResource.UpdateDraftAsync"/>.</summary>
        [JsonPropertyName("version")] public int? Version { get; set; }
        /// <summary><c>active|submitted</c>.</summary>
        [JsonPropertyName("status")] public string? Status { get; set; }
        [JsonPropertyName("submitted_sender_id")] public string? SubmittedSenderId { get; set; }
        [JsonPropertyName("created_at")] public DateTimeOffset? CreatedAt { get; set; }
        [JsonPropertyName("updated_at")] public DateTimeOffset? UpdatedAt { get; set; }
    }

    /// <summary>Parameters for <see cref="SenderIdsResource.CreateDraftAsync"/>.</summary>
    public sealed class CreateSenderIdDraftParams
    {
        [JsonPropertyName("source")] public string? Source { get; set; }
        [JsonPropertyName("value")] public string? Value { get; set; }
        [JsonPropertyName("kind")] public string? Kind { get; set; }
        [JsonPropertyName("countries")] public IList<string>? Countries { get; set; }
        [JsonPropertyName("use_case")] public string? UseCase { get; set; }
        [JsonPropertyName("sample_message")] public string? SampleMessage { get; set; }
        [JsonPropertyName("documents")] public IList<string>? Documents { get; set; }
    }

    /// <summary>Parameters for <see cref="SenderIdsResource.UpdateDraftAsync"/>; <see cref="Version"/> must match the current draft (409 otherwise).</summary>
    public sealed class UpdateSenderIdDraftParams
    {
        [JsonPropertyName("version")] public required int Version { get; set; }
        [JsonPropertyName("value")] public string? Value { get; set; }
        [JsonPropertyName("kind")] public string? Kind { get; set; }
        [JsonPropertyName("countries")] public IList<string>? Countries { get; set; }
        [JsonPropertyName("use_case")] public string? UseCase { get; set; }
        [JsonPropertyName("sample_message")] public string? SampleMessage { get; set; }
        [JsonPropertyName("documents")] public IList<string>? Documents { get; set; }
    }
}
