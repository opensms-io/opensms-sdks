//! The `inbound` resource: received SMS and replies.

use super::{idem, list_query, seg};
use crate::error::Result;
use crate::http::HttpClient;
use crate::models::{InboundMessage, ListParams, Message, Page, ReplyInbound, RequestOptions};

/// Accessed as `client.inbound()`.
#[derive(Debug, Clone)]
pub struct Inbound {
    http: HttpClient,
}

impl Inbound {
    pub(crate) fn new(http: HttpClient) -> Self {
        Self { http }
    }

    /// List inbound messages.
    pub async fn list(&self, params: ListParams) -> Result<Page<InboundMessage>> {
        self.http
            .get(&format!("/v1/inbound{}", list_query(&params)))
            .await
    }

    /// Reply to an inbound message (live keys only). Returns the sent Message.
    pub async fn reply(&self, id: &str, params: &ReplyInbound) -> Result<Message> {
        self.reply_with(id, params, &RequestOptions::default())
            .await
    }

    /// [`Inbound::reply`] with an explicit Idempotency-Key.
    pub async fn reply_with(
        &self,
        id: &str,
        params: &ReplyInbound,
        opts: &RequestOptions,
    ) -> Result<Message> {
        let path = format!("/v1/inbound/{}/reply", seg(id, "id")?);
        self.http.send("POST", &path, params, idem(opts)).await
    }
}
