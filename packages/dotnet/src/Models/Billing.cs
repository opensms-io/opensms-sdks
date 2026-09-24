using System;
using System.Collections.Generic;
using System.Text.Json.Serialization;

namespace Opensms
{
    /// <summary>A prepaid wallet balance.</summary>
    public sealed class WalletBalance
    {
        [JsonPropertyName("id")] public string Id { get; set; } = "";
        [JsonPropertyName("currency")] public string? Currency { get; set; }
        /// <summary>Decimal string.</summary>
        [JsonPropertyName("balance")] public string? Balance { get; set; }
        [JsonPropertyName("reserved")] public string? Reserved { get; set; }
        /// <summary><c>sandbox</c> or <c>live</c>.</summary>
        [JsonPropertyName("environment")] public string? Environment { get; set; }
    }

    /// <summary>One wallet ledger row.</summary>
    public sealed class LedgerEntry
    {
        [JsonPropertyName("id")] public long Id { get; set; }
        [JsonPropertyName("wallet_id")] public string? WalletId { get; set; }
        [JsonPropertyName("type")] public string? Type { get; set; }
        [JsonPropertyName("amount")] public string? Amount { get; set; }
        [JsonPropertyName("balance_after")] public string? BalanceAfter { get; set; }
        [JsonPropertyName("reserved_delta")] public string? ReservedDelta { get; set; }
        [JsonPropertyName("reserved_after")] public string? ReservedAfter { get; set; }
        [JsonPropertyName("reference")] public string? Reference { get; set; }
        [JsonPropertyName("payment_id")] public string? PaymentId { get; set; }
        [JsonPropertyName("message_id")] public string? MessageId { get; set; }
        [JsonPropertyName("created_at")] public DateTimeOffset? CreatedAt { get; set; }
    }

    /// <summary>Paging for <see cref="WalletResource.LedgerAsync"/> (not cursor based).</summary>
    public sealed class LedgerParams
    {
        /// <summary>1..200.</summary>
        public int? Limit { get; set; }
        /// <summary>The smallest ledger <c>id</c> already seen; stop when fewer than <see cref="Limit"/> rows return.</summary>
        public long? Before { get; set; }
    }

    /// <summary>Parameters for <see cref="WalletResource.CreateTopupAsync"/>.</summary>
    public sealed class CreateTopupParams
    {
        /// <summary>Decimal string, for example <c>"100.00"</c>.</summary>
        [JsonPropertyName("amount")] public required string Amount { get; set; }
        [JsonPropertyName("currency")] public required string Currency { get; set; }
        /// <summary><c>card|mobile_money|bank_transfer</c>.</summary>
        [JsonPropertyName("channel")] public required string Channel { get; set; }
        [JsonPropertyName("email")] public required string Email { get; set; }
    }

    /// <summary>An initialised payment-provider top-up.</summary>
    public sealed class Topup
    {
        [JsonPropertyName("id")] public string Id { get; set; } = "";
        [JsonPropertyName("reference")] public string? Reference { get; set; }
        [JsonPropertyName("authorization_url")] public string? AuthorizationUrl { get; set; }
        [JsonPropertyName("access_code")] public string? AccessCode { get; set; }
        [JsonPropertyName("amount")] public string? Amount { get; set; }
        [JsonPropertyName("currency")] public string? Currency { get; set; }
        [JsonPropertyName("status")] public string? Status { get; set; }
    }

    /// <summary>Query for <see cref="PricingResource.GetAsync"/>.</summary>
    public sealed class PricingParams
    {
        /// <summary><c>sms|lookup|number_monthly</c> (default <c>sms</c>).</summary>
        public string? Product { get; set; }
        /// <summary>ISO2 country filter.</summary>
        public string? Country { get; set; }
    }

    /// <summary>Your workspace's price list.</summary>
    public sealed class PriceList
    {
        [JsonPropertyName("workspace_id")] public string? WorkspaceId { get; set; }
        [JsonPropertyName("currency")] public string? Currency { get; set; }
        [JsonPropertyName("product")] public string? Product { get; set; }
        [JsonPropertyName("entries")] public List<PriceEntry>? Entries { get; set; }
    }

    /// <summary>One price row.</summary>
    public sealed class PriceEntry
    {
        [JsonPropertyName("country_iso2")] public string? CountryIso2 { get; set; }
        [JsonPropertyName("country_name")] public string? CountryName { get; set; }
        [JsonPropertyName("carrier_id")] public string? CarrierId { get; set; }
        [JsonPropertyName("carrier_name")] public string? CarrierName { get; set; }
        [JsonPropertyName("product")] public string? Product { get; set; }
        [JsonPropertyName("min_monthly_volume")] public long? MinMonthlyVolume { get; set; }
        [JsonPropertyName("markup_type")] public string? MarkupType { get; set; }
        [JsonPropertyName("markup_value")] public string? MarkupValue { get; set; }
        [JsonPropertyName("sell_currency")] public string? SellCurrency { get; set; }
        [JsonPropertyName("sell_amount")] public string? SellAmount { get; set; }
        [JsonPropertyName("converted_amount")] public string? ConvertedAmount { get; set; }
        [JsonPropertyName("converted_currency")] public string? ConvertedCurrency { get; set; }
        [JsonPropertyName("workspace_override")] public bool? WorkspaceOverride { get; set; }
        [JsonPropertyName("effective_from")] public DateTimeOffset? EffectiveFrom { get; set; }
        [JsonPropertyName("fx_rate")] public string? FxRate { get; set; }
    }

    /// <summary>Common analytics query. Use <see cref="Range"/> or <see cref="From"/>/<see cref="To"/>, not both.</summary>
    public sealed class AnalyticsQuery
    {
        /// <summary>3-letter currency (defaults to the workspace currency).</summary>
        public string? Currency { get; set; }
        /// <summary><c>Nd</c> with N in 1..366 (default <c>30d</c>).</summary>
        public string? Range { get; set; }
        public DateTimeInput? From { get; set; }
        public DateTimeInput? To { get; set; }
        /// <summary><c>day|hour</c>.</summary>
        public string? Bucket { get; set; }
    }

    /// <summary>Delivery metrics shared by every analytics response.</summary>
    public class AnalyticsMetrics
    {
        [JsonPropertyName("sent")] public long? Sent { get; set; }
        [JsonPropertyName("delivered")] public long? Delivered { get; set; }
        [JsonPropertyName("failed")] public long? Failed { get; set; }
        [JsonPropertyName("parts")] public long? Parts { get; set; }
        [JsonPropertyName("delivery_rate")] public double? DeliveryRate { get; set; }
        /// <summary>Decimal string.</summary>
        [JsonPropertyName("spend")] public string? Spend { get; set; }
        [JsonPropertyName("p50_ms")] public double? P50Ms { get; set; }
        [JsonPropertyName("p95_ms")] public double? P95Ms { get; set; }
    }

    /// <summary>Totals for the selected period.</summary>
    public sealed class AnalyticsOverview : AnalyticsMetrics
    {
        [JsonPropertyName("from")] public DateTimeOffset? From { get; set; }
        [JsonPropertyName("to")] public DateTimeOffset? To { get; set; }
        [JsonPropertyName("currency")] public string? Currency { get; set; }
        [JsonPropertyName("environment")] public string? Environment { get; set; }
    }

    /// <summary>Metrics for one country, carrier or sender ID.</summary>
    public sealed class AnalyticsBreakdown : AnalyticsMetrics
    {
        [JsonPropertyName("key")] public string? Key { get; set; }
        [JsonPropertyName("name")] public string? Name { get; set; }
    }

    /// <summary>Metrics for one time bucket.</summary>
    public sealed class AnalyticsPoint : AnalyticsMetrics
    {
        [JsonPropertyName("bucket")] public DateTimeOffset? Bucket { get; set; }
    }
}
