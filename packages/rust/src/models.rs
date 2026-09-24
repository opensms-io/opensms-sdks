//! Serde structs for every request and response shape on the OpenSMS API.
//!
//! Wire names are snake_case, which is also idiomatic Rust, so fields map one
//! to one. Rules applied here, in one place:
//!
//! - Money, prices, balances and FX rates stay `String` (decimal text).
//! - Enums are open: modelled as `String` so a new server value never breaks
//!   decoding.
//! - Every response field is `Option` except `id`, because live payloads omit
//!   empty fields. Unknown response fields are ignored.
//! - Datetimes are kept as RFC 3339 strings. Use [`crate::rfc3339`] to format a
//!   `SystemTime` for inputs such as `scheduled_at`.
//! - Request structs skip unset optional fields entirely (never `null`): the
//!   API rejects unknown fields and treats `null` differently from absent.
//! - `metadata`, `attributes`, webhook `payload`/`data` and `variables` are
//!   free-form JSON.

use std::collections::HashMap;

use serde::{Deserialize, Serialize};
use serde_json::Value;

// -- shared -----------------------------------------------------------------

/// A cursor page: `{ items, next_cursor }`.
#[derive(Debug, Clone, Deserialize)]
pub struct Page<T> {
    /// Items on this page.
    #[serde(default = "Vec::new")]
    pub items: Vec<T>,
    /// Cursor for the next page; `None` on the last page.
    #[serde(default)]
    pub next_cursor: Option<String>,
}

/// `limit` + `cursor` for cursor-paginated lists.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ListParams {
    /// Page size (1..200, default 50 server side).
    pub limit: Option<u32>,
    /// Cursor from a previous page's `next_cursor`.
    pub cursor: Option<String>,
}

impl ListParams {
    /// Params with only a page size.
    pub fn limit(limit: u32) -> Self {
        Self {
            limit: Some(limit),
            cursor: None,
        }
    }
}

/// Per-call options for methods that send an `Idempotency-Key`.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct RequestOptions {
    /// Idempotency key to send verbatim. When unset the SDK generates a
    /// UUIDv4 once per call and reuses it on every retry.
    pub idempotency_key: Option<String>,
}

impl RequestOptions {
    /// Options carrying an explicit idempotency key.
    pub fn idempotency_key(key: impl Into<String>) -> Self {
        Self {
            idempotency_key: Some(key.into()),
        }
    }
}

/// A `{ status }` acknowledgement (webhook test and replay).
#[derive(Debug, Clone, Deserialize)]
pub struct StatusResult {
    /// Status, for example `pending`.
    pub status: Option<String>,
}

/// An `{ amount, currency }` money value.
#[derive(Debug, Clone, Deserialize)]
pub struct Money {
    /// Decimal amount.
    pub amount: Option<String>,
    /// ISO 4217 currency.
    pub currency: Option<String>,
}

// -- messages -----------------------------------------------------------------

/// An SMS message. Also used for batch items, which carry fewer fields.
#[derive(Debug, Clone, Deserialize)]
pub struct Message {
    /// Message UUID.
    pub id: String,
    /// Creation time.
    pub created_at: Option<String>,
    /// Destination, E.164.
    pub to: Option<String>,
    /// Sender ID the message left with.
    pub sender_id: Option<String>,
    /// Message text (omitted when empty).
    pub text: Option<String>,
    /// Number of SMS parts.
    pub parts: Option<i64>,
    /// `queued|scheduled|held|sending|sent|delivered|failed|cancelled|expired`.
    pub status: Option<String>,
    /// Reason for the current status, when any.
    pub status_reason: Option<String>,
    /// When it was sent.
    pub sent_at: Option<String>,
    /// When it was delivered.
    pub delivered_at: Option<String>,
    /// When it failed.
    pub failed_at: Option<String>,
    /// When it was cancelled.
    pub cancelled_at: Option<String>,
    /// When it is scheduled for.
    pub scheduled_at: Option<String>,
    /// Price, decimal string.
    pub price: Option<String>,
    /// Price currency.
    pub currency: Option<String>,
    /// `otp|transactional|marketing`.
    pub traffic_type: Option<String>,
    /// Caller metadata.
    pub metadata: Option<Value>,
    /// `gsm7|ucs2`.
    pub encoding: Option<String>,
    /// Destination country id.
    pub country_id: Option<String>,
    /// Destination country ISO2.
    pub country_iso2: Option<String>,
    /// Destination country name.
    pub country_name: Option<String>,
    /// Destination carrier id.
    pub carrier_id: Option<String>,
    /// Destination carrier name.
    pub carrier_name: Option<String>,
    /// `prefix|hlr|unknown`.
    pub destination_source: Option<String>,
    /// Billing lines (get and list only).
    pub billing: Option<Vec<Value>>,
}

/// Body of `messages.send`.
#[derive(Debug, Clone, Default, Serialize)]
pub struct SendMessage {
    /// Destination, E.164 (required).
    pub to: String,
    /// Text, 1..1600 characters (required).
    pub text: String,
    /// Sender ID.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sender_id: Option<String>,
    /// `otp|transactional|marketing` (default `transactional`).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub traffic_type: Option<String>,
    /// RFC 3339 send time (see [`crate::rfc3339`]).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub scheduled_at: Option<String>,
    /// Per-message status callback URL.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub callback_url: Option<String>,
    /// Free-form JSON object.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub metadata: Option<Value>,
}

impl SendMessage {
    /// A message with the two required fields.
    pub fn new(to: impl Into<String>, text: impl Into<String>) -> Self {
        Self {
            to: to.into(),
            text: text.into(),
            ..Default::default()
        }
    }
}

/// Query for `messages.list`.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ListMessages {
    /// Page size 1..100 (default 20).
    pub limit: Option<u32>,
    /// Cursor from a previous page.
    pub cursor: Option<String>,
    /// Status filter.
    pub status: Option<String>,
    /// Destination fragment (`+2547...`).
    pub to: Option<String>,
    /// Uppercase ISO2 country.
    pub country: Option<String>,
    /// `YYYY-MM-DD` or RFC 3339.
    pub date_from: Option<String>,
    /// `YYYY-MM-DD` (inclusive) or RFC 3339.
    pub date_to: Option<String>,
}

/// One delivery attempt of a message.
#[derive(Debug, Clone, Deserialize)]
pub struct Attempt {
    /// Attempt id (int64).
    pub id: i64,
    /// 1-based sequence.
    pub sequence: Option<i64>,
    /// Route UUID.
    pub route_id: Option<String>,
    /// Route name.
    pub route_name: Option<String>,
    /// Price, decimal string.
    pub price: Option<String>,
    /// Price currency.
    pub currency: Option<String>,
    /// Provider name.
    pub provider: Option<String>,
    /// Provider's message id.
    pub provider_message_id: Option<String>,
    /// Attempt status.
    pub status: Option<String>,
    /// Provider error code.
    pub error_code: Option<String>,
    /// Submission time.
    pub submitted_at: Option<String>,
    /// Delivery report time.
    pub dlr_at: Option<String>,
    /// Submit latency in ms.
    pub submit_latency_ms: Option<i64>,
    /// DLR latency in ms.
    pub dlr_latency_ms: Option<i64>,
}

// -- batches ------------------------------------------------------------------

/// A message batch.
#[derive(Debug, Clone, Deserialize)]
pub struct Batch {
    /// Batch UUID.
    pub id: String,
    /// `ready|running|stopped|completed|failed`.
    pub status: Option<String>,
    /// Total rows.
    pub total: Option<i64>,
    /// Sent rows.
    pub sent: Option<i64>,
    /// Delivered rows.
    pub delivered: Option<i64>,
    /// Failed rows.
    pub failed: Option<i64>,
    /// Invalid rows.
    pub invalid: Option<i64>,
    /// Duplicate rows.
    pub duplicates: Option<i64>,
    /// Suppressed rows.
    pub suppressed: Option<i64>,
    /// Estimated cost (a JSON number on the wire).
    pub estimated_cost: Option<Value>,
    /// Creation time.
    pub created_at: Option<String>,
    /// Completion time.
    pub completed_at: Option<String>,
}

/// One row of a batch create request.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct BatchItemInput {
    /// Destination, E.164.
    #[serde(default)]
    pub to: String,
    /// Text.
    #[serde(default)]
    pub text: String,
    /// Sender ID.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sender_id: Option<String>,
    /// Traffic type.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub traffic_type: Option<String>,
    /// Callback URL.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub callback_url: Option<String>,
    /// Free-form JSON object.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub metadata: Option<Value>,
}

impl BatchItemInput {
    /// A row with the two required fields.
    pub fn new(to: impl Into<String>, text: impl Into<String>) -> Self {
        Self {
            to: to.into(),
            text: text.into(),
            ..Default::default()
        }
    }
}

/// Body of `batches.create`.
#[derive(Debug, Clone, Default, Serialize)]
pub struct CreateBatch {
    /// Rows (required).
    pub items: Vec<BatchItemInput>,
    /// Drop duplicate destinations (default true).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub dedupe: Option<bool>,
}

/// Validation report of a batch.
#[derive(Debug, Clone, Deserialize)]
pub struct BatchReport {
    /// Per-row results.
    #[serde(default)]
    pub rows: Vec<BatchReportRow>,
    /// Total rows.
    pub total: Option<i64>,
    /// Valid rows.
    pub valid: Option<i64>,
    /// Invalid rows.
    pub invalid: Option<i64>,
    /// Duplicate rows.
    pub duplicates: Option<i64>,
    /// Suppressed rows.
    pub suppressed: Option<i64>,
}

/// One row of a [`BatchReport`].
#[derive(Debug, Clone, Deserialize)]
pub struct BatchReportRow {
    /// Row number.
    pub row: Option<i64>,
    /// The submitted row.
    pub item: Option<BatchItemInput>,
    /// Whether it is valid.
    pub valid: Option<bool>,
    /// Whether it duplicates an earlier row.
    pub duplicate: Option<bool>,
    /// Whether the destination is suppressed.
    pub suppressed: Option<bool>,
    /// Validation error.
    pub error: Option<String>,
}

/// Result of `batches.stop`.
#[derive(Debug, Clone, Deserialize)]
pub struct BatchStopResult {
    /// Batch UUID.
    pub id: String,
    /// `stopped`.
    pub status: Option<String>,
    /// Messages cancelled.
    pub cancelled: Option<i64>,
}

/// Query for `batches.list_items`.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ListBatchItems {
    /// Status filter.
    pub status: Option<String>,
    /// Page size.
    pub limit: Option<u32>,
    /// Cursor.
    pub cursor: Option<String>,
}

// -- otp ----------------------------------------------------------------------

/// Body of `otp.send`.
#[derive(Debug, Clone, Default, Serialize)]
pub struct SendOtp {
    /// Destination, E.164 (required).
    pub to: String,
    /// Sender ID.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sender_id: Option<String>,
    /// Template containing `{{code}}`.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub template: Option<String>,
    /// Code length 4..10 (default 6).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub length: Option<u32>,
    /// Lifetime 30..86400 s (default 600).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ttl_seconds: Option<u32>,
}

impl SendOtp {
    /// An OTP request to `to` with server defaults.
    pub fn new(to: impl Into<String>) -> Self {
        Self {
            to: to.into(),
            ..Default::default()
        }
    }
}

/// Result of `otp.send`.
#[derive(Debug, Clone, Deserialize)]
pub struct OtpSendResult {
    /// OTP UUID to verify against.
    pub otp_id: String,
}

/// Body of `otp.verify`.
#[derive(Debug, Clone, Default, Serialize)]
pub struct VerifyOtp {
    /// OTP UUID.
    pub otp_id: String,
    /// The code the user entered.
    pub code: String,
}

impl VerifyOtp {
    /// Verify `code` against `otp_id`.
    pub fn new(otp_id: impl Into<String>, code: impl Into<String>) -> Self {
        Self {
            otp_id: otp_id.into(),
            code: code.into(),
        }
    }
}

/// Result of `otp.verify`.
#[derive(Debug, Clone, Deserialize)]
pub struct OtpVerifyResult {
    /// Whether the code matched.
    pub valid: Option<bool>,
    /// Attempts remaining.
    pub attempts_left: Option<i64>,
}

// -- lookups ------------------------------------------------------------------

/// A number lookup.
#[derive(Debug, Clone, Deserialize)]
pub struct Lookup {
    /// Lookup UUID.
    pub id: String,
    /// `queued|submitting|unknown|completed|failed`.
    pub state: Option<String>,
    /// ISO2 country.
    pub country: Option<String>,
    /// Carrier name.
    pub carrier: Option<String>,
    /// Whether the number was ported.
    pub ported: Option<bool>,
    /// Whether the number is valid.
    pub valid: Option<bool>,
    /// `prefix|hlr|mock`.
    pub source: Option<String>,
    /// Price, decimal string.
    pub price: Option<String>,
    /// Price currency.
    pub currency: Option<String>,
    /// When it was checked.
    pub checked_at: Option<String>,
}

/// Body of `lookups.create`.
#[derive(Debug, Clone, Default, Serialize)]
pub struct CreateLookup {
    /// Number to look up, E.164.
    pub to: String,
}

// -- contacts -----------------------------------------------------------------

/// A contact.
#[derive(Debug, Clone, Deserialize)]
pub struct Contact {
    /// Contact UUID.
    pub id: String,
    /// Workspace UUID.
    pub workspace_id: Option<String>,
    /// Phone number, E.164.
    pub e164: Option<String>,
    /// Name.
    pub name: Option<String>,
    /// Free-form attributes.
    pub attributes: Option<Value>,
    /// Creation time.
    pub created_at: Option<String>,
}

/// Body of `contacts.create`.
#[derive(Debug, Clone, Default, Serialize)]
pub struct CreateContact {
    /// Phone number, E.164 (required).
    pub e164: String,
    /// Name.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    /// Free-form attributes object.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub attributes: Option<Value>,
}

/// Body of `contacts.update` (PATCH; unset fields are kept).
#[derive(Debug, Clone, Default, Serialize)]
pub struct UpdateContact {
    /// Phone number.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub e164: Option<String>,
    /// Name.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    /// Attributes object.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub attributes: Option<Value>,
}

/// A contact group.
#[derive(Debug, Clone, Deserialize)]
pub struct ContactGroup {
    /// Group UUID.
    pub id: String,
    /// Workspace UUID.
    pub workspace_id: Option<String>,
    /// Name.
    pub name: Option<String>,
    /// Member contact UUIDs.
    pub contact_ids: Option<Vec<String>>,
    /// Creation time.
    pub created_at: Option<String>,
}

/// Body of `contact_groups.create`.
#[derive(Debug, Clone, Default, Serialize)]
pub struct CreateContactGroup {
    /// Name (required).
    pub name: String,
    /// Member contact UUIDs.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub contact_ids: Option<Vec<String>>,
}

/// Body of `contact_groups.update`.
#[derive(Debug, Clone, Default, Serialize)]
pub struct UpdateContactGroup {
    /// Name.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    /// Member contact UUIDs.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub contact_ids: Option<Vec<String>>,
}

/// Body of `contact_groups.send`: set `text` or `template_id`.
#[derive(Debug, Clone, Default, Serialize)]
pub struct SendToGroup {
    /// Text.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub text: Option<String>,
    /// Template UUID.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub template_id: Option<String>,
    /// Template variables.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub variables: Option<HashMap<String, String>>,
    /// Sender ID.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sender_id: Option<String>,
    /// Traffic type.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub traffic_type: Option<String>,
    /// Callback URL.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub callback_url: Option<String>,
}

// -- templates ----------------------------------------------------------------

/// A message template.
#[derive(Debug, Clone, Deserialize)]
pub struct Template {
    /// Template UUID.
    pub id: String,
    /// Workspace UUID.
    pub workspace_id: Option<String>,
    /// Name.
    pub name: Option<String>,
    /// Body with `{{name}}` placeholders.
    pub body: Option<String>,
    /// Traffic type.
    pub traffic_type: Option<String>,
    /// Creation time.
    pub created_at: Option<String>,
    /// Update time.
    pub updated_at: Option<String>,
    /// Parsed placeholder names.
    pub variables: Option<Vec<String>>,
}

/// Body of `templates.create`.
#[derive(Debug, Clone, Default, Serialize)]
pub struct CreateTemplate {
    /// Name (required).
    pub name: String,
    /// Body (required).
    pub body: String,
    /// Traffic type.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub traffic_type: Option<String>,
}

/// Body of `templates.update`.
#[derive(Debug, Clone, Default, Serialize)]
pub struct UpdateTemplate {
    /// Name.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    /// Body.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub body: Option<String>,
    /// Traffic type.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub traffic_type: Option<String>,
}

// -- webhooks -----------------------------------------------------------------

/// A webhook endpoint.
#[derive(Debug, Clone, Deserialize)]
pub struct WebhookEndpoint {
    /// Endpoint UUID.
    pub id: String,
    /// HTTPS URL.
    pub url: Option<String>,
    /// Subscribed event names.
    pub events: Option<Vec<String>>,
    /// Whether deliveries are enabled.
    pub enabled: Option<bool>,
    /// Consecutive failed deliveries.
    pub consecutive_failures: Option<i64>,
    /// When it was auto-disabled.
    pub disabled_at: Option<String>,
    /// Creation time.
    pub created_at: Option<String>,
    /// Signing secret (`whsec_...`), only in the create response.
    pub secret: Option<String>,
}

/// Body of `webhooks.create`.
#[derive(Debug, Clone, Default, Serialize)]
pub struct CreateWebhook {
    /// HTTPS URL (required).
    pub url: String,
    /// Event names (required, non-empty).
    pub events: Vec<String>,
    /// Enabled (default true).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub enabled: Option<bool>,
}

/// Body of `webhooks.update`: a full replacement, every field required.
#[derive(Debug, Clone, Serialize)]
pub struct UpdateWebhook {
    /// HTTPS URL.
    pub url: String,
    /// Event names.
    pub events: Vec<String>,
    /// Enabled.
    pub enabled: bool,
}

/// One webhook delivery.
#[derive(Debug, Clone, Deserialize)]
pub struct WebhookDelivery {
    /// Delivery id (int64).
    pub id: i64,
    /// Generation, needed for replay.
    pub generation: Option<i64>,
    /// Event name.
    pub event: Option<String>,
    /// Delivered payload.
    pub payload: Option<Value>,
    /// Attempts so far.
    pub attempts: Option<i64>,
    /// Next retry time.
    pub next_retry_at: Option<String>,
    /// Delivery status.
    pub status: Option<String>,
    /// Last HTTP response code.
    pub last_response_code: Option<i64>,
    /// Last error.
    pub last_error: Option<String>,
    /// Creation time.
    pub created_at: Option<String>,
    /// Delivery time.
    pub delivered_at: Option<String>,
}

/// Body of `webhooks.replay_delivery`.
#[derive(Debug, Clone, Default, Serialize)]
pub struct ReplayDelivery {
    /// Generation from the delivery.
    pub generation: i64,
    /// Reason, 5..1000 characters.
    pub reason: String,
}

/// A verified webhook event envelope.
#[derive(Debug, Clone, Deserialize)]
pub struct WebhookEvent {
    /// Event id.
    pub id: String,
    /// Event type, for example `message.delivered`.
    #[serde(rename = "type")]
    pub r#type: Option<String>,
    /// Workspace UUID.
    pub workspace_id: Option<String>,
    /// `sandbox` or `live`.
    pub environment: Option<String>,
    /// Creation time.
    pub created_at: Option<String>,
    /// Event payload.
    pub data: Option<Value>,
}

// -- inbound ------------------------------------------------------------------

/// An inbound SMS.
#[derive(Debug, Clone, Deserialize)]
pub struct InboundMessage {
    /// Inbound UUID.
    pub id: String,
    /// Sender, E.164.
    pub from: Option<String>,
    /// Receiving number.
    pub to: Option<String>,
    /// Text.
    pub text: Option<String>,
    /// Receive time.
    pub received_at: Option<String>,
    /// Virtual number UUID.
    pub virtual_number_id: Option<String>,
}

/// Body of `inbound.reply`.
#[derive(Debug, Clone, Default, Serialize)]
pub struct ReplyInbound {
    /// Reply text (required).
    pub text: String,
}

// -- numbers ------------------------------------------------------------------

/// A virtual number.
#[derive(Debug, Clone, Deserialize)]
pub struct Number {
    /// Number UUID.
    pub id: String,
    /// ISO2 country.
    pub country: Option<String>,
    /// The phone number.
    pub number: Option<String>,
    /// `long_code|short_code|toll_free`.
    pub kind: Option<String>,
    /// Monthly fee, decimal string.
    pub monthly_fee: Option<String>,
    /// Fee currency.
    pub fee_currency: Option<String>,
    /// `available|assigned|releasing`.
    pub status: Option<String>,
    /// Receives SMS.
    pub inbound: Option<bool>,
    /// Sends SMS.
    pub outbound: Option<bool>,
    /// Assignment time.
    pub assigned_at: Option<String>,
    /// Renewal time.
    pub renews_at: Option<String>,
}

/// Query for `numbers.available` and body of `numbers.assign`.
#[derive(Debug, Clone, Default, Serialize)]
pub struct NumberQuery {
    /// ISO2 country.
    pub country: String,
    /// `long_code|short_code|toll_free`.
    pub kind: String,
}

/// An inbound routing rule on a number.
#[derive(Debug, Clone, Deserialize)]
pub struct NumberRule {
    /// Rule UUID.
    pub id: String,
    /// `keyword|prefix|regex|any`.
    #[serde(rename = "match")]
    pub r#match: Option<String>,
    /// Pattern (omitted when empty).
    pub pattern: Option<String>,
    /// `webhook|auto_reply|forward_email`.
    pub action: Option<String>,
    /// Action target.
    pub target: Option<String>,
    /// Evaluation order.
    pub position: Option<i64>,
}

/// Body of `numbers.create_rule` and `numbers.update_rule`.
#[derive(Debug, Clone, Default, Serialize)]
pub struct NumberRuleInput {
    /// `keyword|prefix|regex|any`.
    #[serde(rename = "match")]
    pub r#match: String,
    /// Pattern (required unless match is `any`).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub pattern: Option<String>,
    /// `webhook|auto_reply|forward_email`.
    pub action: String,
    /// Target, 1..2048 characters.
    pub target: String,
    /// Position 0..10000.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub position: Option<i64>,
}

// -- sender IDs ---------------------------------------------------------------

/// A sender ID.
#[derive(Debug, Clone, Deserialize)]
pub struct SenderId {
    /// Sender ID UUID.
    pub id: String,
    /// The sender value.
    pub value: Option<String>,
    /// `alphanumeric|numeric`.
    pub kind: Option<String>,
    /// Requested markets.
    pub countries: Option<Vec<String>>,
    /// Use case.
    pub use_case: Option<String>,
    /// Sample message.
    pub sample_message: Option<String>,
    /// Status.
    pub status: Option<String>,
    /// Rejection reason.
    pub rejection_reason: Option<String>,
    /// Whether it is restricted.
    pub restricted: Option<bool>,
    /// Restriction reason.
    pub restriction_reason: Option<String>,
    /// Creation time.
    pub created_at: Option<String>,
    /// Provider registrations (get and create).
    pub registrations: Option<Vec<Value>>,
}

/// Body of `sender_ids.create`.
#[derive(Debug, Clone, Default, Serialize)]
pub struct CreateSenderId {
    /// Sender value (required).
    pub value: String,
    /// `alphanumeric|numeric` (required).
    pub kind: String,
    /// ISO2 markets (required).
    pub countries: Vec<String>,
    /// Use case.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub use_case: Option<String>,
    /// Sample message.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sample_message: Option<String>,
    /// Document UUIDs (required).
    pub documents: Vec<String>,
    /// Draft to submit.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub draft_id: Option<String>,
    /// Draft version (with `draft_id`).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub draft_version: Option<i64>,
    /// Fee quote id.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub quote_id: Option<String>,
}

/// Body of `sender_ids.update` (amend a rejected sender ID).
#[derive(Debug, Clone, Default, Serialize)]
pub struct UpdateSenderId {
    /// Use case (required).
    pub use_case: String,
    /// ISO2 markets (required).
    pub countries: Vec<String>,
    /// Document UUIDs (required).
    pub documents: Vec<String>,
    /// Sample message.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sample_message: Option<String>,
}

/// Query for `sender_ids.check`.
#[derive(Debug, Clone, Default)]
pub struct CheckSenderId {
    /// Value to check.
    pub value: String,
    /// ISO2 country.
    pub country: Option<String>,
}

/// Result of `sender_ids.check`.
#[derive(Debug, Clone, Deserialize)]
pub struct SenderIdCheck {
    /// Format is valid.
    pub valid: Option<bool>,
    /// Not taken.
    pub available: Option<bool>,
    /// Reserved value.
    pub reserved: Option<bool>,
    /// Explanation.
    pub reason: Option<String>,
}

/// Query for `sender_ids.quote`.
#[derive(Debug, Clone, Default)]
pub struct QuoteSenderId {
    /// ISO2 markets, sent comma-joined.
    pub countries: Vec<String>,
}

/// Result of `sender_ids.quote`.
#[derive(Debug, Clone, Deserialize)]
pub struct SenderIdQuote {
    /// Quote fingerprint (`sq_...`).
    pub quote_id: Option<String>,
    /// Per-country fees.
    pub entries: Option<Vec<SenderIdQuoteEntry>>,
    /// Totals per currency.
    pub totals: Option<Vec<Money>>,
}

/// One fee line of a [`SenderIdQuote`].
#[derive(Debug, Clone, Deserialize)]
pub struct SenderIdQuoteEntry {
    /// ISO2 country.
    pub country: Option<String>,
    /// Provider.
    pub provider: Option<String>,
    /// Fee, decimal string.
    pub fee_amount: Option<String>,
    /// Fee currency.
    pub fee_currency: Option<String>,
}

/// A sender registration document (metadata only).
#[derive(Debug, Clone, Deserialize)]
pub struct SenderDocument {
    /// Document UUID.
    pub id: String,
    /// `certificate|signatory-id|authorization`.
    pub kind: Option<String>,
    /// File name.
    pub filename: Option<String>,
    /// MIME type.
    pub content_type: Option<String>,
    /// Size in bytes.
    pub size: Option<i64>,
    /// Scan status.
    pub scan_status: Option<String>,
    /// Review status.
    pub review_status: Option<String>,
    /// Review reason.
    pub review_reason: Option<String>,
    /// Review time.
    pub reviewed_at: Option<String>,
    /// Version.
    pub version: Option<i64>,
    /// Superseded document.
    pub supersedes_id: Option<String>,
    /// Current version flag.
    pub is_current: Option<bool>,
    /// Creation time.
    pub created_at: Option<String>,
}

/// A sender ID application draft.
#[derive(Debug, Clone, Deserialize)]
pub struct SenderIdDraft {
    /// Draft UUID.
    pub id: String,
    /// `onboarding|application`.
    pub source: Option<String>,
    /// Sender value.
    pub value: Option<String>,
    /// Kind.
    pub kind: Option<String>,
    /// ISO2 markets.
    pub countries: Option<Vec<String>>,
    /// Use case.
    pub use_case: Option<String>,
    /// Sample message.
    pub sample_message: Option<String>,
    /// Document UUIDs.
    pub documents: Option<Vec<String>>,
    /// Optimistic-lock version.
    pub version: Option<i64>,
    /// `active|submitted`.
    pub status: Option<String>,
    /// Submitted sender ID UUID.
    pub submitted_sender_id: Option<String>,
    /// Creation time.
    pub created_at: Option<String>,
    /// Update time.
    pub updated_at: Option<String>,
}

/// Body of `sender_ids.create_draft`.
#[derive(Debug, Clone, Default, Serialize)]
pub struct CreateSenderIdDraft {
    /// `onboarding|application`.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub source: Option<String>,
    /// Sender value.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub value: Option<String>,
    /// Kind.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub kind: Option<String>,
    /// ISO2 markets.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub countries: Option<Vec<String>>,
    /// Use case.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub use_case: Option<String>,
    /// Sample message.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sample_message: Option<String>,
    /// Document UUIDs.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub documents: Option<Vec<String>>,
}

/// Body of `sender_ids.update_draft`; `version` must be the current one.
#[derive(Debug, Clone, Default, Serialize)]
pub struct UpdateSenderIdDraft {
    /// Current version (required).
    pub version: i64,
    /// Sender value.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub value: Option<String>,
    /// Kind.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub kind: Option<String>,
    /// ISO2 markets.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub countries: Option<Vec<String>>,
    /// Use case.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub use_case: Option<String>,
    /// Sample message.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sample_message: Option<String>,
    /// Document UUIDs.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub documents: Option<Vec<String>>,
}

// -- suppressions -------------------------------------------------------------

/// A suppressed destination.
#[derive(Debug, Clone, Deserialize)]
pub struct Suppression {
    /// Suppression id (int).
    pub id: i64,
    /// Phone number, E.164.
    pub e164: Option<String>,
    /// `stop_keyword|manual|complaint|invalid_number`.
    pub reason: Option<String>,
    /// Creation time.
    pub created_at: Option<String>,
}

/// Body of `suppressions.create` and one row of `suppressions.import`.
#[derive(Debug, Clone, Default, Serialize)]
pub struct CreateSuppression {
    /// Phone number, E.164.
    pub e164: String,
    /// `stop_keyword|manual|complaint|invalid_number`.
    pub reason: String,
}

/// Result of `suppressions.import`.
#[derive(Debug, Clone, Deserialize)]
pub struct SuppressionImportResult {
    /// Rows created.
    pub created: Option<i64>,
    /// Rows received.
    pub received: Option<i64>,
}

// -- compliance / countries ---------------------------------------------------

/// Compliance rules for a country.
#[derive(Debug, Clone, Deserialize)]
pub struct CountryRules {
    /// ISO2.
    pub iso2: Option<String>,
    /// Name.
    pub name: Option<String>,
    /// Status.
    pub status: Option<String>,
    /// Dial code (`+254`).
    pub dial_code: Option<String>,
    /// Opt-out keywords.
    pub stop_keywords: Option<Vec<String>>,
    /// Quiet hours.
    pub quiet_hours: Option<Vec<QuietHours>>,
    /// Content rules.
    pub content_rules: Option<Vec<CountryContentRule>>,
}

/// A quiet-hours window.
#[derive(Debug, Clone, Deserialize)]
pub struct QuietHours {
    /// Traffic type.
    pub traffic_type: Option<String>,
    /// Local start time.
    pub start_local: Option<String>,
    /// Local end time.
    pub end_local: Option<String>,
    /// Enforcement mode, for example `defer`.
    pub enforce: Option<String>,
}

/// A content rule inside [`CountryRules`].
#[derive(Debug, Clone, Deserialize)]
pub struct CountryContentRule {
    /// Kind.
    pub kind: Option<String>,
    /// Pattern.
    pub pattern: Option<String>,
    /// Action.
    pub action: Option<String>,
    /// Traffic types.
    pub traffic_types: Option<Vec<String>>,
    /// Enabled.
    pub enabled: Option<bool>,
}

/// A workspace-visible content rule.
#[derive(Debug, Clone, Deserialize)]
pub struct ContentRule {
    /// Rule id (int).
    pub id: i64,
    /// ISO2 country, `None` for all.
    pub country_iso2: Option<String>,
    /// `blocked_keyword|regex`.
    pub kind: Option<String>,
    /// Pattern.
    pub pattern: Option<String>,
    /// `reject|hold_for_review`.
    pub action: Option<String>,
    /// Traffic types.
    pub traffic_types: Option<Vec<String>>,
    /// Enabled.
    pub enabled: Option<bool>,
}

/// A destination country in the public catalog.
#[derive(Debug, Clone, Deserialize)]
pub struct Country {
    /// ISO2.
    pub iso2: Option<String>,
    /// Name.
    pub name: Option<String>,
    /// Dial code.
    pub dial_code: Option<String>,
    /// Local currency.
    pub currency: Option<String>,
    /// Status.
    pub status: Option<String>,
    /// Effective base price per message.
    pub price_per_message: Option<Money>,
    /// Sender kinds routable.
    pub sender_kinds: Option<Vec<String>>,
    /// Routable providers.
    pub providers_available: Option<i64>,
}

/// A carrier in a country.
#[derive(Debug, Clone, Deserialize)]
pub struct Carrier {
    /// Carrier UUID.
    pub id: String,
    /// Name.
    pub name: Option<String>,
    /// MCC/MNC codes.
    pub mcc_mnc: Option<Vec<String>>,
    /// Number prefixes.
    pub prefixes: Option<Vec<String>>,
}

/// A public routable route in a country.
#[derive(Debug, Clone, Deserialize)]
pub struct Route {
    /// Provider.
    pub provider: Option<String>,
    /// Carrier.
    pub carrier: Option<String>,
    /// Health.
    pub health: Option<String>,
    /// Cost, decimal string.
    pub cost: Option<String>,
    /// Cost currency.
    pub currency: Option<String>,
    /// Priority.
    pub priority: Option<i64>,
    /// Effective sell price.
    pub sell_price: Option<Money>,
    /// Submit p50 in ms.
    pub p50_ms: Option<i64>,
}

// -- wallet -------------------------------------------------------------------

/// A wallet balance.
#[derive(Debug, Clone, Deserialize)]
pub struct WalletBalance {
    /// Wallet UUID.
    pub id: String,
    /// Currency.
    pub currency: Option<String>,
    /// Balance, decimal string.
    pub balance: Option<String>,
    /// Reserved, decimal string.
    pub reserved: Option<String>,
    /// `sandbox` or `live`.
    pub environment: Option<String>,
}

/// A wallet ledger entry.
#[derive(Debug, Clone, Deserialize)]
pub struct LedgerEntry {
    /// Entry id (int64).
    pub id: i64,
    /// Wallet UUID.
    pub wallet_id: Option<String>,
    /// Entry type.
    pub r#type: Option<String>,
    /// Amount, decimal string.
    pub amount: Option<String>,
    /// Balance after, decimal string.
    pub balance_after: Option<String>,
    /// Reserved delta, decimal string.
    pub reserved_delta: Option<String>,
    /// Reserved after, decimal string.
    pub reserved_after: Option<String>,
    /// Reference.
    pub reference: Option<String>,
    /// Payment UUID.
    pub payment_id: Option<String>,
    /// Message UUID.
    pub message_id: Option<String>,
    /// Creation time.
    pub created_at: Option<String>,
}

/// Query for `wallet.ledger` (pages by `before`, not by cursor).
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct LedgerParams {
    /// Rows 1..200.
    pub limit: Option<u32>,
    /// Smallest entry id already seen.
    pub before: Option<i64>,
}

/// Body of `wallet.create_topup`.
#[derive(Debug, Clone, Default, Serialize)]
pub struct CreateTopup {
    /// Amount, decimal string.
    pub amount: String,
    /// Currency.
    pub currency: String,
    /// `card|mobile_money|bank_transfer`.
    pub channel: String,
    /// Payer email (a verified workspace member).
    pub email: String,
}

/// An initialized top-up.
#[derive(Debug, Clone, Deserialize)]
pub struct Topup {
    /// Top-up id.
    pub id: String,
    /// Provider reference.
    pub reference: Option<String>,
    /// Checkout URL.
    pub authorization_url: Option<String>,
    /// Provider access code.
    pub access_code: Option<String>,
    /// Amount, decimal string.
    pub amount: Option<String>,
    /// Currency.
    pub currency: Option<String>,
    /// Status.
    pub status: Option<String>,
}

// -- pricing ------------------------------------------------------------------

/// Query for `pricing.get`.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct PricingParams {
    /// `sms|lookup|number_monthly` (default `sms`).
    pub product: Option<String>,
    /// ISO2 country.
    pub country: Option<String>,
}

/// A workspace price list.
#[derive(Debug, Clone, Deserialize)]
pub struct PriceList {
    /// Workspace UUID.
    pub workspace_id: Option<String>,
    /// Currency.
    pub currency: Option<String>,
    /// Product.
    pub product: Option<String>,
    /// Entries.
    pub entries: Option<Vec<PriceEntry>>,
}

/// One price-list row.
#[derive(Debug, Clone, Deserialize)]
pub struct PriceEntry {
    /// ISO2.
    pub country_iso2: Option<String>,
    /// Country name.
    pub country_name: Option<String>,
    /// Carrier UUID.
    pub carrier_id: Option<String>,
    /// Carrier name.
    pub carrier_name: Option<String>,
    /// Product.
    pub product: Option<String>,
    /// Minimum monthly volume.
    pub min_monthly_volume: Option<i64>,
    /// Markup type.
    pub markup_type: Option<String>,
    /// Markup value, decimal string.
    pub markup_value: Option<String>,
    /// Sell currency.
    pub sell_currency: Option<String>,
    /// Sell amount, decimal string.
    pub sell_amount: Option<String>,
    /// Converted amount, decimal string.
    pub converted_amount: Option<String>,
    /// Converted currency.
    pub converted_currency: Option<String>,
    /// Workspace override flag.
    pub workspace_override: Option<bool>,
    /// Effective from.
    pub effective_from: Option<String>,
    /// FX rate, decimal string.
    pub fx_rate: Option<String>,
}

// -- analytics ----------------------------------------------------------------

/// Query shared by the analytics methods. `range` (`Nd`) cannot be combined
/// with `from`/`to`.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct AnalyticsQuery {
    /// Three-letter currency.
    pub currency: Option<String>,
    /// `7d`, `30d`, ... (1..366 days).
    pub range: Option<String>,
    /// RFC 3339 or `YYYY-MM-DD`.
    pub from: Option<String>,
    /// RFC 3339 or `YYYY-MM-DD`.
    pub to: Option<String>,
    /// `day|hour`.
    pub bucket: Option<String>,
}

/// Headline analytics.
#[derive(Debug, Clone, Deserialize)]
pub struct AnalyticsOverview {
    /// Sent.
    pub sent: Option<i64>,
    /// Delivered.
    pub delivered: Option<i64>,
    /// Failed.
    pub failed: Option<i64>,
    /// Parts.
    pub parts: Option<i64>,
    /// Delivery rate.
    pub delivery_rate: Option<f64>,
    /// Spend, decimal string.
    pub spend: Option<String>,
    /// p50 latency ms.
    pub p50_ms: Option<i64>,
    /// p95 latency ms.
    pub p95_ms: Option<i64>,
    /// Window start.
    pub from: Option<String>,
    /// Window end.
    pub to: Option<String>,
    /// Currency.
    pub currency: Option<String>,
    /// `sandbox` or `live`.
    pub environment: Option<String>,
}

/// One row of a dimension breakdown (`by_country`, `by_carrier`, `by_sender_id`).
#[derive(Debug, Clone, Deserialize)]
pub struct AnalyticsRow {
    /// Dimension key.
    pub key: Option<String>,
    /// Display name.
    pub name: Option<String>,
    /// Sent.
    pub sent: Option<i64>,
    /// Delivered.
    pub delivered: Option<i64>,
    /// Failed.
    pub failed: Option<i64>,
    /// Parts.
    pub parts: Option<i64>,
    /// Delivery rate.
    pub delivery_rate: Option<f64>,
    /// Spend, decimal string.
    pub spend: Option<String>,
    /// p50 latency ms.
    pub p50_ms: Option<i64>,
    /// p95 latency ms.
    pub p95_ms: Option<i64>,
}

/// One time-series bucket.
#[derive(Debug, Clone, Deserialize)]
pub struct AnalyticsPoint {
    /// Bucket start.
    pub bucket: Option<String>,
    /// Sent.
    pub sent: Option<i64>,
    /// Delivered.
    pub delivered: Option<i64>,
    /// Failed.
    pub failed: Option<i64>,
    /// Parts.
    pub parts: Option<i64>,
    /// Delivery rate.
    pub delivery_rate: Option<f64>,
    /// Spend, decimal string.
    pub spend: Option<String>,
    /// p50 latency ms.
    pub p50_ms: Option<i64>,
    /// p95 latency ms.
    pub p95_ms: Option<i64>,
}

// -- sandbox ------------------------------------------------------------------

/// A sandbox message with its rendered text (including OTP codes).
#[derive(Debug, Clone, Deserialize)]
pub struct SandboxMessage {
    /// Message UUID.
    pub id: String,
    /// Destination.
    pub to: Option<String>,
    /// Sender ID.
    pub sender_id: Option<String>,
    /// Rendered text.
    pub text: Option<String>,
    /// Parts.
    pub parts: Option<i64>,
    /// Status.
    pub status: Option<String>,
    /// Traffic type.
    pub traffic_type: Option<String>,
    /// Creation time.
    pub created_at: Option<String>,
    /// Send time.
    pub sent_at: Option<String>,
}
