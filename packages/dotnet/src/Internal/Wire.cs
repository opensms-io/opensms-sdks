using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace Opensms.Internal
{
    /// <summary>
    /// Helpers that turn SDK shapes into exact paths and query strings. Not part
    /// of the public API.
    /// </summary>
    internal static class Wire
    {
        /// <summary>URL-escape one path segment after checking it is non-empty (argument error, no request).</summary>
        public static string Seg(string? value, string name)
        {
            if (string.IsNullOrWhiteSpace(value))
                throw new ArgumentException($"{name} is required", name);
            return Uri.EscapeDataString(value);
        }

        /// <summary>Format an instant as RFC 3339 UTC (<c>2026-09-24T10:00:00Z</c>).</summary>
        public static string FormatTimestamp(DateTimeOffset value)
            => value.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture);

        /// <summary>Accumulates query parameters, skipping unset values.</summary>
        public sealed class QueryBuilder
        {
            private readonly List<KeyValuePair<string, string>> _parts = new List<KeyValuePair<string, string>>();

            public QueryBuilder Add(string key, string? value)
            {
                if (value != null) _parts.Add(new KeyValuePair<string, string>(key, value));
                return this;
            }

            public QueryBuilder Add(string key, int? value)
                => Add(key, value?.ToString(CultureInfo.InvariantCulture));

            public QueryBuilder Add(string key, long? value)
                => Add(key, value?.ToString(CultureInfo.InvariantCulture));

            public QueryBuilder Add(string key, bool? value)
                => Add(key, value == null ? null : (value.Value ? "true" : "false"));

            public QueryBuilder Add(string key, DateTimeInput? value)
                => Add(key, value?.Value);

            /// <summary>List values are joined with commas (<c>countries=KE,NG</c>).</summary>
            public QueryBuilder Add(string key, IEnumerable<string>? values)
                => Add(key, values == null ? null : string.Join(",", values));

            /// <summary>Returns <c>""</c> when empty, else <c>?a=1&amp;b=2</c> with keys and values escaped.</summary>
            public override string ToString()
            {
                if (_parts.Count == 0) return "";
                var sb = new StringBuilder("?");
                for (var i = 0; i < _parts.Count; i++)
                {
                    if (i > 0) sb.Append('&');
                    sb.Append(Uri.EscapeDataString(_parts[i].Key)).Append('=').Append(Uri.EscapeDataString(_parts[i].Value));
                }
                return sb.ToString();
            }
        }

        public static QueryBuilder Query() => new QueryBuilder();

        /// <summary>Start a query with the common <c>limit</c> and <c>cursor</c> keys.</summary>
        public static QueryBuilder Query(ListParams? p) => new QueryBuilder().Add("limit", p?.Limit).Add("cursor", p?.Cursor);
    }
}
