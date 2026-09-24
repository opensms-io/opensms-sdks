using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Text.Json.Serialization;
using Opensms.Internal;

namespace Opensms
{
    /// <summary>Per-call options for methods that send an <c>Idempotency-Key</c>.</summary>
    public sealed class RequestOptions
    {
        /// <summary>
        /// The Idempotency-Key to send. When unset the SDK generates a UUIDv4 once
        /// per call and reuses it on every retry. Reusing a key with a different
        /// body returns <c>409</c>.
        /// </summary>
        public string? IdempotencyKey { get; set; }
    }

    /// <summary>
    /// A timestamp input that accepts either a <see cref="DateTimeOffset"/> /
    /// <see cref="DateTime"/> (sent as RFC 3339 UTC) or a string passed through
    /// verbatim (for example <c>"2026-09-24"</c>).
    /// </summary>
    [JsonConverter(typeof(DateTimeInputConverter))]
    public readonly struct DateTimeInput
    {
        /// <summary>The wire value.</summary>
        public string Value { get; }

        private DateTimeInput(string value) => Value = value;

        /// <summary>Use an instant, serialized as RFC 3339 UTC.</summary>
        public static implicit operator DateTimeInput(DateTimeOffset value) => new DateTimeInput(Wire.FormatTimestamp(value));

        /// <summary>Use a <see cref="DateTime"/>; unspecified kinds are treated as UTC.</summary>
        public static implicit operator DateTimeInput(DateTime value)
            => new DateTimeInput(Wire.FormatTimestamp(value.Kind == DateTimeKind.Unspecified
                ? new DateTimeOffset(DateTime.SpecifyKind(value, DateTimeKind.Utc))
                : new DateTimeOffset(value)));

        /// <summary>Use a string verbatim (RFC 3339 or <c>YYYY-MM-DD</c>).</summary>
        public static implicit operator DateTimeInput(string value) => new DateTimeInput(value);

        /// <inheritdoc />
        public override string ToString() => Value;
    }

    internal sealed class DateTimeInputConverter : JsonConverter<DateTimeInput>
    {
        public override DateTimeInput Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
            => reader.GetString() ?? "";

        public override void Write(Utf8JsonWriter writer, DateTimeInput value, JsonSerializerOptions options)
            => writer.WriteStringValue(value.Value);
    }

    /// <summary>A <c>{ "data": [...] }</c> envelope (wallet endpoints).</summary>
    internal sealed class DataEnvelope<T>
    {
        [JsonPropertyName("data")] public List<T> Data { get; set; } = new List<T>();
    }

    /// <summary>An <c>{ "items": [...] }</c> envelope without a cursor.</summary>
    internal sealed class ItemsEnvelope<T>
    {
        [JsonPropertyName("items")] public List<T> Items { get; set; } = new List<T>();
    }

    /// <summary>A <c>{ "status": ... }</c> acknowledgement (webhook test and replay).</summary>
    public sealed class StatusResult
    {
        [JsonPropertyName("status")] public string? Status { get; set; }
    }
}
