package opensms

import (
	"context"
	"net/http"
)

// Templates manages message templates, reached as client.Templates.
type Templates struct {
	http *transport
}

// List returns a page of templates (GET /v1/templates).
func (r *Templates) List(ctx context.Context, params ListParams) (*Page[Template], error) {
	return call[Page[Template]](ctx, r.http, request{method: http.MethodGet, path: "/v1/templates", query: listQuery(params)})
}

// Create creates a template (POST /v1/templates). Variables are parsed from
// {{name}} placeholders by the server.
func (r *Templates) Create(ctx context.Context, params CreateTemplateParams, opts ...CallOption) (*Template, error) {
	return call[Template](ctx, r.http, request{method: http.MethodPost, path: "/v1/templates", body: params, idempotent: true, opts: applyCallOptions(opts)})
}

// Get fetches a template (GET /v1/templates/{id}).
func (r *Templates) Get(ctx context.Context, id string) (*Template, error) {
	if err := requireID("id", id); err != nil {
		return nil, err
	}
	return call[Template](ctx, r.http, request{method: http.MethodGet, path: "/v1/templates/" + escape(id)})
}

// Update changes the given fields of a template (PATCH /v1/templates/{id}).
func (r *Templates) Update(ctx context.Context, id string, params UpdateTemplateParams) (*Template, error) {
	if err := requireID("id", id); err != nil {
		return nil, err
	}
	return call[Template](ctx, r.http, request{method: http.MethodPatch, path: "/v1/templates/" + escape(id), body: params})
}

// Delete deletes a template (DELETE /v1/templates/{id}).
func (r *Templates) Delete(ctx context.Context, id string) error {
	if err := requireID("id", id); err != nil {
		return err
	}
	return r.http.do(ctx, request{method: http.MethodDelete, path: "/v1/templates/" + escape(id)}, nil)
}
