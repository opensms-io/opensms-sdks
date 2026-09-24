using System;
using System.Collections.Generic;
using System.Text.Json;

namespace Opensms
{
    /// <summary>
    /// Thrown for every non-2xx API response and for transport failures that
    /// survive all retries. Mapped from the RFC 9457 <c>application/problem+json</c>
    /// body the API returns.
    /// </summary>
    /// <remarks>
    /// Most errors carry no <see cref="Code"/>, so branch on <see cref="Status"/>
    /// and show <see cref="Detail"/>. Insufficient scope is <c>401</c> on messages
    /// and OTP but <c>403</c> everywhere else.
    /// </remarks>
    public sealed class OpensmsException : Exception
    {
        /// <summary>HTTP status. <c>0</c> means no response (network failure or timeout), or a local webhook signature failure.</summary>
        public int Status { get; }

        /// <summary>Problem <c>type</c>, usually <c>about:blank</c>.</summary>
        public string? Type { get; }

        /// <summary>Problem <c>title</c>, for example <c>Bad Request</c>.</summary>
        public string? Title { get; }

        /// <summary>Problem <c>detail</c>, the human readable reason.</summary>
        public string? Detail { get; }

        /// <summary>Optional machine code (absent on most errors).</summary>
        public string? Code { get; }

        /// <summary>Optional <c>trace_id</c> from the problem body.</summary>
        public string? TraceId { get; }

        /// <summary>Optional field validation errors (<c>errors</c> in the body).</summary>
        public IReadOnlyDictionary<string, IReadOnlyList<string>>? Errors { get; }

        /// <summary>The <c>X-Request-ID</c> response header (set on message and OTP admission rejections).</summary>
        public string? RequestId { get; }

        /// <summary>The <c>Retry-After</c> response header in seconds, when present.</summary>
        public double? RetryAfter { get; }

        /// <summary>The raw response body text, for debugging and forward compatibility.</summary>
        public string? Body { get; }

        /// <summary>Create an exception.</summary>
        public OpensmsException(
            int status,
            string message,
            string? type = null,
            string? title = null,
            string? detail = null,
            string? code = null,
            string? traceId = null,
            IReadOnlyDictionary<string, IReadOnlyList<string>>? errors = null,
            string? requestId = null,
            double? retryAfter = null,
            string? body = null,
            Exception? innerException = null)
            : base(message, innerException)
        {
            Status = status;
            Type = type;
            Title = title;
            Detail = detail;
            Code = code;
            TraceId = traceId;
            Errors = errors;
            RequestId = requestId;
            RetryAfter = retryAfter;
            Body = body;
        }

        /// <summary>Map an HTTP error response to an exception. Non-JSON bodies leave every problem field null.</summary>
        internal static OpensmsException FromResponse(int status, string? body, string? requestId, double? retryAfter)
        {
            string? type = null, title = null, detail = null, code = null, traceId = null;
            Dictionary<string, IReadOnlyList<string>>? errors = null;

            if (!string.IsNullOrWhiteSpace(body))
            {
                try
                {
                    using var doc = JsonDocument.Parse(body);
                    var root = doc.RootElement;
                    if (root.ValueKind == JsonValueKind.Object)
                    {
                        type = Str(root, "type");
                        title = Str(root, "title");
                        detail = Str(root, "detail");
                        code = Str(root, "code");
                        traceId = Str(root, "trace_id");
                        if (root.TryGetProperty("errors", out var e) && e.ValueKind == JsonValueKind.Object)
                        {
                            errors = new Dictionary<string, IReadOnlyList<string>>();
                            foreach (var prop in e.EnumerateObject())
                            {
                                var list = new List<string>();
                                if (prop.Value.ValueKind == JsonValueKind.Array)
                                {
                                    foreach (var item in prop.Value.EnumerateArray())
                                        list.Add(item.ValueKind == JsonValueKind.String ? item.GetString()! : item.GetRawText());
                                }
                                else if (prop.Value.ValueKind == JsonValueKind.String)
                                {
                                    list.Add(prop.Value.GetString()!);
                                }
                                errors[prop.Name] = list;
                            }
                        }
                    }
                }
                catch (JsonException)
                {
                    // Not JSON (a proxy HTML page, for example): keep the raw text in Body.
                }
            }

            var message = !string.IsNullOrEmpty(detail) ? detail!
                : !string.IsNullOrEmpty(title) ? title!
                : $"OpenSMS request failed with status {status}";

            return new OpensmsException(status, message, type, title, detail, code, traceId, errors, requestId, retryAfter, body);
        }

        private static string? Str(JsonElement root, string name)
            => root.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;
    }
}
