using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
using Opensms.Internal;

namespace Opensms
{
    /// <summary>Address-book contacts. Accessed as <c>client.Contacts</c>.</summary>
    public sealed class ContactsResource
    {
        private readonly ApiTransport _t;

        internal ContactsResource(ApiTransport transport) => _t = transport;

        /// <summary>List contacts (<c>GET /v1/contacts</c>).</summary>
        public Task<Page<Contact>> ListAsync(ListParams? parameters = null, CancellationToken ct = default)
            => _t.SendAsync<Page<Contact>>(new ApiRequest(HttpMethod.Get, "/v1/contacts") { Query = Wire.Query(parameters).ToString() }, ct);

        /// <summary>Create a contact (<c>POST /v1/contacts</c>). 409 when the number already exists.</summary>
        public Task<Contact> CreateAsync(CreateContactParams parameters, RequestOptions? options = null, CancellationToken ct = default)
            => _t.SendAsync<Contact>(new ApiRequest(HttpMethod.Post, "/v1/contacts")
            {
                JsonBody = Check.NotNull(parameters, nameof(parameters)),
                Idempotency = Idempotency.Send,
                IdempotencyKey = options?.IdempotencyKey,
            }, ct);

        /// <summary>Get a contact (<c>GET /v1/contacts/{id}</c>).</summary>
        public Task<Contact> GetAsync(string id, CancellationToken ct = default)
            => _t.SendAsync<Contact>(new ApiRequest(HttpMethod.Get, "/v1/contacts/" + Wire.Seg(id, nameof(id))), ct);

        /// <summary>Update a contact; unset fields are kept (<c>PATCH /v1/contacts/{id}</c>).</summary>
        public Task<Contact> UpdateAsync(string id, UpdateContactParams parameters, CancellationToken ct = default)
            => _t.SendAsync<Contact>(new ApiRequest(ApiTransport.PatchMethod, "/v1/contacts/" + Wire.Seg(id, nameof(id)))
            {
                JsonBody = Check.NotNull(parameters, nameof(parameters)),
            }, ct);

        /// <summary>Delete a contact (<c>DELETE /v1/contacts/{id}</c>).</summary>
        public Task DeleteAsync(string id, CancellationToken ct = default)
            => _t.SendNoContentAsync(new ApiRequest(HttpMethod.Delete, "/v1/contacts/" + Wire.Seg(id, nameof(id))), ct);
    }
}
