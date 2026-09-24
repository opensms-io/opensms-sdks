using System.Collections.Generic;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
using Opensms.Internal;

namespace Opensms
{
    /// <summary>Prepaid balances, ledger and top-ups. Accessed as <c>client.Wallet</c>.</summary>
    public sealed class WalletResource
    {
        private readonly ApiTransport _t;

        internal WalletResource(ApiTransport transport) => _t = transport;

        /// <summary>Wallet balances for the key's environment (<c>GET /v1/wallet</c>).</summary>
        public async Task<List<WalletBalance>> BalancesAsync(CancellationToken ct = default)
        {
            var env = await _t.SendAsync<DataEnvelope<WalletBalance>>(new ApiRequest(HttpMethod.Get, "/v1/wallet"), ct).ConfigureAwait(false);
            return env?.Data ?? new List<WalletBalance>();
        }

        /// <summary>
        /// Ledger entries, newest first (<c>GET /v1/wallet/ledger</c>). Not cursor
        /// based: pass the smallest id seen as <c>Before</c> for the next page and stop
        /// when fewer than <c>Limit</c> rows come back.
        /// </summary>
        public async Task<List<LedgerEntry>> LedgerAsync(LedgerParams? parameters = null, CancellationToken ct = default)
        {
            var env = await _t.SendAsync<DataEnvelope<LedgerEntry>>(new ApiRequest(HttpMethod.Get, "/v1/wallet/ledger")
            {
                Query = Wire.Query().Add("limit", parameters?.Limit).Add("before", parameters?.Before).ToString(),
            }, ct).ConfigureAwait(false);
            return env?.Data ?? new List<LedgerEntry>();
        }

        /// <summary>Start a payment-provider top-up (<c>POST /v1/wallet/topups</c>). Live keys only.</summary>
        public Task<Topup> CreateTopupAsync(CreateTopupParams parameters, RequestOptions? options = null, CancellationToken ct = default)
            => _t.SendAsync<Topup>(new ApiRequest(HttpMethod.Post, "/v1/wallet/topups")
            {
                JsonBody = Check.NotNull(parameters, nameof(parameters)),
                Idempotency = Idempotency.Send,
                IdempotencyKey = options?.IdempotencyKey,
            }, ct);
    }
}
