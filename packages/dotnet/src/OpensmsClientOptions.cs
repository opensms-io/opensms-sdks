using System;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;

namespace Opensms
{
    /// <summary>Optional settings for <see cref="OpensmsClient"/>.</summary>
    public sealed class OpensmsClientOptions
    {
        /// <summary>API base URL. Defaults to <c>https://opensms.io</c>; trailing slashes are stripped.</summary>
        public string? BaseUrl { get; set; }

        /// <summary>Per-attempt timeout covering connect and read. Defaults to 30 seconds.</summary>
        public TimeSpan Timeout { get; set; } = TimeSpan.FromSeconds(30);

        /// <summary>Retries after the first attempt (so 3 attempts in total by default). <c>0</c> disables retries.</summary>
        public int MaxRetries { get; set; } = 2;

        /// <summary>
        /// Supply your own <see cref="System.Net.Http.HttpClient"/> (for example from
        /// <c>IHttpClientFactory</c>). It is not disposed by the SDK. Its own
        /// <c>Timeout</c> still applies on top of <see cref="Timeout"/>.
        /// </summary>
        public HttpClient? HttpClient { get; set; }

        /// <summary>
        /// Supply a message handler (for tests or custom networking). Ignored when
        /// <see cref="HttpClient"/> is set. Not disposed by the SDK.
        /// </summary>
        public HttpMessageHandler? HttpMessageHandler { get; set; }

        /// <summary>
        /// Replace the delay used between retries. Tests inject a zero-delay sleeper
        /// that records the requested delays. Defaults to <see cref="Task.Delay(TimeSpan, CancellationToken)"/>.
        /// </summary>
        public Func<TimeSpan, CancellationToken, Task>? Sleep { get; set; }
    }
}
