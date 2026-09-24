package io.opensms;

import io.opensms.models.Page;

import java.net.http.HttpClient;
import java.time.Duration;
import java.util.function.Function;

/**
 * Official Java client for the OpenSMS API.
 *
 * <p>Resources are exposed as accessor methods that share one transport:
 * {@code messages()}, {@code batches()}, {@code otp()}, {@code lookups()},
 * {@code contacts()}, {@code contactGroups()}, {@code templates()},
 * {@code webhooks()}, {@code inbound()}, {@code numbers()}, {@code senderIds()},
 * {@code suppressions()}, {@code compliance()}, {@code wallet()},
 * {@code pricing()}, {@code analytics()}, {@code sandbox()}, {@code countries()}.
 *
 * <pre>{@code
 * OpensmsClient opensms = new OpensmsClient("sk_test_...");
 * Message m = opensms.messages().send(new SendMessageParams("+254700000012", "Your order has shipped"));
 * }</pre>
 *
 * <p>The client is thread-safe and meant to be reused.
 */
public final class OpensmsClient {

    /** SDK version, sent in {@code User-Agent: opensms-java/<version>}. */
    public static final String VERSION = "0.1.0";
    /** Default API base URL. */
    public static final String DEFAULT_BASE_URL = "https://api.opensms.io";
    /** Default per-attempt timeout. */
    public static final Duration DEFAULT_TIMEOUT = Duration.ofSeconds(30);
    /** Default number of retries after the first attempt. */
    public static final int DEFAULT_MAX_RETRIES = 2;

    private final String environment;
    private final String baseUrl;

    private final Messages messages;
    private final Batches batches;
    private final Otp otp;
    private final Lookups lookups;
    private final Contacts contacts;
    private final ContactGroups contactGroups;
    private final Templates templates;
    private final Webhooks webhooks;
    private final Inbound inbound;
    private final Numbers numbers;
    private final SenderIds senderIds;
    private final Suppressions suppressions;
    private final Compliance compliance;
    private final Wallet wallet;
    private final Pricing pricing;
    private final Analytics analytics;
    private final Sandbox sandbox;
    private final Countries countries;

    /**
     * Create a client with default settings.
     *
     * @param apiKey {@code sk_test_...} (sandbox) or {@code sk_live_...} (live).
     * @throws IllegalArgumentException when the key is missing or malformed.
     */
    public OpensmsClient(String apiKey) {
        this(builder().apiKey(apiKey));
    }

    private OpensmsClient(Builder b) {
        this.environment = validateKey(b.apiKey);
        if (b.maxRetries < 0) {
            throw new IllegalArgumentException("maxRetries must be >= 0");
        }
        if (b.timeout == null || b.timeout.isNegative() || b.timeout.isZero()) {
            throw new IllegalArgumentException("timeout must be positive");
        }
        String base = b.baseUrl == null || b.baseUrl.isBlank() ? DEFAULT_BASE_URL : b.baseUrl.trim();
        this.baseUrl = base.replaceAll("/+$", "");
        HttpTransport http = b.transport != null ? b.transport : new JdkHttpTransport(b.httpClient, b.timeout);
        Sleeper sleeper = b.sleeper != null ? b.sleeper : Sleeper.SYSTEM;
        ApiTransport t = new ApiTransport(b.apiKey, this.baseUrl, b.maxRetries, http, sleeper);

        this.messages = new Messages(t);
        this.batches = new Batches(t);
        this.otp = new Otp(t);
        this.lookups = new Lookups(t);
        this.contacts = new Contacts(t);
        this.contactGroups = new ContactGroups(t);
        this.templates = new Templates(t);
        this.webhooks = new Webhooks(t);
        this.inbound = new Inbound(t);
        this.numbers = new Numbers(t);
        this.senderIds = new SenderIds(t);
        this.suppressions = new Suppressions(t);
        this.compliance = new Compliance(t);
        this.wallet = new Wallet(t);
        this.pricing = new Pricing(t);
        this.analytics = new Analytics(t);
        this.sandbox = new Sandbox(t);
        this.countries = new Countries(t);
    }

    /** Mirrors the server's {@code auth.ValidSecret}: known prefix plus more than 12 characters. */
    private static String validateKey(String key) {
        if (key == null || key.isEmpty()) {
            throw new IllegalArgumentException("apiKey is required");
        }
        String env;
        String rest;
        if (key.startsWith("sk_test_")) {
            env = "sandbox";
            rest = key.substring("sk_test_".length());
        } else if (key.startsWith("sk_live_")) {
            env = "live";
            rest = key.substring("sk_live_".length());
        } else {
            throw new IllegalArgumentException("apiKey must start with sk_test_ or sk_live_");
        }
        if (rest.length() <= 12) {
            throw new IllegalArgumentException("apiKey is too short");
        }
        return env;
    }

    /** @return a builder for custom settings. */
    public static Builder builder() {
        return new Builder();
    }

    /** @return {@code "sandbox"} for {@code sk_test_} keys, {@code "live"} for {@code sk_live_} keys. */
    public String environment() { return environment; }

    /** @return the base URL in use, without a trailing slash. */
    public String baseUrl() { return baseUrl; }

    /** @return send and inspect messages. */
    public Messages messages() { return messages; }

    /** @return message batches. */
    public Batches batches() { return batches; }

    /** @return one-time passcodes. */
    public Otp otp() { return otp; }

    /** @return number lookups. */
    public Lookups lookups() { return lookups; }

    /** @return contacts. */
    public Contacts contacts() { return contacts; }

    /** @return contact groups. */
    public ContactGroups contactGroups() { return contactGroups; }

    /** @return message templates. */
    public Templates templates() { return templates; }

    /** @return webhook endpoints, deliveries and signature verification. */
    public Webhooks webhooks() { return webhooks; }

    /** @return inbound messages. */
    public Inbound inbound() { return inbound; }

    /** @return virtual numbers. */
    public Numbers numbers() { return numbers; }

    /** @return sender IDs, drafts and documents. */
    public SenderIds senderIds() { return senderIds; }

    /** @return the suppression list. */
    public Suppressions suppressions() { return suppressions; }

    /** @return compliance rules. */
    public Compliance compliance() { return compliance; }

    /** @return wallet balances, ledger and top-ups. */
    public Wallet wallet() { return wallet; }

    /** @return prices. */
    public Pricing pricing() { return pricing; }

    /** @return analytics. */
    public Analytics analytics() { return analytics; }

    /** @return sandbox inspection. */
    public Sandbox sandbox() { return sandbox; }

    /** @return the country catalog. */
    public Countries countries() { return countries; }

    /**
     * Iterate every item of a cursor-paginated list, fetching pages lazily.
     *
     * <pre>{@code
     * for (Message m : opensms.paginate(opensms.messages()::list, new MessageListParams().limit(50))) { ... }
     * for (Message m : opensms.paginate(p -> opensms.batches().listItems(batchId, p), new BatchItemListParams())) { ... }
     * }</pre>
     *
     * @param list   a list method taking the parameters.
     * @param params first-page parameters (not modified).
     * @param <P>    the parameter type.
     * @param <T>    the item type.
     * @return a lazy iterable; errors surface as {@link OpensmsException} while iterating.
     */
    public <P extends CursorParams<P>, T> Iterable<T> paginate(Function<P, Page<T>> list, P params) {
        return new Paginator<>(list, params);
    }

    /** Builder for {@link OpensmsClient}. */
    public static final class Builder {
        private String apiKey;
        private String baseUrl;
        private Duration timeout = DEFAULT_TIMEOUT;
        private int maxRetries = DEFAULT_MAX_RETRIES;
        private HttpClient httpClient;
        private HttpTransport transport;
        private Sleeper sleeper;

        private Builder() {
        }

        /** @param apiKey {@code sk_test_...} or {@code sk_live_...}. @return this. */
        public Builder apiKey(String apiKey) { this.apiKey = apiKey; return this; }

        /** @param baseUrl API base URL (default {@code https://api.opensms.io}). @return this. */
        public Builder baseUrl(String baseUrl) { this.baseUrl = baseUrl; return this; }

        /** @param timeout per-attempt timeout (default 30 s). @return this. */
        public Builder timeout(Duration timeout) { this.timeout = timeout; return this; }

        /** @param maxRetries retries after the first attempt (default 2; 0 disables). @return this. */
        public Builder maxRetries(int maxRetries) { this.maxRetries = maxRetries; return this; }

        /** @param httpClient a configured JDK client (proxy, executor, TLS). @return this. */
        public Builder httpClient(HttpClient httpClient) { this.httpClient = httpClient; return this; }

        /** @param transport a custom transport, for example a mock in tests. @return this. */
        public Builder transport(HttpTransport transport) { this.transport = transport; return this; }

        /** @param sleeper how to wait between retries (tests inject a no-op). @return this. */
        public Builder sleeper(Sleeper sleeper) { this.sleeper = sleeper; return this; }

        /** @return the client. @throws IllegalArgumentException on an invalid key or option. */
        public OpensmsClient build() { return new OpensmsClient(this); }
    }
}
