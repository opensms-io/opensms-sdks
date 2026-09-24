//! The OpenSMS client: validates configuration and wires the resources to
//! the shared transport.

use std::future::Future;
use std::sync::Arc;
use std::time::Duration;

use crate::error::{OpensmsError, Result};
use crate::http::{
    HttpClient, ReqwestTransport, Sleeper, TokioSleeper, Transport, DEFAULT_BASE_URL,
};
use crate::models::Page;
use crate::pagination::{paginate, Paginator};
use crate::resources::{
    Analytics, Batches, Compliance, ContactGroups, Contacts, Countries, Inbound, Lookups, Messages,
    Numbers, Otp, Pricing, Sandbox, SenderIds, Suppressions, Templates, Wallet, Webhooks,
};

const DEFAULT_TIMEOUT_SECS: u64 = 30;
const DEFAULT_MAX_RETRIES: u32 = 2;
const MIN_SECRET_LEN: usize = 12;

/// Builder for [`Client`]. Construct with [`Client::builder`].
pub struct ClientBuilder {
    api_key: String,
    base_url: String,
    timeout: Duration,
    max_retries: u32,
    transport: Option<Arc<dyn Transport>>,
    sleeper: Option<Arc<dyn Sleeper>>,
}

impl ClientBuilder {
    /// Override the API base URL (default `https://api.opensms.io`). Trailing
    /// slashes are stripped.
    pub fn base_url(mut self, base_url: impl Into<String>) -> Self {
        self.base_url = base_url.into();
        self
    }

    /// Per-attempt timeout covering connect and read. Default 30 s.
    pub fn timeout(mut self, timeout: Duration) -> Self {
        self.timeout = timeout;
        self
    }

    /// Retries after the first attempt. Default 2 (3 attempts). `0` disables
    /// retries.
    pub fn max_retries(mut self, max_retries: u32) -> Self {
        self.max_retries = max_retries;
        self
    }

    /// Replace the HTTP transport (for tests or custom networking).
    pub fn transport(mut self, transport: Arc<dyn Transport>) -> Self {
        self.transport = Some(transport);
        self
    }

    /// Replace the sleeper used between retries (tests inject a no-op).
    pub fn sleeper(mut self, sleeper: Arc<dyn Sleeper>) -> Self {
        self.sleeper = Some(sleeper);
        self
    }

    /// Validate the key and build the client. No network call is made.
    pub fn build(self) -> Result<Client> {
        let environment = environment_of(&self.api_key).ok_or_else(|| {
            OpensmsError::invalid_argument(
                "api_key must start with sk_test_ or sk_live_ followed by more than 12 characters",
            )
        })?;
        let transport: Arc<dyn Transport> = match self.transport {
            Some(t) => t,
            None => Arc::new(ReqwestTransport::new()?),
        };
        let sleeper = self.sleeper.unwrap_or_else(|| Arc::new(TokioSleeper));
        let http = HttpClient::new(
            self.api_key,
            self.base_url,
            self.timeout,
            self.max_retries,
            transport,
            sleeper,
        );
        Ok(Client {
            environment,
            messages: Messages::new(http.clone()),
            batches: Batches::new(http.clone()),
            otp: Otp::new(http.clone()),
            lookups: Lookups::new(http.clone()),
            contacts: Contacts::new(http.clone()),
            contact_groups: ContactGroups::new(http.clone()),
            templates: Templates::new(http.clone()),
            webhooks: Webhooks::new(http.clone()),
            inbound: Inbound::new(http.clone()),
            numbers: Numbers::new(http.clone()),
            sender_ids: SenderIds::new(http.clone()),
            suppressions: Suppressions::new(http.clone()),
            compliance: Compliance::new(http.clone()),
            wallet: Wallet::new(http.clone()),
            pricing: Pricing::new(http.clone()),
            analytics: Analytics::new(http.clone()),
            sandbox: Sandbox::new(http.clone()),
            countries: Countries::new(http.clone()),
            http,
        })
    }
}

/// `sandbox` for `sk_test_` keys, `live` for `sk_live_`, `None` if invalid.
fn environment_of(key: &str) -> Option<&'static str> {
    let (env, rest) = match key.strip_prefix("sk_test_") {
        Some(rest) => ("sandbox", rest),
        None => ("live", key.strip_prefix("sk_live_")?),
    };
    (rest.len() > MIN_SECRET_LEN).then_some(env)
}

/// OpenSMS API client. Cheap to clone; clones share one connection pool.
///
/// ```no_run
/// use opensms::{Client, SendMessage};
///
/// # async fn run() -> Result<(), opensms::OpensmsError> {
/// let client = Client::new("sk_test_...")?;
/// let message = client.messages().send(&SendMessage::new("+254700000012", "Hello")).await?;
/// println!("{} is {:?}", message.id, message.status);
/// # Ok(())
/// # }
/// ```
#[derive(Debug, Clone)]
pub struct Client {
    http: HttpClient,
    environment: &'static str,
    messages: Messages,
    batches: Batches,
    otp: Otp,
    lookups: Lookups,
    contacts: Contacts,
    contact_groups: ContactGroups,
    templates: Templates,
    webhooks: Webhooks,
    inbound: Inbound,
    numbers: Numbers,
    sender_ids: SenderIds,
    suppressions: Suppressions,
    compliance: Compliance,
    wallet: Wallet,
    pricing: Pricing,
    analytics: Analytics,
    sandbox: Sandbox,
    countries: Countries,
}

impl Client {
    /// A client with default settings. The key must start with `sk_test_` or
    /// `sk_live_` and have more than 12 characters after the prefix.
    pub fn new(api_key: impl Into<String>) -> Result<Self> {
        Self::builder(api_key).build()
    }

    /// Start configuring a client.
    pub fn builder(api_key: impl Into<String>) -> ClientBuilder {
        ClientBuilder {
            api_key: api_key.into(),
            base_url: DEFAULT_BASE_URL.to_string(),
            timeout: Duration::from_secs(DEFAULT_TIMEOUT_SECS),
            max_retries: DEFAULT_MAX_RETRIES,
            transport: None,
            sleeper: None,
        }
    }

    /// `"sandbox"` for `sk_test_` keys, `"live"` for `sk_live_` keys.
    pub fn environment(&self) -> &'static str {
        self.environment
    }

    /// The base URL requests go to.
    pub fn base_url(&self) -> &str {
        self.http.base_url()
    }

    /// Walk every page of a cursor list. See [`Paginator`].
    pub fn paginate<T, F, Fut>(&self, fetch: F) -> Paginator<T, F>
    where
        F: FnMut(Option<String>) -> Fut,
        Fut: Future<Output = Result<Page<T>>>,
    {
        paginate(fetch)
    }

    /// Send, list, fetch and cancel messages.
    pub fn messages(&self) -> &Messages {
        &self.messages
    }
    /// Bulk batches.
    pub fn batches(&self) -> &Batches {
        &self.batches
    }
    /// One-time passcodes.
    pub fn otp(&self) -> &Otp {
        &self.otp
    }
    /// Number lookups.
    pub fn lookups(&self) -> &Lookups {
        &self.lookups
    }
    /// Contacts.
    pub fn contacts(&self) -> &Contacts {
        &self.contacts
    }
    /// Contact groups.
    pub fn contact_groups(&self) -> &ContactGroups {
        &self.contact_groups
    }
    /// Message templates.
    pub fn templates(&self) -> &Templates {
        &self.templates
    }
    /// Webhook endpoints and signature verification.
    pub fn webhooks(&self) -> &Webhooks {
        &self.webhooks
    }
    /// Inbound messages.
    pub fn inbound(&self) -> &Inbound {
        &self.inbound
    }
    /// Virtual numbers.
    pub fn numbers(&self) -> &Numbers {
        &self.numbers
    }
    /// Sender IDs, drafts and documents.
    pub fn sender_ids(&self) -> &SenderIds {
        &self.sender_ids
    }
    /// Suppression list.
    pub fn suppressions(&self) -> &Suppressions {
        &self.suppressions
    }
    /// Compliance rules.
    pub fn compliance(&self) -> &Compliance {
        &self.compliance
    }
    /// Wallet balances, ledger and top-ups.
    pub fn wallet(&self) -> &Wallet {
        &self.wallet
    }
    /// Price lists.
    pub fn pricing(&self) -> &Pricing {
        &self.pricing
    }
    /// Delivery analytics.
    pub fn analytics(&self) -> &Analytics {
        &self.analytics
    }
    /// Sandbox message viewer.
    pub fn sandbox(&self) -> &Sandbox {
        &self.sandbox
    }
    /// Public country catalog.
    pub fn countries(&self) -> &Countries {
        &self.countries
    }
}
