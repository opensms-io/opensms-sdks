using System;
using System.Collections.Generic;
using System.Net;
using System.Net.Http;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace Opensms.Tests
{
    /// <summary>A recorded outgoing request (headers and body captured before disposal).</summary>
    internal sealed class Recorded
    {
        public HttpMethod Method = HttpMethod.Get;
        public Uri Uri = new Uri("http://invalid/");
        public string RawUri = "";
        public Dictionary<string, string> Headers = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        public string? ContentType;
        public string Body = "";

        public string? Header(string name) => Headers.TryGetValue(name, out var v) ? v : null;
    }

    /// <summary>Records requests and replays a scripted sequence of responses (or thrown exceptions).</summary>
    internal sealed class MockHandler : HttpMessageHandler
    {
        private readonly Queue<Func<HttpResponseMessage>> _script = new Queue<Func<HttpResponseMessage>>();
        private Func<HttpResponseMessage>? _last;
        public readonly List<Recorded> Requests = new List<Recorded>();

        public MockHandler Then(Func<HttpResponseMessage> step)
        {
            _script.Enqueue(step);
            return this;
        }

        public MockHandler Then(HttpStatusCode status, string? body = null, string contentType = "application/json", params (string, string)[] headers)
            => Then(() => Response(status, body, contentType, headers));

        public MockHandler Throw(Exception ex) => Then(() => throw ex);

        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            var r = new Recorded
            {
                Method = request.Method,
                Uri = request.RequestUri!,
                RawUri = request.RequestUri!.OriginalString,
            };
            foreach (var h in request.Headers) r.Headers[h.Key] = string.Join(",", h.Value);
            if (request.Content != null)
            {
                r.ContentType = request.Content.Headers.ContentType?.ToString();
                r.Body = await request.Content.ReadAsStringAsync(ct);
            }
            Requests.Add(r);

            var step = _script.Count > 0 ? _script.Dequeue() : _last ?? throw new InvalidOperationException("no scripted response");
            _last = step;
            return step();
        }

        public static HttpResponseMessage Response(HttpStatusCode status, string? body, string contentType = "application/json", params (string, string)[] headers)
        {
            var res = new HttpResponseMessage(status);
            if (body != null)
            {
                res.Content = new StringContent(body, Encoding.UTF8);
                res.Content.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue(contentType);
            }
            else
            {
                res.Content = new ByteArrayContent(Array.Empty<byte>());
            }
            foreach (var (k, v) in headers) res.Headers.TryAddWithoutValidation(k, v);
            return res;
        }
    }

    internal static class Fx
    {
        public const string TestKey = "sk_test_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
        // Split so secret scanners do not mistake the placeholder for a real key.
        public const string LiveKey = "sk_live_" + "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
        public const string MessageJson = "{\"id\":\"11111111-1111-1111-1111-111111111111\",\"to\":\"+254700000012\",\"status\":\"queued\",\"price\":\"0.000000\",\"currency\":\"KES\",\"created_at\":\"2026-09-24T08:25:59.396241+03:00\",\"brand_new_field\":{\"x\":1}}";
        public const string Problem400 = "{\"type\":\"about:blank\",\"title\":\"Bad Request\",\"status\":400,\"detail\":\"to must be an E.164 phone number\"}";

        public static (OpensmsClient Client, MockHandler Handler, List<TimeSpan> Sleeps) Client(
            Action<MockHandler> script, string? baseUrl = "http://mock.test", int maxRetries = 2, string key = TestKey)
        {
            var h = new MockHandler();
            script(h);
            var sleeps = new List<TimeSpan>();
            var client = new OpensmsClient(key, new OpensmsClientOptions
            {
                BaseUrl = baseUrl,
                HttpMessageHandler = h,
                MaxRetries = maxRetries,
                Sleep = (d, _) => { sleeps.Add(d); return Task.CompletedTask; },
            });
            return (client, h, sleeps);
        }
    }
}
