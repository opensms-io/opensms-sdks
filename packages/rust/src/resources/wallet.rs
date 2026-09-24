//! The `wallet` resource: balances, ledger and top-ups.

use serde::Deserialize;

use super::idem;
use crate::error::Result;
use crate::http::HttpClient;
use crate::models::{CreateTopup, LedgerEntry, LedgerParams, RequestOptions, Topup, WalletBalance};
use crate::util::query;

#[derive(Deserialize)]
struct Data<T> {
    #[serde(default = "Vec::new")]
    data: Vec<T>,
}

/// Accessed as `client.wallet()`.
#[derive(Debug, Clone)]
pub struct Wallet {
    http: HttpClient,
}

impl Wallet {
    pub(crate) fn new(http: HttpClient) -> Self {
        Self { http }
    }

    /// Balances in the key's environment.
    pub async fn balances(&self) -> Result<Vec<WalletBalance>> {
        let r: Data<WalletBalance> = self.http.get("/v1/wallet").await?;
        Ok(r.data)
    }

    /// Ledger entries, newest first. Page manually: pass the smallest `id`
    /// seen as `before`, and stop when fewer than `limit` rows come back.
    pub async fn ledger(&self, params: LedgerParams) -> Result<Vec<LedgerEntry>> {
        let q = query(&[
            ("limit", params.limit.map(|v| v.to_string())),
            ("before", params.before.map(|v| v.to_string())),
        ]);
        let r: Data<LedgerEntry> = self.http.get(&format!("/v1/wallet/ledger{q}")).await?;
        Ok(r.data)
    }

    /// Start a payment-provider top-up (live keys only).
    pub async fn create_topup(&self, params: &CreateTopup) -> Result<Topup> {
        self.create_topup_with(params, &RequestOptions::default())
            .await
    }

    /// [`Wallet::create_topup`] with an explicit Idempotency-Key.
    pub async fn create_topup_with(
        &self,
        params: &CreateTopup,
        opts: &RequestOptions,
    ) -> Result<Topup> {
        self.http
            .send("POST", "/v1/wallet/topups", params, idem(opts))
            .await
    }
}
