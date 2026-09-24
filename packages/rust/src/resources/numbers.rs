//! The `numbers` resource: virtual numbers and their inbound rules. Everything
//! except `list` and `available` needs a live key.

use super::{idem, list_query, seg};
use crate::error::Result;
use crate::http::{HttpClient, Idem};
use crate::models::{
    ListParams, Number, NumberQuery, NumberRule, NumberRuleInput, Page, RequestOptions,
};
use crate::util::query;

/// Accessed as `client.numbers()`.
#[derive(Debug, Clone)]
pub struct Numbers {
    http: HttpClient,
}

impl Numbers {
    pub(crate) fn new(http: HttpClient) -> Self {
        Self { http }
    }

    /// List assigned numbers.
    pub async fn list(&self, params: ListParams) -> Result<Page<Number>> {
        self.http
            .get(&format!("/v1/numbers{}", list_query(&params)))
            .await
    }

    /// List numbers available to assign.
    pub async fn available(&self, params: &NumberQuery) -> Result<Vec<Number>> {
        let q = query(&[
            ("country", Some(params.country.clone())),
            ("kind", Some(params.kind.clone())),
        ]);
        self.http.get(&format!("/v1/numbers/available{q}")).await
    }

    /// Assign a number (charges the wallet).
    pub async fn assign(&self, params: &NumberQuery) -> Result<Number> {
        self.assign_with(params, &RequestOptions::default()).await
    }

    /// [`Numbers::assign`] with an explicit Idempotency-Key.
    pub async fn assign_with(&self, params: &NumberQuery, opts: &RequestOptions) -> Result<Number> {
        self.http
            .send("POST", "/v1/numbers", params, idem(opts))
            .await
    }

    /// Release a number.
    pub async fn release(&self, id: &str) -> Result<()> {
        let path = format!("/v1/numbers/{}", seg(id, "id")?);
        self.http.empty("DELETE", &path, Idem::None).await
    }

    /// List inbound rules of a number.
    pub async fn list_rules(&self, id: &str, params: ListParams) -> Result<Page<NumberRule>> {
        self.http
            .get(&format!(
                "/v1/numbers/{}/rules{}",
                seg(id, "id")?,
                list_query(&params)
            ))
            .await
    }

    /// Create an inbound rule.
    pub async fn create_rule(&self, id: &str, rule: &NumberRuleInput) -> Result<NumberRule> {
        self.create_rule_with(id, rule, &RequestOptions::default())
            .await
    }

    /// [`Numbers::create_rule`] with an explicit Idempotency-Key.
    pub async fn create_rule_with(
        &self,
        id: &str,
        rule: &NumberRuleInput,
        opts: &RequestOptions,
    ) -> Result<NumberRule> {
        let path = format!("/v1/numbers/{}/rules", seg(id, "id")?);
        self.http.send("POST", &path, rule, idem(opts)).await
    }

    /// Replace an inbound rule.
    pub async fn update_rule(
        &self,
        id: &str,
        rule_id: &str,
        rule: &NumberRuleInput,
    ) -> Result<NumberRule> {
        let path = format!(
            "/v1/numbers/{}/rules/{}",
            seg(id, "id")?,
            seg(rule_id, "rule_id")?
        );
        self.http.send("PUT", &path, rule, Idem::None).await
    }

    /// Delete an inbound rule.
    pub async fn delete_rule(&self, id: &str, rule_id: &str) -> Result<()> {
        let path = format!(
            "/v1/numbers/{}/rules/{}",
            seg(id, "id")?,
            seg(rule_id, "rule_id")?
        );
        self.http.empty("DELETE", &path, Idem::None).await
    }
}
