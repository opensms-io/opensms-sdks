using System;
using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Opensms.Internal
{
    /// <summary>Shared JSON settings: omit nulls on the wire, tolerate new or loosely typed server values.</summary>
    internal static class Json
    {
        public static readonly JsonSerializerOptions Options = Create();

        private static JsonSerializerOptions Create()
        {
            var o = new JsonSerializerOptions
            {
                // Request bodies omit unset optionals entirely: the API rejects unknown
                // fields and some handlers treat null differently from absent.
                DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
                PropertyNamingPolicy = null,
                NumberHandling = JsonNumberHandling.AllowReadingFromString,
                // Keep '+' in E.164 numbers literal on the wire (the default encoder emits \u002B).
                Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
            };
            o.Converters.Add(new FlexibleStringConverter());
            o.Converters.Add(new LenientDateTimeOffsetConverter());
            return o;
        }

        public static byte[] Serialize(object body) => JsonSerializer.SerializeToUtf8Bytes(body, body.GetType(), Options);

        public static T? Deserialize<T>(string text) => JsonSerializer.Deserialize<T>(text, Options);
    }

    /// <summary>
    /// Reads any JSON scalar into a string so money, prices and FX rates stay
    /// decimal text even if the server sends a number. Objects and arrays are
    /// kept as their raw JSON text.
    /// </summary>
    internal sealed class FlexibleStringConverter : JsonConverter<string>
    {
        public override string? Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
        {
            switch (reader.TokenType)
            {
                case JsonTokenType.String:
                    return reader.GetString();
                case JsonTokenType.Number:
                    using (var doc = JsonDocument.ParseValue(ref reader)) return doc.RootElement.GetRawText();
                case JsonTokenType.True:
                    return "true";
                case JsonTokenType.False:
                    return "false";
                case JsonTokenType.Null:
                    return null;
                default:
                    using (var doc = JsonDocument.ParseValue(ref reader)) return doc.RootElement.GetRawText();
            }
        }

        public override void Write(Utf8JsonWriter writer, string value, JsonSerializerOptions options)
            => writer.WriteStringValue(value);
    }

    /// <summary>
    /// Parses RFC 3339 timestamps with any offset (the API mixes <c>+03:00</c> and
    /// <c>+00:00</c>), falling back to invariant parsing for looser shapes.
    /// </summary>
    internal sealed class LenientDateTimeOffsetConverter : JsonConverter<DateTimeOffset>
    {
        public override DateTimeOffset Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
        {
            if (reader.TokenType == JsonTokenType.String)
            {
                if (reader.TryGetDateTimeOffset(out var v)) return v;
                var s = reader.GetString();
                if (DateTimeOffset.TryParse(s, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out v)) return v;
                throw new JsonException($"Unrecognised timestamp '{s}'.");
            }
            if (reader.TokenType == JsonTokenType.Number && reader.TryGetInt64(out var unix))
                return DateTimeOffset.FromUnixTimeSeconds(unix);
            throw new JsonException($"Expected a timestamp, got {reader.TokenType}.");
        }

        public override void Write(Utf8JsonWriter writer, DateTimeOffset value, JsonSerializerOptions options)
            => writer.WriteStringValue(Wire.FormatTimestamp(value));
    }
}
