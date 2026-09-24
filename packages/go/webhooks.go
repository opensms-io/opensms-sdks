package opensms

import (
	"context"
	"net/http"
	"strconv"
)

// Webhooks manages webhook endpoints, reached as client.Webhooks. Signature
// verification is available here and as the package functions
// VerifySignature and ConstructEvent.
type Webhooks struct {
	http *transport
}

// List returns a page of endpoints (GET /v1/webhooks).
func (r *Webhooks) List(ctx context.Context, params ListParams) (*Page[WebhookEndpoint], error) {
	return call[Page[WebhookEndpoint]](ctx, r.http, request{method: http.MethodGet, path: "/v1/webhooks", query: listQuery(params)})
}

// Create creates an endpoint (POST /v1/webhooks). The returned Secret
// (whsec_...) is shown only once.
func (r *Webhooks) Create(ctx context.Context, params CreateWebhookParams, opts ...CallOption) (*WebhookEndpoint, error) {
	return call[WebhookEndpoint](ctx, r.http, request{method: http.MethodPost, path: "/v1/webhooks", body: params, idempotent: true, opts: applyCallOptions(opts)})
}

// Get fetches an endpoint (GET /v1/webhooks/{id}).
func (r *Webhooks) Get(ctx context.Context, id string) (*WebhookEndpoint, error) {
	if err := requireID("id", id); err != nil {
		return nil, err
	}
	return call[WebhookEndpoint](ctx, r.http, request{method: http.MethodGet, path: "/v1/webhooks/" + escape(id)})
}

// Update replaces an endpoint (PUT /v1/webhooks/{id}). URL, Events and
// Enabled are all sent.
func (r *Webhooks) Update(ctx context.Context, id string, params UpdateWebhookParams, opts ...CallOption) (*WebhookEndpoint, error) {
	if err := requireID("id", id); err != nil {
		return nil, err
	}
	return call[WebhookEndpoint](ctx, r.http, request{method: http.MethodPut, path: "/v1/webhooks/" + escape(id), body: params, idempotent: true, opts: applyCallOptions(opts)})
}

// Delete deletes an endpoint (DELETE /v1/webhooks/{id}).
func (r *Webhooks) Delete(ctx context.Context, id string, opts ...CallOption) error {
	if err := requireID("id", id); err != nil {
		return err
	}
	return r.http.do(ctx, request{method: http.MethodDelete, path: "/v1/webhooks/" + escape(id), idempotent: true, opts: applyCallOptions(opts)}, nil)
}

// Test queues a webhook.test delivery (POST /v1/webhooks/{id}/test).
func (r *Webhooks) Test(ctx context.Context, id string, opts ...CallOption) (*StatusResult, error) {
	if err := requireID("id", id); err != nil {
		return nil, err
	}
	return call[StatusResult](ctx, r.http, request{method: http.MethodPost, path: "/v1/webhooks/" + escape(id) + "/test", idempotent: true, opts: applyCallOptions(opts)})
}

// ListDeliveries returns a page of deliveries for an endpoint
// (GET /v1/webhooks/{id}/deliveries).
func (r *Webhooks) ListDeliveries(ctx context.Context, id string, params ListParams) (*Page[WebhookDelivery], error) {
	if err := requireID("id", id); err != nil {
		return nil, err
	}
	return call[Page[WebhookDelivery]](ctx, r.http, request{method: http.MethodGet, path: "/v1/webhooks/" + escape(id) + "/deliveries", query: listQuery(params)})
}

// ReplayDelivery re-queues a delivery
// (POST /v1/webhooks/{id}/deliveries/{delivery_id}/replay).
func (r *Webhooks) ReplayDelivery(ctx context.Context, id string, deliveryID int64, params ReplayDeliveryParams, opts ...CallOption) (*StatusResult, error) {
	if err := requireID("id", id); err != nil {
		return nil, err
	}
	path := "/v1/webhooks/" + escape(id) + "/deliveries/" + strconv.FormatInt(deliveryID, 10) + "/replay"
	return call[StatusResult](ctx, r.http, request{method: http.MethodPost, path: path, body: params, idempotent: true, opts: applyCallOptions(opts)})
}

// VerifySignature is VerifySignature, reachable from the client.
func (r *Webhooks) VerifySignature(payload []byte, header, secret string, opts ...VerifyOptions) bool {
	return VerifySignature(payload, header, secret, opts...)
}

// ConstructEvent is ConstructEvent, reachable from the client.
func (r *Webhooks) ConstructEvent(payload []byte, header, secret string, opts ...VerifyOptions) (*WebhookEvent, error) {
	return ConstructEvent(payload, header, secret, opts...)
}
