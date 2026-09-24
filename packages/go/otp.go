package opensms

import (
	"context"
	"net/http"
)

// OTP is the one-time passcode resource, reached as client.OTP.
type OTP struct {
	http *transport
}

// Send generates and sends a code (POST /v1/otp/send).
func (r *OTP) Send(ctx context.Context, params SendOTPParams, opts ...CallOption) (*OTPSendResult, error) {
	var out OTPSendResult
	err := r.http.do(ctx, request{method: http.MethodPost, path: "/v1/otp/send", body: params, idempotent: true, opts: applyCallOptions(opts)}, &out)
	if err != nil {
		return nil, err
	}
	return &out, nil
}

// Verify checks a code (POST /v1/otp/verify). A wrong code returns
// Valid false and uses up an attempt, so Verify is never retried.
func (r *OTP) Verify(ctx context.Context, params VerifyOTPParams) (*OTPVerifyResult, error) {
	var out OTPVerifyResult
	if err := r.http.do(ctx, request{method: http.MethodPost, path: "/v1/otp/verify", body: params, noRetry: true}, &out); err != nil {
		return nil, err
	}
	return &out, nil
}
