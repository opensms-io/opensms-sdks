//! The `compliance` resource: country rules and content rules.

use super::seg;
use crate::error::Result;
use crate::http::HttpClient;
use crate::models::{ContentRule, CountryRules};

/// Accessed as `client.compliance()`.
#[derive(Debug, Clone)]
pub struct Compliance {
    http: HttpClient,
}

impl Compliance {
    pub(crate) fn new(http: HttpClient) -> Self {
        Self { http }
    }

    /// Rules for every country.
    pub async fn list_countries(&self) -> Result<Vec<CountryRules>> {
        self.http.get("/v1/compliance/countries").await
    }

    /// Rules for one country (ISO2).
    pub async fn get_country(&self, iso2: &str) -> Result<CountryRules> {
        self.http
            .get(&format!("/v1/compliance/countries/{}", seg(iso2, "iso2")?))
            .await
    }

    /// Content rules that apply to the workspace.
    pub async fn list_content_rules(&self) -> Result<Vec<ContentRule>> {
        self.http.get("/v1/content-rules").await
    }
}
