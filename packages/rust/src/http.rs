//! HTTP transport: the single place that talks to the network.
//!
//! Owns authentication (bearer), default headers, Idempotency-Key handling,
//! JSON encode/decode, retries with backoff on `429`/`5xx`/network errors
//! (honouring `Retry-After`), and turning non-2xx responses into
//! [`OpensmsError`]. Resources depend on this, never on `reqwest` directly.
//!
//! The wire itself sits behind the [`Transport`] trait so tests (and callers
//! with special needs) can inject their own; [`ReqwestTransport`] is the
//! default. Waiting between retries goes through [`Sleeper`] for the same
//! reason.

use std::fmt;
use std::future::Future;
use std::pin::Pin;
use std::sync::Arc;
use std::time::Duration;

use serde::de::DeserializeOwned;
use serde::Serialize;

use crate::error::{OpensmsError, Result};
use crate::util;

pub(crate) const DEFAULT_BASE_URL: &str = "https://opensms.io";
/// The `User-Agent` sent on every request.
pub const USER_AGENT: &str = concat!("opensms-rust/", env!("CARGO_PKG_VERSION"));
const MAX_RETRY_AFTER_SECS: u64 = 60;
const BACKOFF_BASE_SECS: f64 = 0.5;
const BACKOFF_CAP_SECS: f64 = 8.0;

/// A boxed, `Send` future, used by the [`Transport`] and [`Sleeper`] traits.
pub type BoxFuture<'a, T> = Pin<Box<dyn Future<Output = T> + Send + 'a>>;

/// One HTTP request as handed to a [`Transport`].
#[derive(Debug, Clone)]
pub struct HttpRequest {
    /// Upper-case method (`GET`, `POST`, ...).
    pub method: String,
    /// Absolute URL including the query string.
    pub url: String,
    /// Header name/value pairs.
    pub headers: Vec<(String, String)>,
    /// Request body, if any.
    pub body: Option<Vec<u8>>,
}

impl HttpRequest {
    /// Case-insensitive header lookup.
    pub fn header(&self, name: &str) -> Option<&str> {
        find_header(&self.headers, name)
    }
}

/// One HTTP response as returned by a [`Transport`].
#[derive(Debug, Clone)]
pub struct HttpResponse {
    /// Status code.
    pub status: u16,
    /// Header name/value pairs.
    pub headers: Vec<(String, String)>,
    /// Raw body bytes (empty for `204`).
    pub body: Vec<u8>,
}

impl HttpResponse {
    /// Case-insensitive header lookup.
    pub fn header(&self, name: &str) -> Option<&str> {
        find_header(&self.headers, name)
    }
}

fn find_header<'a>(headers: &'a [(String, String)], name: &str) -> Option<&'a str> {
    headers
        .iter()
        .find(|(k, _)| k.eq_ignore_ascii_case(name))
        .map(|(_, v)| v.as_str())
}

/// Sends one HTTP request. Return `Err` for network failures and timeouts
/// (anything with no HTTP response); every HTTP status is an `Ok`.
pub trait Transport: Send + Sync {
    /// Perform the request with the given per-attempt timeout.
    fn send(
        &self,
        request: HttpRequest,
        timeout: Duration,
    ) -> BoxFuture<'_, std::result::Result<HttpResponse, String>>;
}

/// Waits between retry attempts. Tests inject one that returns immediately.
pub trait Sleeper: Send + Sync {
    /// Wait for `duration`.
    fn sleep(&self, duration: Duration) -> BoxFuture<'static, ()>;
}

/// The default [`Transport`], backed by `reqwest`.
#[derive(Debug, Clone)]
pub struct ReqwestTransport {
    client: reqwest::Client,
}

impl ReqwestTransport {
    /// Build the default transport.
    pub fn new() -> Result<Self> {
        let client = reqwest::Client::builder()
            .build()
            .map_err(|e| OpensmsError::transport(format!("failed to build HTTP client: {e}")))?;
        Ok(Self { client })
    }
}

impl Transport for ReqwestTransport {
    fn send(
        &self,
        request: HttpRequest,
        timeout: Duration,
    ) -> BoxFuture<'_, std::result::Result<HttpResponse, String>> {
        Box::pin(async move {
            let method = reqwest::Method::from_bytes(request.method.as_bytes())
                .map_err(|e| e.to_string())?;
            let mut builder = self.client.request(method, &request.url).timeout(timeout);
            for (k, v) in &request.headers {
                builder = builder.header(k.as_str(), v.as_str());
            }
            if let Some(body) = request.body {
                builder = builder.body(body);
            }
            let res = builder.send().await.map_err(|e| e.to_string())?;
            let status = res.status().as_u16();
            let headers = res
                .headers()
                .iter()
                .map(|(k, v)| (k.as_str().to_string(), v.to_str().unwrap_or("").to_string()))
                .collect();
            let body = res.bytes().await.map_err(|e| e.to_string())?.to_vec();
            Ok(HttpResponse {
                status,
                headers,
                body,
            })
        })
    }
}

/// The default [`Sleeper`], backed by `tokio::time::sleep`.
#[derive(Debug, Clone, Copy, Default)]
pub struct TokioSleeper;

impl Sleeper for TokioSleeper {
    fn sleep(&self, duration: Duration) -> BoxFuture<'static, ()> {
        Box::pin(tokio::time::sleep(duration))
    }
}

/// Idempotency handling for one call.
pub(crate) enum Idem<'a> {
    /// The method never sends the header.
    None,
    /// The method sends one: the caller's key, or a generated UUIDv4.
    Key(Option<&'a str>),
}

/// A request body.
pub(crate) enum Body {
    Empty,
    Json(Vec<u8>),
    Raw {
        content_type: String,
        bytes: Vec<u8>,
    },
}

impl Body {
    pub(crate) fn json<B: Serialize + ?Sized>(b: &B) -> Result<Self> {
        serde_json::to_vec(b)
            .map(Body::Json)
            .map_err(|e| OpensmsError::transport(format!("failed to encode request body: {e}")))
    }
}

/// The transport shared by every resource.
#[derive(Clone)]
pub(crate) struct HttpClient {
    inner: Arc<Inner>,
}

struct Inner {
    api_key: String,
    base_url: String,
    timeout: Duration,
    max_retries: u32,
    transport: Arc<dyn Transport>,
    sleeper: Arc<dyn Sleeper>,
}

impl fmt::Debug for HttpClient {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("HttpClient")
            .field("base_url", &self.inner.base_url)
            .field("timeout", &self.inner.timeout)
            .field("max_retries", &self.inner.max_retries)
            .finish_non_exhaustive()
    }
}

impl HttpClient {
    pub(crate) fn new(
        api_key: String,
        base_url: String,
        timeout: Duration,
        max_retries: u32,
        transport: Arc<dyn Transport>,
        sleeper: Arc<dyn Sleeper>,
    ) -> Self {
        Self {
            inner: Arc::new(Inner {
                api_key,
                base_url: base_url.trim_end_matches('/').to_string(),
                timeout,
                max_retries,
                transport,
                sleeper,
            }),
        }
    }

    pub(crate) fn base_url(&self) -> &str {
        &self.inner.base_url
    }

    /// `GET` and decode JSON.
    pub(crate) async fn get<T: DeserializeOwned>(&self, path: &str) -> Result<T> {
        self.json("GET", path, Body::Empty, Idem::None).await
    }

    /// Any method with a JSON body, decoding the JSON response.
    pub(crate) async fn send<B: Serialize + ?Sized, T: DeserializeOwned>(
        &self,
        method: &'static str,
        path: &str,
        body: &B,
        idem: Idem<'_>,
    ) -> Result<T> {
        self.json(method, path, Body::json(body)?, idem).await
    }

    /// Execute and decode a JSON response.
    pub(crate) async fn json<T: DeserializeOwned>(
        &self,
        method: &'static str,
        path: &str,
        body: Body,
        idem: Idem<'_>,
    ) -> Result<T> {
        let res = self.execute(method, path, body, idem).await?;
        let bytes: &[u8] = if res.body.is_empty() {
            b"null"
        } else {
            &res.body
        };
        serde_json::from_slice(bytes)
            .map_err(|e| OpensmsError::transport(format!("failed to decode response: {e}")))
    }

    /// Execute and ignore the body (`204 No Content`).
    pub(crate) async fn empty(
        &self,
        method: &'static str,
        path: &str,
        idem: Idem<'_>,
    ) -> Result<()> {
        self.execute(method, path, Body::Empty, idem)
            .await
            .map(|_| ())
    }

    /// Run the request with retries. Returns the 2xx response or an error.
    pub(crate) async fn execute(
        &self,
        method: &'static str,
        path: &str,
        body: Body,
        idem: Idem<'_>,
    ) -> Result<HttpResponse> {
        let inner = &self.inner;
        let mut headers = vec![
            (
                "Authorization".to_string(),
                format!("Bearer {}", inner.api_key),
            ),
            ("Accept".to_string(), "application/json".to_string()),
            ("User-Agent".to_string(), USER_AGENT.to_string()),
        ];
        let body_bytes = match body {
            Body::Empty => None,
            Body::Json(b) => {
                headers.push(("Content-Type".to_string(), "application/json".to_string()));
                Some(b)
            }
            Body::Raw {
                content_type,
                bytes,
            } => {
                headers.push(("Content-Type".to_string(), content_type));
                Some(bytes)
            }
        };
        let has_key = match idem {
            Idem::None => false,
            Idem::Key(k) => {
                // Generated once per call and reused on every retry.
                let key = k.map(String::from).unwrap_or_else(util::uuid_v4);
                headers.push(("Idempotency-Key".to_string(), key));
                true
            }
        };
        // POSTs are only safe to repeat when they carry an Idempotency-Key.
        let can_retry = method != "POST" || has_key;
        let request = HttpRequest {
            method: method.to_string(),
            url: format!("{}{}", inner.base_url, path),
            headers,
            body: body_bytes,
        };

        let attempts = inner.max_retries + 1;
        let mut attempt = 1;
        loop {
            let last = attempt >= attempts || !can_retry;
            match inner.transport.send(request.clone(), inner.timeout).await {
                Ok(res) if (200..300).contains(&res.status) => return Ok(res),
                Ok(res) => {
                    let retry_after = parse_retry_after(res.header("retry-after"));
                    let request_id = res.header("x-request-id").map(String::from);
                    let err = || {
                        OpensmsError::from_response(
                            res.status,
                            &res.body,
                            request_id.clone(),
                            retry_after,
                        )
                    };
                    if last || !retryable_status(res.status) {
                        return Err(err());
                    }
                    let delay = match retry_after {
                        Some(secs) if secs > MAX_RETRY_AFTER_SECS => return Err(err()),
                        Some(secs) => Duration::from_secs(secs),
                        None => backoff(attempt),
                    };
                    inner.sleeper.sleep(delay).await;
                }
                Err(e) => {
                    if last {
                        return Err(OpensmsError::transport(format!(
                            "OpenSMS request failed: {e}"
                        )));
                    }
                    inner.sleeper.sleep(backoff(attempt)).await;
                }
            }
            attempt += 1;
        }
    }
}

fn retryable_status(status: u16) -> bool {
    matches!(status, 429 | 500 | 502 | 503 | 504)
}

/// Full-jitter exponential backoff: `random(0, min(8 s, 0.5 s * 2^(n-1)))`.
fn backoff(attempt: u32) -> Duration {
    let ceiling =
        (BACKOFF_BASE_SECS * 2f64.powi(attempt.saturating_sub(1) as i32)).min(BACKOFF_CAP_SECS);
    Duration::from_secs_f64(util::random_f64() * ceiling)
}

/// `Retry-After` as whole seconds: an integer, or an HTTP date relative to now.
fn parse_retry_after(value: Option<&str>) -> Option<u64> {
    let v = value?.trim();
    if let Ok(n) = v.parse::<u64>() {
        return Some(n);
    }
    if let Ok(f) = v.parse::<f64>() {
        if f.is_finite() && f >= 0.0 {
            return Some(f.ceil() as u64);
        }
    }
    let at = util::parse_http_date(v)?;
    Some((at - util::unix_now()).max(0) as u64)
}
