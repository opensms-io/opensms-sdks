//! The `contacts` resource.

use super::{idem, list_query, seg};
use crate::error::Result;
use crate::http::{HttpClient, Idem};
use crate::models::{Contact, CreateContact, ListParams, Page, RequestOptions, UpdateContact};

/// Accessed as `client.contacts()`.
#[derive(Debug, Clone)]
pub struct Contacts {
    http: HttpClient,
}

impl Contacts {
    pub(crate) fn new(http: HttpClient) -> Self {
        Self { http }
    }

    /// List contacts.
    pub async fn list(&self, params: ListParams) -> Result<Page<Contact>> {
        self.http
            .get(&format!("/v1/contacts{}", list_query(&params)))
            .await
    }

    /// Create a contact. A duplicate `e164` returns `409`.
    pub async fn create(&self, params: &CreateContact) -> Result<Contact> {
        self.create_with(params, &RequestOptions::default()).await
    }

    /// [`Contacts::create`] with an explicit Idempotency-Key.
    pub async fn create_with(
        &self,
        params: &CreateContact,
        opts: &RequestOptions,
    ) -> Result<Contact> {
        self.http
            .send("POST", "/v1/contacts", params, idem(opts))
            .await
    }

    /// Fetch a contact.
    pub async fn get(&self, id: &str) -> Result<Contact> {
        self.http
            .get(&format!("/v1/contacts/{}", seg(id, "id")?))
            .await
    }

    /// Update a contact (PATCH: unset fields are kept).
    pub async fn update(&self, id: &str, params: &UpdateContact) -> Result<Contact> {
        let path = format!("/v1/contacts/{}", seg(id, "id")?);
        self.http.send("PATCH", &path, params, Idem::None).await
    }

    /// Delete a contact.
    pub async fn delete(&self, id: &str) -> Result<()> {
        let path = format!("/v1/contacts/{}", seg(id, "id")?);
        self.http.empty("DELETE", &path, Idem::None).await
    }
}
