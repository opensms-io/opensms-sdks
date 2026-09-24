//! The `contact_groups` resource.

use super::{idem, list_query, seg};
use crate::error::Result;
use crate::http::{HttpClient, Idem};
use crate::models::{
    Batch, ContactGroup, CreateContactGroup, ListParams, Page, RequestOptions, SendToGroup,
    UpdateContactGroup,
};

/// Accessed as `client.contact_groups()`.
#[derive(Debug, Clone)]
pub struct ContactGroups {
    http: HttpClient,
}

impl ContactGroups {
    pub(crate) fn new(http: HttpClient) -> Self {
        Self { http }
    }

    /// List groups.
    pub async fn list(&self, params: ListParams) -> Result<Page<ContactGroup>> {
        self.http
            .get(&format!("/v1/contact-groups{}", list_query(&params)))
            .await
    }

    /// Create a group.
    pub async fn create(&self, params: &CreateContactGroup) -> Result<ContactGroup> {
        self.create_with(params, &RequestOptions::default()).await
    }

    /// [`ContactGroups::create`] with an explicit Idempotency-Key.
    pub async fn create_with(
        &self,
        params: &CreateContactGroup,
        opts: &RequestOptions,
    ) -> Result<ContactGroup> {
        self.http
            .send("POST", "/v1/contact-groups", params, idem(opts))
            .await
    }

    /// Fetch a group.
    pub async fn get(&self, id: &str) -> Result<ContactGroup> {
        self.http
            .get(&format!("/v1/contact-groups/{}", seg(id, "id")?))
            .await
    }

    /// Update a group.
    pub async fn update(&self, id: &str, params: &UpdateContactGroup) -> Result<ContactGroup> {
        let path = format!("/v1/contact-groups/{}", seg(id, "id")?);
        self.http.send("PATCH", &path, params, Idem::None).await
    }

    /// Delete a group.
    pub async fn delete(&self, id: &str) -> Result<()> {
        let path = format!("/v1/contact-groups/{}", seg(id, "id")?);
        self.http.empty("DELETE", &path, Idem::None).await
    }

    /// Send to every member. Returns a batch that is already `running`.
    pub async fn send(&self, id: &str, params: &SendToGroup) -> Result<Batch> {
        self.send_with(id, params, &RequestOptions::default()).await
    }

    /// [`ContactGroups::send`] with an explicit Idempotency-Key.
    pub async fn send_with(
        &self,
        id: &str,
        params: &SendToGroup,
        opts: &RequestOptions,
    ) -> Result<Batch> {
        let path = format!("/v1/contact-groups/{}/send", seg(id, "id")?);
        self.http.send("POST", &path, params, idem(opts)).await
    }
}
