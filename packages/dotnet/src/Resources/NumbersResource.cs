using System.Collections.Generic;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
using Opensms.Internal;

namespace Opensms
{
    /// <summary>Virtual numbers and their inbound rules. Accessed as <c>client.Numbers</c>. Writes need a live key.</summary>
    public sealed class NumbersResource
    {
        private readonly ApiTransport _t;

        internal NumbersResource(ApiTransport transport) => _t = transport;

        /// <summary>List your numbers (<c>GET /v1/numbers</c>).</summary>
        public Task<Page<PhoneNumber>> ListAsync(ListParams? parameters = null, CancellationToken ct = default)
            => _t.SendAsync<Page<PhoneNumber>>(new ApiRequest(HttpMethod.Get, "/v1/numbers") { Query = Wire.Query(parameters).ToString() }, ct);

        /// <summary>Numbers available to assign (<c>GET /v1/numbers/available</c>).</summary>
        public Task<List<PhoneNumber>> AvailableAsync(NumberSearchParams parameters, CancellationToken ct = default)
        {
            Check.NotNull(parameters, nameof(parameters));
            return _t.SendAsync<List<PhoneNumber>>(new ApiRequest(HttpMethod.Get, "/v1/numbers/available")
            {
                Query = Wire.Query().Add("country", parameters.Country).Add("kind", parameters.Kind).ToString(),
            }, ct);
        }

        /// <summary>Assign a number (<c>POST /v1/numbers</c>). Charges the wallet; live keys only.</summary>
        public Task<PhoneNumber> AssignAsync(NumberSearchParams parameters, RequestOptions? options = null, CancellationToken ct = default)
            => _t.SendAsync<PhoneNumber>(new ApiRequest(HttpMethod.Post, "/v1/numbers")
            {
                JsonBody = Check.NotNull(parameters, nameof(parameters)),
                Idempotency = Idempotency.Send,
                IdempotencyKey = options?.IdempotencyKey,
            }, ct);

        /// <summary>Release a number (<c>DELETE /v1/numbers/{id}</c>).</summary>
        public Task ReleaseAsync(string id, CancellationToken ct = default)
            => _t.SendNoContentAsync(new ApiRequest(HttpMethod.Delete, "/v1/numbers/" + Wire.Seg(id, nameof(id))), ct);

        /// <summary>List inbound rules on a number (<c>GET /v1/numbers/{id}/rules</c>).</summary>
        public Task<Page<NumberRule>> ListRulesAsync(string id, ListParams? parameters = null, CancellationToken ct = default)
            => _t.SendAsync<Page<NumberRule>>(new ApiRequest(HttpMethod.Get, "/v1/numbers/" + Wire.Seg(id, nameof(id)) + "/rules")
            {
                Query = Wire.Query(parameters).ToString(),
            }, ct);

        /// <summary>Add an inbound rule (<c>POST /v1/numbers/{id}/rules</c>).</summary>
        public Task<NumberRule> CreateRuleAsync(string id, NumberRuleParams rule, RequestOptions? options = null, CancellationToken ct = default)
            => _t.SendAsync<NumberRule>(new ApiRequest(HttpMethod.Post, "/v1/numbers/" + Wire.Seg(id, nameof(id)) + "/rules")
            {
                JsonBody = Check.NotNull(rule, nameof(rule)),
                Idempotency = Idempotency.Send,
                IdempotencyKey = options?.IdempotencyKey,
            }, ct);

        /// <summary>Replace an inbound rule (<c>PUT /v1/numbers/{id}/rules/{rule_id}</c>).</summary>
        public Task<NumberRule> UpdateRuleAsync(string id, string ruleId, NumberRuleParams rule, CancellationToken ct = default)
            => _t.SendAsync<NumberRule>(new ApiRequest(HttpMethod.Put,
                "/v1/numbers/" + Wire.Seg(id, nameof(id)) + "/rules/" + Wire.Seg(ruleId, nameof(ruleId)))
            {
                JsonBody = Check.NotNull(rule, nameof(rule)),
            }, ct);

        /// <summary>Delete an inbound rule (<c>DELETE /v1/numbers/{id}/rules/{rule_id}</c>).</summary>
        public Task DeleteRuleAsync(string id, string ruleId, CancellationToken ct = default)
            => _t.SendNoContentAsync(new ApiRequest(HttpMethod.Delete,
                "/v1/numbers/" + Wire.Seg(id, nameof(id)) + "/rules/" + Wire.Seg(ruleId, nameof(ruleId))), ct);
    }
}
