using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
using Opensms.Internal;

namespace Opensms
{
    /// <summary>One-time passcodes. Accessed as <c>client.Otp</c>.</summary>
    public sealed class OtpResource
    {
        private readonly ApiTransport _t;

        internal OtpResource(ApiTransport transport) => _t = transport;

        /// <summary>Generate and send a code (<c>POST /v1/otp/send</c>).</summary>
        public Task<OtpSendResult> SendAsync(SendOtpParams parameters, RequestOptions? options = null, CancellationToken ct = default)
            => _t.SendAsync<OtpSendResult>(new ApiRequest(HttpMethod.Post, "/v1/otp/send")
            {
                JsonBody = Check.NotNull(parameters, nameof(parameters)),
                Idempotency = Idempotency.Send,
                IdempotencyKey = options?.IdempotencyKey,
            }, ct);

        /// <summary>
        /// Check a code (<c>POST /v1/otp/verify</c>). A wrong code returns
        /// <c>Valid == false</c> and uses up an attempt, so this is never retried.
        /// </summary>
        public Task<OtpVerifyResult> VerifyAsync(VerifyOtpParams parameters, CancellationToken ct = default)
            => _t.SendAsync<OtpVerifyResult>(new ApiRequest(HttpMethod.Post, "/v1/otp/verify")
            {
                JsonBody = Check.NotNull(parameters, nameof(parameters)),
            }, ct);
    }
}
