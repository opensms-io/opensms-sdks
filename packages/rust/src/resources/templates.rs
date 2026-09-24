//! The `templates` resource.

use super::{idem, list_query, seg};
use crate::error::Result;
use crate::http::{HttpClient, Idem};
use crate::models::{CreateTemplate, ListParams, Page, RequestOptions, Template, UpdateTemplate};

/// Accessed as `client.templates()`.
#[derive(Debug, Clone)]
pub struct Templates {
    http: HttpClient,
}

impl Templates {
    pub(crate) fn new(http: HttpClient) -> Self {
        Self { http }
    }

    /// List templates.
    pub async fn list(&self, params: ListParams) -> Result<Page<Template>> {
        self.http
            .get(&format!("/v1/templates{}", list_query(&params)))
            .await
    }

    /// Create a template. `{{name}}` placeholders are parsed into `variables`.
    pub async fn create(&self, params: &CreateTemplate) -> Result<Template> {
        self.create_with(params, &RequestOptions::default()).await
    }

    /// [`Templates::create`] with an explicit Idempotency-Key.
    pub async fn create_with(
        &self,
        params: &CreateTemplate,
        opts: &RequestOptions,
    ) -> Result<Template> {
        self.http
            .send("POST", "/v1/templates", params, idem(opts))
            .await
    }

    /// Fetch a template.
    pub async fn get(&self, id: &str) -> Result<Template> {
        self.http
            .get(&format!("/v1/templates/{}", seg(id, "id")?))
            .await
    }

    /// Update a template.
    pub async fn update(&self, id: &str, params: &UpdateTemplate) -> Result<Template> {
        let path = format!("/v1/templates/{}", seg(id, "id")?);
        self.http.send("PATCH", &path, params, Idem::None).await
    }

    /// Delete a template.
    pub async fn delete(&self, id: &str) -> Result<()> {
        let path = format!("/v1/templates/{}", seg(id, "id")?);
        self.http.empty("DELETE", &path, Idem::None).await
    }
}
