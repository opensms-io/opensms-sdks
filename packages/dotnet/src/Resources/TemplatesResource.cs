using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
using Opensms.Internal;

namespace Opensms
{
    /// <summary>Reusable message templates with <c>{{name}}</c> placeholders. Accessed as <c>client.Templates</c>.</summary>
    public sealed class TemplatesResource
    {
        private readonly ApiTransport _t;

        internal TemplatesResource(ApiTransport transport) => _t = transport;

        /// <summary>List templates (<c>GET /v1/templates</c>).</summary>
        public Task<Page<Template>> ListAsync(ListParams? parameters = null, CancellationToken ct = default)
            => _t.SendAsync<Page<Template>>(new ApiRequest(HttpMethod.Get, "/v1/templates") { Query = Wire.Query(parameters).ToString() }, ct);

        /// <summary>Create a template (<c>POST /v1/templates</c>). 409 when the name is taken.</summary>
        public Task<Template> CreateAsync(CreateTemplateParams parameters, RequestOptions? options = null, CancellationToken ct = default)
            => _t.SendAsync<Template>(new ApiRequest(HttpMethod.Post, "/v1/templates")
            {
                JsonBody = Check.NotNull(parameters, nameof(parameters)),
                Idempotency = Idempotency.Send,
                IdempotencyKey = options?.IdempotencyKey,
            }, ct);

        /// <summary>Get a template (<c>GET /v1/templates/{id}</c>).</summary>
        public Task<Template> GetAsync(string id, CancellationToken ct = default)
            => _t.SendAsync<Template>(new ApiRequest(HttpMethod.Get, "/v1/templates/" + Wire.Seg(id, nameof(id))), ct);

        /// <summary>Update a template (<c>PATCH /v1/templates/{id}</c>).</summary>
        public Task<Template> UpdateAsync(string id, UpdateTemplateParams parameters, CancellationToken ct = default)
            => _t.SendAsync<Template>(new ApiRequest(ApiTransport.PatchMethod, "/v1/templates/" + Wire.Seg(id, nameof(id)))
            {
                JsonBody = Check.NotNull(parameters, nameof(parameters)),
            }, ct);

        /// <summary>Delete a template (<c>DELETE /v1/templates/{id}</c>).</summary>
        public Task DeleteAsync(string id, CancellationToken ct = default)
            => _t.SendNoContentAsync(new ApiRequest(HttpMethod.Delete, "/v1/templates/" + Wire.Seg(id, nameof(id))), ct);
    }
}
