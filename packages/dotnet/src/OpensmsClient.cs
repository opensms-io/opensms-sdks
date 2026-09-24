using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using Opensms.Internal;

namespace Opensms
{
    /// <summary>
    /// Official .NET client for the OpenSMS prepaid SMS API.
    /// </summary>
    /// <remarks>
    /// The key alone selects the workspace and the environment: <c>sk_test_</c>
    /// keys use the sandbox, <c>sk_live_</c> keys send real traffic. Every
    /// resource hangs off the client (<see cref="Messages"/>, <see cref="Batches"/>,
    /// <see cref="Otp"/>, ...). The client is thread safe; create one and reuse it.
    /// </remarks>
    /// <example>
    /// <code>
    /// using var client = new OpensmsClient("sk_test_...");
    /// var message = await client.Messages.SendAsync(new SendMessageParams
    /// {
    ///     To = "+254700000012",
    ///     Text = "Your order has shipped",
    /// });
    /// </code>
    /// </example>
    public sealed class OpensmsClient : IDisposable
    {
        private const string TestPrefix = "sk_test_";
        private const string LivePrefix = "sk_live_";

        private readonly ApiTransport _transport;

        /// <summary><c>"sandbox"</c> for <c>sk_test_</c> keys, <c>"live"</c> for <c>sk_live_</c> keys.</summary>
        public string Environment { get; }

        /// <summary>The effective base URL (no trailing slash).</summary>
        public string BaseUrl => _transport.BaseUrl;

        /// <summary>Send, list, inspect and cancel SMS.</summary>
        public MessagesResource Messages { get; }
        /// <summary>Bulk sends.</summary>
        public BatchesResource Batches { get; }
        /// <summary>One-time passcodes.</summary>
        public OtpResource Otp { get; }
        /// <summary>Number lookups.</summary>
        public LookupsResource Lookups { get; }
        /// <summary>Address-book contacts.</summary>
        public ContactsResource Contacts { get; }
        /// <summary>Contact groups and group sends.</summary>
        public ContactGroupsResource ContactGroups { get; }
        /// <summary>Message templates.</summary>
        public TemplatesResource Templates { get; }
        /// <summary>Webhook endpoints, deliveries and signature verification.</summary>
        public WebhooksResource Webhooks { get; }
        /// <summary>Inbound SMS.</summary>
        public InboundResource Inbound { get; }
        /// <summary>Virtual numbers and inbound rules.</summary>
        public NumbersResource Numbers { get; }
        /// <summary>Sender IDs, drafts and documents.</summary>
        public SenderIdsResource SenderIds { get; }
        /// <summary>The do-not-send list.</summary>
        public SuppressionsResource Suppressions { get; }
        /// <summary>Country and content rules.</summary>
        public ComplianceResource Compliance { get; }
        /// <summary>Balances, ledger and top-ups.</summary>
        public WalletResource Wallet { get; }
        /// <summary>Your price list.</summary>
        public PricingResource Pricing { get; }
        /// <summary>Delivery and spend analytics.</summary>
        public AnalyticsResource Analytics { get; }
        /// <summary>Sandbox inspection.</summary>
        public SandboxResource Sandbox { get; }
        /// <summary>The public country catalog.</summary>
        public CountriesResource Countries { get; }

        /// <summary>Create a client.</summary>
        /// <param name="apiKey">An <c>sk_test_</c> or <c>sk_live_</c> secret key.</param>
        /// <param name="options">Base URL, timeout, retries and transport overrides.</param>
        /// <exception cref="ArgumentException">The key is missing or malformed (checked locally, no request is made).</exception>
        public OpensmsClient(string apiKey, OpensmsClientOptions? options = null)
        {
            Environment = ValidateKey(apiKey);
            _transport = new ApiTransport(apiKey, options ?? new OpensmsClientOptions());

            Messages = new MessagesResource(_transport);
            Batches = new BatchesResource(_transport);
            Otp = new OtpResource(_transport);
            Lookups = new LookupsResource(_transport);
            Contacts = new ContactsResource(_transport);
            ContactGroups = new ContactGroupsResource(_transport);
            Templates = new TemplatesResource(_transport);
            Webhooks = new WebhooksResource(_transport);
            Inbound = new InboundResource(_transport);
            Numbers = new NumbersResource(_transport);
            SenderIds = new SenderIdsResource(_transport);
            Suppressions = new SuppressionsResource(_transport);
            Compliance = new ComplianceResource(_transport);
            Wallet = new WalletResource(_transport);
            Pricing = new PricingResource(_transport);
            Analytics = new AnalyticsResource(_transport);
            Sandbox = new SandboxResource(_transport);
            Countries = new CountriesResource(_transport);
        }

        /// <summary>
        /// Iterate every item of a cursor-paged list, fetching pages lazily.
        /// </summary>
        /// <example>
        /// <code>
        /// await foreach (var m in client.PaginateAsync(client.Messages.ListAsync, new MessageListParams { Limit = 50 }))
        ///     Console.WriteLine(m.Id);
        /// </code>
        /// </example>
        public IAsyncEnumerable<T> PaginateAsync<TParams, T>(
            Func<TParams?, CancellationToken, Task<Page<T>>> list,
            TParams? parameters = null,
            CancellationToken ct = default)
            where TParams : ListParams, new()
            => Paginator.PaginateAsync(list, parameters, ct);

        /// <summary>Dispose the underlying <see cref="System.Net.Http.HttpClient"/> if this client created it.</summary>
        public void Dispose() => _transport.Dispose();

        private static string ValidateKey(string? apiKey)
        {
            if (string.IsNullOrEmpty(apiKey))
                throw new ArgumentException("apiKey is required", nameof(apiKey));
            string environment;
            if (apiKey.StartsWith(TestPrefix, StringComparison.Ordinal)) environment = "sandbox";
            else if (apiKey.StartsWith(LivePrefix, StringComparison.Ordinal)) environment = "live";
            else throw new ArgumentException("apiKey must start with sk_test_ or sk_live_", nameof(apiKey));
            if (apiKey.Length - TestPrefix.Length <= 12)
                throw new ArgumentException("apiKey is too short to be a valid OpenSMS secret key", nameof(apiKey));
            return environment;
        }
    }
}
