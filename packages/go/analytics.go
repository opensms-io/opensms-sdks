package opensms

import (
	"context"
	"net/http"
	"net/url"
)

// Analytics reads delivery and spend metrics, reached as client.Analytics.
type Analytics struct {
	http *transport
}

func analyticsQuery(p AnalyticsParams) url.Values {
	return newQuery().
		str("currency", p.Currency).
		str("range", p.Range).
		time("from", p.From).
		time("to", p.To).
		str("bucket", p.Bucket).
		values()
}

// Overview returns totals for the period (GET /v1/analytics/overview).
func (r *Analytics) Overview(ctx context.Context, params AnalyticsParams) (*AnalyticsOverview, error) {
	return call[AnalyticsOverview](ctx, r.http, request{method: http.MethodGet, path: "/v1/analytics/overview", query: analyticsQuery(params)})
}

// ByCountry breaks metrics down by country (GET /v1/analytics/by-country).
func (r *Analytics) ByCountry(ctx context.Context, params AnalyticsParams) ([]AnalyticsBreakdown, error) {
	return callSlice[AnalyticsBreakdown](ctx, r.http, request{method: http.MethodGet, path: "/v1/analytics/by-country", query: analyticsQuery(params)})
}

// ByCarrier breaks metrics down by carrier (GET /v1/analytics/by-carrier).
func (r *Analytics) ByCarrier(ctx context.Context, params AnalyticsParams) ([]AnalyticsBreakdown, error) {
	return callSlice[AnalyticsBreakdown](ctx, r.http, request{method: http.MethodGet, path: "/v1/analytics/by-carrier", query: analyticsQuery(params)})
}

// BySenderID breaks metrics down by sender ID
// (GET /v1/analytics/by-sender-id).
func (r *Analytics) BySenderID(ctx context.Context, params AnalyticsParams) ([]AnalyticsBreakdown, error) {
	return callSlice[AnalyticsBreakdown](ctx, r.http, request{method: http.MethodGet, path: "/v1/analytics/by-sender-id", query: analyticsQuery(params)})
}

// Timeseries returns metrics per bucket (GET /v1/analytics/timeseries).
func (r *Analytics) Timeseries(ctx context.Context, params AnalyticsParams) ([]AnalyticsPoint, error) {
	return callSlice[AnalyticsPoint](ctx, r.http, request{method: http.MethodGet, path: "/v1/analytics/timeseries", query: analyticsQuery(params)})
}
