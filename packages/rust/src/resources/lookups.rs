//! The `lookups` resource: number intelligence lookups.

use super::{idem, seg};
use crate::error::Result;
use crate::http::HttpClient;
use crate::models::{CreateLookup, Lookup, RequestOptions};

/// Accessed as `client.lookups()`.
#[derive(Debug, Clone)]
pub struct Lookups {
    http: HttpClient,
}

impl Lookups {
    pub(crate) fn new(http: HttpClient) -> Self {
        Self { http }
    }

    /// Request a lookup (`POST /v1/lookup`). Returns the completed lookup
    /// (200) or a pending one (202).
    pub async fn create(&self, params: &CreateLookup) -> Result<Lookup> {
        self.create_with(params, &RequestOptions::default()).await
    }

    /// [`Lookups::create`] with an explicit Idempotency-Key.
    pub async fn create_with(
        &self,
        params: &CreateLookup,
        opts: &RequestOptions,
    ) -> Result<Lookup> {
        self.http
            .send("POST", "/v1/lookup", params, idem(opts))
            .await
    }

    /// Fetch a lookup.
    pub async fn get(&self, id: &str) -> Result<Lookup> {
        self.http
            .get(&format!("/v1/lookup/{}", seg(id, "id")?))
            .await
    }
}
