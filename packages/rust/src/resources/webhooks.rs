//! The `webhooks` resource, plus signature verification helpers.

use super::{idem, list_query, seg};
use crate::error::Result;
use crate::http::{Body, HttpClient};
use crate::models::{
    CreateWebhook, ListParams, Page, ReplayDelivery, RequestOptions, StatusResult, UpdateWebhook,
    WebhookDelivery, WebhookEndpoint, WebhookEvent,
};
use crate::webhook::{self, VerifyOptions};

/// Accessed as `client.webhooks()`.
#[derive(Debug, Clone)]
pub struct Webhooks {
    http: HttpClient,
}

impl Webhooks {
    pub(crate) fn new(http: HttpClient) -> Self {
        Self { http }
    }

    /// List endpoints.
    pub async fn list(&self, params: ListParams) -> Result<Page<WebhookEndpoint>> {
        self.http
            .get(&format!("/v1/webhooks{}", list_query(&params)))
            .await
    }

    /// Create an endpoint. The response carries the signing `secret`, shown
    /// only once.
    pub async fn create(&self, params: &CreateWebhook) -> Result<WebhookEndpoint> {
        self.create_with(params, &RequestOptions::default()).await
    }

    /// [`Webhooks::create`] with an explicit Idempotency-Key.
    pub async fn create_with(
        &self,
        params: &CreateWebhook,
        opts: &RequestOptions,
    ) -> Result<WebhookEndpoint> {
        self.http
            .send("POST", "/v1/webhooks", params, idem(opts))
            .await
    }

    /// Fetch an endpoint (never includes the secret).
    pub async fn get(&self, id: &str) -> Result<WebhookEndpoint> {
        self.http
            .get(&format!("/v1/webhooks/{}", seg(id, "id")?))
            .await
    }

    /// Replace an endpoint (`PUT`): `url`, `events` and `enabled` are required.
    pub async fn update(&self, id: &str, params: &UpdateWebhook) -> Result<WebhookEndpoint> {
        self.update_with(id, params, &RequestOptions::default())
            .await
    }

    /// [`Webhooks::update`] with an explicit Idempotency-Key.
    pub async fn update_with(
        &self,
        id: &str,
        params: &UpdateWebhook,
        opts: &RequestOptions,
    ) -> Result<WebhookEndpoint> {
        let path = format!("/v1/webhooks/{}", seg(id, "id")?);
        self.http.send("PUT", &path, params, idem(opts)).await
    }

    /// Delete an endpoint.
    pub async fn delete(&self, id: &str) -> Result<()> {
        self.delete_with(id, &RequestOptions::default()).await
    }

    /// [`Webhooks::delete`] with an explicit Idempotency-Key.
    pub async fn delete_with(&self, id: &str, opts: &RequestOptions) -> Result<()> {
        let path = format!("/v1/webhooks/{}", seg(id, "id")?);
        self.http.empty("DELETE", &path, idem(opts)).await
    }

    /// Queue a `webhook.test` delivery.
    pub async fn test(&self, id: &str) -> Result<StatusResult> {
        self.test_with(id, &RequestOptions::default()).await
    }

    /// [`Webhooks::test`] with an explicit Idempotency-Key.
    pub async fn test_with(&self, id: &str, opts: &RequestOptions) -> Result<StatusResult> {
        let path = format!("/v1/webhooks/{}/test", seg(id, "id")?);
        self.http.json("POST", &path, Body::Empty, idem(opts)).await
    }

    /// List deliveries for an endpoint.
    pub async fn list_deliveries(
        &self,
        id: &str,
        params: ListParams,
    ) -> Result<Page<WebhookDelivery>> {
        self.http
            .get(&format!(
                "/v1/webhooks/{}/deliveries{}",
                seg(id, "id")?,
                list_query(&params)
            ))
            .await
    }

    /// Replay a delivery. `generation` comes from the delivery.
    pub async fn replay_delivery(
        &self,
        id: &str,
        delivery_id: i64,
        params: &ReplayDelivery,
    ) -> Result<StatusResult> {
        self.replay_delivery_with(id, delivery_id, params, &RequestOptions::default())
            .await
    }

    /// [`Webhooks::replay_delivery`] with an explicit Idempotency-Key.
    pub async fn replay_delivery_with(
        &self,
        id: &str,
        delivery_id: i64,
        params: &ReplayDelivery,
        opts: &RequestOptions,
    ) -> Result<StatusResult> {
        let path = format!(
            "/v1/webhooks/{}/deliveries/{}/replay",
            seg(id, "id")?,
            delivery_id
        );
        self.http.send("POST", &path, params, idem(opts)).await
    }

    /// Same as [`crate::webhook::verify_signature`].
    pub fn verify_signature(
        &self,
        payload: &[u8],
        header: &str,
        secret: &str,
        opts: VerifyOptions,
    ) -> bool {
        webhook::verify_signature(payload, header, secret, opts)
    }

    /// Same as [`crate::webhook::construct_event`].
    pub fn construct_event(
        &self,
        payload: &[u8],
        header: &str,
        secret: &str,
        opts: VerifyOptions,
    ) -> Result<WebhookEvent> {
        webhook::construct_event(payload, header, secret, opts)
    }
}
