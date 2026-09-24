using System;
using System.Collections.Generic;
using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Opensms.Internal;

namespace Opensms
{
    /// <summary>
    /// Verifies the <c>X-OpenSMS-Signature</c> header on webhook deliveries. Needs
    /// no API key, so a receiver can use it without constructing a client.
    /// </summary>
    /// <remarks>
    /// The header is <c>t=&lt;unix seconds&gt;,v1=&lt;hex&gt;</c> where <c>v1</c> is
    /// HMAC-SHA256 of <c>"&lt;t&gt;.&lt;raw body&gt;"</c> keyed with the full
    /// <c>whsec_...</c> secret as UTF-8 bytes. Always verify the exact raw bytes you
    /// received, before parsing JSON.
    /// </remarks>
    public static class WebhookSignature
    {
        /// <summary>The header carrying the signature.</summary>
        public const string HeaderName = "X-OpenSMS-Signature";

        /// <summary>Default clock-skew tolerance (300 seconds, inclusive).</summary>
        public static readonly TimeSpan DefaultTolerance = TimeSpan.FromSeconds(300);

        private enum Outcome { Valid, Invalid, Expired }

        /// <summary>True when <paramref name="header"/> is a valid, fresh signature of <paramref name="payload"/>.</summary>
        public static bool Verify(string payload, string? header, string? secret, TimeSpan? tolerance = null, DateTimeOffset? now = null)
            => Check(Encoding.UTF8.GetBytes(payload ?? ""), header, secret, tolerance, now) == Outcome.Valid;

        /// <summary>True when <paramref name="header"/> is a valid, fresh signature of the raw <paramref name="payload"/> bytes.</summary>
        public static bool Verify(byte[] payload, string? header, string? secret, TimeSpan? tolerance = null, DateTimeOffset? now = null)
            => Check(payload ?? Array.Empty<byte>(), header, secret, tolerance, now) == Outcome.Valid;

        /// <summary>
        /// Verify and parse a delivery. Throws <see cref="OpensmsException"/> with
        /// <c>Status == 0</c> and <c>Code</c> <c>invalid_signature</c> or
        /// <c>expired_signature</c> (or <c>invalid_payload</c> when the verified body is not an event).
        /// </summary>
        public static WebhookEvent ConstructEvent(string payload, string? header, string? secret, TimeSpan? tolerance = null, DateTimeOffset? now = null)
            => ConstructEvent(Encoding.UTF8.GetBytes(payload ?? ""), header, secret, tolerance, now);

        /// <inheritdoc cref="ConstructEvent(string, string?, string?, TimeSpan?, DateTimeOffset?)"/>
        public static WebhookEvent ConstructEvent(byte[] payload, string? header, string? secret, TimeSpan? tolerance = null, DateTimeOffset? now = null)
        {
            payload ??= Array.Empty<byte>();
            switch (Check(payload, header, secret, tolerance, now))
            {
                case Outcome.Expired:
                    throw new OpensmsException(0, "Webhook signature timestamp is outside the tolerance.", code: "expired_signature");
                case Outcome.Invalid:
                    throw new OpensmsException(0, "Webhook signature is invalid.", code: "invalid_signature");
            }
            try
            {
                return JsonSerializer.Deserialize<WebhookEvent>(payload, Json.Options)
                    ?? throw new JsonException("empty payload");
            }
            catch (JsonException ex)
            {
                throw new OpensmsException(0, "Webhook payload is not a valid event.", code: "invalid_payload", innerException: ex);
            }
        }

        /// <summary>Compute a header value the way the API does (useful for testing your receiver).</summary>
        public static string Sign(string secret, byte[] payload, DateTimeOffset at)
        {
            if (string.IsNullOrWhiteSpace(secret)) throw new ArgumentException("secret is required", nameof(secret));
            var t = at.ToUnixTimeSeconds().ToString(CultureInfo.InvariantCulture);
            return "t=" + t + ",v1=" + Convert.ToHexString(Mac(secret, t, payload)).ToLowerInvariant();
        }

        private static Outcome Check(byte[] payload, string? header, string? secret, TimeSpan? tolerance, DateTimeOffset? now)
        {
            var tol = tolerance ?? DefaultTolerance;
            if (string.IsNullOrWhiteSpace(secret) || tol < TimeSpan.Zero || header == null) return Outcome.Invalid;

            var values = ParseHeader(header);
            if (values == null) return Outcome.Invalid;
            if (!long.TryParse(values["t"], NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out var ts))
                return Outcome.Invalid;

            var nowUnix = (now ?? DateTimeOffset.UtcNow).ToUnixTimeSeconds();
            var tolSeconds = (long)Math.Floor(tol.TotalSeconds);
            if (nowUnix - ts > tolSeconds || ts - nowUnix > tolSeconds) return Outcome.Expired;

            var v1 = values["v1"];
            if (v1.Length != 64) return Outcome.Invalid;
            byte[] want;
            try { want = Convert.FromHexString(v1); }
            catch (FormatException) { return Outcome.Invalid; }

            var got = Mac(secret!, values["t"], payload);
            return CryptographicOperations.FixedTimeEquals(got, want) ? Outcome.Valid : Outcome.Invalid;
        }

        /// <summary>Mirrors the server: comma separated, trimmed, split on the first '=', exactly the keys t and v1.</summary>
        private static Dictionary<string, string>? ParseHeader(string header)
        {
            var values = new Dictionary<string, string>(StringComparer.Ordinal);
            foreach (var part in header.Split(','))
            {
                var trimmed = part.Trim();
                var eq = trimmed.IndexOf('=');
                if (eq <= 0 || eq == trimmed.Length - 1) return null;
                var key = trimmed.Substring(0, eq);
                if (values.ContainsKey(key)) return null;
                values[key] = trimmed.Substring(eq + 1);
            }
            if (values.Count != 2 || !values.ContainsKey("t") || !values.ContainsKey("v1")) return null;
            return values;
        }

        private static byte[] Mac(string secret, string timestamp, byte[] body)
        {
            using var h = new HMACSHA256(Encoding.UTF8.GetBytes(secret));
            var prefix = Encoding.UTF8.GetBytes(timestamp + ".");
            h.TransformBlock(prefix, 0, prefix.Length, null, 0);
            h.TransformFinalBlock(body, 0, body.Length);
            return h.Hash!;
        }
    }
}
