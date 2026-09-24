using System.Collections.Generic;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
using Opensms.Internal;

namespace Opensms
{
    /// <summary>Sender IDs, application drafts and registration documents. Accessed as <c>client.SenderIds</c>.</summary>
    public sealed class SenderIdsResource
    {
        private readonly ApiTransport _t;

        internal SenderIdsResource(ApiTransport transport) => _t = transport;

        /// <summary>List sender IDs (<c>GET /v1/sender-ids</c>).</summary>
        public Task<Page<SenderId>> ListAsync(ListParams? parameters = null, CancellationToken ct = default)
            => _t.SendAsync<Page<SenderId>>(new ApiRequest(HttpMethod.Get, "/v1/sender-ids") { Query = Wire.Query(parameters).ToString() }, ct);

        /// <summary>Get a sender ID with its registrations (<c>GET /v1/sender-ids/{id}</c>).</summary>
        public Task<SenderId> GetAsync(string id, CancellationToken ct = default)
            => _t.SendAsync<SenderId>(new ApiRequest(HttpMethod.Get, "/v1/sender-ids/" + Wire.Seg(id, nameof(id))), ct);

        /// <summary>Apply for a sender ID (<c>POST /v1/sender-ids</c>). May charge fees, so it is never auto-retried.</summary>
        public Task<SenderId> CreateAsync(CreateSenderIdParams parameters, CancellationToken ct = default)
            => _t.SendAsync<SenderId>(new ApiRequest(HttpMethod.Post, "/v1/sender-ids")
            {
                JsonBody = Check.NotNull(parameters, nameof(parameters)),
            }, ct);

        /// <summary>Amend an application (<c>PATCH /v1/sender-ids/{id}</c>).</summary>
        public Task<SenderId> UpdateAsync(string id, UpdateSenderIdParams parameters, CancellationToken ct = default)
            => _t.SendAsync<SenderId>(new ApiRequest(ApiTransport.PatchMethod, "/v1/sender-ids/" + Wire.Seg(id, nameof(id)))
            {
                JsonBody = Check.NotNull(parameters, nameof(parameters)),
            }, ct);

        /// <summary>Delete a sender ID (<c>DELETE /v1/sender-ids/{id}</c>).</summary>
        public Task DeleteAsync(string id, CancellationToken ct = default)
            => _t.SendNoContentAsync(new ApiRequest(HttpMethod.Delete, "/v1/sender-ids/" + Wire.Seg(id, nameof(id))), ct);

        /// <summary>Check whether a value can be registered (<c>GET /v1/sender-ids/check</c>).</summary>
        public Task<SenderIdCheckResult> CheckAsync(SenderIdCheckParams parameters, CancellationToken ct = default)
        {
            Check.NotNull(parameters, nameof(parameters));
            return _t.SendAsync<SenderIdCheckResult>(new ApiRequest(HttpMethod.Get, "/v1/sender-ids/check")
            {
                Query = Wire.Query().Add("value", parameters.Value).Add("country", parameters.Country).ToString(),
            }, ct);
        }

        /// <summary>Quote registration fees (<c>GET /v1/sender-ids/quote?countries=KE,NG</c>).</summary>
        public Task<SenderIdQuote> QuoteAsync(SenderIdQuoteParams parameters, CancellationToken ct = default)
        {
            Check.NotNull(parameters, nameof(parameters));
            return _t.SendAsync<SenderIdQuote>(new ApiRequest(HttpMethod.Get, "/v1/sender-ids/quote")
            {
                Query = Wire.Query().Add("countries", parameters.Countries).ToString(),
            }, ct);
        }

        /// <summary>List uploaded registration documents (<c>GET /v1/sender-documents</c>). Upload and download are console only.</summary>
        public async Task<List<SenderDocument>> ListDocumentsAsync(CancellationToken ct = default)
        {
            var env = await _t.SendAsync<ItemsEnvelope<SenderDocument>>(new ApiRequest(HttpMethod.Get, "/v1/sender-documents"), ct).ConfigureAwait(false);
            return env?.Items ?? new List<SenderDocument>();
        }

        /// <summary>List application drafts (<c>GET /v1/sender-id-drafts</c>).</summary>
        public Task<Page<SenderIdDraft>> ListDraftsAsync(ListParams? parameters = null, CancellationToken ct = default)
            => _t.SendAsync<Page<SenderIdDraft>>(new ApiRequest(HttpMethod.Get, "/v1/sender-id-drafts") { Query = Wire.Query(parameters).ToString() }, ct);

        /// <summary>Save a new application draft (<c>POST /v1/sender-id-drafts</c>). Not auto-retried.</summary>
        public Task<SenderIdDraft> CreateDraftAsync(CreateSenderIdDraftParams parameters, CancellationToken ct = default)
            => _t.SendAsync<SenderIdDraft>(new ApiRequest(HttpMethod.Post, "/v1/sender-id-drafts")
            {
                JsonBody = Check.NotNull(parameters, nameof(parameters)),
            }, ct);

        /// <summary>Get a draft (<c>GET /v1/sender-id-drafts/{id}</c>).</summary>
        public Task<SenderIdDraft> GetDraftAsync(string id, CancellationToken ct = default)
            => _t.SendAsync<SenderIdDraft>(new ApiRequest(HttpMethod.Get, "/v1/sender-id-drafts/" + Wire.Seg(id, nameof(id))), ct);

        /// <summary>Update a draft (<c>PATCH /v1/sender-id-drafts/{id}</c>). Pass the current version; 409 on mismatch.</summary>
        public Task<SenderIdDraft> UpdateDraftAsync(string id, UpdateSenderIdDraftParams parameters, CancellationToken ct = default)
            => _t.SendAsync<SenderIdDraft>(new ApiRequest(ApiTransport.PatchMethod, "/v1/sender-id-drafts/" + Wire.Seg(id, nameof(id)))
            {
                JsonBody = Check.NotNull(parameters, nameof(parameters)),
            }, ct);

        /// <summary>Delete a draft (<c>DELETE /v1/sender-id-drafts/{id}</c>).</summary>
        public Task DeleteDraftAsync(string id, CancellationToken ct = default)
            => _t.SendNoContentAsync(new ApiRequest(HttpMethod.Delete, "/v1/sender-id-drafts/" + Wire.Seg(id, nameof(id))), ct);
    }
}
