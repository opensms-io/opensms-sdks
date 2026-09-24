package opensms

import (
	"encoding/json"
	"errors"
	"fmt"
	"time"
)

// ErrInvalidArgument is wrapped by errors returned before any request is made
// (an invalid API key in NewClient, an empty id). Test with errors.Is.
var ErrInvalidArgument = errors.New("opensms: invalid argument")

// Error is returned for every non-2xx API response, for transport failures
// that survive all retries, and for webhook signature failures. It is mapped
// from the RFC 9457 problem+json body the API returns.
//
// Most OpenSMS errors carry no Code, so branch on Status first and use Detail
// for display. Insufficient scope is 401 on messages and otp but 403 on every
// other resource.
type Error struct {
	// Status is the HTTP status code. 0 means no response was received
	// (network failure, timeout) or a local failure such as an invalid
	// webhook signature.
	Status int
	// Type is the problem type URI, usually "about:blank", otherwise
	// "https://api.opensms.io/problems/<code>".
	Type string
	// Title is the short problem title ("Bad Request", "Unauthorized", ...).
	Title string
	// Detail is the human-readable explanation.
	Detail string
	// Code is the machine-readable code, when the handler sets one
	// ("invalid_message_id", "not_found", "invalid_signature", ...).
	Code string
	// TraceID is the problem trace_id, when present.
	TraceID string
	// Errors holds field validation errors, when present.
	Errors map[string][]string
	// RequestID is the X-Request-ID response header, set on message and OTP
	// admission rejections (for example 422 destination is suppressed).
	RequestID string
	// RetryAfter is the Retry-After header value, or 0 when absent.
	RetryAfter time.Duration
	// Body is the raw response body (JSON or text), for debugging.
	Body []byte

	message string
	cause   error
}

// Error implements the error interface.
func (e *Error) Error() string {
	msg := e.Message()
	if e.Code != "" {
		return fmt.Sprintf("opensms: %s (status %d, code %s)", msg, e.Status, e.Code)
	}
	return fmt.Sprintf("opensms: %s (status %d)", msg, e.Status)
}

// Message returns Detail, else Title, else a generic message with the status.
func (e *Error) Message() string {
	switch {
	case e.message != "":
		return e.message
	case e.Detail != "":
		return e.Detail
	case e.Title != "":
		return e.Title
	default:
		return fmt.Sprintf("OpenSMS request failed with status %d", e.Status)
	}
}

// Unwrap returns the underlying transport error, if any.
func (e *Error) Unwrap() error { return e.cause }

type problem struct {
	Type    string              `json:"type"`
	Title   string              `json:"title"`
	Detail  string              `json:"detail"`
	Code    string              `json:"code"`
	TraceID string              `json:"trace_id"`
	Errors  map[string][]string `json:"errors"`
}

// newAPIError maps a non-2xx response into *Error. Non-JSON bodies (a proxy
// HTML page, for example) leave every problem field empty and keep the text
// in Body.
func newAPIError(status int, body []byte, requestID string, retryAfter time.Duration) *Error {
	e := &Error{Status: status, Body: body, RequestID: requestID, RetryAfter: retryAfter}
	var p problem
	if len(body) > 0 && json.Unmarshal(body, &p) == nil {
		e.Type = p.Type
		e.Title = p.Title
		e.Detail = p.Detail
		e.Code = p.Code
		e.TraceID = p.TraceID
		e.Errors = p.Errors
	}
	return e
}

// newLocalError builds an *Error with Status 0 for failures with no response.
func newLocalError(code, message string, cause error) *Error {
	return &Error{Status: 0, Code: code, message: message, cause: cause}
}
