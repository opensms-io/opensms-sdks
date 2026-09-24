using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
using Opensms.Internal;

namespace Opensms
{
    /// <summary>The do-not-send list. Accessed as <c>client.Suppressions</c>.</summary>
    public sealed class SuppressionsResource
    {
        private readonly ApiTransport _t;

        internal SuppressionsResource(ApiTransport transport) => _t = transport;

        /// <summary>List suppressions (<c>GET /v1/compliance/suppressions</c>).</summary>
        public Task<Page<Suppression>> ListAsync(ListParams? parameters = null, CancellationToken ct = default)
            => _t.SendAsync<Page<Suppression>>(new ApiRequest(HttpMethod.Get, "/v1/compliance/suppressions") { Query = Wire.Query(parameters).ToString() }, ct);

        /// <summary>Suppress one number (<c>POST /v1/compliance/suppressions</c>). Not auto-retried.</summary>
        public Task<Suppression> CreateAsync(SuppressionParams parameters, CancellationToken ct = default)
            => _t.SendAsync<Suppression>(new ApiRequest(HttpMethod.Post, "/v1/compliance/suppressions")
            {
                JsonBody = Check.NotNull(parameters, nameof(parameters)),
            }, ct);

        /// <summary>Suppress many numbers (<c>POST /v1/compliance/suppressions/import</c>). Not auto-retried.</summary>
        public Task<SuppressionImportResult> ImportAsync(IEnumerable<SuppressionParams> items, CancellationToken ct = default)
            => _t.SendAsync<SuppressionImportResult>(new ApiRequest(HttpMethod.Post, "/v1/compliance/suppressions/import")
            {
                JsonBody = new ImportBody { Items = Check.NotNull(items, nameof(items)).ToList() },
            }, ct);

        /// <summary>Remove a suppression (<c>DELETE /v1/compliance/suppressions/{id}</c>).</summary>
        public Task DeleteAsync(long id, CancellationToken ct = default)
            => _t.SendNoContentAsync(new ApiRequest(HttpMethod.Delete,
                "/v1/compliance/suppressions/" + id.ToString(CultureInfo.InvariantCulture)), ct);

        private sealed class ImportBody
        {
            [System.Text.Json.Serialization.JsonPropertyName("items")]
            public List<SuppressionParams> Items { get; set; } = new List<SuppressionParams>();
        }
    }
}
