package opensms

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	mrand "math/rand"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

const (
	// Version is the SDK version, sent in the User-Agent header.
	Version = "0.1.0"

	// DefaultBaseURL is the production API origin.
	DefaultBaseURL = "https://api.opensms.io"

	defaultMaxRetries = 2
	defaultTimeout    = 30 * time.Second
	userAgent         = "opensms-go/" + Version

	maxRetryAfter = 60 * time.Second
	backoffBase   = 500 * time.Millisecond
	backoffCap    = 8 * time.Second
)

// transport is the only code that talks to the network. It owns bearer
// authentication, JSON encoding and decoding, Idempotency-Key handling,
// retries with backoff (honouring Retry-After) and error mapping to *Error.
type transport struct {
	apiKey     string
	baseURL    string
	maxRetries int
	timeout    time.Duration
	httpClient *http.Client

	// sleep and jitter are replaced in tests.
	sleep  func(ctx context.Context, d time.Duration) error
	jitter func(max time.Duration) time.Duration
}

// request describes one API call. Resources build it; transport sends it.
type request struct {
	method string
	path   string
	query  url.Values

	// body is JSON-encoded when non-nil. rawBody with contentType is sent
	// verbatim instead (CSV, multipart).
	body        any
	rawBody     []byte
	contentType string

	// idempotent marks methods that send an Idempotency-Key ("req"/"opt" in
	// SURFACE.md). The key is generated once per call and reused on retries.
	idempotent bool
	// noRetry disables automatic retries (non-idempotent POSTs).
	noRetry bool

	opts callOptions
}

// CallOption configures a single method call.
type CallOption func(*callOptions)

type callOptions struct {
	idempotencyKey string
}

// WithIdempotencyKey sets the Idempotency-Key for a call. Without it, methods
// that support idempotency send a generated UUIDv4. The same key is reused on
// every retry of that call. Ignored by methods that do not send the header.
func WithIdempotencyKey(key string) CallOption {
	return func(o *callOptions) { o.idempotencyKey = key }
}

func applyCallOptions(opts []CallOption) callOptions {
	var o callOptions
	for _, opt := range opts {
		if opt != nil {
			opt(&o)
		}
	}
	return o
}

// do sends req and decodes a 2xx JSON body into out (which may be nil).
func (t *transport) do(ctx context.Context, req request, out any) error {
	var payload []byte
	contentType := req.contentType
	if req.body != nil {
		encoded, err := json.Marshal(req.body)
		if err != nil {
			return newLocalError("", fmt.Sprintf("failed to encode request body: %v", err), err)
		}
		payload = encoded
		contentType = "application/json"
	} else if req.rawBody != nil {
		payload = req.rawBody
	}

	target := t.baseURL + req.path
	if len(req.query) > 0 {
		target += "?" + encodeQuery(req.query)
	}

	idemKey := ""
	if req.idempotent {
		idemKey = req.opts.idempotencyKey
		if idemKey == "" {
			idemKey = newUUID()
		}
	}
	retryable := !req.noRetry && (req.method != http.MethodPost || idemKey != "")

	attempts := 1
	if retryable {
		attempts += t.maxRetries
	}

	var lastErr error
	for attempt := 1; attempt <= attempts; attempt++ {
		status, header, data, err := t.send(ctx, req.method, target, payload, contentType, idemKey)
		last := attempt == attempts
		if err != nil {
			if ctx.Err() != nil {
				return newLocalError("", fmt.Sprintf("request cancelled: %v", ctx.Err()), ctx.Err())
			}
			lastErr = err
			if last {
				break
			}
			if werr := t.sleep(ctx, t.jitter(backoffDelay(attempt))); werr != nil {
				return werr
			}
			continue
		}

		if status >= 200 && status < 300 {
			if out == nil || len(bytes.TrimSpace(data)) == 0 || status == http.StatusNoContent {
				return nil
			}
			if err := json.Unmarshal(data, out); err != nil {
				return &Error{Status: status, Body: data, message: fmt.Sprintf("failed to decode response: %v", err), cause: err}
			}
			return nil
		}

		retryAfter, hasRetryAfter := parseRetryAfter(header.Get("Retry-After"), time.Now())
		apiErr := newAPIError(status, data, header.Get("X-Request-ID"), retryAfter)
		if last || !isRetryableStatus(status) {
			return apiErr
		}
		wait := t.jitter(backoffDelay(attempt))
		if hasRetryAfter {
			if retryAfter > maxRetryAfter {
				return apiErr
			}
			wait = retryAfter
		}
		if werr := t.sleep(ctx, wait); werr != nil {
			return werr
		}
	}
	return newLocalError("", fmt.Sprintf("request failed: %v", lastErr), lastErr)
}

// send performs one HTTP attempt with the per-attempt timeout and returns the
// fully read response.
func (t *transport) send(ctx context.Context, method, target string, payload []byte, contentType, idemKey string) (int, http.Header, []byte, error) {
	actx := ctx
	if t.timeout > 0 {
		var cancel context.CancelFunc
		actx, cancel = context.WithTimeout(ctx, t.timeout)
		defer cancel()
	}
	var body io.Reader
	if payload != nil {
		body = bytes.NewReader(payload)
	}
	httpReq, err := http.NewRequestWithContext(actx, method, target, body)
	if err != nil {
		return 0, nil, nil, err
	}
	httpReq.Header.Set("Authorization", "Bearer "+t.apiKey)
	httpReq.Header.Set("Accept", "application/json")
	httpReq.Header.Set("User-Agent", userAgent)
	if payload != nil && contentType != "" {
		httpReq.Header.Set("Content-Type", contentType)
	}
	if idemKey != "" {
		httpReq.Header.Set("Idempotency-Key", idemKey)
	}
	resp, err := t.httpClient.Do(httpReq)
	if err != nil {
		return 0, nil, nil, err
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return 0, nil, nil, err
	}
	return resp.StatusCode, resp.Header, data, nil
}

func isRetryableStatus(status int) bool {
	switch status {
	case 429, 500, 502, 503, 504:
		return true
	}
	return false
}

// backoffDelay is the upper bound for retry n (1-based):
// min(8s, 0.5s * 2^(n-1)). The actual wait is a full-jitter random value in
// [0, bound].
func backoffDelay(n int) time.Duration {
	d := backoffBase
	for i := 1; i < n && d < backoffCap; i++ {
		d *= 2
	}
	if d > backoffCap {
		d = backoffCap
	}
	return d
}

func fullJitter(max time.Duration) time.Duration {
	if max <= 0 {
		return 0
	}
	return time.Duration(mrand.Int63n(int64(max) + 1))
}

func sleepContext(ctx context.Context, d time.Duration) error {
	if d <= 0 {
		return nil
	}
	timer := time.NewTimer(d)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return newLocalError("", fmt.Sprintf("request cancelled: %v", ctx.Err()), ctx.Err())
	case <-timer.C:
		return nil
	}
}

// parseRetryAfter reads integer seconds or an HTTP date.
func parseRetryAfter(v string, now time.Time) (time.Duration, bool) {
	v = strings.TrimSpace(v)
	if v == "" {
		return 0, false
	}
	if secs, err := strconv.Atoi(v); err == nil {
		if secs < 0 {
			secs = 0
		}
		return time.Duration(secs) * time.Second, true
	}
	if at, err := http.ParseTime(v); err == nil {
		d := at.Sub(now)
		if d < 0 {
			d = 0
		}
		return d, true
	}
	return 0, false
}

// encodeQuery encodes query parameters in key order. Commas in values are
// kept literal so list parameters read countries=KE,NG.
func encodeQuery(q url.Values) string {
	return strings.ReplaceAll(q.Encode(), "%2C", ",")
}

// newUUID returns a random RFC 4122 version 4 UUID.
func newUUID() string {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		panic(errors.New("opensms: crypto/rand failed: " + err.Error()))
	}
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16])
}

// escape URL-escapes one path segment.
func escape(s string) string { return url.PathEscape(s) }

// requireID fails fast, without a request, when a path id is empty.
func requireID(name, v string) error {
	if strings.TrimSpace(v) == "" {
		return fmt.Errorf("%w: %s must not be empty", ErrInvalidArgument, name)
	}
	return nil
}

// call sends req and decodes the response into a new T.
func call[T any](ctx context.Context, t *transport, req request) (*T, error) {
	var out T
	if err := t.do(ctx, req, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

// callSlice sends req and decodes a bare JSON array.
func callSlice[T any](ctx context.Context, t *transport, req request) ([]T, error) {
	var out []T
	if err := t.do(ctx, req, &out); err != nil {
		return nil, err
	}
	return out, nil
}
