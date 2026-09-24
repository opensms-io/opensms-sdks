//! The `messages` resource: send, list, fetch, inspect attempts, cancel.

use super::{idem, seg};
use crate::error::Result;
use crate::http::{Body, HttpClient, Idem};
use crate::models::{Attempt, ListMessages, Message, Page, RequestOptions, SendMessage};
use crate::util::query;

/// Accessed as `client.messages()`.
#[derive(Debug, Clone)]
pub struct Messages {
    http: HttpClient,
}

impl Messages {
    pub(crate) fn new(http: HttpClient) -> Self {
        Self { http }
    }

    /// Send one SMS (`POST /v1/messages`). Sends a generated Idempotency-Key.
    pub async fn send(&self, params: &SendMessage) -> Result<Message> {
        self.send_with(params, &RequestOptions::default()).await
    }

    /// [`Messages::send`] with an explicit Idempotency-Key.
    pub async fn send_with(&self, params: &SendMessage, opts: &RequestOptions) -> Result<Message> {
        self.http
            .send("POST", "/v1/messages", params, idem(opts))
            .await
    }

    /// List messages, newest first (`GET /v1/messages`).
    pub async fn list(&self, params: ListMessages) -> Result<Page<Message>> {
        let q = query(&[
            ("limit", params.limit.map(|v| v.to_string())),
            ("cursor", params.cursor),
            ("status", params.status),
            ("to", params.to),
            ("country", params.country),
            ("date_from", params.date_from),
            ("date_to", params.date_to),
        ]);
        self.http.get(&format!("/v1/messages{q}")).await
    }

    /// Fetch one message.
    pub async fn get(&self, id: &str) -> Result<Message> {
        self.http
            .get(&format!("/v1/messages/{}", seg(id, "id")?))
            .await
    }

    /// List delivery attempts for a message.
    pub async fn attempts(&self, id: &str) -> Result<Vec<Attempt>> {
        self.http
            .get(&format!("/v1/messages/{}/attempts", seg(id, "id")?))
            .await
    }

    /// Cancel a `queued` or `scheduled` message. Never retried.
    pub async fn cancel(&self, id: &str) -> Result<Message> {
        let path = format!("/v1/messages/{}/cancel", seg(id, "id")?);
        self.http.json("POST", &path, Body::Empty, Idem::None).await
    }
}
