//! The `pricing` resource.

use crate::error::Result;
use crate::http::HttpClient;
use crate::models::{PriceList, PricingParams};
use crate::util::query;

/// Accessed as `client.pricing()`.
#[derive(Debug, Clone)]
pub struct Pricing {
    http: HttpClient,
}

impl Pricing {
    pub(crate) fn new(http: HttpClient) -> Self {
        Self { http }
    }

    /// The workspace price list for a product and optional country.
    pub async fn get(&self, params: PricingParams) -> Result<PriceList> {
        let q = query(&[("product", params.product), ("country", params.country)]);
        self.http.get(&format!("/v1/pricing{q}")).await
    }
}
