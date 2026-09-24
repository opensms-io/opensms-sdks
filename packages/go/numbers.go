package opensms

import (
	"context"
	"net/http"
)

// Numbers manages virtual numbers, reached as client.Numbers. Everything
// except List and Available requires a live key.
type Numbers struct {
	http *transport
}

// List returns a page of assigned numbers (GET /v1/numbers).
func (r *Numbers) List(ctx context.Context, params ListParams) (*Page[Number], error) {
	return call[Page[Number]](ctx, r.http, request{method: http.MethodGet, path: "/v1/numbers", query: listQuery(params)})
}

// Available lists numbers that can be assigned (GET /v1/numbers/available).
func (r *Numbers) Available(ctx context.Context, params AvailableNumbersParams) ([]Number, error) {
	q := newQuery().str("country", params.Country).str("kind", params.Kind).values()
	return callSlice[Number](ctx, r.http, request{method: http.MethodGet, path: "/v1/numbers/available", query: q})
}

// Assign assigns a number and charges the wallet (POST /v1/numbers).
func (r *Numbers) Assign(ctx context.Context, params AssignNumberParams, opts ...CallOption) (*Number, error) {
	return call[Number](ctx, r.http, request{method: http.MethodPost, path: "/v1/numbers", body: params, idempotent: true, opts: applyCallOptions(opts)})
}

// Release releases a number (DELETE /v1/numbers/{id}).
func (r *Numbers) Release(ctx context.Context, id string) error {
	if err := requireID("id", id); err != nil {
		return err
	}
	return r.http.do(ctx, request{method: http.MethodDelete, path: "/v1/numbers/" + escape(id)}, nil)
}

// ListRules returns a page of inbound rules (GET /v1/numbers/{id}/rules).
func (r *Numbers) ListRules(ctx context.Context, id string, params ListParams) (*Page[NumberRule], error) {
	if err := requireID("id", id); err != nil {
		return nil, err
	}
	return call[Page[NumberRule]](ctx, r.http, request{method: http.MethodGet, path: "/v1/numbers/" + escape(id) + "/rules", query: listQuery(params)})
}

// CreateRule adds an inbound rule (POST /v1/numbers/{id}/rules).
func (r *Numbers) CreateRule(ctx context.Context, id string, params NumberRuleParams, opts ...CallOption) (*NumberRule, error) {
	if err := requireID("id", id); err != nil {
		return nil, err
	}
	return call[NumberRule](ctx, r.http, request{method: http.MethodPost, path: "/v1/numbers/" + escape(id) + "/rules", body: params, idempotent: true, opts: applyCallOptions(opts)})
}

// UpdateRule replaces an inbound rule (PUT /v1/numbers/{id}/rules/{rule_id}).
func (r *Numbers) UpdateRule(ctx context.Context, id, ruleID string, params NumberRuleParams) (*NumberRule, error) {
	if err := requireID("id", id); err != nil {
		return nil, err
	}
	if err := requireID("ruleID", ruleID); err != nil {
		return nil, err
	}
	return call[NumberRule](ctx, r.http, request{method: http.MethodPut, path: "/v1/numbers/" + escape(id) + "/rules/" + escape(ruleID), body: params})
}

// DeleteRule deletes an inbound rule (DELETE /v1/numbers/{id}/rules/{rule_id}).
func (r *Numbers) DeleteRule(ctx context.Context, id, ruleID string) error {
	if err := requireID("id", id); err != nil {
		return err
	}
	if err := requireID("ruleID", ruleID); err != nil {
		return err
	}
	return r.http.do(ctx, request{method: http.MethodDelete, path: "/v1/numbers/" + escape(id) + "/rules/" + escape(ruleID)}, nil)
}
