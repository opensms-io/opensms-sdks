using System;
using System.Globalization;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
using Opensms.Internal;

namespace Opensms
{
    /// <summary>Webhook endpoints, deliveries and signature verification. Accessed as <c>client.Webhooks</c>.</summary>
    public sealed class WebhooksResource
    {
        private readonly ApiTransport _t;

        internal WebhooksResource(ApiTransport transport) => _t = transport;

        /// <summary>List endpoints (<c>GET /v1/webhooks</c>).</summary>
        public Task<Page<WebhookEndpoint>> ListAsync(ListParams? parameters = null, CancellationToken ct = default)
            => _t.SendAsync<Page<WebhookEndpoint>>(new ApiRequest(HttpMethod.Get, "/v1/webhooks") { Query = Wire.Query(parameters).ToString() }, ct);

        /// <summary>Create an endpoint (<c>POST /v1/webhooks</c>). The response carries the signing <c>Secret</c> once.</summary>
        public Task<WebhookEndpoint> CreateAsync(CreateWebhookParams parameters, RequestOptions? options = null, CancellationToken ct = default)
            => _t.SendAsync<WebhookEndpoint>(new ApiRequest(HttpMethod.Post, "/v1/webhooks")
            {
                JsonBody = Check.NotNull(parameters, nameof(parameters)),
                Idempotency = Idempotency.Send,
                IdempotencyKey = options?.IdempotencyKey,
            }, ct);

        /// <summary>Get an endpoint (<c>GET /v1/webhooks/{id}</c>). The secret is never returned again.</summary>
        public Task<WebhookEndpoint> GetAsync(string id, CancellationToken ct = default)
            => _t.SendAsync<WebhookEndpoint>(new ApiRequest(HttpMethod.Get, "/v1/webhooks/" + Wire.Seg(id, nameof(id))), ct);

        /// <summary>Replace an endpoint (<c>PUT /v1/webhooks/{id}</c>): url, events and enabled are all required.</summary>
        public Task<WebhookEndpoint> UpdateAsync(string id, UpdateWebhookParams parameters, RequestOptions? options = null, CancellationToken ct = default)
            => _t.SendAsync<WebhookEndpoint>(new ApiRequest(HttpMethod.Put, "/v1/webhooks/" + Wire.Seg(id, nameof(id)))
            {
                JsonBody = Check.NotNull(parameters, nameof(parameters)),
                Idempotency = Idempotency.Send,
                IdempotencyKey = options?.IdempotencyKey,
            }, ct);

        /// <summary>Delete an endpoint (<c>DELETE /v1/webhooks/{id}</c>).</summary>
        public Task DeleteAsync(string id, RequestOptions? options = null, CancellationToken ct = default)
            => _t.SendNoContentAsync(new ApiRequest(HttpMethod.Delete, "/v1/webhooks/" + Wire.Seg(id, nameof(id)))
            {
                Idempotency = Idempotency.Send,
                IdempotencyKey = options?.IdempotencyKey,
            }, ct);

        /// <summary>Queue a <c>webhook.test</c> delivery (<c>POST /v1/webhooks/{id}/test</c>).</summary>
        public Task<StatusResult> TestAsync(string id, RequestOptions? options = null, CancellationToken ct = default)
            => _t.SendAsync<StatusResult>(new ApiRequest(HttpMethod.Post, "/v1/webhooks/" + Wire.Seg(id, nameof(id)) + "/test")
            {
                Idempotency = Idempotency.Send,
                IdempotencyKey = options?.IdempotencyKey,
            }, ct);

        /// <summary>List deliveries for an endpoint (<c>GET /v1/webhooks/{id}/deliveries</c>).</summary>
        public Task<Page<WebhookDelivery>> ListDeliveriesAsync(string id, ListParams? parameters = null, CancellationToken ct = default)
            => _t.SendAsync<Page<WebhookDelivery>>(new ApiRequest(HttpMethod.Get, "/v1/webhooks/" + Wire.Seg(id, nameof(id)) + "/deliveries")
            {
                Query = Wire.Query(parameters).ToString(),
            }, ct);

        /// <summary>Replay a delivery (<c>POST /v1/webhooks/{id}/deliveries/{delivery_id}/replay</c>).</summary>
        public Task<StatusResult> ReplayDeliveryAsync(string id, long deliveryId, ReplayDeliveryParams parameters, RequestOptions? options = null, CancellationToken ct = default)
            => _t.SendAsync<StatusResult>(new ApiRequest(HttpMethod.Post,
                "/v1/webhooks/" + Wire.Seg(id, nameof(id)) + "/deliveries/" + deliveryId.ToString(CultureInfo.InvariantCulture) + "/replay")
            {
                JsonBody = Check.NotNull(parameters, nameof(parameters)),
                Idempotency = Idempotency.Send,
                IdempotencyKey = options?.IdempotencyKey,
            }, ct);

        /// <summary>Verify an <c>X-OpenSMS-Signature</c> header. See <see cref="WebhookSignature.Verify(string, string?, string?, TimeSpan?, DateTimeOffset?)"/>.</summary>
        public bool VerifySignature(string payload, string? header, string? secret, TimeSpan? tolerance = null, DateTimeOffset? now = null)
            => WebhookSignature.Verify(payload, header, secret, tolerance, now);

        /// <summary>Verify the raw body bytes. See <see cref="WebhookSignature.Verify(byte[], string?, string?, TimeSpan?, DateTimeOffset?)"/>.</summary>
        public bool VerifySignature(byte[] payload, string? header, string? secret, TimeSpan? tolerance = null, DateTimeOffset? now = null)
            => WebhookSignature.Verify(payload, header, secret, tolerance, now);

        /// <summary>Verify and parse a delivery. See <see cref="WebhookSignature.ConstructEvent(string, string?, string?, TimeSpan?, DateTimeOffset?)"/>.</summary>
        public WebhookEvent ConstructEvent(string payload, string? header, string? secret, TimeSpan? tolerance = null, DateTimeOffset? now = null)
            => WebhookSignature.ConstructEvent(payload, header, secret, tolerance, now);

        /// <summary>Verify and parse raw body bytes. See <see cref="WebhookSignature.ConstructEvent(byte[], string?, string?, TimeSpan?, DateTimeOffset?)"/>.</summary>
        public WebhookEvent ConstructEvent(byte[] payload, string? header, string? secret, TimeSpan? tolerance = null, DateTimeOffset? now = null)
            => WebhookSignature.ConstructEvent(payload, header, secret, tolerance, now);
    }
}
