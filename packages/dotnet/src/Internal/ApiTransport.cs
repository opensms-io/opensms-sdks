using System;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Threading;
using System.Threading.Tasks;

namespace Opensms.Internal
{
    /// <summary>How a request uses the Idempotency-Key header.</summary>
    internal enum Idempotency
    {
        /// <summary>Never send the header.</summary>
        None,
        /// <summary>Always send one: the caller's key or a generated UUIDv4.</summary>
        Send,
    }

    /// <summary>One logical API call (possibly several HTTP attempts).</summary>
    internal sealed class ApiRequest
    {
        public HttpMethod Method { get; }
        public string Path { get; }
        public string Query { get; set; } = "";
        public object? JsonBody { get; set; }
        public Func<HttpContent>? Content { get; set; }
        public Idempotency Idempotency { get; set; } = Idempotency.None;
        public string? IdempotencyKey { get; set; }

        public ApiRequest(HttpMethod method, string path)
        {
            Method = method;
            Path = path;
        }
    }

    /// <summary>
    /// The only code that touches the network. Owns authentication headers,
    /// JSON encoding, Idempotency-Key handling, retries with backoff, per-attempt
    /// timeouts and mapping non-2xx responses to <see cref="OpensmsException"/>.
    /// </summary>
    internal sealed class ApiTransport : IDisposable
    {
        public const string DefaultBaseUrl = "https://opensms.io";
        public const string Version = "0.1.1";
        public const string UserAgent = "opensms-dotnet/" + Version;

        private static readonly HttpMethod Patch = new HttpMethod("PATCH");
        private static readonly TimeSpan MaxRetryAfter = TimeSpan.FromSeconds(60);

        private readonly string _apiKey;
        private readonly HttpClient _http;
        private readonly bool _ownsHttp;
        private readonly Func<TimeSpan, CancellationToken, Task> _sleep;

        public string BaseUrl { get; }
        public int MaxRetries { get; }
        public TimeSpan Timeout { get; }

        public ApiTransport(string apiKey, OpensmsClientOptions options)
        {
            _apiKey = apiKey;
            BaseUrl = (options.BaseUrl ?? DefaultBaseUrl).TrimEnd('/');
            if (!Uri.TryCreate(BaseUrl, UriKind.Absolute, out _))
                throw new ArgumentException($"baseUrl '{options.BaseUrl}' is not an absolute URL", nameof(options));
            MaxRetries = options.MaxRetries < 0 ? throw new ArgumentOutOfRangeException(nameof(options), "maxRetries must be >= 0") : options.MaxRetries;
            Timeout = options.Timeout <= TimeSpan.Zero ? throw new ArgumentOutOfRangeException(nameof(options), "timeout must be positive") : options.Timeout;
            _sleep = options.Sleep ?? ((d, ct) => Task.Delay(d, ct));

            if (options.HttpClient != null)
            {
                _http = options.HttpClient;
                _ownsHttp = false;
            }
            else
            {
                // Per-attempt timeouts are enforced with a CancellationToken below.
                _http = options.HttpMessageHandler != null
                    ? new HttpClient(options.HttpMessageHandler, disposeHandler: false)
                    : new HttpClient();
                _http.Timeout = System.Threading.Timeout.InfiniteTimeSpan;
                _ownsHttp = true;
            }
        }

        public static HttpMethod PatchMethod => Patch;

        /// <summary>Send and decode a JSON response body. Returns <c>default</c> for an empty body or 204.</summary>
        public async Task<T> SendAsync<T>(ApiRequest request, CancellationToken ct)
        {
            var text = await SendRawAsync(request, ct).ConfigureAwait(false);
            if (string.IsNullOrWhiteSpace(text)) return default!;
            try
            {
                return Json.Deserialize<T>(text!)!;
            }
            catch (System.Text.Json.JsonException ex)
            {
                throw new OpensmsException(0, $"OpenSMS response could not be decoded: {ex.Message}", body: text, innerException: ex);
            }
        }

        /// <summary>Send a request whose success response has no useful body (204).</summary>
        public Task SendNoContentAsync(ApiRequest request, CancellationToken ct) => SendRawAsync(request, ct);

        private async Task<string?> SendRawAsync(ApiRequest request, CancellationToken ct)
        {
            // Generated once per call and reused on every retry: that is what makes POST retries safe.
            string? idempotencyKey = request.Idempotency == Idempotency.Send
                ? (string.IsNullOrEmpty(request.IdempotencyKey) ? Guid.NewGuid().ToString() : request.IdempotencyKey)
                : null;
            var retryable = request.Method != HttpMethod.Post || idempotencyKey != null;
            var jsonBytes = request.JsonBody != null ? Json.Serialize(request.JsonBody) : null;
            var url = BaseUrl + request.Path + request.Query;

            for (var attempt = 0; ; attempt++)
            {
                ct.ThrowIfCancellationRequested();
                var canRetry = retryable && attempt < MaxRetries;
                using var message = new HttpRequestMessage(request.Method, url);
                message.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _apiKey);
                message.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
                message.Headers.TryAddWithoutValidation("User-Agent", UserAgent);
                if (idempotencyKey != null) message.Headers.TryAddWithoutValidation("Idempotency-Key", idempotencyKey);
                if (jsonBytes != null)
                {
                    var content = new ByteArrayContent(jsonBytes);
                    content.Headers.ContentType = new MediaTypeHeaderValue("application/json");
                    message.Content = content;
                }
                else if (request.Content != null)
                {
                    message.Content = request.Content();
                }

                using var attemptCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
                attemptCts.CancelAfter(Timeout);

                HttpResponseMessage response;
                string text;
                try
                {
                    response = await _http.SendAsync(message, HttpCompletionOption.ResponseContentRead, attemptCts.Token).ConfigureAwait(false);
                    text = await response.Content.ReadAsStringAsync(attemptCts.Token).ConfigureAwait(false);
                }
                catch (OperationCanceledException) when (ct.IsCancellationRequested)
                {
                    throw; // the caller cancelled: never retry or wrap
                }
                catch (Exception ex) when (ex is HttpRequestException || ex is OperationCanceledException || ex is IOException)
                {
                    if (canRetry)
                    {
                        await _sleep(Backoff(attempt + 1), ct).ConfigureAwait(false);
                        continue;
                    }
                    var reason = ex is OperationCanceledException ? $"timed out after {Timeout.TotalSeconds:0.#} s" : ex.Message;
                    throw new OpensmsException(0, $"OpenSMS request failed: {reason}", innerException: ex);
                }

                using (response)
                {
                    var status = (int)response.StatusCode;
                    if (status >= 200 && status < 300)
                        return status == 204 ? null : text;

                    var retryAfter = ParseRetryAfter(response);
                    if (canRetry && IsRetryStatus(status) && (retryAfter == null || retryAfter.Value <= MaxRetryAfter))
                    {
                        await _sleep(retryAfter ?? Backoff(attempt + 1), ct).ConfigureAwait(false);
                        continue;
                    }

                    throw OpensmsException.FromResponse(
                        status,
                        text,
                        Header(response, "X-Request-ID"),
                        retryAfter?.TotalSeconds);
                }
            }
        }

        private static bool IsRetryStatus(int status)
            => status == 429 || status == 500 || status == 502 || status == 503 || status == 504;

        /// <summary>Full-jitter exponential backoff: random(0, min(8 s, 0.5 s * 2^(n-1))).</summary>
        internal static TimeSpan Backoff(int retryNumber)
        {
            var cap = Math.Min(8.0, 0.5 * Math.Pow(2, retryNumber - 1));
            return TimeSpan.FromSeconds(Random.Shared.NextDouble() * cap);
        }

        private static TimeSpan? ParseRetryAfter(HttpResponseMessage response)
        {
            var typed = response.Headers.RetryAfter;
            if (typed?.Delta != null) return typed.Delta;
            if (typed?.Date != null)
            {
                var d = typed.Date.Value - DateTimeOffset.UtcNow;
                return d < TimeSpan.Zero ? TimeSpan.Zero : d;
            }
            var raw = Header(response, "Retry-After");
            if (raw != null && double.TryParse(raw, NumberStyles.Float, CultureInfo.InvariantCulture, out var secs) && secs >= 0)
                return TimeSpan.FromSeconds(secs);
            return null;
        }

        private static string? Header(HttpResponseMessage response, string name)
            => response.Headers.TryGetValues(name, out var values) ? values.FirstOrDefault() : null;

        public void Dispose()
        {
            if (_ownsHttp) _http.Dispose();
        }
    }
}
