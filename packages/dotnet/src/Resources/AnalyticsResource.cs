using System.Collections.Generic;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
using Opensms.Internal;

namespace Opensms
{
    /// <summary>Delivery and spend analytics. Accessed as <c>client.Analytics</c>.</summary>
    public sealed class AnalyticsResource
    {
        private readonly ApiTransport _t;

        internal AnalyticsResource(ApiTransport transport) => _t = transport;

        /// <summary>Totals for the period (<c>GET /v1/analytics/overview</c>).</summary>
        public Task<AnalyticsOverview> OverviewAsync(AnalyticsQuery? query = null, CancellationToken ct = default)
            => _t.SendAsync<AnalyticsOverview>(Build("/v1/analytics/overview", query), ct);

        /// <summary>Metrics per destination country (<c>GET /v1/analytics/by-country</c>).</summary>
        public Task<List<AnalyticsBreakdown>> ByCountryAsync(AnalyticsQuery? query = null, CancellationToken ct = default)
            => _t.SendAsync<List<AnalyticsBreakdown>>(Build("/v1/analytics/by-country", query), ct);

        /// <summary>Metrics per carrier (<c>GET /v1/analytics/by-carrier</c>).</summary>
        public Task<List<AnalyticsBreakdown>> ByCarrierAsync(AnalyticsQuery? query = null, CancellationToken ct = default)
            => _t.SendAsync<List<AnalyticsBreakdown>>(Build("/v1/analytics/by-carrier", query), ct);

        /// <summary>Metrics per sender ID (<c>GET /v1/analytics/by-sender-id</c>).</summary>
        public Task<List<AnalyticsBreakdown>> BySenderIdAsync(AnalyticsQuery? query = null, CancellationToken ct = default)
            => _t.SendAsync<List<AnalyticsBreakdown>>(Build("/v1/analytics/by-sender-id", query), ct);

        /// <summary>Metrics per time bucket (<c>GET /v1/analytics/timeseries</c>).</summary>
        public Task<List<AnalyticsPoint>> TimeseriesAsync(AnalyticsQuery? query = null, CancellationToken ct = default)
            => _t.SendAsync<List<AnalyticsPoint>>(Build("/v1/analytics/timeseries", query), ct);

        private static ApiRequest Build(string path, AnalyticsQuery? q) => new ApiRequest(HttpMethod.Get, path)
        {
            Query = Wire.Query()
                .Add("currency", q?.Currency)
                .Add("range", q?.Range)
                .Add("from", q?.From)
                .Add("to", q?.To)
                .Add("bucket", q?.Bucket)
                .ToString(),
        };
    }
}
