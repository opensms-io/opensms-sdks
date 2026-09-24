package opensms

import (
	"context"
	"net/http"
)

// Compliance reads country and content rules, reached as client.Compliance.
type Compliance struct {
	http *transport
}

// ListCountries returns the rules for every country
// (GET /v1/compliance/countries).
func (r *Compliance) ListCountries(ctx context.Context) ([]CountryRules, error) {
	return callSlice[CountryRules](ctx, r.http, request{method: http.MethodGet, path: "/v1/compliance/countries"})
}

// GetCountry returns one country's rules (GET /v1/compliance/countries/{iso2}).
func (r *Compliance) GetCountry(ctx context.Context, iso2 string) (*CountryRules, error) {
	if err := requireID("iso2", iso2); err != nil {
		return nil, err
	}
	return call[CountryRules](ctx, r.http, request{method: http.MethodGet, path: "/v1/compliance/countries/" + escape(iso2)})
}

// ListContentRules returns the platform content rules (GET /v1/content-rules).
func (r *Compliance) ListContentRules(ctx context.Context) ([]ContentRule, error) {
	return callSlice[ContentRule](ctx, r.http, request{method: http.MethodGet, path: "/v1/content-rules"})
}
