package opensms

import (
	"context"
	"net/http"
	"strings"
)

// SenderIDs manages sender IDs, drafts and documents, reached as
// client.SenderIDs. Document upload and download are console only.
type SenderIDs struct {
	http *transport
}

// List returns a page of sender IDs (GET /v1/sender-ids).
func (r *SenderIDs) List(ctx context.Context, params ListParams) (*Page[SenderID], error) {
	return call[Page[SenderID]](ctx, r.http, request{method: http.MethodGet, path: "/v1/sender-ids", query: listQuery(params)})
}

// Get fetches a sender ID with its registrations (GET /v1/sender-ids/{id}).
func (r *SenderIDs) Get(ctx context.Context, id string) (*SenderID, error) {
	if err := requireID("id", id); err != nil {
		return nil, err
	}
	return call[SenderID](ctx, r.http, request{method: http.MethodGet, path: "/v1/sender-ids/" + escape(id)})
}

// Create submits a sender ID registration (POST /v1/sender-ids). It may
// charge fees (see Quote), so it is never retried.
func (r *SenderIDs) Create(ctx context.Context, params CreateSenderIDParams) (*SenderID, error) {
	if params.Documents == nil {
		params.Documents = []string{}
	}
	return call[SenderID](ctx, r.http, request{method: http.MethodPost, path: "/v1/sender-ids", body: params, noRetry: true})
}

// Update amends a sender ID registration (PATCH /v1/sender-ids/{id}).
func (r *SenderIDs) Update(ctx context.Context, id string, params UpdateSenderIDParams) (*SenderID, error) {
	if err := requireID("id", id); err != nil {
		return nil, err
	}
	if params.Documents == nil {
		params.Documents = []string{}
	}
	return call[SenderID](ctx, r.http, request{method: http.MethodPatch, path: "/v1/sender-ids/" + escape(id), body: params})
}

// Delete deletes a sender ID (DELETE /v1/sender-ids/{id}).
func (r *SenderIDs) Delete(ctx context.Context, id string) error {
	if err := requireID("id", id); err != nil {
		return err
	}
	return r.http.do(ctx, request{method: http.MethodDelete, path: "/v1/sender-ids/" + escape(id)}, nil)
}

// Check reports whether a value can be registered (GET /v1/sender-ids/check).
func (r *SenderIDs) Check(ctx context.Context, params CheckSenderIDParams) (*SenderIDCheck, error) {
	q := newQuery().str("value", params.Value).str("country", params.Country).values()
	return call[SenderIDCheck](ctx, r.http, request{method: http.MethodGet, path: "/v1/sender-ids/check", query: q})
}

// Quote prices registration in the given countries
// (GET /v1/sender-ids/quote?countries=KE,NG).
func (r *SenderIDs) Quote(ctx context.Context, params QuoteSenderIDParams) (*SenderIDQuote, error) {
	q := newQuery().str("countries", strings.Join(params.Countries, ",")).values()
	return call[SenderIDQuote](ctx, r.http, request{method: http.MethodGet, path: "/v1/sender-ids/quote", query: q})
}

// ListDocuments lists uploaded sender documents (GET /v1/sender-documents).
func (r *SenderIDs) ListDocuments(ctx context.Context) ([]SenderDocument, error) {
	out, err := call[struct {
		Items []SenderDocument `json:"items"`
	}](ctx, r.http, request{method: http.MethodGet, path: "/v1/sender-documents"})
	if err != nil {
		return nil, err
	}
	return out.Items, nil
}

// ListDrafts returns a page of drafts (GET /v1/sender-id-drafts).
func (r *SenderIDs) ListDrafts(ctx context.Context, params ListParams) (*Page[SenderIDDraft], error) {
	return call[Page[SenderIDDraft]](ctx, r.http, request{method: http.MethodGet, path: "/v1/sender-id-drafts", query: listQuery(params)})
}

// CreateDraft saves a draft application (POST /v1/sender-id-drafts). Never
// retried.
func (r *SenderIDs) CreateDraft(ctx context.Context, params SenderIDDraftParams) (*SenderIDDraft, error) {
	return call[SenderIDDraft](ctx, r.http, request{method: http.MethodPost, path: "/v1/sender-id-drafts", body: params, noRetry: true})
}

// GetDraft fetches a draft (GET /v1/sender-id-drafts/{id}).
func (r *SenderIDs) GetDraft(ctx context.Context, id string) (*SenderIDDraft, error) {
	if err := requireID("id", id); err != nil {
		return nil, err
	}
	return call[SenderIDDraft](ctx, r.http, request{method: http.MethodGet, path: "/v1/sender-id-drafts/" + escape(id)})
}

// UpdateDraft changes a draft; params.Version must be the current version
// (PATCH /v1/sender-id-drafts/{id}).
func (r *SenderIDs) UpdateDraft(ctx context.Context, id string, params UpdateSenderIDDraftParams) (*SenderIDDraft, error) {
	if err := requireID("id", id); err != nil {
		return nil, err
	}
	return call[SenderIDDraft](ctx, r.http, request{method: http.MethodPatch, path: "/v1/sender-id-drafts/" + escape(id), body: params})
}

// DeleteDraft deletes a draft (DELETE /v1/sender-id-drafts/{id}).
func (r *SenderIDs) DeleteDraft(ctx context.Context, id string) error {
	if err := requireID("id", id); err != nil {
		return err
	}
	return r.http.do(ctx, request{method: http.MethodDelete, path: "/v1/sender-id-drafts/" + escape(id)}, nil)
}
