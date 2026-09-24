package opensms

import (
	"context"
	"net/http"
	"strconv"
)

// Suppressions manages the do-not-send list, reached as client.Suppressions.
type Suppressions struct {
	http *transport
}

// List returns a page of suppressions (GET /v1/compliance/suppressions).
func (r *Suppressions) List(ctx context.Context, params ListParams) (*Page[Suppression], error) {
	return call[Page[Suppression]](ctx, r.http, request{method: http.MethodGet, path: "/v1/compliance/suppressions", query: listQuery(params)})
}

// Create suppresses a number (POST /v1/compliance/suppressions). Never
// retried.
func (r *Suppressions) Create(ctx context.Context, params CreateSuppressionParams) (*Suppression, error) {
	return call[Suppression](ctx, r.http, request{method: http.MethodPost, path: "/v1/compliance/suppressions", body: params, noRetry: true})
}

// Import suppresses many numbers (POST /v1/compliance/suppressions/import).
// Never retried.
func (r *Suppressions) Import(ctx context.Context, items []SuppressionInput) (*SuppressionImportResult, error) {
	if items == nil {
		items = []SuppressionInput{}
	}
	body := struct {
		Items []SuppressionInput `json:"items"`
	}{items}
	return call[SuppressionImportResult](ctx, r.http, request{method: http.MethodPost, path: "/v1/compliance/suppressions/import", body: body, noRetry: true})
}

// Delete removes a suppression (DELETE /v1/compliance/suppressions/{id}).
func (r *Suppressions) Delete(ctx context.Context, id int64) error {
	return r.http.do(ctx, request{method: http.MethodDelete, path: "/v1/compliance/suppressions/" + strconv.FormatInt(id, 10)}, nil)
}
