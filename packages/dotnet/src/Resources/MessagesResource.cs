using System.Collections.Generic;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
using Opensms.Internal;

namespace Opensms
{
    /// <summary>Send, list, inspect and cancel SMS. Accessed as <c>client.Messages</c>.</summary>
    public sealed class MessagesResource
    {
        private readonly ApiTransport _t;

        internal MessagesResource(ApiTransport transport) => _t = transport;

        /// <summary>Send one SMS (<c>POST /v1/messages</c>). Sends an Idempotency-Key, so retries are safe.</summary>
        public Task<Message> SendAsync(SendMessageParams parameters, RequestOptions? options = null, CancellationToken ct = default)
            => _t.SendAsync<Message>(new ApiRequest(HttpMethod.Post, "/v1/messages")
            {
                JsonBody = Check.NotNull(parameters, nameof(parameters)),
                Idempotency = Idempotency.Send,
                IdempotencyKey = options?.IdempotencyKey,
            }, ct);

        /// <summary>List messages, newest first (<c>GET /v1/messages</c>).</summary>
        public Task<Page<Message>> ListAsync(MessageListParams? parameters = null, CancellationToken ct = default)
            => _t.SendAsync<Page<Message>>(new ApiRequest(HttpMethod.Get, "/v1/messages")
            {
                Query = Wire.Query(parameters)
                    .Add("status", parameters?.Status)
                    .Add("to", parameters?.To)
                    .Add("country", parameters?.Country)
                    .Add("date_from", parameters?.DateFrom)
                    .Add("date_to", parameters?.DateTo)
                    .ToString(),
            }, ct);

        /// <summary>Get one message (<c>GET /v1/messages/{id}</c>).</summary>
        public Task<Message> GetAsync(string id, CancellationToken ct = default)
            => _t.SendAsync<Message>(new ApiRequest(HttpMethod.Get, "/v1/messages/" + Wire.Seg(id, nameof(id))), ct);

        /// <summary>Provider submission attempts for a message (<c>GET /v1/messages/{id}/attempts</c>).</summary>
        public Task<List<Attempt>> AttemptsAsync(string id, CancellationToken ct = default)
            => _t.SendAsync<List<Attempt>>(new ApiRequest(HttpMethod.Get, "/v1/messages/" + Wire.Seg(id, nameof(id)) + "/attempts"), ct);

        /// <summary>Cancel a queued or scheduled message (<c>POST /v1/messages/{id}/cancel</c>). Never retried; 409 when not cancellable.</summary>
        public Task<Message> CancelAsync(string id, CancellationToken ct = default)
            => _t.SendAsync<Message>(new ApiRequest(HttpMethod.Post, "/v1/messages/" + Wire.Seg(id, nameof(id)) + "/cancel"), ct);
    }
}
