package opensms

import (
	"context"
	"net/http"
)

// Lookups is the number lookup resource, reached as client.Lookups.
type Lookups struct {
	http *transport
}

// Create runs a lookup (POST /v1/lookup). The result is completed (200) or
// still pending (202); poll Get for pending lookups.
func (r *Lookups) Create(ctx context.Context, params CreateLookupParams, opts ...CallOption) (*Lookup, error) {
	var out Lookup
	err := r.http.do(ctx, request{method: http.MethodPost, path: "/v1/lookup", body: params, idempotent: true, opts: applyCallOptions(opts)}, &out)
	if err != nil {
		return nil, err
	}
	return &out, nil
}

// Get fetches a lookup (GET /v1/lookup/{id}).
func (r *Lookups) Get(ctx context.Context, id string) (*Lookup, error) {
	if err := requireID("id", id); err != nil {
		return nil, err
	}
	var out Lookup
	if err := r.http.do(ctx, request{method: http.MethodGet, path: "/v1/lookup/" + escape(id)}, &out); err != nil {
		return nil, err
	}
	return &out, nil
}
