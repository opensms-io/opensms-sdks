package opensms

import (
	"context"
	"net/http"
)

// Messages is the messages resource, reached as client.Messages.
type Messages struct {
	http *transport
}

// Send sends one SMS (POST /v1/messages). An Idempotency-Key is generated
// unless WithIdempotencyKey is passed, and reused on retries.
func (r *Messages) Send(ctx context.Context, params SendMessageParams, opts ...CallOption) (*Message, error) {
	var out Message
	err := r.http.do(ctx, request{method: http.MethodPost, path: "/v1/messages", body: params, idempotent: true, opts: applyCallOptions(opts)}, &out)
	if err != nil {
		return nil, err
	}
	return &out, nil
}

// List returns a page of messages, newest first (GET /v1/messages).
func (r *Messages) List(ctx context.Context, params ListMessagesParams) (*Page[Message], error) {
	q := newQuery().
		int("limit", int64(params.Limit)).
		str("cursor", params.Cursor).
		str("status", params.Status).
		str("to", params.To).
		str("country", params.Country).
		time("date_from", params.DateFrom).
		time("date_to", params.DateTo).
		values()
	var out Page[Message]
	if err := r.http.do(ctx, request{method: http.MethodGet, path: "/v1/messages", query: q}, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

// Get fetches one message (GET /v1/messages/{id}).
func (r *Messages) Get(ctx context.Context, id string) (*Message, error) {
	if err := requireID("id", id); err != nil {
		return nil, err
	}
	var out Message
	if err := r.http.do(ctx, request{method: http.MethodGet, path: "/v1/messages/" + escape(id)}, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

// Attempts lists the provider submissions of a message
// (GET /v1/messages/{id}/attempts).
func (r *Messages) Attempts(ctx context.Context, id string) ([]Attempt, error) {
	if err := requireID("id", id); err != nil {
		return nil, err
	}
	var out []Attempt
	if err := r.http.do(ctx, request{method: http.MethodGet, path: "/v1/messages/" + escape(id) + "/attempts"}, &out); err != nil {
		return nil, err
	}
	return out, nil
}

// Cancel cancels a queued or scheduled message (POST /v1/messages/{id}/cancel).
// Any other state returns a 409 *Error. Never retried.
func (r *Messages) Cancel(ctx context.Context, id string) (*Message, error) {
	if err := requireID("id", id); err != nil {
		return nil, err
	}
	var out Message
	if err := r.http.do(ctx, request{method: http.MethodPost, path: "/v1/messages/" + escape(id) + "/cancel", noRetry: true}, &out); err != nil {
		return nil, err
	}
	return &out, nil
}
