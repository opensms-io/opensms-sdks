using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
using Opensms.Internal;

namespace Opensms
{
    /// <summary>Inbound SMS on your numbers. Accessed as <c>client.Inbound</c>.</summary>
    public sealed class InboundResource
    {
        private readonly ApiTransport _t;

        internal InboundResource(ApiTransport transport) => _t = transport;

        /// <summary>List received messages (<c>GET /v1/inbound</c>).</summary>
        public Task<Page<InboundMessage>> ListAsync(ListParams? parameters = null, CancellationToken ct = default)
            => _t.SendAsync<Page<InboundMessage>>(new ApiRequest(HttpMethod.Get, "/v1/inbound") { Query = Wire.Query(parameters).ToString() }, ct);

        /// <summary>Reply to an inbound message (<c>POST /v1/inbound/{id}/reply</c>). Live keys only; returns the sent Message.</summary>
        public Task<Message> ReplyAsync(string id, InboundReplyParams parameters, RequestOptions? options = null, CancellationToken ct = default)
            => _t.SendAsync<Message>(new ApiRequest(HttpMethod.Post, "/v1/inbound/" + Wire.Seg(id, nameof(id)) + "/reply")
            {
                JsonBody = Check.NotNull(parameters, nameof(parameters)),
                Idempotency = Idempotency.Send,
                IdempotencyKey = options?.IdempotencyKey,
            }, ct);
    }
}
