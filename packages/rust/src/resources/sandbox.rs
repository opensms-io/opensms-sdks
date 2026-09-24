//! The `sandbox` resource: rendered sandbox messages (including OTP codes).

use super::list_query;
use crate::error::Result;
use crate::http::HttpClient;
use crate::models::{ListParams, Page, SandboxMessage};

/// Accessed as `client.sandbox()`.
#[derive(Debug, Clone)]
pub struct Sandbox {
    http: HttpClient,
}

impl Sandbox {
    pub(crate) fn new(http: HttpClient) -> Self {
        Self { http }
    }

    /// List sandbox messages with their rendered text.
    pub async fn list_messages(&self, params: ListParams) -> Result<Page<SandboxMessage>> {
        self.http
            .get(&format!("/v1/sandbox/messages{}", list_query(&params)))
            .await
    }
}
