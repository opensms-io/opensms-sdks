using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Opensms.Internal;

namespace Opensms
{
    /// <summary>Create, inspect, start and stop bulk sends. Accessed as <c>client.Batches</c>.</summary>
    public sealed class BatchesResource
    {
        private readonly ApiTransport _t;

        internal BatchesResource(ApiTransport transport) => _t = transport;

        /// <summary>Create a batch from JSON rows (<c>POST /v1/messages/batch</c>). The batch is <c>ready</c> and sends nothing until started.</summary>
        public Task<Batch> CreateAsync(CreateBatchParams parameters, RequestOptions? options = null, CancellationToken ct = default)
            => _t.SendAsync<Batch>(new ApiRequest(HttpMethod.Post, "/v1/messages/batch")
            {
                JsonBody = Check.NotNull(parameters, nameof(parameters)),
                Idempotency = Idempotency.Send,
                IdempotencyKey = options?.IdempotencyKey,
            }, ct);

        /// <summary>
        /// Create a batch from CSV text with a header row (<c>to,text[,sender_id,...]</c>),
        /// posted as <c>text/csv</c>. The API only honours <paramref name="dedupe"/>
        /// on multipart uploads, so <c>dedupe: false</c> is sent as
        /// <c>multipart/form-data</c> (file field plus <c>dedupe=false</c>).
        /// </summary>
        public Task<Batch> CreateFromCsvAsync(string csv, bool? dedupe = null, RequestOptions? options = null, CancellationToken ct = default)
        {
            var bytes = Encoding.UTF8.GetBytes(Check.NotNull(csv, nameof(csv)));
            return _t.SendAsync<Batch>(new ApiRequest(HttpMethod.Post, "/v1/messages/batch")
            {
                Content = dedupe == false
                    ? () =>
                    {
                        var form = new MultipartFormDataContent();
                        var file = new ByteArrayContent(bytes);
                        file.Headers.ContentType = new MediaTypeHeaderValue("text/csv");
                        form.Add(file, "file", "batch.csv");
                        form.Add(new StringContent("false"), "dedupe");
                        return form;
                    }
                    : () =>
                    {
                        var content = new ByteArrayContent(bytes);
                        content.Headers.ContentType = new MediaTypeHeaderValue("text/csv");
                        return content;
                    },
                Idempotency = Idempotency.Send,
                IdempotencyKey = options?.IdempotencyKey,
            }, ct);
        }

        /// <summary>Get a batch with its counters (<c>GET /v1/batches/{id}</c>).</summary>
        public Task<Batch> GetAsync(string id, CancellationToken ct = default)
            => _t.SendAsync<Batch>(new ApiRequest(HttpMethod.Get, "/v1/batches/" + Wire.Seg(id, nameof(id))), ct);

        /// <summary>Per-row validation report (<c>GET /v1/batches/{id}/validation</c>).</summary>
        public Task<BatchValidationReport> ValidationAsync(string id, CancellationToken ct = default)
            => _t.SendAsync<BatchValidationReport>(new ApiRequest(HttpMethod.Get, "/v1/batches/" + Wire.Seg(id, nameof(id)) + "/validation"), ct);

        /// <summary>Start sending a <c>ready</c> batch (<c>POST /v1/batches/{id}/start</c>).</summary>
        public Task<Batch> StartAsync(string id, RequestOptions? options = null, CancellationToken ct = default)
            => _t.SendAsync<Batch>(new ApiRequest(HttpMethod.Post, "/v1/batches/" + Wire.Seg(id, nameof(id)) + "/start")
            {
                Idempotency = Idempotency.Send,
                IdempotencyKey = options?.IdempotencyKey,
            }, ct);

        /// <summary>Stop a batch and cancel its unsent items (<c>POST /v1/batches/{id}/stop</c>).</summary>
        public Task<BatchStopResult> StopAsync(string id, RequestOptions? options = null, CancellationToken ct = default)
            => _t.SendAsync<BatchStopResult>(new ApiRequest(HttpMethod.Post, "/v1/batches/" + Wire.Seg(id, nameof(id)) + "/stop")
            {
                Idempotency = Idempotency.Send,
                IdempotencyKey = options?.IdempotencyKey,
            }, ct);

        /// <summary>List the messages in a batch (<c>GET /v1/batches/{id}/items</c>). Items carry a subset of <see cref="Message"/> fields.</summary>
        public Task<Page<Message>> ListItemsAsync(string id, BatchItemListParams? parameters = null, CancellationToken ct = default)
            => _t.SendAsync<Page<Message>>(new ApiRequest(HttpMethod.Get, "/v1/batches/" + Wire.Seg(id, nameof(id)) + "/items")
            {
                Query = Wire.Query(parameters).Add("status", parameters?.Status).ToString(),
            }, ct);
    }
}
