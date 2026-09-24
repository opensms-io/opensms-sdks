package opensms

import (
	"context"
	"net/http"
)

// Sandbox exposes sandbox-only helpers, reached as client.Sandbox.
type Sandbox struct {
	http *transport
}

// ListMessages returns a page of rendered sandbox sends, including OTP codes
// (GET /v1/sandbox/messages).
func (r *Sandbox) ListMessages(ctx context.Context, params ListParams) (*Page[SandboxMessage], error) {
	return call[Page[SandboxMessage]](ctx, r.http, request{method: http.MethodGet, path: "/v1/sandbox/messages", query: listQuery(params)})
}
