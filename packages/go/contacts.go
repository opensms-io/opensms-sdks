package opensms

import (
	"context"
	"net/http"
)

// Contacts is the contact book, reached as client.Contacts.
type Contacts struct {
	http *transport
}

// List returns a page of contacts (GET /v1/contacts).
func (r *Contacts) List(ctx context.Context, params ListParams) (*Page[Contact], error) {
	return call[Page[Contact]](ctx, r.http, request{method: http.MethodGet, path: "/v1/contacts", query: listQuery(params)})
}

// Create creates a contact (POST /v1/contacts). A duplicate e164 returns 409.
func (r *Contacts) Create(ctx context.Context, params CreateContactParams, opts ...CallOption) (*Contact, error) {
	return call[Contact](ctx, r.http, request{method: http.MethodPost, path: "/v1/contacts", body: params, idempotent: true, opts: applyCallOptions(opts)})
}

// Get fetches a contact (GET /v1/contacts/{id}).
func (r *Contacts) Get(ctx context.Context, id string) (*Contact, error) {
	if err := requireID("id", id); err != nil {
		return nil, err
	}
	return call[Contact](ctx, r.http, request{method: http.MethodGet, path: "/v1/contacts/" + escape(id)})
}

// Update changes the given fields of a contact (PATCH /v1/contacts/{id}).
func (r *Contacts) Update(ctx context.Context, id string, params UpdateContactParams) (*Contact, error) {
	if err := requireID("id", id); err != nil {
		return nil, err
	}
	return call[Contact](ctx, r.http, request{method: http.MethodPatch, path: "/v1/contacts/" + escape(id), body: params})
}

// Delete deletes a contact (DELETE /v1/contacts/{id}).
func (r *Contacts) Delete(ctx context.Context, id string) error {
	if err := requireID("id", id); err != nil {
		return err
	}
	return r.http.do(ctx, request{method: http.MethodDelete, path: "/v1/contacts/" + escape(id)}, nil)
}
