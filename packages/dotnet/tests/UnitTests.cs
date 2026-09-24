using System;
using System.Collections.Generic;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Text.Json;
using System.Threading.Tasks;
using Xunit;

namespace Opensms.Tests
{
    /// <summary>CONFORMANCE.md "Mock-transport unit tests" (offline).</summary>
    public class UnitTests
    {
        private static SendMessageParams Minimal => new SendMessageParams { To = "+254700000012", Text = "hi" };

        // 1. Header injection
        [Fact]
        public async Task T01_headers_are_injected_and_workspace_headers_never_sent()
        {
            var (c, h, _) = Fx.Client(m => m.Then(HttpStatusCode.Created, Fx.MessageJson).Then(HttpStatusCode.OK, Fx.MessageJson));
            await c.Messages.SendAsync(Minimal);
            await c.Messages.GetAsync("11111111-1111-1111-1111-111111111111");

            foreach (var r in h.Requests)
            {
                Assert.Equal("Bearer " + Fx.TestKey, r.Header("Authorization"));
                Assert.Equal("application/json", r.Header("Accept"));
                Assert.Equal("opensms-dotnet/0.1.0", r.Header("User-Agent"));
                Assert.Null(r.Header("X-Workspace-ID"));
                Assert.Null(r.Header("X-Environment"));
            }
            Assert.Equal("application/json", h.Requests[0].ContentType);
            Assert.Null(h.Requests[1].ContentType);
        }

        // 2. Base URL
        [Fact]
        public async Task T02_base_url_default_and_trailing_slash()
        {
            using (var def = new OpensmsClient(Fx.TestKey)) Assert.Equal("https://api.opensms.io", def.BaseUrl);

            var (c, h, _) = Fx.Client(m => m.Then(HttpStatusCode.Created, Fx.MessageJson), baseUrl: "http://host//");
            await c.Messages.SendAsync(Minimal);
            Assert.Equal("http://host/v1/messages", h.Requests[0].Uri.ToString());
        }

        // 3. Key validation
        [Theory]
        [InlineData(null)]
        [InlineData("")]
        [InlineData("pk_test_x")]
        [InlineData("sk_test_short")]
        [InlineData("sk_test_123456789012")]
        public void T03_bad_keys_fail_at_construction(string? key)
            => Assert.Throws<ArgumentException>(() => new OpensmsClient(key!));

        [Fact]
        public void T03_good_keys_set_environment()
        {
            Assert.Equal("live", new OpensmsClient(Fx.LiveKey).Environment);
            Assert.Equal("sandbox", new OpensmsClient(Fx.TestKey).Environment);
            Assert.Equal("sandbox", new OpensmsClient("sk_test_1234567890123").Environment); // 13 chars after the prefix
        }

        // 4. Body mapping
        [Fact]
        public async Task T04_send_body_uses_snake_case_and_omits_unset()
        {
            var (c, h, _) = Fx.Client(m => m.Then(HttpStatusCode.Created, Fx.MessageJson).Then(HttpStatusCode.Created, Fx.MessageJson));
            await c.Messages.SendAsync(new SendMessageParams
            {
                To = "+254700000012",
                Text = "hello",
                SenderId = "ACME",
                TrafficType = "marketing",
                ScheduledAt = new DateTimeOffset(2026, 9, 24, 13, 0, 0, TimeSpan.FromHours(3)),
                CallbackUrl = "https://example.com/cb",
                Metadata = new Dictionary<string, object?> { ["order"] = 42 },
            });
            using (var doc = JsonDocument.Parse(h.Requests[0].Body))
            {
                var keys = doc.RootElement.EnumerateObject().Select(p => p.Name).OrderBy(k => k).ToArray();
                Assert.Equal(new[] { "callback_url", "metadata", "scheduled_at", "sender_id", "text", "to", "traffic_type" }, keys);
                Assert.Equal("2026-09-24T10:00:00Z", doc.RootElement.GetProperty("scheduled_at").GetString());
                Assert.Equal(42, doc.RootElement.GetProperty("metadata").GetProperty("order").GetInt32());
            }

            await c.Messages.SendAsync(Minimal);
            using (var doc = JsonDocument.Parse(h.Requests[1].Body))
            {
                var keys = doc.RootElement.EnumerateObject().Select(p => p.Name).OrderBy(k => k).ToArray();
                Assert.Equal(new[] { "text", "to" }, keys);
            }
            Assert.DoesNotContain("null", h.Requests[1].Body);
        }

        [Fact]
        public async Task T04_scheduled_at_accepts_a_string_verbatim()
        {
            var (c, h, _) = Fx.Client(m => m.Then(HttpStatusCode.Created, Fx.MessageJson));
            await c.Messages.SendAsync(new SendMessageParams { To = "+254700000012", Text = "x", ScheduledAt = "2026-09-24T12:00:00+03:00" });
            Assert.Contains("\"scheduled_at\":\"2026-09-24T12:00:00+03:00\"", h.Requests[0].Body);
            Assert.Contains("\"to\":\"+254700000012\"", h.Requests[0].Body);
        }

        // 5. Idempotency-Key auto
        [Fact]
        public async Task T05_idempotency_key_generated_or_passed_through()
        {
            var (c, h, _) = Fx.Client(m => m.Then(HttpStatusCode.Created, Fx.MessageJson).Then(HttpStatusCode.Created, Fx.MessageJson).Then(HttpStatusCode.OK, Fx.MessageJson));
            await c.Messages.SendAsync(Minimal);
            await c.Messages.SendAsync(Minimal, new RequestOptions { IdempotencyKey = "my-key-1" });
            await c.Messages.GetAsync("x");

            var auto = h.Requests[0].Header("Idempotency-Key");
            Assert.NotNull(auto);
            Assert.Equal(36, auto!.Length);
            Assert.True(Guid.TryParse(auto, out _));
            Assert.Equal("my-key-1", h.Requests[1].Header("Idempotency-Key"));
            Assert.Null(h.Requests[2].Header("Idempotency-Key"));
        }

        // 6. Retry on 429 with Retry-After
        [Fact]
        public async Task T06_retry_429_honours_retry_after_and_reuses_key()
        {
            var (c, h, sleeps) = Fx.Client(m => m
                .Then(HttpStatusCode.TooManyRequests, "{\"type\":\"about:blank\",\"title\":\"Too Many Requests\",\"status\":429,\"detail\":\"rate limited\"}", "application/problem+json", ("Retry-After", "2"))
                .Then(HttpStatusCode.Created, Fx.MessageJson));
            var msg = await c.Messages.SendAsync(Minimal);

            Assert.Equal("11111111-1111-1111-1111-111111111111", msg.Id);
            Assert.Equal(2, h.Requests.Count);
            Assert.Equal(new[] { TimeSpan.FromSeconds(2) }, sleeps);
            Assert.Equal(h.Requests[0].Header("Idempotency-Key"), h.Requests[1].Header("Idempotency-Key"));
            Assert.Equal(h.Requests[0].Body, h.Requests[1].Body);
        }

        // 7. Retry on 503 without Retry-After
        [Fact]
        public async Task T07_retry_503_with_jittered_backoff()
        {
            var (c, h, sleeps) = Fx.Client(m => m.Then(HttpStatusCode.ServiceUnavailable, "{}").Then(HttpStatusCode.OK, Fx.MessageJson));
            await c.Messages.GetAsync("x");
            Assert.Equal(2, h.Requests.Count);
            Assert.Single(sleeps);
            Assert.InRange(sleeps[0], TimeSpan.Zero, TimeSpan.FromSeconds(0.5));
        }

        // 8. Retries exhausted
        [Fact]
        public async Task T08_retries_exhausted_raise_last_status()
        {
            var (c, h, _) = Fx.Client(m => m.Then(HttpStatusCode.InternalServerError, "{\"title\":\"Internal Server Error\",\"status\":500,\"detail\":\"database unavailable\"}", "application/problem+json"), maxRetries: 2);
            var ex = await Assert.ThrowsAsync<OpensmsException>(() => c.Messages.GetAsync("x"));
            Assert.Equal(500, ex.Status);
            Assert.Equal("database unavailable", ex.Message);
            Assert.Equal(3, h.Requests.Count);
        }

        [Fact]
        public async Task T08_max_retries_zero_disables_retries()
        {
            var (c, h, _) = Fx.Client(m => m.Then(HttpStatusCode.InternalServerError, "{}"), maxRetries: 0);
            await Assert.ThrowsAsync<OpensmsException>(() => c.Messages.GetAsync("x"));
            Assert.Single(h.Requests);
        }

        // 9. Retry-After too large
        [Fact]
        public async Task T09_retry_after_over_60s_is_not_retried()
        {
            var (c, h, sleeps) = Fx.Client(m => m.Then(HttpStatusCode.TooManyRequests, "{\"status\":429,\"title\":\"Too Many Requests\"}", "application/problem+json", ("Retry-After", "120")));
            var ex = await Assert.ThrowsAsync<OpensmsException>(() => c.Messages.GetAsync("x"));
            Assert.Equal(429, ex.Status);
            Assert.Equal(120, ex.RetryAfter);
            Assert.Single(h.Requests);
            Assert.Empty(sleeps);
        }

        // 10. No retry on 4xx
        [Theory]
        [InlineData(400)]
        [InlineData(401)]
        [InlineData(402)]
        [InlineData(403)]
        [InlineData(404)]
        [InlineData(409)]
        [InlineData(422)]
        public async Task T10_client_errors_are_not_retried(int status)
        {
            var (c, h, _) = Fx.Client(m => m.Then((HttpStatusCode)status, "{\"status\":" + status + ",\"title\":\"x\",\"detail\":\"d\"}", "application/problem+json"));
            var ex = await Assert.ThrowsAsync<OpensmsException>(() => c.Messages.SendAsync(Minimal));
            Assert.Equal(status, ex.Status);
            Assert.Single(h.Requests);
        }

        // 11. No retry for non-idempotent POST
        [Fact]
        public async Task T11_otp_verify_and_cancel_are_not_retried()
        {
            var (c, h, _) = Fx.Client(m => m.Then(HttpStatusCode.ServiceUnavailable, "{}"));
            var e1 = await Assert.ThrowsAsync<OpensmsException>(() => c.Otp.VerifyAsync(new VerifyOtpParams { OtpId = "o", Code = "123456" }));
            Assert.Equal(503, e1.Status);
            Assert.Single(h.Requests);
            Assert.Null(h.Requests[0].Header("Idempotency-Key"));

            await Assert.ThrowsAsync<OpensmsException>(() => c.Messages.CancelAsync("m1"));
            Assert.Equal(2, h.Requests.Count);
        }

        [Fact]
        public async Task T11_other_non_idempotent_posts_are_not_retried()
        {
            var (c, h, _) = Fx.Client(m => m.Then(HttpStatusCode.BadGateway, "{}"));
            await Assert.ThrowsAsync<OpensmsException>(() => c.SenderIds.CreateAsync(new CreateSenderIdParams { Value = "ACME", Kind = "alphanumeric", Countries = new[] { "KE" }, Documents = new string[0] }));
            await Assert.ThrowsAsync<OpensmsException>(() => c.SenderIds.CreateDraftAsync(new CreateSenderIdDraftParams()));
            await Assert.ThrowsAsync<OpensmsException>(() => c.Suppressions.CreateAsync(new SuppressionParams { E164 = "+254700000099", Reason = "manual" }));
            await Assert.ThrowsAsync<OpensmsException>(() => c.Suppressions.ImportAsync(new[] { new SuppressionParams { E164 = "+254700000099", Reason = "manual" } }));
            Assert.Equal(4, h.Requests.Count);
        }

        // 12. Network error
        [Fact]
        public async Task T12_network_errors_retry_then_succeed()
        {
            var (c, h, sleeps) = Fx.Client(m => m
                .Throw(new HttpRequestException("connection refused"))
                .Throw(new HttpRequestException("connection reset"))
                .Then(HttpStatusCode.OK, Fx.MessageJson));
            var msg = await c.Messages.GetAsync("x");
            Assert.Equal("queued", msg.Status);
            Assert.Equal(3, h.Requests.Count);
            Assert.Equal(2, sleeps.Count);
        }

        [Fact]
        public async Task T12_persistent_network_error_is_status_zero()
        {
            var (c, h, _) = Fx.Client(m => m.Throw(new HttpRequestException("connection refused")));
            var ex = await Assert.ThrowsAsync<OpensmsException>(() => c.Messages.GetAsync("x"));
            Assert.Equal(0, ex.Status);
            Assert.IsType<HttpRequestException>(ex.InnerException);
            Assert.Equal(3, h.Requests.Count);
        }

        [Fact]
        public async Task T12_timeout_is_status_zero()
        {
            var c = new OpensmsClient(Fx.TestKey, new OpensmsClientOptions
            {
                BaseUrl = "http://mock.test",
                HttpMessageHandler = new DelayHandler(TimeSpan.FromSeconds(5)),
                Timeout = TimeSpan.FromMilliseconds(100),
                MaxRetries = 0,
            });
            var ex = await Assert.ThrowsAsync<OpensmsException>(() => c.Messages.GetAsync("x"));
            Assert.Equal(0, ex.Status);
            Assert.Contains("timed out", ex.Message);
        }

        private sealed class DelayHandler : HttpMessageHandler
        {
            private readonly TimeSpan _delay;
            public DelayHandler(TimeSpan delay) => _delay = delay;
            protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, System.Threading.CancellationToken ct)
            {
                await Task.Delay(_delay, ct);
                return MockHandler.Response(HttpStatusCode.OK, Fx.MessageJson);
            }
        }

        // 13. Error mapping
        [Fact]
        public async Task T13_problem_json_is_mapped()
        {
            const string body = "{\"type\":\"https://api.opensms.io/problems/invalid_message_id\",\"title\":\"Bad Request\",\"status\":400,\"detail\":\"Message ID must be a valid UUID.\",\"code\":\"invalid_message_id\",\"trace_id\":\"t1\",\"errors\":{\"to\":[\"bad\"]}}";
            var (c, _, _) = Fx.Client(m => m.Then(HttpStatusCode.BadRequest, body, "application/problem+json"));
            var ex = await Assert.ThrowsAsync<OpensmsException>(() => c.Messages.GetAsync("nope"));
            Assert.Equal(400, ex.Status);
            Assert.Equal("https://api.opensms.io/problems/invalid_message_id", ex.Type);
            Assert.Equal("Bad Request", ex.Title);
            Assert.Equal("Message ID must be a valid UUID.", ex.Detail);
            Assert.Equal("invalid_message_id", ex.Code);
            Assert.Equal("t1", ex.TraceId);
            Assert.Equal(new[] { "bad" }, ex.Errors!["to"]);
            Assert.Equal(ex.Detail, ex.Message);
            Assert.Equal(body, ex.Body);
        }

        [Fact]
        public async Task T13_about_blank_has_null_code_and_request_id_is_read()
        {
            var (c, _, _) = Fx.Client(m => m
                .Then(HttpStatusCode.BadRequest, Fx.Problem400, "application/problem+json")
                .Then((HttpStatusCode)422, "{\"type\":\"about:blank\",\"title\":\"Unprocessable Entity\",\"status\":422,\"detail\":\"destination is suppressed\"}", "application/problem+json", ("X-Request-ID", "r1")));
            var e1 = await Assert.ThrowsAsync<OpensmsException>(() => c.Messages.SendAsync(Minimal));
            Assert.Null(e1.Code);
            Assert.Equal("about:blank", e1.Type);
            var e2 = await Assert.ThrowsAsync<OpensmsException>(() => c.Messages.SendAsync(Minimal));
            Assert.Equal("r1", e2.RequestId);
            Assert.Equal("destination is suppressed", e2.Message);
        }

        [Fact]
        public async Task T13_html_body_is_kept_raw()
        {
            var (c, _, _) = Fx.Client(m => m.Then(HttpStatusCode.BadGateway, "<html><body>Bad gateway</body></html>", "text/html"), maxRetries: 0);
            var ex = await Assert.ThrowsAsync<OpensmsException>(() => c.Messages.GetAsync("x"));
            Assert.Equal(502, ex.Status);
            Assert.Null(ex.Detail);
            Assert.Null(ex.Title);
            Assert.Equal("<html><body>Bad gateway</body></html>", ex.Body);
            Assert.Equal("OpenSMS request failed with status 502", ex.Message);
        }

        // 14. 204 handling
        [Fact]
        public async Task T14_delete_204_returns_without_parsing()
        {
            var (c, h, _) = Fx.Client(m => m.Then(HttpStatusCode.NoContent));
            await c.Contacts.DeleteAsync("c1");
            Assert.Equal(HttpMethod.Delete, h.Requests[0].Method);
            Assert.Equal("/v1/contacts/c1", h.Requests[0].Uri.AbsolutePath);
        }

        // 15. Pagination
        [Fact]
        public async Task T15_paginate_follows_next_cursor()
        {
            var (c, h, _) = Fx.Client(m => m
                .Then(HttpStatusCode.OK, "{\"items\":[{\"id\":\"a\"},{\"id\":\"b\"}],\"next_cursor\":\"c1\"}")
                .Then(HttpStatusCode.OK, "{\"items\":[{\"id\":\"c\"}],\"next_cursor\":null}"));
            var p = new MessageListParams { Limit = 2 };
            var ids = new List<string>();
            await foreach (var m in c.PaginateAsync(c.Messages.ListAsync, p)) ids.Add(m.Id);

            Assert.Equal(new[] { "a", "b", "c" }, ids);
            Assert.Equal(2, h.Requests.Count);
            Assert.Equal("?limit=2", h.Requests[0].Uri.Query);
            Assert.Equal("?limit=2&cursor=c1", h.Requests[1].Uri.Query);
            Assert.Null(p.Cursor); // caller's params are not mutated
        }

        [Fact]
        public async Task T15_paginate_works_for_sub_resource_lists()
        {
            var (c, h, _) = Fx.Client(m => m
                .Then(HttpStatusCode.OK, "{\"items\":[{\"id\":\"a\",\"to\":\"+254700000012\"}],\"next_cursor\":\"n\"}")
                .Then(HttpStatusCode.OK, "{\"items\":[{\"id\":\"b\"}],\"next_cursor\":null}"));
            var ids = new List<string>();
            await foreach (var m in c.PaginateAsync<BatchItemListParams, Message>((p, ct) => c.Batches.ListItemsAsync("b1", p, ct), new BatchItemListParams { Status = "sent" }))
                ids.Add(m.Id);
            Assert.Equal(new[] { "a", "b" }, ids);
            Assert.Equal("?cursor=n&status=sent", h.Requests[1].Uri.Query);
        }

        // 16. Query encoding
        [Fact]
        public async Task T16_query_encoding()
        {
            var (c, h, _) = Fx.Client(m => m
                .Then(HttpStatusCode.OK, "{\"quote_id\":\"sq_1\",\"entries\":[],\"totals\":[]}")
                .Then(HttpStatusCode.OK, "{\"items\":[],\"next_cursor\":null}")
                .Then(HttpStatusCode.OK, "{\"items\":[],\"next_cursor\":null}"));
            await c.SenderIds.QuoteAsync(new SenderIdQuoteParams { Countries = new[] { "KE", "NG" } });
            await c.Messages.ListAsync(new MessageListParams { Status = "delivered", To = "+2547" });
            await c.Messages.ListAsync();

            Assert.Equal("/v1/sender-ids/quote?countries=KE%2CNG", h.Requests[0].RawUri.Substring("http://mock.test".Length));
            Assert.Equal("KE,NG", Uri.UnescapeDataString(h.Requests[0].Uri.Query.Substring("?countries=".Length)));
            Assert.Equal("?status=delivered&to=%2B2547", h.Requests[1].Uri.Query);
            Assert.Equal("", h.Requests[2].Uri.Query);
        }

        // 17. Path escaping
        [Fact]
        public async Task T17_path_segments_are_escaped()
        {
            var (c, h, _) = Fx.Client(m => m.Then(HttpStatusCode.OK, Fx.MessageJson));
            await c.Messages.GetAsync("a/b");
            Assert.Equal("/v1/messages/a%2Fb", h.Requests[0].Uri.AbsolutePath);
            Assert.EndsWith("/v1/messages/a%2Fb", h.Requests[0].RawUri);
        }

        [Fact]
        public async Task T17_empty_ids_fail_locally()
        {
            var (c, h, _) = Fx.Client(m => m.Then(HttpStatusCode.OK, Fx.MessageJson));
            await Assert.ThrowsAsync<ArgumentException>(() => c.Messages.GetAsync(""));
            await Assert.ThrowsAsync<ArgumentException>(() => c.Webhooks.DeleteAsync(" "));
            Assert.Empty(h.Requests);
        }

        // 19. Batch CSV
        [Fact]
        public async Task T19_batch_csv_is_posted_as_text_csv_with_key()
        {
            const string csv = "to,text\n+254700000014,csv run\n";
            var (c, h, _) = Fx.Client(m => m.Then(HttpStatusCode.Accepted, "{\"id\":\"b1\",\"status\":\"ready\",\"total\":1,\"invalid\":0}"));
            var batch = await c.Batches.CreateFromCsvAsync(csv);
            Assert.Equal("ready", batch.Status);
            Assert.Equal("text/csv", h.Requests[0].ContentType);
            Assert.Equal(csv, h.Requests[0].Body);
            Assert.Equal(36, h.Requests[0].Header("Idempotency-Key")!.Length);
            Assert.Equal("/v1/messages/batch", h.Requests[0].Uri.AbsolutePath);
        }

        [Fact]
        public async Task T19_batch_csv_without_dedupe_uses_multipart()
        {
            var (c, h, _) = Fx.Client(m => m.Then(HttpStatusCode.Accepted, "{\"id\":\"b1\",\"status\":\"ready\"}"));
            await c.Batches.CreateFromCsvAsync("to,text\n+254700000014,a\n", dedupe: false);
            Assert.StartsWith("multipart/form-data", h.Requests[0].ContentType);
            Assert.Contains("name=dedupe", h.Requests[0].Body);
            Assert.Contains("false", h.Requests[0].Body);
        }

        // 20. Decimal strings, unknown fields, timestamps
        [Fact]
        public async Task T20_decimals_stay_strings_and_unknown_fields_are_ignored()
        {
            var (c, _, _) = Fx.Client(m => m
                .Then(HttpStatusCode.OK, Fx.MessageJson)
                .Then(HttpStatusCode.OK, "{\"id\":\"b\",\"status\":\"ready\",\"estimated_cost\":12.5}"));
            var msg = await c.Messages.GetAsync("x");
            Assert.Equal("0.000000", msg.Price);
            Assert.Equal(new DateTimeOffset(2026, 9, 24, 5, 25, 59, TimeSpan.Zero).AddTicks(3962410), msg.CreatedAt);
            var batch = await c.Batches.GetAsync("b");
            Assert.Equal("12.5", batch.EstimatedCost);
        }

        // Extra: other body/verb mappings the surface depends on
        [Fact]
        public async Task Webhook_update_is_a_full_put_with_idempotency_key()
        {
            var (c, h, _) = Fx.Client(m => m.Then(HttpStatusCode.OK, "{\"id\":\"w1\",\"enabled\":false}"));
            await c.Webhooks.UpdateAsync("w1", new UpdateWebhookParams { Url = "https://e.com/h", Events = new[] { "message.sent" }, Enabled = false });
            Assert.Equal(HttpMethod.Put, h.Requests[0].Method);
            Assert.Equal("{\"url\":\"https://e.com/h\",\"events\":[\"message.sent\"],\"enabled\":false}", h.Requests[0].Body);
            Assert.NotNull(h.Requests[0].Header("Idempotency-Key"));
        }

        [Fact]
        public async Task Wallet_unwraps_data_envelopes_and_ledger_pages_with_before()
        {
            var (c, h, _) = Fx.Client(m => m
                .Then(HttpStatusCode.OK, "{\"data\":[{\"id\":\"w\",\"currency\":\"KES\",\"balance\":\"10000.000000\",\"environment\":\"sandbox\"}]}")
                .Then(HttpStatusCode.OK, "{\"data\":[{\"id\":193,\"amount\":\"1.000000\"}]}"));
            var bal = await c.Wallet.BalancesAsync();
            Assert.Equal("10000.000000", bal[0].Balance);
            var ledger = await c.Wallet.LedgerAsync(new LedgerParams { Limit = 1, Before = 200 });
            Assert.Equal(193, ledger[0].Id);
            Assert.Equal("?limit=1&before=200", h.Requests[1].Uri.Query);
        }

        [Fact]
        public async Task Otp_verify_maps_fields()
        {
            var (c, h, _) = Fx.Client(m => m.Then(HttpStatusCode.OK, "{\"valid\":false,\"attempts_left\":4}"));
            var r = await c.Otp.VerifyAsync(new VerifyOtpParams { OtpId = "o1", Code = "000000" });
            Assert.False(r.Valid);
            Assert.Equal(4, r.AttemptsLeft);
            Assert.Equal("{\"otp_id\":\"o1\",\"code\":\"000000\"}", h.Requests[0].Body);
        }

        [Fact]
        public async Task Caller_cancellation_is_not_wrapped_or_retried()
        {
            var (c, h, _) = Fx.Client(m => m.Then(HttpStatusCode.OK, Fx.MessageJson));
            using var cts = new System.Threading.CancellationTokenSource();
            cts.Cancel();
            await Assert.ThrowsAnyAsync<OperationCanceledException>(() => c.Messages.GetAsync("x", cts.Token));
        }
    }
}
