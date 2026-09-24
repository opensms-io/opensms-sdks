using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
using Opensms.Internal;

namespace Opensms
{
    /// <summary>Sandbox inspection. Accessed as <c>client.Sandbox</c>.</summary>
    public sealed class SandboxResource
    {
        private readonly ApiTransport _t;

        internal SandboxResource(ApiTransport transport) => _t = transport;

        /// <summary>Messages sent with a test key, with rendered text including OTP codes (<c>GET /v1/sandbox/messages</c>).</summary>
        public Task<Page<SandboxMessage>> ListMessagesAsync(ListParams? parameters = null, CancellationToken ct = default)
            => _t.SendAsync<Page<SandboxMessage>>(new ApiRequest(HttpMethod.Get, "/v1/sandbox/messages") { Query = Wire.Query(parameters).ToString() }, ct);
    }
}
