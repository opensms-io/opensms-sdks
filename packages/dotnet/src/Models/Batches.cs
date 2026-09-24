using System;
using System.Collections.Generic;
using System.Text.Json.Serialization;

namespace Opensms
{
    /// <summary>A bulk send.</summary>
    public sealed class Batch
    {
        [JsonPropertyName("id")] public string Id { get; set; } = "";
        /// <summary><c>ready|running|stopped|completed|failed</c>.</summary>
        [JsonPropertyName("status")] public string? Status { get; set; }
        [JsonPropertyName("total")] public int? Total { get; set; }
        [JsonPropertyName("sent")] public int? Sent { get; set; }
        [JsonPropertyName("delivered")] public int? Delivered { get; set; }
        [JsonPropertyName("failed")] public int? Failed { get; set; }
        [JsonPropertyName("invalid")] public int? Invalid { get; set; }
        [JsonPropertyName("duplicates")] public int? Duplicates { get; set; }
        [JsonPropertyName("suppressed")] public int? Suppressed { get; set; }
        /// <summary>Estimated cost as decimal text (the API sends a number or null).</summary>
        [JsonPropertyName("estimated_cost")] public string? EstimatedCost { get; set; }
        [JsonPropertyName("created_at")] public DateTimeOffset? CreatedAt { get; set; }
        [JsonPropertyName("completed_at")] public DateTimeOffset? CompletedAt { get; set; }
    }

    /// <summary>One row of a batch.</summary>
    public sealed class BatchItemInput
    {
        [JsonPropertyName("to")] public required string To { get; set; }
        [JsonPropertyName("text")] public required string Text { get; set; }
        [JsonPropertyName("sender_id")] public string? SenderId { get; set; }
        [JsonPropertyName("traffic_type")] public string? TrafficType { get; set; }
        [JsonPropertyName("callback_url")] public string? CallbackUrl { get; set; }
        [JsonPropertyName("metadata")] public IDictionary<string, object?>? Metadata { get; set; }
    }

    /// <summary>Parameters for <see cref="BatchesResource.CreateAsync"/>.</summary>
    public sealed class CreateBatchParams
    {
        [JsonPropertyName("items")] public required IList<BatchItemInput> Items { get; set; }
        /// <summary>Drop repeated destinations (default true).</summary>
        [JsonPropertyName("dedupe")] public bool? Dedupe { get; set; }
    }

    /// <summary>A batch row as echoed by the validation report (every field optional).</summary>
    public sealed class BatchReportItem
    {
        [JsonPropertyName("to")] public string? To { get; set; }
        [JsonPropertyName("text")] public string? Text { get; set; }
        [JsonPropertyName("sender_id")] public string? SenderId { get; set; }
        [JsonPropertyName("traffic_type")] public string? TrafficType { get; set; }
        [JsonPropertyName("callback_url")] public string? CallbackUrl { get; set; }
        [JsonPropertyName("metadata")] public Dictionary<string, System.Text.Json.JsonElement>? Metadata { get; set; }
    }

    /// <summary>One row of <see cref="BatchValidationReport"/>.</summary>
    public sealed class BatchValidationRow
    {
        [JsonPropertyName("row")] public int Row { get; set; }
        [JsonPropertyName("item")] public BatchReportItem? Item { get; set; }
        [JsonPropertyName("valid")] public bool Valid { get; set; }
        [JsonPropertyName("duplicate")] public bool? Duplicate { get; set; }
        [JsonPropertyName("suppressed")] public bool? Suppressed { get; set; }
        [JsonPropertyName("error")] public string? Error { get; set; }
    }

    /// <summary>Per-row validation of a batch.</summary>
    public sealed class BatchValidationReport
    {
        [JsonPropertyName("rows")] public List<BatchValidationRow> Rows { get; set; } = new List<BatchValidationRow>();
        [JsonPropertyName("total")] public int? Total { get; set; }
        [JsonPropertyName("valid")] public int? Valid { get; set; }
        [JsonPropertyName("invalid")] public int? Invalid { get; set; }
        [JsonPropertyName("duplicates")] public int? Duplicates { get; set; }
        [JsonPropertyName("suppressed")] public int? Suppressed { get; set; }
    }

    /// <summary>Result of <see cref="BatchesResource.StopAsync"/>.</summary>
    public sealed class BatchStopResult
    {
        [JsonPropertyName("id")] public string Id { get; set; } = "";
        [JsonPropertyName("status")] public string? Status { get; set; }
        [JsonPropertyName("cancelled")] public int? Cancelled { get; set; }
    }

    /// <summary>Filters for <see cref="BatchesResource.ListItemsAsync"/>.</summary>
    public sealed class BatchItemListParams : ListParams
    {
        public string? Status { get; set; }
    }
}
