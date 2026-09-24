using System.Collections.Generic;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
using Opensms.Internal;

namespace Opensms
{
    /// <summary>The public country catalog. Accessed as <c>client.Countries</c>.</summary>
    public sealed class CountriesResource
    {
        private readonly ApiTransport _t;

        internal CountriesResource(ApiTransport transport) => _t = transport;

        /// <summary>Supported countries (<c>GET /v1/countries</c>).</summary>
        public Task<List<Country>> ListAsync(CancellationToken ct = default)
            => _t.SendAsync<List<Country>>(new ApiRequest(HttpMethod.Get, "/v1/countries"), ct);

        /// <summary>Carriers in a country (<c>GET /v1/countries/{iso2}/carriers</c>).</summary>
        public Task<List<Carrier>> CarriersAsync(string iso2, CancellationToken ct = default)
            => _t.SendAsync<List<Carrier>>(new ApiRequest(HttpMethod.Get, "/v1/countries/" + Wire.Seg(iso2, nameof(iso2)) + "/carriers"), ct);

        /// <summary>Delivery routes into a country (<c>GET /v1/countries/{iso2}/routes</c>).</summary>
        public Task<List<Route>> RoutesAsync(string iso2, CancellationToken ct = default)
            => _t.SendAsync<List<Route>>(new ApiRequest(HttpMethod.Get, "/v1/countries/" + Wire.Seg(iso2, nameof(iso2)) + "/routes"), ct);

        /// <summary>Messaging rules for a country (<c>GET /v1/countries/{iso2}/compliance</c>).</summary>
        public Task<CountryRules> ComplianceAsync(string iso2, CancellationToken ct = default)
            => _t.SendAsync<CountryRules>(new ApiRequest(HttpMethod.Get, "/v1/countries/" + Wire.Seg(iso2, nameof(iso2)) + "/compliance"), ct);
    }
}
