using System;
using System.Collections.Generic;
using System.Linq;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using Xunit;

namespace Opensms.Tests
{
    /// <summary>A [Fact] that is skipped (not failed) unless OPENSMS_BASE_URL and OPENSMS_API_KEY are set.</summary>
    public sealed class LiveFactAttribute : FactAttribute
    {
        public LiveFactAttribute()
        {
            if (string.IsNullOrEmpty(Environment.GetEnvironmentVariable("OPENSMS_BASE_URL")) ||
                string.IsNullOrEmpty(Environment.GetEnvironmentVariable("OPENSMS_API_KEY")))
                Skip = "OPENSMS_BASE_URL and OPENSMS_API_KEY are not set; live conformance skipped.";
        }
    }

    /// <summary>Counts HTTP attempts on top of the real network handler.</summary>
    internal sealed class CountingHandler : DelegatingHandler
    {
        public int Count;
        public CountingHandler() : base(new SocketsHttpHandler()) { }
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            Interlocked.Increment(ref Count);
            return base.SendAsync(request, ct);
        }
    }

    /// <summary>
    /// CONFORMANCE.md "Live scenario", steps 1 to 29, against the stack named by
    /// OPENSMS_BASE_URL with the sandbox key in OPENSMS_API_KEY. Methods in one
    /// xUnit class run sequentially (not necessarily in file order), so each test
    /// creates the data it needs and keeps the scenario order within itself.
    /// </summary>
    public class LiveConformanceTests
    {
        private const string Phone = "+254700000012";
        private const string ZeroId = "00000000-0000-0000-0000-000000000000";
        private static readonly TimeSpan Deadline = TimeSpan.FromSeconds(45);

        private static readonly string Run = Convert.ToHexString(RandomNumberGenerator.GetBytes(4)).ToLowerInvariant();
        private static string BaseUrl => Environment.GetEnvironmentVariable("OPENSMS_BASE_URL")!;
        private static string ApiKey => Environment.GetEnvironmentVariable("OPENSMS_API_KEY")!;

        private static OpensmsClient NewClient(string? key = null, HttpMessageHandler? handler = null)
            => new OpensmsClient(key ?? ApiKey, new OpensmsClientOptions
            {
                BaseUrl = BaseUrl,
                Timeout = TimeSpan.FromSeconds(60),
                HttpMessageHandler = handler,
            });

        // Real sends go to a fresh +25470xxxxxxx (Safaricom, KE) number per call: the API
        // enforces 5 sends per destination per hour and 20 per day, and every SDK run
        // shares the same workspace, so the fixed +254700000012 is exhausted quickly.
        private static string RandomPhone()
            => "+25470" + string.Concat(Enumerable.Range(0, 7).Select(_ => RandomNumberGenerator.GetInt32(10).ToString()));

        private static async Task<OpensmsException> Err(Func<Task> call, int status, string detail)
        {
            var ex = await Assert.ThrowsAsync<OpensmsException>(call);
            Assert.Equal(status, ex.Status);
            Assert.Equal(detail, ex.Detail);
            return ex;
        }

        private static async Task<T> Poll<T>(Func<Task<T>> fetch, Func<T, bool> done, string what)
        {
            var until = DateTime.UtcNow + Deadline;
            while (true)
            {
                var value = await fetch();
                if (done(value)) return value;
                if (DateTime.UtcNow > until) throw new TimeoutException($"timed out waiting for {what}");
                await Task.Delay(500);
            }
        }

        [LiveFact]
        public async Task Step01_02_constructor_and_auth_errors()
        {
            Assert.Throws<ArgumentException>(() => new OpensmsClient("not_a_key"));
            Assert.Throws<ArgumentException>(() => new OpensmsClient("sk_test_short"));

            var counter = new CountingHandler();
            using var bad = NewClient("sk_test_" + new string('A', 32), counter);
            var ex = await Err(() => bad.Messages.ListAsync(new MessageListParams { Limit = 1 }), 401, "missing or invalid API key");
            Assert.Equal("about:blank", ex.Type);
            Assert.Equal("Unauthorized", ex.Title);
            Assert.Null(ex.Code);
            Assert.Equal(1, counter.Count);
        }

        [LiveFact]
        public async Task Step03_11_messages()
        {
            using var c = NewClient();

            // 3. send
            var text = $"conformance dotnet {Run}";
            var dest = RandomPhone();
            var m = await c.Messages.SendAsync(new SendMessageParams
            {
                To = dest,
                Text = text,
                Metadata = new Dictionary<string, object?> { ["sdk"] = "dotnet", ["run"] = Run },
            });
            Assert.True(Guid.TryParse(m.Id, out _));
            Assert.Equal(dest, m.To);
            Assert.Equal("OPENSMS", m.SenderId);
            Assert.Equal("transactional", m.TrafficType);
            Assert.Contains(m.Status, new[] { "queued", "sending", "sent", "delivered" });
            Assert.Equal(1, m.Parts);
            Assert.Equal("gsm7", m.Encoding);
            Assert.Equal("KE", m.CountryIso2);
            Assert.Equal("KES", m.Currency);
            Assert.Equal("0.000000", m.Price);
            Assert.Equal(Run, m.Metadata!["run"].GetString());

            // 4. idempotent replay
            var key = Guid.NewGuid().ToString();
            var idemTo = RandomPhone();
            var p = new SendMessageParams { To = idemTo, Text = $"idem {Run}" };
            var r1 = await c.Messages.SendAsync(p, new RequestOptions { IdempotencyKey = key });
            var r2 = await c.Messages.SendAsync(p, new RequestOptions { IdempotencyKey = key });
            Assert.Equal(r1.Id, r2.Id);
            await Err(() => c.Messages.SendAsync(new SendMessageParams { To = idemTo, Text = $"idem changed {Run}" }, new RequestOptions { IdempotencyKey = key }),
                409, "Idempotency-Key was already used with a different request");

            // 5. get and wait
            var delivered = await Poll(() => c.Messages.GetAsync(m.Id), x => x.Status == "delivered", "message delivered");
            Assert.NotNull(delivered.DeliveredAt);
            Assert.NotNull(delivered.SentAt);
            Assert.Equal(text, delivered.Text);

            // 6. list + cursor
            var page1 = await c.Messages.ListAsync(new MessageListParams { Limit = 1 });
            Assert.Single(page1.Items);
            Assert.NotNull(page1.NextCursor);
            var page2 = await c.Messages.ListAsync(new MessageListParams { Limit = 1, Cursor = page1.NextCursor });
            Assert.Single(page2.Items);
            Assert.NotEqual(page1.Items[0].Id, page2.Items[0].Id);
            await Err(() => c.Messages.ListAsync(new MessageListParams { Limit = 1, Cursor = "garbage" }), 400, "invalid cursor");
            await Err(() => c.Messages.ListAsync(new MessageListParams { Status = "bogus" }), 400, "invalid status");
            var seen = 0;
            await foreach (var _ in c.PaginateAsync(c.Messages.ListAsync, new MessageListParams { Limit = 2 }))
                if (++seen == 3) break;
            Assert.Equal(3, seen);

            // 7. attempts
            var attempts = await c.Messages.AttemptsAsync(m.Id);
            Assert.NotEmpty(attempts);
            Assert.Equal(1, attempts[0].Sequence);
            Assert.StartsWith("Mock provider (sandbox)", attempts[0].RouteName);
            Assert.Equal("delivered", attempts[0].Status);
            Assert.Equal("0.000000", attempts[0].Price);

            // 8. validation error
            var v = await Err(() => c.Messages.SendAsync(new SendMessageParams { To = "12345", Text = "x" }), 400, "to must be an E.164 phone number");
            Assert.Equal("Bad Request", v.Title);
            Assert.Equal("about:blank", v.Type);

            // 9. coded error
            var coded = await Err(() => c.Messages.GetAsync("not-a-uuid"), 400, "Message ID must be a valid UUID.");
            Assert.Equal("invalid_message_id", coded.Code);
            Assert.Equal("https://api.opensms.io/problems/invalid_message_id", coded.Type);

            // 10. not found
            await Err(() => c.Messages.GetAsync(ZeroId), 404, "message not found");

            // 11. schedule and cancel
            var scheduled = await c.Messages.SendAsync(new SendMessageParams { To = RandomPhone(), Text = $"scheduled {Run}", ScheduledAt = DateTimeOffset.UtcNow.AddHours(2) });
            Assert.Equal("scheduled", scheduled.Status);
            var cancelled = await c.Messages.CancelAsync(scheduled.Id);
            Assert.Equal("cancelled", cancelled.Status);
            Assert.NotNull(cancelled.CancelledAt);
            await Err(() => c.Messages.CancelAsync(scheduled.Id), 409, "message cannot be cancelled in its current state");
            await Err(() => c.Messages.CancelAsync(m.Id), 409, "message cannot be cancelled in its current state");
        }

        [LiveFact]
        public async Task Step12_14_batches()
        {
            using var c = NewClient();

            // 12
            var b = await c.Batches.CreateAsync(new CreateBatchParams
            {
                Items = new[]
                {
                    new BatchItemInput { To = RandomPhone(), Text = $"b1 {Run}" },
                    new BatchItemInput { To = RandomPhone(), Text = $"b2 {Run}" },
                    new BatchItemInput { To = "bad", Text = "x" },
                },
            });
            Assert.Equal("ready", b.Status);
            Assert.Equal(3, b.Total);
            Assert.Equal(1, b.Invalid);
            Assert.Equal(0, b.Sent);

            var report = await c.Batches.ValidationAsync(b.Id);
            Assert.Equal(3, report.Rows.Count);
            Assert.Equal(2, report.Valid);
            Assert.False(report.Rows[2].Valid);
            Assert.Equal("to must be an E.164 phone number", report.Rows[2].Error);

            var got = await c.Batches.GetAsync(b.Id);
            Assert.Equal(3, got.Total);
            Assert.Equal(1, got.Invalid);

            var started = await c.Batches.StartAsync(b.Id);
            Assert.Equal("running", started.Status);
            var items = await Poll(() => c.Batches.ListItemsAsync(b.Id), pg => pg.Items.Count == 2, "batch items");
            Assert.All(items.Items, i => { Assert.NotNull(i.To); Assert.NotNull(i.Status); });

            // 13
            var b2 = await c.Batches.CreateAsync(new CreateBatchParams { Items = new[] { new BatchItemInput { To = RandomPhone(), Text = $"stop {Run}" } } });
            var stopped = await c.Batches.StopAsync(b2.Id);
            Assert.Equal(b2.Id, stopped.Id);
            Assert.Equal("stopped", stopped.Status);
            Assert.Equal(0, stopped.Cancelled);
            await Err(() => c.Batches.StartAsync(b2.Id), 409, "batch is not ready to start");
            await Err(() => c.Batches.GetAsync(ZeroId), 404, "batch not found");

            // 14
            var csv = await c.Batches.CreateFromCsvAsync($"to,text\n{RandomPhone()},csv {Run}\n");
            Assert.Equal("ready", csv.Status);
            Assert.Equal(1, csv.Total);
            Assert.Equal(0, csv.Invalid);
        }

        [LiveFact]
        public async Task Step15_otp()
        {
            using var c = NewClient();
            // A per-run destination so parallel SDK runs cannot read each other's codes.
            var to = RandomPhone();
            var sentAfter = DateTimeOffset.UtcNow.AddSeconds(-30);
            var otp = await c.Otp.SendAsync(new SendOtpParams { To = to, Length = 6, TtlSeconds = 300 });
            Assert.True(Guid.TryParse(otp.OtpId, out _));

            var re = new Regex(@"Your OpenSMS verification code is (\d{6})");
            var page = await Poll(() => c.Sandbox.ListMessagesAsync(new ListParams { Limit = 10 }),
                pg => pg.Items.Any(i => i.TrafficType == "otp" && i.To == to && i.CreatedAt >= sentAfter && re.IsMatch(i.Text ?? "")),
                "OTP in sandbox messages");
            var code = re.Match(page.Items.First(i => i.TrafficType == "otp" && i.To == to && re.IsMatch(i.Text ?? "")).Text!).Groups[1].Value;

            var wrong = code == "000000" ? "111111" : "000000";
            var bad = await c.Otp.VerifyAsync(new VerifyOtpParams { OtpId = otp.OtpId, Code = wrong });
            Assert.False(bad.Valid);
            Assert.Equal(4, bad.AttemptsLeft);
            var good = await c.Otp.VerifyAsync(new VerifyOtpParams { OtpId = otp.OtpId, Code = code });
            Assert.True(good.Valid);
            Assert.Equal(3, good.AttemptsLeft);

            await Err(() => c.Otp.SendAsync(new SendOtpParams { To = Phone, Template = "no placeholder" }), 400, "template must contain {{code}}");
            await Err(() => c.Otp.VerifyAsync(new VerifyOtpParams { OtpId = ZeroId, Code = "123456" }), 404, "OTP not found");
        }

        [LiveFact]
        public async Task Step16_lookups()
        {
            using var c = NewClient();
            var l = await c.Lookups.CreateAsync(new CreateLookupParams { To = Phone });
            Assert.Equal("completed", l.State);
            Assert.Equal("KE", l.Country);
            Assert.Equal("mock", l.Source);
            Assert.Equal("0.000000", l.Price);
            var again = await c.Lookups.GetAsync(l.Id);
            Assert.Equal(l.Id, again.Id);
            Assert.Equal(l.State, again.State);
            var nf = await Err(() => c.Lookups.GetAsync(ZeroId), 404, "Lookup not found.");
            Assert.Equal("not_found", nf.Code);
        }

        [LiveFact]
        public async Task Step17_19_contacts_groups_templates()
        {
            using var c = NewClient();

            // 17
            var r1 = RandomPhone();
            var contact = await c.Contacts.CreateAsync(new CreateContactParams
            {
                E164 = r1,
                Name = $"Ada {Run}",
                Attributes = new Dictionary<string, object?> { ["tier"] = "gold" },
            });
            Assert.Equal(r1, contact.E164);
            var fetched = await c.Contacts.GetAsync(contact.Id);
            Assert.Equal(contact.Id, fetched.Id);
            Assert.Equal(contact.Name, fetched.Name);
            var updated = await c.Contacts.UpdateAsync(contact.Id, new UpdateContactParams { Name = $"Ada L {Run}" });
            Assert.Equal($"Ada L {Run}", updated.Name);
            Assert.Equal("gold", updated.Attributes!["tier"].GetString());
            var found = false;
            await foreach (var x in c.PaginateAsync(c.Contacts.ListAsync, new ListParams { Limit = 200 }))
                if (x.Id == contact.Id) { found = true; break; }
            Assert.True(found);
            await Err(() => c.Contacts.CreateAsync(new CreateContactParams { E164 = r1 }), 409, "A record with this phone number or name already exists.");

            // 18
            var group = await c.ContactGroups.CreateAsync(new CreateContactGroupParams { Name = $"grp {Run}", ContactIds = new[] { contact.Id } });
            Assert.Equal(new[] { contact.Id }, group.ContactIds);
            var renamed = await c.ContactGroups.UpdateAsync(group.Id, new UpdateContactGroupParams { Name = $"grp2 {Run}" });
            Assert.Equal($"grp2 {Run}", renamed.Name);
            Assert.Equal(group.Id, (await c.ContactGroups.GetAsync(group.Id)).Id);
            var gsend = await c.ContactGroups.SendAsync(group.Id, new GroupSendParams { Text = $"Hi {Run}" });
            Assert.Equal("running", gsend.Status);
            Assert.Equal(1, gsend.Total);
            var empty = await c.ContactGroups.CreateAsync(new CreateContactGroupParams { Name = $"empty {Run}" });
            await Err(() => c.ContactGroups.SendAsync(empty.Id, new GroupSendParams { Text = "x" }), 422, "Group must contain between 1 and 1000 contacts.");
            await c.ContactGroups.DeleteAsync(empty.Id);
            Assert.Contains((await c.ContactGroups.ListAsync(new ListParams { Limit = 200 })).Items, g => g.Id == group.Id);

            // 19
            var tpl = await c.Templates.CreateAsync(new CreateTemplateParams { Name = $"tpl-{Run}", Body = "Hi {{name}}", TrafficType = "transactional" });
            Assert.Equal(new[] { "name" }, tpl.Variables);
            var tpl2 = await c.Templates.UpdateAsync(tpl.Id, new UpdateTemplateParams { Body = "Hello {{name}}" });
            Assert.Equal("Hello {{name}}", tpl2.Body);
            Assert.Equal(new[] { "name" }, tpl2.Variables);
            Assert.Equal(tpl.Id, (await c.Templates.GetAsync(tpl.Id)).Id);
            Assert.NotNull((await c.Templates.ListAsync(new ListParams { Limit = 1 })).Items);
            var tsend = await c.ContactGroups.SendAsync(group.Id, new GroupSendParams { TemplateId = tpl.Id, Variables = new Dictionary<string, string> { ["name"] = "Ada" } });
            Assert.Equal("running", tsend.Status);

            await c.Templates.DeleteAsync(tpl.Id);
            await c.ContactGroups.DeleteAsync(group.Id);
            await c.Contacts.DeleteAsync(contact.Id);
            await Err(() => c.Contacts.GetAsync(contact.Id), 404, "Record not found.");
        }

        [LiveFact]
        public async Task Step20_webhooks()
        {
            using var c = NewClient();
            var hook = await c.Webhooks.CreateAsync(new CreateWebhookParams
            {
                Url = $"https://example.com/opensms/{Run}",
                Events = new[] { "message.delivered", "message.failed" },
            });
            Assert.StartsWith("whsec_", hook.Secret);
            Assert.True(hook.Enabled);
            var got = await c.Webhooks.GetAsync(hook.Id);
            Assert.Null(got.Secret);
            Assert.Contains((await c.Webhooks.ListAsync(new ListParams { Limit = 200 })).Items, w => w.Id == hook.Id);

            await Err(() => c.Webhooks.CreateAsync(new CreateWebhookParams { Url = "http://example.com/x", Events = new[] { "message.delivered" } }),
                400, "url must be an HTTPS URL without credentials or fragment");

            var upd = await c.Webhooks.UpdateAsync(hook.Id, new UpdateWebhookParams
            {
                Url = $"https://example.com/opensms/{Run}/v2",
                Events = new[] { "message.delivered" },
                Enabled = true,
            });
            Assert.Equal($"https://example.com/opensms/{Run}/v2", upd.Url);
            Assert.Equal(new[] { "message.delivered" }, upd.Events);

            var test = await c.Webhooks.TestAsync(hook.Id);
            Assert.Equal("pending", test.Status);

            var deliveries = await Poll(() => c.Webhooks.ListDeliveriesAsync(hook.Id), pg => pg.Items.Any(d => d.Event == "webhook.test"), "webhook.test delivery");
            var d = deliveries.Items.First(x => x.Event == "webhook.test");
            Assert.True(d.Id > 0);
            Assert.NotNull(d.Generation);

            try
            {
                var replay = await c.Webhooks.ReplayDeliveryAsync(hook.Id, d.Id, new ReplayDeliveryParams { Generation = d.Generation!.Value, Reason = "sdk conformance replay" });
                Assert.NotNull(replay.Status);
            }
            catch (OpensmsException ex)
            {
                Assert.Equal(409, ex.Status);
                Assert.Equal("Delivery state, lease or generation does not permit replay.", ex.Detail);
            }

            await c.Webhooks.DeleteAsync(hook.Id);
            await Err(() => c.Webhooks.GetAsync(hook.Id), 404, "webhook not found");
        }

        [LiveFact]
        public async Task Step21_suppressions()
        {
            using var c = NewClient();
            var r2 = RandomPhone();
            var s = await c.Suppressions.CreateAsync(new SuppressionParams { E164 = r2, Reason = "manual" });
            Assert.True(s.Id > 0);
            Assert.Equal("manual", s.Reason);

            var rejected = await Err(() => c.Messages.SendAsync(new SendMessageParams { To = r2, Text = "x" }), 422, "destination is suppressed");
            Assert.False(string.IsNullOrEmpty(rejected.RequestId));

            var found = false;
            await foreach (var x in c.PaginateAsync(c.Suppressions.ListAsync, new ListParams { Limit = 200 }))
                if (x.E164 == r2) { found = true; break; }
            Assert.True(found);

            var imported = await c.Suppressions.ImportAsync(new[] { new SuppressionParams { E164 = RandomPhone(), Reason = "complaint" } });
            Assert.Equal(1, imported.Created);
            Assert.Equal(1, imported.Received);

            await c.Suppressions.DeleteAsync(s.Id);
            await Err(() => c.Suppressions.DeleteAsync(s.Id), 404, "suppression not found");
        }

        [LiveFact]
        public async Task Step22_25_compliance_wallet_pricing_analytics()
        {
            using var c = NewClient();

            // 22
            var ke = await c.Compliance.GetCountryAsync("KE");
            Assert.Equal("KE", ke.Iso2);
            Assert.Equal("+254", ke.DialCode);
            Assert.Contains("STOP", ke.StopKeywords!);
            await Err(() => c.Compliance.GetCountryAsync("ZZ"), 404, "country not found");
            Assert.Contains(await c.Compliance.ListCountriesAsync(), x => x.Iso2 == "KE");
            var rules = await c.Compliance.ListContentRulesAsync();
            Assert.All(rules, r => Assert.True(r.Id > 0));

            // 23
            var balances = await c.Wallet.BalancesAsync();
            Assert.NotEmpty(balances);
            Assert.Equal("sandbox", balances[0].Environment);
            Assert.Equal("KES", balances[0].Currency);
            Assert.True(decimal.TryParse(balances[0].Balance, System.Globalization.NumberStyles.Number, System.Globalization.CultureInfo.InvariantCulture, out _));
            var ledger = await c.Wallet.LedgerAsync(new LedgerParams { Limit = 1 });
            Assert.Single(ledger);
            Assert.True(ledger[0].Id > 0);
            await Err(() => c.Wallet.LedgerAsync(new LedgerParams { Limit = 0 }), 400, "limit must be between 1 and 200");
            await Err(() => c.Wallet.CreateTopupAsync(new CreateTopupParams { Amount = "100", Currency = "KES", Channel = "card", Email = "dev@opensms.test" }),
                422, "sandbox wallets cannot use payment providers");

            // 24
            var prices = await c.Pricing.GetAsync(new PricingParams { Product = "sms", Country = "KE" });
            Assert.Equal("KES", prices.Currency);
            Assert.Equal("sms", prices.Product);
            Assert.All(prices.Entries!, e => Assert.Equal("KE", e.CountryIso2));
            await Err(() => c.Pricing.GetAsync(new PricingParams { Product = "bogus" }), 400, "product must be sms, lookup, or number_monthly");

            // 25
            var ov = await c.Analytics.OverviewAsync();
            Assert.Equal("sandbox", ov.Environment);
            Assert.Equal("KES", ov.Currency);
            Assert.NotNull(ov.Sent);
            Assert.NotNull(await c.Analytics.OverviewAsync(new AnalyticsQuery { Range = "7d" }));
            Assert.NotNull(await c.Analytics.ByCountryAsync());
            Assert.NotNull(await c.Analytics.ByCarrierAsync());
            Assert.NotNull(await c.Analytics.BySenderIdAsync());
            Assert.NotNull(await c.Analytics.TimeseriesAsync(new AnalyticsQuery { Range = "7d", Bucket = "day" }));
        }

        [LiveFact]
        public async Task Step26_28_numbers_inbound_sender_ids_countries()
        {
            using var c = NewClient();

            // 26
            Assert.NotNull((await c.Numbers.ListAsync()).Items);
            Assert.NotNull(await c.Numbers.AvailableAsync(new NumberSearchParams { Country = "KE", Kind = "long_code" }));
            await Err(() => c.Numbers.AssignAsync(new NumberSearchParams { Country = "KE", Kind = "long_code" }), 422, "This operation requires the live environment.");
            Assert.Empty((await c.Inbound.ListAsync()).Items);

            // 27
            var hasOpensms = false;
            await foreach (var s in c.PaginateAsync(c.SenderIds.ListAsync, new ListParams { Limit = 200 }))
                if (s.Value == "OPENSMS" && s.Status == "approved") { hasOpensms = true; break; }
            Assert.True(hasOpensms);
            Assert.True((await c.SenderIds.CheckAsync(new SenderIdCheckParams { Value = "ACME", Country = "KE" })).Valid);
            Assert.StartsWith("sq_", (await c.SenderIds.QuoteAsync(new SenderIdQuoteParams { Countries = new[] { "KE" } })).QuoteId);
            Assert.NotNull(await c.SenderIds.ListDocumentsAsync());

            var letters = string.Concat(Enumerable.Range(0, 4).Select(_ => (char)('A' + RandomNumberGenerator.GetInt32(26))));
            var draft = await c.SenderIds.CreateDraftAsync(new CreateSenderIdDraftParams
            {
                Source = "application",
                Value = "SDK" + letters,
                Kind = "alphanumeric",
                Countries = new[] { "KE" },
                UseCase = "transactional",
                SampleMessage = "Your order shipped",
            });
            Assert.Equal(1, draft.Version);
            Assert.Equal("active", draft.Status);
            var d2 = await c.SenderIds.UpdateDraftAsync(draft.Id, new UpdateSenderIdDraftParams { Version = 1, SampleMessage = "Your order has shipped" });
            Assert.Equal(2, d2.Version);
            Assert.Equal("Your order has shipped", (await c.SenderIds.GetDraftAsync(draft.Id)).SampleMessage);
            Assert.NotNull((await c.SenderIds.ListDraftsAsync()).Items);
            await c.SenderIds.DeleteDraftAsync(draft.Id);
            await Err(() => c.SenderIds.GetAsync(ZeroId), 404, "sender ID not found");

            // 28
            var countries = await c.Countries.ListAsync();
            Assert.Contains(countries, x => x.Iso2 == "KE" && x.DialCode == "+254");
            Assert.NotEmpty(await c.Countries.CarriersAsync("KE"));
            Assert.NotNull(await c.Countries.RoutesAsync("KE"));
            Assert.Equal("KE", (await c.Countries.ComplianceAsync("KE")).Iso2);
        }

        [LiveFact]
        public async Task Step29_scope_errors()
        {
            var readOnly = Environment.GetEnvironmentVariable("OPENSMS_READONLY_API_KEY");
            if (string.IsNullOrEmpty(readOnly)) return; // optional step: needs a messages:read-only key
            using var c = NewClient(readOnly);
            await Err(() => c.Messages.SendAsync(new SendMessageParams { To = Phone, Text = "x" }), 401, "insufficient scope");
            await Err(() => c.Contacts.ListAsync(), 403, "Insufficient API key scope.");
            Assert.NotNull((await c.Messages.ListAsync(new MessageListParams { Limit = 1 })).Items);
        }
    }
}
