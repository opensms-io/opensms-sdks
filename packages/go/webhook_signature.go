package opensms

import (
	"crypto/hmac"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"errors"
	"strconv"
	"strings"
	"time"
)

// SignatureHeader is the header that carries a webhook delivery signature.
const SignatureHeader = "X-OpenSMS-Signature"

// DefaultSignatureTolerance is the default allowed clock skew.
const DefaultSignatureTolerance = 300 * time.Second

// VerifyOptions tunes signature verification.
type VerifyOptions struct {
	// Tolerance is the allowed difference between now and the signed
	// timestamp (default 300s). The boundary is inclusive.
	Tolerance time.Duration
	// Now overrides the current time (for tests).
	Now time.Time
}

var (
	errInvalidSignature = errors.New("invalid signature")
	errExpiredSignature = errors.New("expired signature")
)

// VerifySignature reports whether header (the X-OpenSMS-Signature value) is
// a valid signature of payload, the exact raw request body, for the endpoint
// secret. The secret is used verbatim, including its whsec_ prefix. It needs
// no API key or client.
func VerifySignature(payload []byte, header, secret string, opts ...VerifyOptions) bool {
	return verifySignature(payload, header, secret, opts...) == nil
}

// ConstructEvent verifies the signature and then decodes the event envelope.
// A bad signature returns *Error with Status 0 and Code "invalid_signature";
// a timestamp outside the tolerance returns Code "expired_signature".
func ConstructEvent(payload []byte, header, secret string, opts ...VerifyOptions) (*WebhookEvent, error) {
	switch err := verifySignature(payload, header, secret, opts...); err {
	case nil:
	case errExpiredSignature:
		return nil, newLocalError("expired_signature", "webhook signature timestamp is outside the tolerance", err)
	default:
		return nil, newLocalError("invalid_signature", "webhook signature is invalid", err)
	}
	var ev WebhookEvent
	if err := json.Unmarshal(payload, &ev); err != nil {
		return nil, newLocalError("invalid_payload", "webhook payload is not valid JSON: "+err.Error(), err)
	}
	return &ev, nil
}

// verifySignature mirrors the server's VerifyWithTolerance exactly.
func verifySignature(payload []byte, header, secret string, opts ...VerifyOptions) error {
	tolerance := DefaultSignatureTolerance
	now := time.Now()
	if len(opts) > 0 {
		if opts[0].Tolerance > 0 {
			tolerance = opts[0].Tolerance
		}
		if !opts[0].Now.IsZero() {
			now = opts[0].Now
		}
	}
	if strings.TrimSpace(secret) == "" {
		return errInvalidSignature
	}
	values, ok := parseSignatureHeader(header)
	if !ok {
		return errInvalidSignature
	}
	ts, err := strconv.ParseInt(values["t"], 10, 64)
	if err != nil {
		return errInvalidSignature
	}
	when := time.Unix(ts, 0)
	if now.Sub(when) > tolerance || when.Sub(now) > tolerance {
		return errExpiredSignature
	}
	want, err := hex.DecodeString(values["v1"])
	if err != nil || len(want) != sha256.Size {
		return errInvalidSignature
	}
	h := hmac.New(sha256.New, []byte(secret))
	h.Write([]byte(values["t"]))
	h.Write([]byte("."))
	h.Write(payload)
	if subtle.ConstantTimeCompare(h.Sum(nil), want) != 1 {
		return errInvalidSignature
	}
	return nil
}

// parseSignatureHeader requires exactly the keys t and v1, no empty keys or
// values and no duplicates.
func parseSignatureHeader(header string) (map[string]string, bool) {
	values := make(map[string]string, 2)
	for _, part := range strings.Split(header, ",") {
		pair := strings.SplitN(strings.TrimSpace(part), "=", 2)
		if len(pair) != 2 || pair[0] == "" || pair[1] == "" {
			return nil, false
		}
		if _, dup := values[pair[0]]; dup {
			return nil, false
		}
		values[pair[0]] = pair[1]
	}
	if len(values) != 2 || values["t"] == "" || values["v1"] == "" {
		return nil, false
	}
	return values, true
}
