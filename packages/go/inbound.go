package opensms

import (
	"context"
	"net/http"
)

// Inbound lists and answers inbound messages, reached as client.Inbound.
type Inbound struct {
	http *transport
}

// List returns a page of inbound messages (GET /v1/inbound).
func (r *Inbound) List(ctx context.Context, params ListParams) (*Page[InboundMessage], error) {
	return call[Page[InboundMessage]](ctx, r.http, request{method: http.MethodGet, path: "/v1/inbound", query: listQuery(params)})
}

// Reply answers an inbound message and returns the outbound Message
// (POST /v1/inbound/{id}/reply). Live keys only.
func (r *Inbound) Reply(ctx context.Context, id string, params InboundReplyParams, opts ...CallOption) (*Message, error) {
	if err := requireID("id", id); err != nil {
		return nil, err
	}
	return call[Message](ctx, r.http, request{method: http.MethodPost, path: "/v1/inbound/" + escape(id) + "/reply", body: params, idempotent: true, opts: applyCallOptions(opts)})
}
