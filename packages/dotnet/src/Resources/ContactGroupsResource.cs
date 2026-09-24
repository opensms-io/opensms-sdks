using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
using Opensms.Internal;

namespace Opensms
{
    /// <summary>Contact groups and group sends. Accessed as <c>client.ContactGroups</c>.</summary>
    public sealed class ContactGroupsResource
    {
        private readonly ApiTransport _t;

        internal ContactGroupsResource(ApiTransport transport) => _t = transport;

        /// <summary>List groups (<c>GET /v1/contact-groups</c>).</summary>
        public Task<Page<ContactGroup>> ListAsync(ListParams? parameters = null, CancellationToken ct = default)
            => _t.SendAsync<Page<ContactGroup>>(new ApiRequest(HttpMethod.Get, "/v1/contact-groups") { Query = Wire.Query(parameters).ToString() }, ct);

        /// <summary>Create a group (<c>POST /v1/contact-groups</c>).</summary>
        public Task<ContactGroup> CreateAsync(CreateContactGroupParams parameters, RequestOptions? options = null, CancellationToken ct = default)
            => _t.SendAsync<ContactGroup>(new ApiRequest(HttpMethod.Post, "/v1/contact-groups")
            {
                JsonBody = Check.NotNull(parameters, nameof(parameters)),
                Idempotency = Idempotency.Send,
                IdempotencyKey = options?.IdempotencyKey,
            }, ct);

        /// <summary>Get a group (<c>GET /v1/contact-groups/{id}</c>).</summary>
        public Task<ContactGroup> GetAsync(string id, CancellationToken ct = default)
            => _t.SendAsync<ContactGroup>(new ApiRequest(HttpMethod.Get, "/v1/contact-groups/" + Wire.Seg(id, nameof(id))), ct);

        /// <summary>Rename a group or replace its members (<c>PATCH /v1/contact-groups/{id}</c>).</summary>
        public Task<ContactGroup> UpdateAsync(string id, UpdateContactGroupParams parameters, CancellationToken ct = default)
            => _t.SendAsync<ContactGroup>(new ApiRequest(ApiTransport.PatchMethod, "/v1/contact-groups/" + Wire.Seg(id, nameof(id)))
            {
                JsonBody = Check.NotNull(parameters, nameof(parameters)),
            }, ct);

        /// <summary>Delete a group (<c>DELETE /v1/contact-groups/{id}</c>). Contacts are kept.</summary>
        public Task DeleteAsync(string id, CancellationToken ct = default)
            => _t.SendNoContentAsync(new ApiRequest(HttpMethod.Delete, "/v1/contact-groups/" + Wire.Seg(id, nameof(id))), ct);

        /// <summary>
        /// Send text or a template to every member (<c>POST /v1/contact-groups/{id}/send</c>).
        /// Returns a Batch that is already <c>running</c>.
        /// </summary>
        public Task<Batch> SendAsync(string id, GroupSendParams parameters, RequestOptions? options = null, CancellationToken ct = default)
            => _t.SendAsync<Batch>(new ApiRequest(HttpMethod.Post, "/v1/contact-groups/" + Wire.Seg(id, nameof(id)) + "/send")
            {
                JsonBody = Check.NotNull(parameters, nameof(parameters)),
                Idempotency = Idempotency.Send,
                IdempotencyKey = options?.IdempotencyKey,
            }, ct);
    }
}
