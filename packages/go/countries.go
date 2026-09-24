package opensms

import (
	"context"
	"net/http"
)

// Countries reads the public country catalog, reached as client.Countries.
type Countries struct {
	http *transport
}

// List returns the active countries (GET /v1/countries).
func (r *Countries) List(ctx context.Context) ([]Country, error) {
	return callSlice[Country](ctx, r.http, request{method: http.MethodGet, path: "/v1/countries"})
}

// Carriers returns a country's carriers (GET /v1/countries/{iso2}/carriers).
func (r *Countries) Carriers(ctx context.Context, iso2 string) ([]Carrier, error) {
	if err := requireID("iso2", iso2); err != nil {
		return nil, err
	}
	return callSlice[Carrier](ctx, r.http, request{method: http.MethodGet, path: "/v1/countries/" + escape(iso2) + "/carriers"})
}

// Routes returns a country's routable routes (GET /v1/countries/{iso2}/routes).
func (r *Countries) Routes(ctx context.Context, iso2 string) ([]Route, error) {
	if err := requireID("iso2", iso2); err != nil {
		return nil, err
	}
	return callSlice[Route](ctx, r.http, request{method: http.MethodGet, path: "/v1/countries/" + escape(iso2) + "/routes"})
}

// Compliance returns a country's compliance rules
// (GET /v1/countries/{iso2}/compliance).
func (r *Countries) Compliance(ctx context.Context, iso2 string) (*CountryRules, error) {
	if err := requireID("iso2", iso2); err != nil {
		return nil, err
	}
	return call[CountryRules](ctx, r.http, request{method: http.MethodGet, path: "/v1/countries/" + escape(iso2) + "/compliance"})
}
