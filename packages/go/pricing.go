package opensms

import (
	"context"
	"net/http"
)

// Pricing reads the workspace price list, reached as client.Pricing.
type Pricing struct {
	http *transport
}

// Get returns the price list (GET /v1/pricing).
func (r *Pricing) Get(ctx context.Context, params PricingParams) (*PriceList, error) {
	q := newQuery().str("product", params.Product).str("country", params.Country).values()
	return call[PriceList](ctx, r.http, request{method: http.MethodGet, path: "/v1/pricing", query: q})
}
