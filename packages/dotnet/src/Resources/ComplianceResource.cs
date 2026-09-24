using System.Collections.Generic;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
using Opensms.Internal;

namespace Opensms
{
    /// <summary>Country messaging rules and content rules. Accessed as <c>client.Compliance</c>.</summary>
    public sealed class ComplianceResource
    {
        private readonly ApiTransport _t;

        internal ComplianceResource(ApiTransport transport) => _t = transport;

        /// <summary>Rules for every country (<c>GET /v1/compliance/countries</c>).</summary>
        public Task<List<CountryRules>> ListCountriesAsync(CancellationToken ct = default)
            => _t.SendAsync<List<CountryRules>>(new ApiRequest(HttpMethod.Get, "/v1/compliance/countries"), ct);

        /// <summary>Rules for one country (<c>GET /v1/compliance/countries/{iso2}</c>).</summary>
        public Task<CountryRules> GetCountryAsync(string iso2, CancellationToken ct = default)
            => _t.SendAsync<CountryRules>(new ApiRequest(HttpMethod.Get, "/v1/compliance/countries/" + Wire.Seg(iso2, nameof(iso2))), ct);

        /// <summary>Platform content rules (<c>GET /v1/content-rules</c>).</summary>
        public Task<List<ContentRule>> ListContentRulesAsync(CancellationToken ct = default)
            => _t.SendAsync<List<ContentRule>>(new ApiRequest(HttpMethod.Get, "/v1/content-rules"), ct);
    }
}
