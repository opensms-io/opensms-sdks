using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
using Opensms.Internal;

namespace Opensms
{
    /// <summary>Number lookups (carrier, validity, porting). Accessed as <c>client.Lookups</c>.</summary>
    public sealed class LookupsResource
    {
        private readonly ApiTransport _t;

        internal LookupsResource(ApiTransport transport) => _t = transport;

        /// <summary>Start a lookup (<c>POST /v1/lookup</c>). Returns a completed lookup (200) or a pending one (202).</summary>
        public Task<Lookup> CreateAsync(CreateLookupParams parameters, RequestOptions? options = null, CancellationToken ct = default)
            => _t.SendAsync<Lookup>(new ApiRequest(HttpMethod.Post, "/v1/lookup")
            {
                JsonBody = Check.NotNull(parameters, nameof(parameters)),
                Idempotency = Idempotency.Send,
                IdempotencyKey = options?.IdempotencyKey,
            }, ct);

        /// <summary>Get a lookup (<c>GET /v1/lookup/{id}</c>).</summary>
        public Task<Lookup> GetAsync(string id, CancellationToken ct = default)
            => _t.SendAsync<Lookup>(new ApiRequest(HttpMethod.Get, "/v1/lookup/" + Wire.Seg(id, nameof(id))), ct);
    }
}
