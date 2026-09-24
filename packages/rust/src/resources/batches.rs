//! The `batches` resource: stage, validate, start, stop and inspect batches.

use super::{idem, seg};
use crate::error::Result;
use crate::http::{Body, HttpClient};
use crate::models::{
    Batch, BatchReport, BatchStopResult, CreateBatch, ListBatchItems, Message, Page, RequestOptions,
};
use crate::util::{query, uuid_v4};

/// Accessed as `client.batches()`.
#[derive(Debug, Clone)]
pub struct Batches {
    http: HttpClient,
}

impl Batches {
    pub(crate) fn new(http: HttpClient) -> Self {
        Self { http }
    }

    /// Stage a batch from JSON rows (`POST /v1/messages/batch`). It is created
    /// `ready` and sends nothing until [`Batches::start`].
    pub async fn create(&self, params: &CreateBatch) -> Result<Batch> {
        self.create_with(params, &RequestOptions::default()).await
    }

    /// [`Batches::create`] with an explicit Idempotency-Key.
    pub async fn create_with(&self, params: &CreateBatch, opts: &RequestOptions) -> Result<Batch> {
        self.http
            .send("POST", "/v1/messages/batch", params, idem(opts))
            .await
    }

    /// Stage a batch from CSV text with a `to,text[,...]` header row. With
    /// `dedupe` unset the body is sent as `text/csv` (server default: dedupe
    /// on); with `dedupe` set it is sent as a multipart upload carrying the
    /// flag, because a raw `text/csv` body cannot carry it.
    pub async fn create_from_csv(
        &self,
        csv: impl Into<Vec<u8>>,
        dedupe: Option<bool>,
    ) -> Result<Batch> {
        self.create_from_csv_with(csv, dedupe, &RequestOptions::default())
            .await
    }

    /// [`Batches::create_from_csv`] with an explicit Idempotency-Key.
    pub async fn create_from_csv_with(
        &self,
        csv: impl Into<Vec<u8>>,
        dedupe: Option<bool>,
        opts: &RequestOptions,
    ) -> Result<Batch> {
        let csv = csv.into();
        let body = match dedupe {
            None => Body::Raw {
                content_type: "text/csv".to_string(),
                bytes: csv,
            },
            Some(flag) => {
                let boundary = format!("opensms-{}", uuid_v4());
                let mut b = Vec::with_capacity(csv.len() + 400);
                b.extend_from_slice(
                    format!(
                        "--{boundary}\r\nContent-Disposition: form-data; name=\"dedupe\"\r\n\r\n{flag}\r\n\
                         --{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"batch.csv\"\r\n\
                         Content-Type: text/csv\r\n\r\n"
                    )
                    .as_bytes(),
                );
                b.extend_from_slice(&csv);
                b.extend_from_slice(format!("\r\n--{boundary}--\r\n").as_bytes());
                Body::Raw {
                    content_type: format!("multipart/form-data; boundary={boundary}"),
                    bytes: b,
                }
            }
        };
        self.http
            .json("POST", "/v1/messages/batch", body, idem(opts))
            .await
    }

    /// Fetch a batch.
    pub async fn get(&self, id: &str) -> Result<Batch> {
        self.http
            .get(&format!("/v1/batches/{}", seg(id, "id")?))
            .await
    }

    /// Per-row validation report.
    pub async fn validation(&self, id: &str) -> Result<BatchReport> {
        self.http
            .get(&format!("/v1/batches/{}/validation", seg(id, "id")?))
            .await
    }

    /// Start sending a `ready` batch.
    pub async fn start(&self, id: &str) -> Result<Batch> {
        self.start_with(id, &RequestOptions::default()).await
    }

    /// [`Batches::start`] with an explicit Idempotency-Key.
    pub async fn start_with(&self, id: &str, opts: &RequestOptions) -> Result<Batch> {
        let path = format!("/v1/batches/{}/start", seg(id, "id")?);
        self.http.json("POST", &path, Body::Empty, idem(opts)).await
    }

    /// Stop a batch, cancelling unsent messages.
    pub async fn stop(&self, id: &str) -> Result<BatchStopResult> {
        self.stop_with(id, &RequestOptions::default()).await
    }

    /// [`Batches::stop`] with an explicit Idempotency-Key.
    pub async fn stop_with(&self, id: &str, opts: &RequestOptions) -> Result<BatchStopResult> {
        let path = format!("/v1/batches/{}/stop", seg(id, "id")?);
        self.http.json("POST", &path, Body::Empty, idem(opts)).await
    }

    /// List the messages of a batch. Items carry fewer fields than a full
    /// [`Message`].
    pub async fn list_items(&self, id: &str, params: ListBatchItems) -> Result<Page<Message>> {
        let q = query(&[
            ("status", params.status),
            ("limit", params.limit.map(|v| v.to_string())),
            ("cursor", params.cursor),
        ]);
        self.http
            .get(&format!("/v1/batches/{}/items{q}", seg(id, "id")?))
            .await
    }
}
