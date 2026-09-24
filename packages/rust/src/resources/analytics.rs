//! The `analytics` resource.

use crate::error::Result;
use crate::http::HttpClient;
use crate::models::{AnalyticsOverview, AnalyticsPoint, AnalyticsQuery, AnalyticsRow};
use crate::util::query;

/// Accessed as `client.analytics()`.
#[derive(Debug, Clone)]
pub struct Analytics {
    http: HttpClient,
}

fn q(p: AnalyticsQuery) -> String {
    query(&[
        ("currency", p.currency),
        ("range", p.range),
        ("from", p.from),
        ("to", p.to),
        ("bucket", p.bucket),
    ])
}

impl Analytics {
    pub(crate) fn new(http: HttpClient) -> Self {
        Self { http }
    }

    /// Headline metrics.
    pub async fn overview(&self, params: AnalyticsQuery) -> Result<AnalyticsOverview> {
        self.http
            .get(&format!("/v1/analytics/overview{}", q(params)))
            .await
    }

    /// Metrics per destination country.
    pub async fn by_country(&self, params: AnalyticsQuery) -> Result<Vec<AnalyticsRow>> {
        self.http
            .get(&format!("/v1/analytics/by-country{}", q(params)))
            .await
    }

    /// Metrics per carrier.
    pub async fn by_carrier(&self, params: AnalyticsQuery) -> Result<Vec<AnalyticsRow>> {
        self.http
            .get(&format!("/v1/analytics/by-carrier{}", q(params)))
            .await
    }

    /// Metrics per sender ID.
    pub async fn by_sender_id(&self, params: AnalyticsQuery) -> Result<Vec<AnalyticsRow>> {
        self.http
            .get(&format!("/v1/analytics/by-sender-id{}", q(params)))
            .await
    }

    /// Metrics per time bucket.
    pub async fn timeseries(&self, params: AnalyticsQuery) -> Result<Vec<AnalyticsPoint>> {
        self.http
            .get(&format!("/v1/analytics/timeseries{}", q(params)))
            .await
    }
}
