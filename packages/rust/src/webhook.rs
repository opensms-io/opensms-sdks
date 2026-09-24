//! Webhook signature verification.
//!
//! The API signs every delivery with
//! `X-OpenSMS-Signature: t=<unix seconds>,v1=<hex>`, where
//! `v1 = hex(HMAC-SHA256(secret, "<t>." + raw body))` and `secret` is the full
//! `whsec_...` string returned once by `webhooks.create`. Parsing mirrors the
//! server exactly. These functions need no client or API key.

use std::collections::HashMap;

use crate::crypto::{constant_time_eq, hmac_sha256, unhex};
use crate::error::{OpensmsError, Result};
use crate::models::WebhookEvent;
use crate::util::unix_now;

/// The header that carries the signature.
pub const SIGNATURE_HEADER: &str = "X-OpenSMS-Signature";

/// Default allowed clock skew, in seconds.
pub const DEFAULT_TOLERANCE_SECONDS: i64 = 300;

/// Options for [`verify_signature`] and [`construct_event`].
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct VerifyOptions {
    /// Maximum `|now - t|` in seconds (inclusive). Default 300.
    pub tolerance_seconds: i64,
    /// Current Unix time override, for tests. Default: the system clock.
    pub now: Option<i64>,
}

impl Default for VerifyOptions {
    fn default() -> Self {
        Self {
            tolerance_seconds: DEFAULT_TOLERANCE_SECONDS,
            now: None,
        }
    }
}

enum Failure {
    Invalid,
    Expired,
}

fn check(
    payload: &[u8],
    header: &str,
    secret: &str,
    opts: VerifyOptions,
) -> std::result::Result<(), Failure> {
    if secret.trim().is_empty() || opts.tolerance_seconds < 0 {
        return Err(Failure::Invalid);
    }
    let mut fields: HashMap<&str, &str> = HashMap::new();
    for part in header.split(',') {
        let part = part.trim();
        let (k, v) = part.split_once('=').ok_or(Failure::Invalid)?;
        if k.is_empty() || v.is_empty() || fields.insert(k, v).is_some() {
            return Err(Failure::Invalid);
        }
    }
    if fields.len() != 2 {
        return Err(Failure::Invalid);
    }
    let t_raw = *fields.get("t").ok_or(Failure::Invalid)?;
    let v1 = *fields.get("v1").ok_or(Failure::Invalid)?;
    let t: i64 = t_raw.parse().map_err(|_| Failure::Invalid)?;
    let now = opts.now.unwrap_or_else(unix_now);
    if (now - t).abs() > opts.tolerance_seconds {
        return Err(Failure::Expired);
    }
    if v1.len() != 64 {
        return Err(Failure::Invalid);
    }
    let given = unhex(v1).ok_or(Failure::Invalid)?;
    let mut message = Vec::with_capacity(t_raw.len() + 1 + payload.len());
    message.extend_from_slice(t_raw.as_bytes());
    message.push(b'.');
    message.extend_from_slice(payload);
    let expected = hmac_sha256(secret.as_bytes(), &message);
    if constant_time_eq(&expected, &given) {
        Ok(())
    } else {
        Err(Failure::Invalid)
    }
}

/// `true` when `header` is a valid, fresh signature of `payload` (the exact
/// raw body bytes) under `secret`.
pub fn verify_signature(payload: &[u8], header: &str, secret: &str, opts: VerifyOptions) -> bool {
    check(payload, header, secret, opts).is_ok()
}

/// Verify the signature, then parse the event envelope. Fails with an
/// [`OpensmsError`] whose `code` is `invalid_signature` or `expired_signature`.
pub fn construct_event(
    payload: &[u8],
    header: &str,
    secret: &str,
    opts: VerifyOptions,
) -> Result<WebhookEvent> {
    match check(payload, header, secret, opts) {
        Ok(()) => serde_json::from_slice(payload)
            .map_err(|e| OpensmsError::transport(format!("failed to decode webhook event: {e}"))),
        Err(Failure::Invalid) => Err(OpensmsError::signature(
            "invalid_signature",
            "webhook signature does not match",
        )),
        Err(Failure::Expired) => Err(OpensmsError::signature(
            "expired_signature",
            "webhook signature timestamp is outside the tolerance",
        )),
    }
}
