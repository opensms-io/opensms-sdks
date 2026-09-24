//! Error type returned by the SDK.

use std::collections::HashMap;
use std::fmt;

use serde_json::Value;

/// What kind of failure an [`OpensmsError`] describes.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ErrorKind {
    /// The API answered with a non-2xx status (`status` is that status).
    Api,
    /// No HTTP response: network failure, timeout, or an undecodable body
    /// (`status` is `0`).
    Transport,
    /// A local argument check failed before any request was sent (bad API
    /// key, empty id). `status` is `0`.
    InvalidArgument,
    /// Webhook signature verification failed (`code` is `invalid_signature`
    /// or `expired_signature`). `status` is `0`.
    Signature,
}

/// Returned for every non-2xx response, for transport failures that survive
/// all retries, for invalid arguments, and for webhook signature failures.
///
/// Branch on [`OpensmsError::status`] first: most API errors carry no `code`.
/// Insufficient scope is `401` on messages and OTP but `403` everywhere else.
#[derive(Debug, Clone)]
pub struct OpensmsError {
    /// Failure category.
    pub kind: ErrorKind,
    /// HTTP status. `0` means no HTTP response was received.
    pub status: u16,
    /// Problem `type` URI (`about:blank` or `https://api.opensms.io/problems/<code>`).
    pub r#type: Option<String>,
    /// Problem `title` (`Bad Request`, `Unauthorized`, ...).
    pub title: Option<String>,
    /// Problem `detail`, the human-readable explanation.
    pub detail: Option<String>,
    /// Machine-readable `code`, present on only a few errors.
    pub code: Option<String>,
    /// Problem `trace_id`, when present.
    pub trace_id: Option<String>,
    /// Field validation errors (`errors`), when present.
    pub errors: Option<HashMap<String, Vec<String>>>,
    /// `X-Request-ID` response header (message and OTP admission rejections).
    pub request_id: Option<String>,
    /// `Retry-After` in seconds, when the server sent one.
    pub retry_after: Option<u64>,
    /// Raw decoded body: JSON when it parsed, otherwise a JSON string holding the text.
    pub body: Option<Value>,
    /// Display message: `detail`, else `title`, else a generic text.
    pub message: String,
}

impl OpensmsError {
    fn bare(kind: ErrorKind, status: u16, message: String, code: Option<String>) -> Self {
        Self {
            kind,
            status,
            r#type: None,
            title: None,
            detail: None,
            code,
            trace_id: None,
            errors: None,
            request_id: None,
            retry_after: None,
            body: None,
            message,
        }
    }

    /// A transport-level error (no HTTP response). `status` is `0`.
    pub fn transport(message: impl Into<String>) -> Self {
        Self::bare(ErrorKind::Transport, 0, message.into(), None)
    }

    /// A local argument error. `status` is `0`, `code` is `invalid_argument`.
    pub fn invalid_argument(message: impl Into<String>) -> Self {
        Self::bare(
            ErrorKind::InvalidArgument,
            0,
            message.into(),
            Some("invalid_argument".to_string()),
        )
    }

    /// A webhook signature failure with the given `code`.
    pub fn signature(code: &str, message: impl Into<String>) -> Self {
        Self::bare(
            ErrorKind::Signature,
            0,
            message.into(),
            Some(code.to_string()),
        )
    }

    /// Map an HTTP error response into an error. The body is parsed as RFC 9457
    /// problem+json when possible; otherwise it is kept as text in `body`.
    pub(crate) fn from_response(
        status: u16,
        body: &[u8],
        request_id: Option<String>,
        retry_after: Option<u64>,
    ) -> Self {
        let parsed: Option<Value> = if body.is_empty() {
            None
        } else {
            serde_json::from_slice(body).ok()
        };
        let obj = parsed.as_ref().and_then(|v| v.as_object());
        let s = |k: &str| -> Option<String> {
            obj.and_then(|o| o.get(k))
                .and_then(|v| v.as_str())
                .map(String::from)
        };
        let errors = obj
            .and_then(|o| o.get("errors"))
            .and_then(|v| serde_json::from_value::<HashMap<String, Vec<String>>>(v.clone()).ok());
        let detail = s("detail");
        let title = s("title");
        let message = detail
            .clone()
            .or_else(|| title.clone())
            .unwrap_or_else(|| format!("OpenSMS request failed with status {status}"));
        let (r#type, code, trace_id) = (s("type"), s("code"), s("trace_id"));
        let raw = match parsed {
            Some(v) => Some(v),
            None if !body.is_empty() => {
                Some(Value::String(String::from_utf8_lossy(body).into_owned()))
            }
            None => None,
        };
        Self {
            kind: ErrorKind::Api,
            status,
            r#type,
            title,
            detail,
            code,
            trace_id,
            errors,
            request_id,
            retry_after,
            body: raw,
            message,
        }
    }
}

impl fmt::Display for OpensmsError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match &self.code {
            Some(code) => write!(
                f,
                "OpenSMS error {} ({}): {}",
                self.status, code, self.message
            ),
            None => write!(f, "OpenSMS error {}: {}", self.status, self.message),
        }
    }
}

impl std::error::Error for OpensmsError {}

/// Convenience alias for results returned by the SDK.
pub type Result<T> = std::result::Result<T, OpensmsError>;
