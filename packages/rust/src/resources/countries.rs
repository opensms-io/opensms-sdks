//! The `countries` resource: the public destination catalog.

use super::seg;
use crate::error::Result;
use crate::http::HttpClient;
use crate::models::{Carrier, Country, CountryRules, Route};

/// Accessed as `client.countries()`.
#[derive(Debug, Clone)]
pub struct Countries {
    http: HttpClient,
}

impl Countries {
    pub(crate) fn new(http: HttpClient) -> Self {
        Self { http }
    }

    /// Active destination countries with workspace pricing.
    pub async fn list(&self) -> Result<Vec<Country>> {
        self.http.get("/v1/countries").await
    }

    /// Carriers in a country.
    pub async fn carriers(&self, iso2: &str) -> Result<Vec<Carrier>> {
        self.http
            .get(&format!("/v1/countries/{}/carriers", seg(iso2, "iso2")?))
            .await
    }

    /// Routable routes in a country.
    pub async fn routes(&self, iso2: &str) -> Result<Vec<Route>> {
        self.http
            .get(&format!("/v1/countries/{}/routes", seg(iso2, "iso2")?))
            .await
    }

    /// Compliance rules for a country.
    pub async fn compliance(&self, iso2: &str) -> Result<CountryRules> {
        self.http
            .get(&format!("/v1/countries/{}/compliance", seg(iso2, "iso2")?))
            .await
    }
}
