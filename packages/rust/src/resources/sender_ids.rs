//! The `sender_ids` resource: sender IDs, application drafts and the
//! document list.

use serde::Deserialize;

use super::{list_query, seg};
use crate::error::Result;
use crate::http::{HttpClient, Idem};
use crate::models::{
    CheckSenderId, CreateSenderId, CreateSenderIdDraft, ListParams, Page, QuoteSenderId,
    SenderDocument, SenderId, SenderIdCheck, SenderIdDraft, SenderIdQuote, UpdateSenderId,
    UpdateSenderIdDraft,
};
use crate::util::query;

#[derive(Deserialize)]
struct Items<T> {
    #[serde(default = "Vec::new")]
    items: Vec<T>,
}

/// Accessed as `client.sender_ids()`.
#[derive(Debug, Clone)]
pub struct SenderIds {
    http: HttpClient,
}

impl SenderIds {
    pub(crate) fn new(http: HttpClient) -> Self {
        Self { http }
    }

    /// List sender IDs.
    pub async fn list(&self, params: ListParams) -> Result<Page<SenderId>> {
        self.http
            .get(&format!("/v1/sender-ids{}", list_query(&params)))
            .await
    }

    /// Fetch a sender ID with its registrations.
    pub async fn get(&self, id: &str) -> Result<SenderId> {
        self.http
            .get(&format!("/v1/sender-ids/{}", seg(id, "id")?))
            .await
    }

    /// Apply for a sender ID. May charge fees, so it is never retried.
    pub async fn create(&self, params: &CreateSenderId) -> Result<SenderId> {
        self.http
            .send("POST", "/v1/sender-ids", params, Idem::None)
            .await
    }

    /// Amend and resubmit a rejected sender ID.
    pub async fn update(&self, id: &str, params: &UpdateSenderId) -> Result<SenderId> {
        let path = format!("/v1/sender-ids/{}", seg(id, "id")?);
        self.http.send("PATCH", &path, params, Idem::None).await
    }

    /// Delete a sender ID.
    pub async fn delete(&self, id: &str) -> Result<()> {
        let path = format!("/v1/sender-ids/{}", seg(id, "id")?);
        self.http.empty("DELETE", &path, Idem::None).await
    }

    /// Check whether a value is valid and available.
    pub async fn check(&self, params: &CheckSenderId) -> Result<SenderIdCheck> {
        let q = query(&[
            ("value", Some(params.value.clone())),
            ("country", params.country.clone()),
        ]);
        self.http.get(&format!("/v1/sender-ids/check{q}")).await
    }

    /// Quote registration fees for markets (`countries=KE,NG`).
    pub async fn quote(&self, params: &QuoteSenderId) -> Result<SenderIdQuote> {
        let countries = if params.countries.is_empty() {
            None
        } else {
            Some(params.countries.join(","))
        };
        let q = query(&[("countries", countries)]);
        self.http.get(&format!("/v1/sender-ids/quote{q}")).await
    }

    /// List uploaded registration documents (upload and download are
    /// console-only).
    pub async fn list_documents(&self) -> Result<Vec<SenderDocument>> {
        let r: Items<SenderDocument> = self.http.get("/v1/sender-documents").await?;
        Ok(r.items)
    }

    /// List application drafts.
    pub async fn list_drafts(&self, params: ListParams) -> Result<Page<SenderIdDraft>> {
        self.http
            .get(&format!("/v1/sender-id-drafts{}", list_query(&params)))
            .await
    }

    /// Create a draft. Not retried.
    pub async fn create_draft(&self, params: &CreateSenderIdDraft) -> Result<SenderIdDraft> {
        self.http
            .send("POST", "/v1/sender-id-drafts", params, Idem::None)
            .await
    }

    /// Fetch a draft.
    pub async fn get_draft(&self, id: &str) -> Result<SenderIdDraft> {
        self.http
            .get(&format!("/v1/sender-id-drafts/{}", seg(id, "id")?))
            .await
    }

    /// Update a draft; `version` must be current (409 otherwise).
    pub async fn update_draft(
        &self,
        id: &str,
        params: &UpdateSenderIdDraft,
    ) -> Result<SenderIdDraft> {
        let path = format!("/v1/sender-id-drafts/{}", seg(id, "id")?);
        self.http.send("PATCH", &path, params, Idem::None).await
    }

    /// Delete a draft.
    pub async fn delete_draft(&self, id: &str) -> Result<()> {
        let path = format!("/v1/sender-id-drafts/{}", seg(id, "id")?);
        self.http.empty("DELETE", &path, Idem::None).await
    }
}
