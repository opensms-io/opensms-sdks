import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// OpenSMS API client.
///
/// Construct it once with a secret key and reuse it. The key alone selects the
/// workspace and the environment (`sk_test_` is sandbox, `sk_live_` is live).
///
/// ```swift
/// let opensms = try OpensmsClient(apiKey: "sk_test_...")
/// let message = try await opensms.messages.send(.init(to: "+254700000012", text: "Hello"))
/// ```
public final class OpensmsClient {
    /// `"sandbox"` for `sk_test_` keys, `"live"` for `sk_live_` keys.
    public let environment: String

    public let messages: Messages
    public let batches: Batches
    public let otp: Otp
    public let lookups: Lookups
    public let contacts: Contacts
    public let contactGroups: ContactGroups
    public let templates: Templates
    public let webhooks: Webhooks
    public let inbound: Inbound
    public let numbers: Numbers
    public let senderIds: SenderIds
    public let suppressions: Suppressions
    public let compliance: Compliance
    public let wallet: Wallet
    public let pricing: Pricing
    public let analytics: Analytics
    public let sandbox: Sandbox
    public let countries: Countries

    let transport: Transport

    /// Create a client from full options. Throws ``OpensmsArgumentError`` for a
    /// malformed key (no network call is made).
    public init(options: OpensmsOptions) throws {
        self.environment = try Self.validateKey(options.apiKey)
        let t = Transport(options)
        self.transport = t
        self.messages = Messages(t)
        self.batches = Batches(t)
        self.otp = Otp(t)
        self.lookups = Lookups(t)
        self.contacts = Contacts(t)
        self.contactGroups = ContactGroups(t)
        self.templates = Templates(t)
        self.webhooks = Webhooks(t)
        self.inbound = Inbound(t)
        self.numbers = Numbers(t)
        self.senderIds = SenderIds(t)
        self.suppressions = Suppressions(t)
        self.compliance = Compliance(t)
        self.wallet = Wallet(t)
        self.pricing = Pricing(t)
        self.analytics = Analytics(t)
        self.sandbox = Sandbox(t)
        self.countries = Countries(t)
    }

    /// Create a client with a key and optional overrides.
    public convenience init(
        apiKey: String,
        baseURL: String = "https://api.opensms.io",
        timeout: TimeInterval = 30,
        maxRetries: Int = 2,
        session: URLSession = .shared,
        sleeper: OpensmsSleeper? = nil
    ) throws {
        try self.init(options: OpensmsOptions(
            apiKey: apiKey,
            baseURL: baseURL,
            timeout: timeout,
            maxRetries: maxRetries,
            session: session,
            sleeper: sleeper
        ))
    }

    /// The effective base URL (trailing slashes stripped).
    public var baseURL: String { transport.baseURL }

    /// Iterate every item of a cursor list lazily, fetching pages on demand.
    ///
    /// ```swift
    /// for try await m in opensms.paginate(opensms.messages.list, ListMessagesParams(limit: 50)) { ... }
    /// ```
    public func paginate<P: CursorParams, T>(
        _ list: @escaping (P) async throws -> Page<T>,
        _ params: P
    ) -> AsyncThrowingStream<T, Error> {
        Opensms.paginate(list, params)
    }

    /// Mirrors `auth.ValidSecret`: `sk_test_` or `sk_live_` plus more than 12 characters.
    static func validateKey(_ key: String) throws -> String {
        for (prefix, env) in [("sk_test_", "sandbox"), ("sk_live_", "live")] where key.hasPrefix(prefix) {
            if key.count - prefix.count > 12 { return env }
        }
        throw OpensmsArgumentError(
            "OpenSMS: `apiKey` must be a secret key starting with sk_test_ or sk_live_ followed by more than 12 characters."
        )
    }
}
