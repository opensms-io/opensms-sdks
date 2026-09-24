package opensms

import (
	"bytes"
	"context"
	"mime/multipart"
	"net/http"
	"strconv"
)

// Batches is the batches resource, reached as client.Batches. A batch is
// created in the ready state and sends nothing until Start.
type Batches struct {
	http *transport
}

// Create creates a batch from JSON items (POST /v1/messages/batch). Invalid
// rows do not fail the request; they are counted and listed by Validation.
func (r *Batches) Create(ctx context.Context, params CreateBatchParams, opts ...CallOption) (*Batch, error) {
	var out Batch
	err := r.http.do(ctx, request{method: http.MethodPost, path: "/v1/messages/batch", body: params, idempotent: true, opts: applyCallOptions(opts)}, &out)
	if err != nil {
		return nil, err
	}
	return &out, nil
}

// CreateFromCSV creates a batch from CSV text with a to,text[,sender_id,...]
// header row (POST /v1/messages/batch, Content-Type text/csv). When
// params.Dedupe is set, the CSV is sent as a multipart upload with a dedupe
// field, the only form in which the API accepts that flag for CSV.
func (r *Batches) CreateFromCSV(ctx context.Context, csv []byte, params CreateBatchFromCSVParams, opts ...CallOption) (*Batch, error) {
	req := request{method: http.MethodPost, path: "/v1/messages/batch", rawBody: csv, contentType: "text/csv", idempotent: true, opts: applyCallOptions(opts)}
	if req.rawBody == nil {
		req.rawBody = []byte{}
	}
	if params.Dedupe != nil {
		var buf bytes.Buffer
		mw := multipart.NewWriter(&buf)
		part, err := mw.CreateFormFile("file", "batch.csv")
		if err == nil {
			_, err = part.Write(csv)
		}
		if err == nil {
			err = mw.WriteField("dedupe", strconv.FormatBool(*params.Dedupe))
		}
		if err == nil {
			err = mw.Close()
		}
		if err != nil {
			return nil, newLocalError("", "failed to build multipart body: "+err.Error(), err)
		}
		req.rawBody = buf.Bytes()
		req.contentType = mw.FormDataContentType()
	}
	var out Batch
	if err := r.http.do(ctx, req, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

// Get fetches a batch (GET /v1/batches/{id}).
func (r *Batches) Get(ctx context.Context, id string) (*Batch, error) {
	if err := requireID("id", id); err != nil {
		return nil, err
	}
	var out Batch
	if err := r.http.do(ctx, request{method: http.MethodGet, path: "/v1/batches/" + escape(id)}, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

// Validation returns the per-row validation report
// (GET /v1/batches/{id}/validation).
func (r *Batches) Validation(ctx context.Context, id string) (*ValidationReport, error) {
	if err := requireID("id", id); err != nil {
		return nil, err
	}
	var out ValidationReport
	if err := r.http.do(ctx, request{method: http.MethodGet, path: "/v1/batches/" + escape(id) + "/validation"}, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

// Start starts a ready batch (POST /v1/batches/{id}/start).
func (r *Batches) Start(ctx context.Context, id string, opts ...CallOption) (*Batch, error) {
	if err := requireID("id", id); err != nil {
		return nil, err
	}
	var out Batch
	err := r.http.do(ctx, request{method: http.MethodPost, path: "/v1/batches/" + escape(id) + "/start", idempotent: true, opts: applyCallOptions(opts)}, &out)
	if err != nil {
		return nil, err
	}
	return &out, nil
}

// Stop stops a batch and cancels its unsent items
// (POST /v1/batches/{id}/stop).
func (r *Batches) Stop(ctx context.Context, id string, opts ...CallOption) (*BatchStopResult, error) {
	if err := requireID("id", id); err != nil {
		return nil, err
	}
	var out BatchStopResult
	err := r.http.do(ctx, request{method: http.MethodPost, path: "/v1/batches/" + escape(id) + "/stop", idempotent: true, opts: applyCallOptions(opts)}, &out)
	if err != nil {
		return nil, err
	}
	return &out, nil
}

// ListItems returns a page of the messages a batch created
// (GET /v1/batches/{id}/items).
func (r *Batches) ListItems(ctx context.Context, id string, params ListBatchItemsParams) (*Page[BatchItem], error) {
	if err := requireID("id", id); err != nil {
		return nil, err
	}
	q := newQuery().str("status", params.Status).int("limit", int64(params.Limit)).str("cursor", params.Cursor).values()
	var out Page[BatchItem]
	if err := r.http.do(ctx, request{method: http.MethodGet, path: "/v1/batches/" + escape(id) + "/items", query: q}, &out); err != nil {
		return nil, err
	}
	return &out, nil
}
