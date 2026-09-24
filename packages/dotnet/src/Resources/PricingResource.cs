using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
using Opensms.Internal;

namespace Opensms
{
    /// <summary>Your price list. Accessed as <c>client.Pricing</c>.</summary>
    public sealed class PricingResource
    {
        private readonly ApiTransport _t;

        internal PricingResource(ApiTransport transport) => _t = transport;

        /// <summary>Get prices (<c>GET /v1/pricing</c>).</summary>
        public Task<PriceList> GetAsync(PricingParams? parameters = null, CancellationToken ct = default)
            => _t.SendAsync<PriceList>(new ApiRequest(HttpMethod.Get, "/v1/pricing")
            {
                Query = Wire.Query().Add("product", parameters?.Product).Add("country", parameters?.Country).ToString(),
            }, ct);
    }
}
