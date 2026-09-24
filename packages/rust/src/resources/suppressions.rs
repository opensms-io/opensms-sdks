//! The `suppressions` resource: the do-not-send list.

use serde::Serialize;

use super::list_query;
use crate::error::Result;
use crate::http::{HttpClient, Idem};
use crate::models::{CreateSuppression, ListParams, Page, Suppression, SuppressionImportResult};

#[derive(Serialize)]
struct ImportBody<'a> {
    items: &'a [CreateSuppression],
}

/// Accessed as `client.suppressions()`.
#[derive(Debug, Clone)]
pub struct Suppressions {
    http: HttpClient,
}

impl Suppressions {
    pub(crate) fn new(http: HttpClient) -> Self {
        Self { http }
    }

    /// List suppressions.
    pub async fn list(&self, params: ListParams) -> Result<Page<Suppression>> {
        self.http
            .get(&format!(
                "/v1/compliance/suppressions{}",
                list_query(&params)
            ))
            .await
    }

    /// Suppress a number. Not retried.
    pub async fn create(&self, params: &CreateSuppression) -> Result<Suppression> {
        self.http
            .send("POST", "/v1/compliance/suppressions", params, Idem::None)
            .await
    }

    /// Bulk-import suppressions. Not retried.
    pub async fn import(&self, items: &[CreateSuppression]) -> Result<SuppressionImportResult> {
        self.http
            .send(
                "POST",
                "/v1/compliance/suppressions/import",
                &ImportBody { items },
                Idem::None,
            )
            .await
    }

    /// Remove a suppression.
    pub async fn delete(&self, id: i64) -> Result<()> {
        self.http
            .empty(
                "DELETE",
                &format!("/v1/compliance/suppressions/{id}"),
                Idem::None,
            )
            .await
    }
}
