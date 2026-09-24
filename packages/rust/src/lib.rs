//! Async Rust SDK for the [OpenSMS](https://opensms.io) prepaid SMS API.
//!
//! Send SMS and OTPs, run batches, look up numbers, manage contacts,
//! templates, webhooks, numbers and sender IDs, and read the wallet and
//! analytics. Built on `reqwest` and `serde`, with one transport layer that
//! owns bearer auth, Idempotency-Keys, retries on `429`/`5xx`/network errors
//! (honouring `Retry-After`), and error mapping to [`OpensmsError`].
//!
//! # Quickstart
//!
//! ```no_run
//! use opensms::{Client, SendMessage};
//!
//! #[tokio::main]
//! async fn main() -> Result<(), opensms::OpensmsError> {
//!     let client = Client::new(std::env::var("OPENSMS_API_KEY").unwrap())?;
//!     let message = client
//!         .messages()
//!         .send(&SendMessage::new("+254700000012", "Your order has shipped"))
//!         .await?;
//!     println!("{} {:?}", message.id, message.status);
//!     Ok(())
//! }
//! ```

#![forbid(unsafe_code)]
#![warn(missing_docs)]
// OpensmsError keeps every problem field public and inline by design.
#![allow(clippy::result_large_err)]

mod client;
mod crypto;
mod error;
mod http;
mod models;
mod pagination;
mod resources;
mod util;
pub mod webhook;

pub use client::{Client, ClientBuilder};
pub use error::{ErrorKind, OpensmsError, Result};
pub use http::{
    BoxFuture, HttpRequest, HttpResponse, ReqwestTransport, Sleeper, TokioSleeper, Transport,
    USER_AGENT,
};
pub use models::*;
pub use pagination::{paginate, Paginator};
pub use resources::{
    Analytics, Batches, Compliance, ContactGroups, Contacts, Countries, Inbound, Lookups, Messages,
    Numbers, Otp, Pricing, Sandbox, SenderIds, Suppressions, Templates, Wallet, Webhooks,
};
pub use util::{rfc3339, uuid_v4};
pub use webhook::{construct_event, verify_signature, VerifyOptions};

/// Compiles every README example as a doctest.
#[cfg(doctest)]
#[doc = include_str!("../README.md")]
pub struct ReadmeDoctests;
