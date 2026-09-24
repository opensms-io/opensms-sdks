package opensms

import (
	"context"
	"net/http"
)

// ContactGroups manages contact groups, reached as client.ContactGroups.
type ContactGroups struct {
	http *transport
}

// List returns a page of groups (GET /v1/contact-groups).
func (r *ContactGroups) List(ctx context.Context, params ListParams) (*Page[ContactGroup], error) {
	return call[Page[ContactGroup]](ctx, r.http, request{method: http.MethodGet, path: "/v1/contact-groups", query: listQuery(params)})
}

// Create creates a group (POST /v1/contact-groups).
func (r *ContactGroups) Create(ctx context.Context, params CreateContactGroupParams, opts ...CallOption) (*ContactGroup, error) {
	return call[ContactGroup](ctx, r.http, request{method: http.MethodPost, path: "/v1/contact-groups", body: params, idempotent: true, opts: applyCallOptions(opts)})
}

// Get fetches a group (GET /v1/contact-groups/{id}).
func (r *ContactGroups) Get(ctx context.Context, id string) (*ContactGroup, error) {
	if err := requireID("id", id); err != nil {
		return nil, err
	}
	return call[ContactGroup](ctx, r.http, request{method: http.MethodGet, path: "/v1/contact-groups/" + escape(id)})
}

// Update changes a group's name or members (PATCH /v1/contact-groups/{id}).
func (r *ContactGroups) Update(ctx context.Context, id string, params UpdateContactGroupParams) (*ContactGroup, error) {
	if err := requireID("id", id); err != nil {
		return nil, err
	}
	return call[ContactGroup](ctx, r.http, request{method: http.MethodPatch, path: "/v1/contact-groups/" + escape(id), body: params})
}

// Delete deletes a group (DELETE /v1/contact-groups/{id}).
func (r *ContactGroups) Delete(ctx context.Context, id string) error {
	if err := requireID("id", id); err != nil {
		return err
	}
	return r.http.do(ctx, request{method: http.MethodDelete, path: "/v1/contact-groups/" + escape(id)}, nil)
}

// Send sends text or a template to every member and returns the running
// batch (POST /v1/contact-groups/{id}/send).
func (r *ContactGroups) Send(ctx context.Context, id string, params GroupSendParams, opts ...CallOption) (*Batch, error) {
	if err := requireID("id", id); err != nil {
		return nil, err
	}
	return call[Batch](ctx, r.http, request{method: http.MethodPost, path: "/v1/contact-groups/" + escape(id) + "/send", body: params, idempotent: true, opts: applyCallOptions(opts)})
}
