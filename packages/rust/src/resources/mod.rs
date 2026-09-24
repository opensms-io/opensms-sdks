//! Resource handles. Each is a thin wrapper over the shared transport: build
//! the path, query and body, call the transport, decode the model.

mod analytics;
mod batches;
mod compliance;
mod contact_groups;
mod contacts;
mod countries;
mod inbound;
mod lookups;
mod messages;
mod numbers;
mod otp;
mod pricing;
mod sandbox;
mod sender_ids;
mod suppressions;
mod templates;
mod wallet;
mod webhooks;

pub use analytics::Analytics;
pub use batches::Batches;
pub use compliance::Compliance;
pub use contact_groups::ContactGroups;
pub use contacts::Contacts;
pub use countries::Countries;
pub use inbound::Inbound;
pub use lookups::Lookups;
pub use messages::Messages;
pub use numbers::Numbers;
pub use otp::Otp;
pub use pricing::Pricing;
pub use sandbox::Sandbox;
pub use sender_ids::SenderIds;
pub use suppressions::Suppressions;
pub use templates::Templates;
pub use wallet::Wallet;
pub use webhooks::Webhooks;

use crate::error::{OpensmsError, Result};
use crate::http::Idem;
use crate::models::{ListParams, RequestOptions};
use crate::util::{encode, query};

/// Validate a non-empty id and percent-encode it as one path segment.
pub(crate) fn seg(value: &str, name: &str) -> Result<String> {
    if value.trim().is_empty() {
        return Err(OpensmsError::invalid_argument(format!(
            "{name} must be a non-empty string"
        )));
    }
    Ok(encode(value, false))
}

/// `?limit=..&cursor=..` for a cursor list.
pub(crate) fn list_query(p: &ListParams) -> String {
    query(&[
        ("limit", p.limit.map(|v| v.to_string())),
        ("cursor", p.cursor.clone()),
    ])
}

/// The idempotency setting for a req/opt method.
pub(crate) fn idem(opts: &RequestOptions) -> Idem<'_> {
    Idem::Key(opts.idempotency_key.as_deref())
}
