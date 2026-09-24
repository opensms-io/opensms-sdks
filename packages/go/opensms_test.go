package opensms

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"
	"sync"
	"testing"
	"time"
)

// ---------------------------------------------------------- mock transport

type mockResponse struct {
	status  int
	body    string
	headers map[string]string
	err     error
}

type recorded struct {
	method string
	url    string
	path   string // escaped path
	header http.Header
	body   []byte
}

// mockTransport records requests and replays canned responses in order; the
// last response repeats when the list runs out.
type mockTransport struct {
	mu        sync.Mutex
	responses []mockResponse
	requests  []recorded
}

func (m *mockTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	var body []byte
	if req.Body != nil {
		body, _ = io.ReadAll(req.Body)
	}
	m.requests = append(m.requests, recorded{
		method: req.Method,
		url:    req.URL.String(),
		path:   req.URL.EscapedPath(),
		header: req.Header.Clone(),
		body:   body,
	})
	i := len(m.requests) - 1
	if i >= len(m.responses) {
		i = len(m.responses) - 1
	}
	r := m.responses[i]
	if r.err != nil {
		return nil, r.err
	}
	h := http.Header{}
	h.Set("Content-Type", "application/json")
	for k, v := range r.headers {
		h.Set(k, v)
	}
	return &http.Response{
		StatusCode: r.status,
		Header:     h,
		Body:       io.NopCloser(strings.NewReader(r.body)),
		Request:    req,
	}, nil
}

const testKey = "sk_test_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

type harness struct {
	client *Client
	mock   *mockTransport
	sleeps []time.Duration
}

func newHarness(t *testing.T, responses []mockResponse, opts ...Option) *harness {
	t.Helper()
	h := &harness{mock: &mockTransport{responses: responses}}
	all := append([]Option{WithBaseURL("http://mock.test"), WithHTTPClient(&http.Client{Transport: h.mock})}, opts...)
	c, err := NewClient(testKey, all...)
	if err != nil {
		t.Fatalf("NewClient: %v", err)
	}
	c.transport.sleep = func(_ context.Context, d time.Duration) error {
		h.sleeps = append(h.sleeps, d)
		return nil
	}
	h.client = c
	return h
}

func ok(status int, body string) mockResponse { return mockResponse{status: status, body: body} }

const messageJSON = `{"id":"00000000-0000-0000-0000-000000000001","to":"+254700000012","status":"queued","price":"0.000000","currency":"KES","parts":1,"created_at":"2026-09-24T08:25:59.396241+03:00","unknown_field":{"x":1}}`

func asError(t *testing.T, err error) *Error {
	t.Helper()
	var e *Error
	if !errors.As(err, &e) {
		t.Fatalf("expected *Error, got %T %v", err, err)
	}
	return e
}

func problemBody(status int, detail string) string {
	b, _ := json.Marshal(map[string]any{"type": "about:blank", "title": http.StatusText(status), "status": status, "detail": detail})
	return string(b)
}

var ctx = context.Background()

// 1. Header injection
func TestHeaders(t *testing.T) {
	h := newHarness(t, []mockResponse{ok(201, messageJSON), ok(200, messageJSON)})
	if _, err := h.client.Messages.Send(ctx, SendMessageParams{To: "+254700000012", Text: "hi"}); err != nil {
		t.Fatal(err)
	}
	if _, err := h.client.Messages.Get(ctx, "m1"); err != nil {
		t.Fatal(err)
	}
	for i, r := range h.mock.requests {
		if got := r.header.Get("Authorization"); got != "Bearer "+testKey {
			t.Errorf("req %d Authorization = %q", i, got)
		}
		if got := r.header.Get("Accept"); got != "application/json" {
			t.Errorf("req %d Accept = %q", i, got)
		}
		if got := r.header.Get("User-Agent"); got != "opensms-go/0.1.0" {
			t.Errorf("req %d User-Agent = %q", i, got)
		}
		if r.header.Get("X-Workspace-ID") != "" || r.header.Get("X-Environment") != "" {
			t.Errorf("req %d sent workspace/environment headers", i)
		}
	}
	if got := h.mock.requests[0].header.Get("Content-Type"); got != "application/json" {
		t.Errorf("JSON call Content-Type = %q", got)
	}
	if got := h.mock.requests[1].header.Get("Content-Type"); got != "" {
		t.Errorf("GET Content-Type = %q, want none", got)
	}
}

// 2. Base URL
func TestBaseURL(t *testing.T) {
	c, err := NewClient(testKey)
	if err != nil {
		t.Fatal(err)
	}
	if c.transport.baseURL != "https://api.opensms.io" {
		t.Fatalf("default base URL = %q", c.transport.baseURL)
	}
	h := newHarness(t, []mockResponse{ok(200, `{"items":[],"next_cursor":null}`)}, WithBaseURL("http://host/"))
	if _, err := h.client.Messages.List(ctx, ListMessagesParams{}); err != nil {
		t.Fatal(err)
	}
	if got := h.mock.requests[0].url; got != "http://host/v1/messages" {
		t.Fatalf("url = %q", got)
	}
}

// 3. Key validation
func TestKeyValidation(t *testing.T) {
	for _, k := range []string{"", "pk_test_x", "sk_test_short", "not_a_key", "sk_test_123456789012"} {
		if _, err := NewClient(k); err == nil || !errors.Is(err, ErrInvalidArgument) {
			t.Errorf("NewClient(%q) err = %v, want ErrInvalidArgument", k, err)
		}
	}
	live, err := NewClient("sk_live_" + strings.Repeat("A", 32))
	if err != nil || live.Environment() != "live" {
		t.Fatalf("live key: %v %v", err, live)
	}
	sb, err := NewClient("sk_test_" + strings.Repeat("A", 32))
	if err != nil || sb.Environment() != "sandbox" {
		t.Fatalf("test key: %v %v", err, sb)
	}
}

// 4. Body mapping
func TestSendBodyMapping(t *testing.T) {
	h := newHarness(t, []mockResponse{ok(201, messageJSON), ok(201, messageJSON)})
	at := time.Date(2026, 9, 24, 12, 0, 0, 0, time.FixedZone("EAT", 3*3600))
	_, err := h.client.Messages.Send(ctx, SendMessageParams{
		To: "+254700000012", Text: "hi", SenderID: "ACME", TrafficType: "marketing",
		ScheduledAt: at, CallbackURL: "https://cb.test/x", Metadata: map[string]any{"a": "b"},
	})
	if err != nil {
		t.Fatal(err)
	}
	var body map[string]any
	_ = json.Unmarshal(h.mock.requests[0].body, &body)
	want := []string{"to", "text", "sender_id", "traffic_type", "scheduled_at", "callback_url", "metadata"}
	if len(body) != len(want) {
		t.Fatalf("keys = %v", body)
	}
	for _, k := range want {
		if _, ok := body[k]; !ok {
			t.Errorf("missing key %s", k)
		}
	}
	if body["scheduled_at"] != "2026-09-24T09:00:00Z" {
		t.Errorf("scheduled_at = %v", body["scheduled_at"])
	}
	// Unset optionals are absent.
	if _, err := h.client.Messages.Send(ctx, SendMessageParams{To: "+254700000012", Text: "hi"}); err != nil {
		t.Fatal(err)
	}
	if got := string(h.mock.requests[1].body); got != `{"to":"+254700000012","text":"hi"}` {
		t.Errorf("minimal body = %s", got)
	}
}

// 5. Idempotency-Key auto
func TestIdempotencyKey(t *testing.T) {
	h := newHarness(t, []mockResponse{ok(201, messageJSON), ok(201, messageJSON), ok(200, messageJSON)})
	if _, err := h.client.Messages.Send(ctx, SendMessageParams{To: "+1", Text: "x"}); err != nil {
		t.Fatal(err)
	}
	if _, err := h.client.Messages.Send(ctx, SendMessageParams{To: "+1", Text: "x"}, WithIdempotencyKey("my-key")); err != nil {
		t.Fatal(err)
	}
	if _, err := h.client.Messages.Get(ctx, "m1"); err != nil {
		t.Fatal(err)
	}
	k := h.mock.requests[0].header.Get("Idempotency-Key")
	if len(k) != 36 || k[14] != '4' {
		t.Errorf("generated key = %q, want UUIDv4", k)
	}
	if got := h.mock.requests[1].header.Get("Idempotency-Key"); got != "my-key" {
		t.Errorf("explicit key = %q", got)
	}
	if got := h.mock.requests[2].header.Get("Idempotency-Key"); got != "" {
		t.Errorf("GET sent key %q", got)
	}
}

// 6. Retry on 429 with Retry-After
func TestRetry429RetryAfter(t *testing.T) {
	h := newHarness(t, []mockResponse{
		{status: 429, body: problemBody(429, "rate limited"), headers: map[string]string{"Retry-After": "2"}},
		ok(201, messageJSON),
	})
	if _, err := h.client.Messages.Send(ctx, SendMessageParams{To: "+1", Text: "x"}); err != nil {
		t.Fatal(err)
	}
	if len(h.mock.requests) != 2 {
		t.Fatalf("requests = %d", len(h.mock.requests))
	}
	if len(h.sleeps) != 1 || h.sleeps[0] != 2*time.Second {
		t.Fatalf("sleeps = %v", h.sleeps)
	}
	a, b := h.mock.requests[0].header.Get("Idempotency-Key"), h.mock.requests[1].header.Get("Idempotency-Key")
	if a == "" || a != b {
		t.Fatalf("keys differ across retries: %q vs %q", a, b)
	}
}

// Retry-After as an HTTP date.
func TestRetryAfterHTTPDate(t *testing.T) {
	d, ok := parseRetryAfter("Wed, 21 Oct 2015 07:28:05 GMT", time.Date(2015, 10, 21, 7, 28, 0, 0, time.UTC))
	if !ok || d != 5*time.Second {
		t.Fatalf("got %v %v", d, ok)
	}
}

// 7. Retry on 503 without Retry-After
func TestRetry503Backoff(t *testing.T) {
	h := newHarness(t, []mockResponse{ok(503, problemBody(503, "down")), ok(200, messageJSON)})
	if _, err := h.client.Messages.Get(ctx, "m1"); err != nil {
		t.Fatal(err)
	}
	if len(h.mock.requests) != 2 || len(h.sleeps) != 1 {
		t.Fatalf("requests=%d sleeps=%v", len(h.mock.requests), h.sleeps)
	}
	if h.sleeps[0] < 0 || h.sleeps[0] > 500*time.Millisecond {
		t.Fatalf("backoff %v outside [0, 0.5s]", h.sleeps[0])
	}
	if backoffDelay(1) != 500*time.Millisecond || backoffDelay(2) != time.Second || backoffDelay(10) != 8*time.Second {
		t.Fatalf("backoff bounds wrong: %v %v %v", backoffDelay(1), backoffDelay(2), backoffDelay(10))
	}
}

// 8. Retries exhausted
func TestRetriesExhausted(t *testing.T) {
	h := newHarness(t, []mockResponse{ok(500, problemBody(500, "boom"))}, WithMaxRetries(2))
	_, err := h.client.Messages.Get(ctx, "m1")
	if e := asError(t, err); e.Status != 500 {
		t.Fatalf("status = %d", e.Status)
	}
	if len(h.mock.requests) != 3 {
		t.Fatalf("requests = %d", len(h.mock.requests))
	}
	h0 := newHarness(t, []mockResponse{ok(500, problemBody(500, "boom"))}, WithMaxRetries(0))
	_, _ = h0.client.Messages.Get(ctx, "m1")
	if len(h0.mock.requests) != 1 {
		t.Fatalf("maxRetries 0 made %d requests", len(h0.mock.requests))
	}
}

// 9. Retry-After too large
func TestRetryAfterTooLarge(t *testing.T) {
	h := newHarness(t, []mockResponse{{status: 429, body: problemBody(429, "slow down"), headers: map[string]string{"Retry-After": "120"}}})
	_, err := h.client.Messages.Get(ctx, "m1")
	e := asError(t, err)
	if e.Status != 429 || e.RetryAfter != 120*time.Second {
		t.Fatalf("status=%d retryAfter=%v", e.Status, e.RetryAfter)
	}
	if len(h.mock.requests) != 1 {
		t.Fatalf("requests = %d", len(h.mock.requests))
	}
}

// 10. No retry on 400/401/404/409/422
func TestNoRetryOn4xx(t *testing.T) {
	for _, status := range []int{400, 401, 402, 403, 404, 409, 410, 413, 422} {
		h := newHarness(t, []mockResponse{ok(status, problemBody(status, "nope")), ok(200, messageJSON)})
		_, err := h.client.Messages.Send(ctx, SendMessageParams{To: "+1", Text: "x"})
		if e := asError(t, err); e.Status != status {
			t.Errorf("status %d: got %d", status, e.Status)
		}
		if len(h.mock.requests) != 1 {
			t.Errorf("status %d: %d requests", status, len(h.mock.requests))
		}
	}
}

// 11. No retry for non-idempotent POST
func TestNoRetryNonIdempotentPost(t *testing.T) {
	h := newHarness(t, []mockResponse{ok(503, problemBody(503, "down")), ok(200, `{"valid":true}`)})
	_, err := h.client.OTP.Verify(ctx, VerifyOTPParams{OTPID: "o", Code: "123456"})
	if e := asError(t, err); e.Status != 503 || len(h.mock.requests) != 1 {
		t.Fatalf("otp.verify: status=%d requests=%d", e.Status, len(h.mock.requests))
	}
	if h.mock.requests[0].header.Get("Idempotency-Key") != "" {
		t.Fatal("otp.verify sent an Idempotency-Key")
	}
	h2 := newHarness(t, []mockResponse{ok(503, problemBody(503, "down")), ok(200, messageJSON)})
	_, err = h2.client.Messages.Cancel(ctx, "m1")
	if e := asError(t, err); e.Status != 503 || len(h2.mock.requests) != 1 {
		t.Fatalf("messages.cancel: status=%d requests=%d", e.Status, len(h2.mock.requests))
	}
	h3 := newHarness(t, []mockResponse{ok(503, problemBody(503, "down")), ok(201, `{}`)})
	_, _ = h3.client.SenderIDs.Create(ctx, CreateSenderIDParams{Value: "ACME"})
	_, _ = h3.client.Suppressions.Create(ctx, CreateSuppressionParams{E164: "+1", Reason: "manual"})
	if len(h3.mock.requests) != 2 {
		t.Fatalf("senderIds.create/suppressions.create retried: %d requests", len(h3.mock.requests))
	}
}

// 12. Network error
func TestNetworkError(t *testing.T) {
	netErr := errors.New("connection refused")
	h := newHarness(t, []mockResponse{{err: netErr}, {err: netErr}, ok(200, messageJSON)})
	if _, err := h.client.Messages.Get(ctx, "m1"); err != nil {
		t.Fatal(err)
	}
	if len(h.mock.requests) != 3 {
		t.Fatalf("requests = %d", len(h.mock.requests))
	}
	h2 := newHarness(t, []mockResponse{{err: netErr}})
	_, err := h2.client.Messages.Get(ctx, "m1")
	if e := asError(t, err); e.Status != 0 || !errors.Is(err, netErr) {
		t.Fatalf("status=%d err=%v", e.Status, err)
	}
	if len(h2.mock.requests) != 3 {
		t.Fatalf("requests = %d", len(h2.mock.requests))
	}
}

// Per-attempt timeout turns into a retryable network error.
func TestTimeout(t *testing.T) {
	var calls int
	slow := roundTripFunc(func(r *http.Request) (*http.Response, error) {
		calls++
		<-r.Context().Done()
		return nil, r.Context().Err()
	})
	c, _ := NewClient(testKey, WithHTTPClient(&http.Client{Transport: slow}), WithTimeout(10*time.Millisecond), WithMaxRetries(1))
	c.transport.sleep = func(context.Context, time.Duration) error { return nil }
	_, err := c.Messages.Get(ctx, "m1")
	if e := asError(t, err); e.Status != 0 || calls != 2 {
		t.Fatalf("status=%d calls=%d", e.Status, calls)
	}
}

type roundTripFunc func(*http.Request) (*http.Response, error)

func (f roundTripFunc) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }

// 13. Error mapping
func TestErrorMapping(t *testing.T) {
	coded := `{"type":"https://api.opensms.io/problems/invalid_message_id","title":"Bad Request","status":400,"detail":"Message ID must be a valid UUID.","code":"invalid_message_id","trace_id":"t1","errors":{"to":["bad"]}}`
	h := newHarness(t, []mockResponse{{status: 400, body: coded, headers: map[string]string{"Content-Type": "application/problem+json"}}})
	_, err := h.client.Messages.Get(ctx, "x")
	e := asError(t, err)
	if e.Status != 400 || e.Type != "https://api.opensms.io/problems/invalid_message_id" || e.Title != "Bad Request" ||
		e.Detail != "Message ID must be a valid UUID." || e.Code != "invalid_message_id" || e.TraceID != "t1" ||
		len(e.Errors["to"]) != 1 || e.Errors["to"][0] != "bad" || e.Message() != e.Detail {
		t.Fatalf("mapped = %+v", e)
	}
	if !strings.Contains(e.Error(), "Message ID must be a valid UUID.") {
		t.Fatalf("Error() = %q", e.Error())
	}

	h2 := newHarness(t, []mockResponse{ok(404, problemBody(404, "message not found"))})
	_, err = h2.client.Messages.Get(ctx, "x")
	if e := asError(t, err); e.Code != "" || e.Type != "about:blank" {
		t.Fatalf("about:blank mapped = %+v", e)
	}

	h3 := newHarness(t, []mockResponse{{status: 422, body: problemBody(422, "destination is suppressed"), headers: map[string]string{"X-Request-ID": "r1"}}})
	_, err = h3.client.Messages.Send(ctx, SendMessageParams{To: "+1", Text: "x"})
	if e := asError(t, err); e.RequestID != "r1" || e.Status != 422 {
		t.Fatalf("requestId mapped = %+v", e)
	}

	html := "<html><body>Bad Gateway</body></html>"
	h4 := newHarness(t, []mockResponse{{status: 502, body: html, headers: map[string]string{"Content-Type": "text/html"}}}, WithMaxRetries(0))
	_, err = h4.client.Messages.Get(ctx, "x")
	e = asError(t, err)
	if e.Status != 502 || e.Detail != "" || e.Title != "" || string(e.Body) != html {
		t.Fatalf("html mapped = %+v", e)
	}
	if e.Message() != "OpenSMS request failed with status 502" {
		t.Fatalf("fallback message = %q", e.Message())
	}
}

// 14. 204 handling
func TestNoContent(t *testing.T) {
	h := newHarness(t, []mockResponse{ok(204, "")})
	if err := h.client.Contacts.Delete(ctx, "c1"); err != nil {
		t.Fatal(err)
	}
	if h.mock.requests[0].method != "DELETE" || h.mock.requests[0].path != "/v1/contacts/c1" {
		t.Fatalf("request = %+v", h.mock.requests[0])
	}
}

// 15. Pagination
func TestPagination(t *testing.T) {
	h := newHarness(t, []mockResponse{
		ok(200, `{"items":[{"id":"a"},{"id":"b"}],"next_cursor":"c1"}`),
		ok(200, `{"items":[{"id":"c"}],"next_cursor":null}`),
	})
	it := Paginate(ctx, h.client.Messages.List, ListMessagesParams{Limit: 2})
	var ids []string
	for it.Next() {
		ids = append(ids, it.Item().ID)
	}
	if it.Err() != nil {
		t.Fatal(it.Err())
	}
	if strings.Join(ids, ",") != "a,b,c" {
		t.Fatalf("ids = %v", ids)
	}
	if len(h.mock.requests) != 2 {
		t.Fatalf("requests = %d", len(h.mock.requests))
	}
	if got := h.mock.requests[0].url; got != "http://mock.test/v1/messages?limit=2" {
		t.Fatalf("first url = %q", got)
	}
	if got := h.mock.requests[1].url; got != "http://mock.test/v1/messages?cursor=c1&limit=2" {
		t.Fatalf("second url = %q", got)
	}

	// Pagination error surfaces through Err.
	h2 := newHarness(t, []mockResponse{ok(400, problemBody(400, "invalid cursor"))})
	it2 := Paginate(ctx, h2.client.Contacts.List, ListParams{Cursor: "bad"})
	if it2.Next() || asError(t, it2.Err()).Status != 400 {
		t.Fatal("expected pagination error")
	}
}

// 16. Query encoding
func TestQueryEncoding(t *testing.T) {
	h := newHarness(t, []mockResponse{ok(200, `{"quote_id":"sq_1","entries":[],"totals":[]}`), ok(200, `{"items":[],"next_cursor":null}`), ok(200, `{"data":[]}`)})
	if _, err := h.client.SenderIDs.Quote(ctx, QuoteSenderIDParams{Countries: []string{"KE", "NG"}}); err != nil {
		t.Fatal(err)
	}
	if got := h.mock.requests[0].url; got != "http://mock.test/v1/sender-ids/quote?countries=KE,NG" {
		t.Fatalf("quote url = %q", got)
	}
	if _, err := h.client.Messages.List(ctx, ListMessagesParams{Status: "delivered", To: "+2547"}); err != nil {
		t.Fatal(err)
	}
	if got := h.mock.requests[1].url; got != "http://mock.test/v1/messages?status=delivered&to=%2B2547" {
		t.Fatalf("list url = %q", got)
	}
	if _, err := h.client.Wallet.Ledger(ctx, LedgerParams{Limit: Int(0)}); err != nil {
		t.Fatal(err)
	}
	if got := h.mock.requests[2].url; got != "http://mock.test/v1/wallet/ledger?limit=0" {
		t.Fatalf("ledger url = %q", got)
	}
}

// 17. Path escaping
func TestPathEscaping(t *testing.T) {
	h := newHarness(t, []mockResponse{ok(200, messageJSON)})
	if _, err := h.client.Messages.Get(ctx, "a/b"); err != nil {
		t.Fatal(err)
	}
	if got := h.mock.requests[0].path; got != "/v1/messages/a%2Fb" {
		t.Fatalf("path = %q", got)
	}
	// Empty ids fail before any request.
	if _, err := h.client.Messages.Get(ctx, ""); !errors.Is(err, ErrInvalidArgument) {
		t.Fatalf("empty id err = %v", err)
	}
	if len(h.mock.requests) != 1 {
		t.Fatal("empty id made a request")
	}
}

// 18. Webhook signature vector
func TestWebhookSignatureVector(t *testing.T) {
	const (
		secret = "whsec_c2RrLWNvbmZvcm1hbmNlLXRlc3QtdmVjdG9yLTAwMDE"
		ts     = int64(1790208000)
		body   = `{"id":"evt_01","type":"message.delivered","workspace_id":"00000000-0000-0000-0000-000000000001","environment":"sandbox","created_at":"2026-09-24T00:00:00Z","data":{"id":"00000000-0000-0000-0000-000000000002","status":"delivered"}}`
		digest = "eeb2ec420dd348b253dae35c1f3bce03d261109eb8788e3ad836072e894fac23"
		header = "t=1790208000,v1=" + digest
	)
	if len(body) != 230 {
		t.Fatalf("vector body is %d bytes", len(body))
	}
	at := func(delta int64) VerifyOptions { return VerifyOptions{Now: time.Unix(ts+delta, 0)} }
	tampered := strings.Replace(body, `"status":"delivered"`, `"status":"failed"`, 1)
	cases := []struct {
		name   string
		body   string
		header string
		secret string
		opts   VerifyOptions
		want   bool
	}{
		{"valid", body, header, secret, at(0), true},
		{"boundary +300", body, header, secret, at(300), true},
		{"expired +301", body, header, secret, at(301), false},
		{"expired -301", body, header, secret, at(-301), false},
		{"tampered body", tampered, header, secret, at(0), false},
		{"secret without prefix", body, header, strings.TrimPrefix(secret, "whsec_"), at(0), false},
		{"order swapped", body, "v1=" + digest + ",t=1790208000", secret, at(0), true},
		{"extra v0", body, header + ",v0=abc", secret, at(0), false},
		{"t only", body, "t=1790208000", secret, at(0), false},
		{"uppercase hex", body, "t=1790208000,v1=" + strings.ToUpper(digest), secret, at(0), true},
		{"empty secret", body, header, "", at(0), false},
	}
	for _, c := range cases {
		if got := VerifySignature([]byte(c.body), c.header, c.secret, c.opts); got != c.want {
			t.Errorf("%s: got %v want %v", c.name, got, c.want)
		}
	}

	ev, err := ConstructEvent([]byte(body), header, secret, at(0))
	if err != nil {
		t.Fatal(err)
	}
	if ev.Type != "message.delivered" || ev.Data["status"] != "delivered" || ev.ID != "evt_01" {
		t.Fatalf("event = %+v", ev)
	}
	_, err = ConstructEvent([]byte(tampered), header, secret, at(0))
	if e := asError(t, err); e.Status != 0 || e.Code != "invalid_signature" {
		t.Fatalf("tampered err = %+v", e)
	}
	_, err = ConstructEvent([]byte(body), header, secret, at(301))
	if e := asError(t, err); e.Code != "expired_signature" {
		t.Fatalf("expired err = %+v", e)
	}
	// Reachable from the client too.
	c, _ := NewClient(testKey)
	if !c.Webhooks.VerifySignature([]byte(body), header, secret, at(0)) {
		t.Fatal("client VerifySignature failed")
	}
}

// 19. Batch CSV
func TestBatchCSV(t *testing.T) {
	batch := `{"id":"b1","status":"ready","total":1,"invalid":0,"estimated_cost":null}`
	h := newHarness(t, []mockResponse{ok(202, batch), ok(202, batch)})
	csv := "to,text\n+254700000014,csv run\n"
	b, err := h.client.Batches.CreateFromCSV(ctx, []byte(csv), CreateBatchFromCSVParams{})
	if err != nil {
		t.Fatal(err)
	}
	r := h.mock.requests[0]
	if r.header.Get("Content-Type") != "text/csv" || string(r.body) != csv || len(r.header.Get("Idempotency-Key")) != 36 {
		t.Fatalf("csv request: ct=%q body=%q key=%q", r.header.Get("Content-Type"), r.body, r.header.Get("Idempotency-Key"))
	}
	if b.Status != "ready" || b.Total != 1 {
		t.Fatalf("batch = %+v", b)
	}
	// With Dedupe set, the CSV goes multipart with a dedupe field.
	if _, err := h.client.Batches.CreateFromCSV(ctx, []byte(csv), CreateBatchFromCSVParams{Dedupe: Bool(false)}); err != nil {
		t.Fatal(err)
	}
	r = h.mock.requests[1]
	if !strings.HasPrefix(r.header.Get("Content-Type"), "multipart/form-data") || !bytes.Contains(r.body, []byte(csv)) || !bytes.Contains(r.body, []byte("false")) {
		t.Fatalf("multipart request: ct=%q", r.header.Get("Content-Type"))
	}
}

// 20. Decimal strings and unknown fields
func TestDecimalStrings(t *testing.T) {
	h := newHarness(t, []mockResponse{ok(200, messageJSON)})
	m, err := h.client.Messages.Get(ctx, "m1")
	if err != nil {
		t.Fatal(err)
	}
	if m.Price != "0.000000" || m.Currency != "KES" || m.Parts != 1 {
		t.Fatalf("message = %+v", m)
	}
	if m.CreatedAt.IsZero() {
		t.Fatal("created_at not parsed")
	}
}

// Webhook update always sends url, events and enabled (full replacement).
func TestWebhookUpdateFullBody(t *testing.T) {
	h := newHarness(t, []mockResponse{ok(200, `{"id":"w1"}`)})
	if _, err := h.client.Webhooks.Update(ctx, "w1", UpdateWebhookParams{URL: "https://x.test", Events: []string{"message.delivered"}}); err != nil {
		t.Fatal(err)
	}
	r := h.mock.requests[0]
	if r.method != "PUT" || string(r.body) != `{"url":"https://x.test","events":["message.delivered"],"enabled":false}` {
		t.Fatalf("webhook update: %s %s", r.method, r.body)
	}
	if r.header.Get("Idempotency-Key") == "" {
		t.Fatal("webhook update should send an Idempotency-Key (opt)")
	}
}

// Group update: nil members omitted, empty slice sent.
func TestGroupUpdateContactIDs(t *testing.T) {
	h := newHarness(t, []mockResponse{ok(200, `{"id":"g1"}`)})
	_, _ = h.client.ContactGroups.Update(ctx, "g1", UpdateContactGroupParams{Name: "n"})
	_, _ = h.client.ContactGroups.Update(ctx, "g1", UpdateContactGroupParams{ContactIDs: []string{}})
	if string(h.mock.requests[0].body) != `{"name":"n"}` || string(h.mock.requests[1].body) != `{"contact_ids":[]}` {
		t.Fatalf("bodies: %s | %s", h.mock.requests[0].body, h.mock.requests[1].body)
	}
}

// Every resource method hits the documented method and path.
func TestSurfaceRoutes(t *testing.T) {
	h := newHarness(t, []mockResponse{ok(200, `{}`)})
	c := h.client
	type call struct {
		method, path string
		fn           func() error
	}
	e := func(_ any, err error) error { return err }
	arr := newHarness(t, []mockResponse{ok(200, `[]`)})
	a := arr.client
	calls := []call{
		{"POST", "/v1/messages", func() error { return e(c.Messages.Send(ctx, SendMessageParams{})) }},
		{"GET", "/v1/messages", func() error { return e(c.Messages.List(ctx, ListMessagesParams{})) }},
		{"GET", "/v1/messages/i", func() error { return e(c.Messages.Get(ctx, "i")) }},
		{"POST", "/v1/messages/i/cancel", func() error { return e(c.Messages.Cancel(ctx, "i")) }},
		{"POST", "/v1/messages/batch", func() error { return e(c.Batches.Create(ctx, CreateBatchParams{})) }},
		{"GET", "/v1/batches/i", func() error { return e(c.Batches.Get(ctx, "i")) }},
		{"GET", "/v1/batches/i/validation", func() error { return e(c.Batches.Validation(ctx, "i")) }},
		{"POST", "/v1/batches/i/start", func() error { return e(c.Batches.Start(ctx, "i")) }},
		{"POST", "/v1/batches/i/stop", func() error { return e(c.Batches.Stop(ctx, "i")) }},
		{"GET", "/v1/batches/i/items", func() error { return e(c.Batches.ListItems(ctx, "i", ListBatchItemsParams{})) }},
		{"POST", "/v1/otp/send", func() error { return e(c.OTP.Send(ctx, SendOTPParams{})) }},
		{"POST", "/v1/otp/verify", func() error { return e(c.OTP.Verify(ctx, VerifyOTPParams{})) }},
		{"POST", "/v1/lookup", func() error { return e(c.Lookups.Create(ctx, CreateLookupParams{})) }},
		{"GET", "/v1/lookup/i", func() error { return e(c.Lookups.Get(ctx, "i")) }},
		{"GET", "/v1/contacts", func() error { return e(c.Contacts.List(ctx, ListParams{})) }},
		{"POST", "/v1/contacts", func() error { return e(c.Contacts.Create(ctx, CreateContactParams{})) }},
		{"GET", "/v1/contacts/i", func() error { return e(c.Contacts.Get(ctx, "i")) }},
		{"PATCH", "/v1/contacts/i", func() error { return e(c.Contacts.Update(ctx, "i", UpdateContactParams{})) }},
		{"GET", "/v1/contact-groups", func() error { return e(c.ContactGroups.List(ctx, ListParams{})) }},
		{"POST", "/v1/contact-groups", func() error { return e(c.ContactGroups.Create(ctx, CreateContactGroupParams{})) }},
		{"GET", "/v1/contact-groups/i", func() error { return e(c.ContactGroups.Get(ctx, "i")) }},
		{"PATCH", "/v1/contact-groups/i", func() error { return e(c.ContactGroups.Update(ctx, "i", UpdateContactGroupParams{})) }},
		{"DELETE", "/v1/contact-groups/i", func() error { return c.ContactGroups.Delete(ctx, "i") }},
		{"POST", "/v1/contact-groups/i/send", func() error { return e(c.ContactGroups.Send(ctx, "i", GroupSendParams{})) }},
		{"GET", "/v1/templates", func() error { return e(c.Templates.List(ctx, ListParams{})) }},
		{"POST", "/v1/templates", func() error { return e(c.Templates.Create(ctx, CreateTemplateParams{})) }},
		{"GET", "/v1/templates/i", func() error { return e(c.Templates.Get(ctx, "i")) }},
		{"PATCH", "/v1/templates/i", func() error { return e(c.Templates.Update(ctx, "i", UpdateTemplateParams{})) }},
		{"DELETE", "/v1/templates/i", func() error { return c.Templates.Delete(ctx, "i") }},
		{"GET", "/v1/webhooks", func() error { return e(c.Webhooks.List(ctx, ListParams{})) }},
		{"POST", "/v1/webhooks", func() error { return e(c.Webhooks.Create(ctx, CreateWebhookParams{})) }},
		{"GET", "/v1/webhooks/i", func() error { return e(c.Webhooks.Get(ctx, "i")) }},
		{"DELETE", "/v1/webhooks/i", func() error { return c.Webhooks.Delete(ctx, "i") }},
		{"POST", "/v1/webhooks/i/test", func() error { return e(c.Webhooks.Test(ctx, "i")) }},
		{"GET", "/v1/webhooks/i/deliveries", func() error { return e(c.Webhooks.ListDeliveries(ctx, "i", ListParams{})) }},
		{"POST", "/v1/webhooks/i/deliveries/7/replay", func() error {
			return e(c.Webhooks.ReplayDelivery(ctx, "i", 7, ReplayDeliveryParams{}))
		}},
		{"GET", "/v1/inbound", func() error { return e(c.Inbound.List(ctx, ListParams{})) }},
		{"POST", "/v1/inbound/i/reply", func() error { return e(c.Inbound.Reply(ctx, "i", InboundReplyParams{})) }},
		{"GET", "/v1/numbers", func() error { return e(c.Numbers.List(ctx, ListParams{})) }},
		{"POST", "/v1/numbers", func() error { return e(c.Numbers.Assign(ctx, AssignNumberParams{})) }},
		{"DELETE", "/v1/numbers/i", func() error { return c.Numbers.Release(ctx, "i") }},
		{"GET", "/v1/numbers/i/rules", func() error { return e(c.Numbers.ListRules(ctx, "i", ListParams{})) }},
		{"POST", "/v1/numbers/i/rules", func() error { return e(c.Numbers.CreateRule(ctx, "i", NumberRuleParams{})) }},
		{"PUT", "/v1/numbers/i/rules/r", func() error { return e(c.Numbers.UpdateRule(ctx, "i", "r", NumberRuleParams{})) }},
		{"DELETE", "/v1/numbers/i/rules/r", func() error { return c.Numbers.DeleteRule(ctx, "i", "r") }},
		{"GET", "/v1/sender-ids", func() error { return e(c.SenderIDs.List(ctx, ListParams{})) }},
		{"GET", "/v1/sender-ids/i", func() error { return e(c.SenderIDs.Get(ctx, "i")) }},
		{"POST", "/v1/sender-ids", func() error { return e(c.SenderIDs.Create(ctx, CreateSenderIDParams{})) }},
		{"PATCH", "/v1/sender-ids/i", func() error { return e(c.SenderIDs.Update(ctx, "i", UpdateSenderIDParams{})) }},
		{"DELETE", "/v1/sender-ids/i", func() error { return c.SenderIDs.Delete(ctx, "i") }},
		{"GET", "/v1/sender-ids/check", func() error { return e(c.SenderIDs.Check(ctx, CheckSenderIDParams{})) }},
		{"GET", "/v1/sender-documents", func() error { return e(c.SenderIDs.ListDocuments(ctx)) }},
		{"GET", "/v1/sender-id-drafts", func() error { return e(c.SenderIDs.ListDrafts(ctx, ListParams{})) }},
		{"POST", "/v1/sender-id-drafts", func() error { return e(c.SenderIDs.CreateDraft(ctx, SenderIDDraftParams{})) }},
		{"GET", "/v1/sender-id-drafts/i", func() error { return e(c.SenderIDs.GetDraft(ctx, "i")) }},
		{"PATCH", "/v1/sender-id-drafts/i", func() error { return e(c.SenderIDs.UpdateDraft(ctx, "i", UpdateSenderIDDraftParams{})) }},
		{"DELETE", "/v1/sender-id-drafts/i", func() error { return c.SenderIDs.DeleteDraft(ctx, "i") }},
		{"GET", "/v1/compliance/suppressions", func() error { return e(c.Suppressions.List(ctx, ListParams{})) }},
		{"POST", "/v1/compliance/suppressions", func() error { return e(c.Suppressions.Create(ctx, CreateSuppressionParams{})) }},
		{"POST", "/v1/compliance/suppressions/import", func() error { return e(c.Suppressions.Import(ctx, nil)) }},
		{"DELETE", "/v1/compliance/suppressions/5", func() error { return c.Suppressions.Delete(ctx, 5) }},
		{"GET", "/v1/compliance/countries/KE", func() error { return e(c.Compliance.GetCountry(ctx, "KE")) }},
		{"GET", "/v1/wallet", func() error { return e(c.Wallet.Balances(ctx)) }},
		{"GET", "/v1/wallet/ledger", func() error { return e(c.Wallet.Ledger(ctx, LedgerParams{})) }},
		{"POST", "/v1/wallet/topups", func() error { return e(c.Wallet.CreateTopup(ctx, CreateTopupParams{})) }},
		{"GET", "/v1/pricing", func() error { return e(c.Pricing.Get(ctx, PricingParams{})) }},
		{"GET", "/v1/analytics/overview", func() error { return e(c.Analytics.Overview(ctx, AnalyticsParams{})) }},
		{"GET", "/v1/sandbox/messages", func() error { return e(c.Sandbox.ListMessages(ctx, ListParams{})) }},
		{"GET", "/v1/countries/KE/compliance", func() error { return e(c.Countries.Compliance(ctx, "KE")) }},
	}
	for _, cl := range calls {
		before := len(h.mock.requests)
		if err := cl.fn(); err != nil {
			t.Errorf("%s %s: %v", cl.method, cl.path, err)
			continue
		}
		r := h.mock.requests[before]
		if r.method != cl.method || r.path != cl.path {
			t.Errorf("want %s %s, got %s %s", cl.method, cl.path, r.method, r.path)
		}
	}
	arrCalls := []call{
		{"GET", "/v1/messages/i/attempts", func() error { return e(a.Messages.Attempts(ctx, "i")) }},
		{"GET", "/v1/numbers/available", func() error { return e(a.Numbers.Available(ctx, AvailableNumbersParams{})) }},
		{"GET", "/v1/compliance/countries", func() error { return e(a.Compliance.ListCountries(ctx)) }},
		{"GET", "/v1/content-rules", func() error { return e(a.Compliance.ListContentRules(ctx)) }},
		{"GET", "/v1/analytics/by-country", func() error { return e(a.Analytics.ByCountry(ctx, AnalyticsParams{})) }},
		{"GET", "/v1/analytics/by-carrier", func() error { return e(a.Analytics.ByCarrier(ctx, AnalyticsParams{})) }},
		{"GET", "/v1/analytics/by-sender-id", func() error { return e(a.Analytics.BySenderID(ctx, AnalyticsParams{})) }},
		{"GET", "/v1/analytics/timeseries", func() error { return e(a.Analytics.Timeseries(ctx, AnalyticsParams{})) }},
		{"GET", "/v1/countries", func() error { return e(a.Countries.List(ctx)) }},
		{"GET", "/v1/countries/KE/carriers", func() error { return e(a.Countries.Carriers(ctx, "KE")) }},
		{"GET", "/v1/countries/KE/routes", func() error { return e(a.Countries.Routes(ctx, "KE")) }},
	}
	for _, cl := range arrCalls {
		before := len(arr.mock.requests)
		if err := cl.fn(); err != nil {
			t.Errorf("%s %s: %v", cl.method, cl.path, err)
			continue
		}
		r := arr.mock.requests[before]
		if r.method != cl.method || r.path != cl.path {
			t.Errorf("want %s %s, got %s %s", cl.method, cl.path, r.method, r.path)
		}
	}
}
