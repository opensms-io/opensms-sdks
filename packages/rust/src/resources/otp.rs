//! The `otp` resource: send and verify one-time passcodes.

use super::idem;
use crate::error::Result;
use crate::http::{HttpClient, Idem};
use crate::models::{OtpSendResult, OtpVerifyResult, RequestOptions, SendOtp, VerifyOtp};

/// Accessed as `client.otp()`.
#[derive(Debug, Clone)]
pub struct Otp {
    http: HttpClient,
}

impl Otp {
    pub(crate) fn new(http: HttpClient) -> Self {
        Self { http }
    }

    /// Send a code (`POST /v1/otp/send`).
    pub async fn send(&self, params: &SendOtp) -> Result<OtpSendResult> {
        self.send_with(params, &RequestOptions::default()).await
    }

    /// [`Otp::send`] with an explicit Idempotency-Key.
    pub async fn send_with(
        &self,
        params: &SendOtp,
        opts: &RequestOptions,
    ) -> Result<OtpSendResult> {
        self.http
            .send("POST", "/v1/otp/send", params, idem(opts))
            .await
    }

    /// Check a code. A wrong code returns `valid: false` and burns an
    /// attempt, so this is never retried.
    pub async fn verify(&self, params: &VerifyOtp) -> Result<OtpVerifyResult> {
        self.http
            .send("POST", "/v1/otp/verify", params, Idem::None)
            .await
    }
}
