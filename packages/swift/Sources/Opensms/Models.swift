import Foundation

// All response models. Wire names are snake_case and map to camelCase here,
// in one place, through explicit CodingKeys. Every field except `id` is
// optional because live payloads omit empty fields. Money, prices, balances
// and FX rates stay decimal strings. Enums are plain strings so a new server
// value never breaks decoding. Unknown fields are ignored.

// MARK: - Pagination

/// One page of a cursor list: `{ items, next_cursor }`.
public struct Page<T: Decodable>: Decodable {
    public let items: [T]
    /// Pass back as `cursor` for the next page; `nil` on the last page.
    public let nextCursor: String?

    public init(items: [T], nextCursor: String?) {
        self.items = items
        self.nextCursor = nextCursor
    }

    enum CodingKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.items = try c.decodeIfPresent([T].self, forKey: .items) ?? []
        self.nextCursor = try c.decodeIfPresent(String.self, forKey: .nextCursor)
    }
}

/// `{ data: [...] }` envelope used by the wallet endpoints.
struct DataEnvelope<T: Decodable>: Decodable {
    let data: [T]
    enum CodingKeys: String, CodingKey { case data }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.data = try c.decodeIfPresent([T].self, forKey: .data) ?? []
    }
}

/// `{ items: [...] }` envelope without a cursor.
struct ItemsEnvelope<T: Decodable>: Decodable {
    let items: [T]
    enum CodingKeys: String, CodingKey { case items }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.items = try c.decodeIfPresent([T].self, forKey: .items) ?? []
    }
}

/// A decimal amount with its currency.
public struct Money: Decodable, Equatable {
    public let amount: String?
    public let currency: String?
}

// MARK: - Messages

/// An SMS message. Batch items decode into this type too, with fewer fields set.
public struct Message: Decodable {
    public let id: String
    public let createdAt: Date?
    public let to: String?
    public let senderId: String?
    public let text: String?
    public let parts: Int?
    /// `queued|scheduled|held|sending|sent|delivered|failed|cancelled|expired`
    public let status: String?
    public let statusReason: String?
    public let sentAt: Date?
    public let deliveredAt: Date?
    public let failedAt: Date?
    public let cancelledAt: Date?
    public let scheduledAt: Date?
    /// Decimal string, for example `"0.000000"`.
    public let price: String?
    public let currency: String?
    /// `otp|transactional|marketing`
    public let trafficType: String?
    public let metadata: JSONObject?
    /// `gsm7|ucs2`
    public let encoding: String?
    public let countryId: String?
    public let countryIso2: String?
    public let countryName: String?
    public let carrierId: String?
    public let carrierName: String?
    /// `prefix|hlr|unknown`
    public let destinationSource: String?
    public let billing: [MessageBilling]?

    enum CodingKeys: String, CodingKey {
        case id, to, text, parts, status, price, currency, metadata, encoding, billing
        case createdAt = "created_at"
        case senderId = "sender_id"
        case statusReason = "status_reason"
        case sentAt = "sent_at"
        case deliveredAt = "delivered_at"
        case failedAt = "failed_at"
        case cancelledAt = "cancelled_at"
        case scheduledAt = "scheduled_at"
        case trafficType = "traffic_type"
        case countryId = "country_id"
        case countryIso2 = "country_iso2"
        case countryName = "country_name"
        case carrierId = "carrier_id"
        case carrierName = "carrier_name"
        case destinationSource = "destination_source"
    }
}

/// Billing summary attached to a message.
public struct MessageBilling: Decodable {
    public let currency: String?
    public let reservedAmount: String?
    public let chargedAmount: String?
    public let refundedAmount: String?

    enum CodingKeys: String, CodingKey {
        case currency
        case reservedAmount = "reserved_amount"
        case chargedAmount = "charged_amount"
        case refundedAmount = "refunded_amount"
    }
}

/// One provider submission attempt for a message.
public struct MessageAttempt: Decodable {
    public let id: Int
    public let sequence: Int?
    public let routeId: String?
    public let routeName: String?
    public let price: String?
    public let currency: String?
    public let provider: String?
    public let providerMessageId: String?
    /// `submitting|submission_unknown|submitted|not_accepted|delivered|failed|expired`
    public let status: String?
    public let errorCode: String?
    public let submittedAt: Date?
    public let dlrAt: Date?
    public let submitLatencyMs: Int?
    public let dlrLatencyMs: Int?

    enum CodingKeys: String, CodingKey {
        case id, sequence, price, currency, provider, status
        case routeId = "route_id"
        case routeName = "route_name"
        case providerMessageId = "provider_message_id"
        case errorCode = "error_code"
        case submittedAt = "submitted_at"
        case dlrAt = "dlr_at"
        case submitLatencyMs = "submit_latency_ms"
        case dlrLatencyMs = "dlr_latency_ms"
    }
}

// MARK: - Batches

/// A bulk send.
public struct Batch: Decodable {
    public let id: String
    /// `ready|running|stopped|completed|failed`
    public let status: String?
    public let total: Int?
    public let sent: Int?
    public let delivered: Int?
    public let failed: Int?
    public let invalid: Int?
    public let duplicates: Int?
    public let suppressed: Int?
    public let estimatedCost: Double?
    public let createdAt: Date?
    public let completedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, status, total, sent, delivered, failed, invalid, duplicates, suppressed
        case estimatedCost = "estimated_cost"
        case createdAt = "created_at"
        case completedAt = "completed_at"
    }
}

/// Result of ``Batches/stop(_:idempotencyKey:)``.
public struct BatchStopResult: Decodable {
    public let id: String
    public let status: String?
    public let cancelled: Int?
}

/// One row of a batch: used both as input to ``Batches/create(_:idempotencyKey:)``
/// and as the echoed `item` in a validation report.
public struct BatchItemInput: Codable, Equatable {
    public var to: String
    public var text: String
    public var senderId: String?
    public var trafficType: String?
    public var callbackUrl: String?
    public var metadata: JSONObject?

    public init(
        to: String,
        text: String,
        senderId: String? = nil,
        trafficType: String? = nil,
        callbackUrl: String? = nil,
        metadata: JSONObject? = nil
    ) {
        self.to = to
        self.text = text
        self.senderId = senderId
        self.trafficType = trafficType
        self.callbackUrl = callbackUrl
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case to, text, metadata
        case senderId = "sender_id"
        case trafficType = "traffic_type"
        case callbackUrl = "callback_url"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.to = try c.decodeIfPresent(String.self, forKey: .to) ?? ""
        self.text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        self.senderId = try c.decodeIfPresent(String.self, forKey: .senderId)
        self.trafficType = try c.decodeIfPresent(String.self, forKey: .trafficType)
        self.callbackUrl = try c.decodeIfPresent(String.self, forKey: .callbackUrl)
        self.metadata = try c.decodeIfPresent(JSONObject.self, forKey: .metadata)
    }

    var json: JSONValue {
        .object(jsonObject([
            ("to", .string(to)),
            ("text", .string(text)),
            ("sender_id", senderId.json),
            ("traffic_type", trafficType.json),
            ("callback_url", callbackUrl.json),
            ("metadata", metadata.json)
        ]))
    }
}

/// Per-row validation of a batch.
public struct BatchValidationReport: Decodable {
    public let rows: [BatchValidationRow]?
    public let total: Int?
    public let valid: Int?
    public let invalid: Int?
    public let duplicates: Int?
    public let suppressed: Int?
}

public struct BatchValidationRow: Decodable {
    public let row: Int?
    public let item: BatchItemInput?
    public let valid: Bool?
    public let duplicate: Bool?
    public let suppressed: Bool?
    public let error: String?
}

// MARK: - OTP

/// Result of ``Otp/send(_:idempotencyKey:)``.
public struct OtpSendResult: Decodable {
    public let otpId: String
    enum CodingKeys: String, CodingKey { case otpId = "otp_id" }
}

/// Result of ``Otp/verify(otpId:code:)``.
public struct OtpVerification: Decodable {
    public let valid: Bool?
    public let attemptsLeft: Int?
    enum CodingKeys: String, CodingKey {
        case valid
        case attemptsLeft = "attempts_left"
    }
}

// MARK: - Lookups

/// A number lookup (HLR or prefix).
public struct Lookup: Decodable {
    public let id: String
    /// `queued|submitting|unknown|completed|failed`
    public let state: String?
    public let country: String?
    public let carrier: String?
    public let ported: Bool?
    public let valid: Bool?
    /// `prefix|hlr|mock`
    public let source: String?
    public let price: String?
    public let currency: String?
    public let checkedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, state, country, carrier, ported, valid, source, price, currency
        case checkedAt = "checked_at"
    }
}

// MARK: - Contacts

public struct Contact: Decodable {
    public let id: String
    public let workspaceId: String?
    public let e164: String?
    public let name: String?
    public let attributes: JSONObject?
    public let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, e164, name, attributes
        case workspaceId = "workspace_id"
        case createdAt = "created_at"
    }
}

public struct ContactGroup: Decodable {
    public let id: String
    public let workspaceId: String?
    public let name: String?
    public let contactIds: [String]?
    public let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name
        case workspaceId = "workspace_id"
        case contactIds = "contact_ids"
        case createdAt = "created_at"
    }
}

// MARK: - Templates

public struct Template: Decodable {
    public let id: String
    public let workspaceId: String?
    public let name: String?
    public let body: String?
    public let trafficType: String?
    public let createdAt: Date?
    public let updatedAt: Date?
    /// Parsed `{{name}}` placeholders.
    public let variables: [String]?

    enum CodingKeys: String, CodingKey {
        case id, name, body, variables
        case workspaceId = "workspace_id"
        case trafficType = "traffic_type"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Webhooks

/// A webhook endpoint. `secret` is only present in the create response.
public struct WebhookEndpoint: Decodable {
    public let id: String
    public let url: String?
    public let events: [String]?
    public let enabled: Bool?
    public let consecutiveFailures: Int?
    public let disabledAt: Date?
    public let createdAt: Date?
    /// `whsec_...`, returned once by create.
    public let secret: String?

    enum CodingKeys: String, CodingKey {
        case id, url, events, enabled, secret
        case consecutiveFailures = "consecutive_failures"
        case disabledAt = "disabled_at"
        case createdAt = "created_at"
    }
}

/// One delivery of an event to a webhook endpoint.
public struct WebhookDelivery: Decodable {
    public let id: Int
    public let generation: Int?
    public let event: String?
    public let payload: JSONValue?
    public let attempts: Int?
    public let nextRetryAt: Date?
    public let status: String?
    public let lastResponseCode: Int?
    public let lastError: String?
    public let createdAt: Date?
    public let deliveredAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, generation, event, payload, attempts, status
        case nextRetryAt = "next_retry_at"
        case lastResponseCode = "last_response_code"
        case lastError = "last_error"
        case createdAt = "created_at"
        case deliveredAt = "delivered_at"
    }
}

/// `{ status }` acknowledgement (webhook test and replay).
public struct StatusAck: Decodable {
    public let status: String?
}

/// A verified webhook delivery envelope.
public struct WebhookEvent: Decodable {
    public let id: String
    public let type: String?
    public let workspaceId: String?
    public let environment: String?
    public let createdAt: Date?
    public let data: JSONValue?

    enum CodingKeys: String, CodingKey {
        case id, type, environment, data
        case workspaceId = "workspace_id"
        case createdAt = "created_at"
    }
}

// MARK: - Inbound

public struct InboundMessage: Decodable {
    public let id: String
    public let from: String?
    public let to: String?
    public let text: String?
    public let receivedAt: Date?
    public let virtualNumberId: String?

    enum CodingKeys: String, CodingKey {
        case id, from, to, text
        case receivedAt = "received_at"
        case virtualNumberId = "virtual_number_id"
    }
}

// MARK: - Numbers

/// A virtual phone number.
public struct VirtualNumber: Decodable {
    public let id: String
    public let country: String?
    public let number: String?
    /// `long_code|short_code|toll_free`
    public let kind: String?
    public let monthlyFee: String?
    public let feeCurrency: String?
    /// `available|assigned|releasing`
    public let status: String?
    public let inbound: Bool?
    public let outbound: Bool?
    public let assignedAt: Date?
    public let renewsAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, country, number, kind, status, inbound, outbound
        case monthlyFee = "monthly_fee"
        case feeCurrency = "fee_currency"
        case assignedAt = "assigned_at"
        case renewsAt = "renews_at"
    }
}

/// An inbound routing rule on a number.
public struct InboundRule: Decodable {
    public let id: String
    /// `keyword|prefix|regex|any`
    public let match: String?
    public let pattern: String?
    /// `webhook|auto_reply|forward_email`
    public let action: String?
    public let target: String?
    public let position: Int?
}

// MARK: - Sender IDs

public struct SenderId: Decodable {
    public let id: String
    public let value: String?
    /// `alphanumeric|numeric`
    public let kind: String?
    public let countries: [String]?
    public let useCase: String?
    public let sampleMessage: String?
    public let status: String?
    public let rejectionReason: String?
    public let restricted: Bool?
    public let restrictionReason: String?
    public let createdAt: Date?
    /// Per-country registrations (get and create only).
    public let registrations: [JSONObject]?
    public let reviewHistory: [JSONObject]?

    enum CodingKeys: String, CodingKey {
        case id, value, kind, countries, status, restricted, registrations
        case useCase = "use_case"
        case sampleMessage = "sample_message"
        case rejectionReason = "rejection_reason"
        case restrictionReason = "restriction_reason"
        case createdAt = "created_at"
        case reviewHistory = "review_history"
    }
}

public struct SenderIdDraft: Decodable {
    public let id: String
    /// `onboarding|application`
    public let source: String?
    public let value: String?
    public let kind: String?
    public let countries: [String]?
    public let useCase: String?
    public let sampleMessage: String?
    public let documents: [String]?
    public let version: Int?
    /// `active|submitted`
    public let status: String?
    public let submittedSenderId: String?
    public let createdAt: Date?
    public let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, source, value, kind, countries, documents, version, status
        case useCase = "use_case"
        case sampleMessage = "sample_message"
        case submittedSenderId = "submitted_sender_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

public struct SenderDocument: Decodable {
    public let id: String
    /// `certificate|signatory-id|authorization`
    public let kind: String?
    public let filename: String?
    public let contentType: String?
    public let size: Int?
    public let scanStatus: String?
    public let reviewStatus: String?
    public let reviewReason: String?
    public let reviewedAt: Date?
    public let version: Int?
    public let supersedesId: String?
    public let isCurrent: Bool?
    public let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, kind, filename, size, version
        case contentType = "content_type"
        case scanStatus = "scan_status"
        case reviewStatus = "review_status"
        case reviewReason = "review_reason"
        case reviewedAt = "reviewed_at"
        case supersedesId = "supersedes_id"
        case isCurrent = "is_current"
        case createdAt = "created_at"
    }
}

public struct SenderIdCheck: Decodable {
    public let valid: Bool?
    public let available: Bool?
    public let reserved: Bool?
    public let reason: String?
}

public struct SenderIdQuote: Decodable {
    public let quoteId: String?
    public let entries: [Entry]?
    public let totals: [Total]?

    public struct Entry: Decodable {
        public let country: String?
        public let provider: String?
        public let feeAmount: String?
        public let feeCurrency: String?
        enum CodingKeys: String, CodingKey {
            case country, provider
            case feeAmount = "fee_amount"
            case feeCurrency = "fee_currency"
        }
    }

    public struct Total: Decodable {
        public let currency: String?
        public let amount: String?
    }

    enum CodingKeys: String, CodingKey {
        case entries, totals
        case quoteId = "quote_id"
    }
}

// MARK: - Suppressions and compliance

public struct Suppression: Decodable {
    public let id: Int
    public let e164: String?
    /// `stop_keyword|manual|complaint|invalid_number`
    public let reason: String?
    public let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, e164, reason
        case createdAt = "created_at"
    }
}

public struct SuppressionImportResult: Decodable {
    public let created: Int?
    public let received: Int?
}

/// Compliance rules for one country.
public struct CountryRules: Decodable {
    public let iso2: String?
    public let name: String?
    public let status: String?
    public let dialCode: String?
    public let stopKeywords: [String]?
    public let quietHours: [QuietHours]?
    public let contentRules: [CountryContentRule]?

    public struct QuietHours: Decodable {
        public let trafficType: String?
        public let startLocal: String?
        public let endLocal: String?
        public let enforce: String?
        enum CodingKeys: String, CodingKey {
            case enforce
            case trafficType = "traffic_type"
            case startLocal = "start_local"
            case endLocal = "end_local"
        }
    }

    public struct CountryContentRule: Decodable {
        public let kind: String?
        public let pattern: String?
        public let action: String?
        public let trafficTypes: [String]?
        public let enabled: Bool?
        enum CodingKeys: String, CodingKey {
            case kind, pattern, action, enabled
            case trafficTypes = "traffic_types"
        }
    }

    enum CodingKeys: String, CodingKey {
        case iso2, name, status
        case dialCode = "dial_code"
        case stopKeywords = "stop_keywords"
        case quietHours = "quiet_hours"
        case contentRules = "content_rules"
    }
}

public struct ContentRule: Decodable {
    public let id: Int
    public let countryIso2: String?
    /// `blocked_keyword|regex`
    public let kind: String?
    public let pattern: String?
    /// `reject|hold_for_review`
    public let action: String?
    public let trafficTypes: [String]?
    public let enabled: Bool?

    enum CodingKeys: String, CodingKey {
        case id, kind, pattern, action, enabled
        case countryIso2 = "country_iso2"
        case trafficTypes = "traffic_types"
    }
}

// MARK: - Wallet

public struct WalletBalance: Decodable {
    public let id: String
    public let currency: String?
    public let balance: String?
    public let reserved: String?
    public let environment: String?
}

public struct LedgerEntry: Decodable {
    public let id: Int
    public let walletId: String?
    public let type: String?
    public let amount: String?
    public let balanceAfter: String?
    public let reservedDelta: String?
    public let reservedAfter: String?
    public let reference: String?
    public let paymentId: String?
    public let messageId: String?
    public let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, type, amount, reference
        case walletId = "wallet_id"
        case balanceAfter = "balance_after"
        case reservedDelta = "reserved_delta"
        case reservedAfter = "reserved_after"
        case paymentId = "payment_id"
        case messageId = "message_id"
        case createdAt = "created_at"
    }
}

public struct Topup: Decodable {
    public let id: String
    public let reference: String?
    public let authorizationUrl: String?
    public let accessCode: String?
    public let amount: String?
    public let currency: String?
    public let status: String?

    enum CodingKeys: String, CodingKey {
        case id, reference, amount, currency, status
        case authorizationUrl = "authorization_url"
        case accessCode = "access_code"
    }
}

// MARK: - Pricing

public struct PriceList: Decodable {
    public let workspaceId: String?
    public let currency: String?
    public let product: String?
    public let entries: [PriceEntry]?

    enum CodingKeys: String, CodingKey {
        case currency, product, entries
        case workspaceId = "workspace_id"
    }
}

public struct PriceEntry: Decodable {
    public let countryIso2: String?
    public let countryName: String?
    public let carrierId: String?
    public let carrierName: String?
    public let product: String?
    public let minMonthlyVolume: Int?
    public let markupType: String?
    public let markupValue: String?
    public let sellCurrency: String?
    public let sellAmount: String?
    public let convertedAmount: String?
    public let convertedCurrency: String?
    public let workspaceOverride: Bool?
    public let effectiveFrom: Date?
    public let fxRate: String?

    enum CodingKeys: String, CodingKey {
        case product
        case countryIso2 = "country_iso2"
        case countryName = "country_name"
        case carrierId = "carrier_id"
        case carrierName = "carrier_name"
        case minMonthlyVolume = "min_monthly_volume"
        case markupType = "markup_type"
        case markupValue = "markup_value"
        case sellCurrency = "sell_currency"
        case sellAmount = "sell_amount"
        case convertedAmount = "converted_amount"
        case convertedCurrency = "converted_currency"
        case workspaceOverride = "workspace_override"
        case effectiveFrom = "effective_from"
        case fxRate = "fx_rate"
    }
}

// MARK: - Analytics

/// Delivery metrics. Used by every analytics method; `from`, `to`,
/// `currency` and `environment` are set on the overview, `key` and `name` on
/// breakdown rows, `bucket` on timeseries rows.
public struct AnalyticsMetrics: Decodable {
    public let sent: Int?
    public let delivered: Int?
    public let failed: Int?
    public let parts: Int?
    public let deliveryRate: Double?
    public let spend: String?
    public let p50Ms: Int?
    public let p95Ms: Int?
    public let from: Date?
    public let to: Date?
    public let currency: String?
    public let environment: String?
    public let key: String?
    public let name: String?
    public let bucket: Date?

    enum CodingKeys: String, CodingKey {
        case sent, delivered, failed, parts, spend, from, to, currency, environment, key, name, bucket
        case deliveryRate = "delivery_rate"
        case p50Ms = "p50_ms"
        case p95Ms = "p95_ms"
    }
}

// MARK: - Sandbox

/// A sandbox send as the mock carrier saw it, including the rendered text.
public struct SandboxMessage: Decodable {
    public let id: String
    public let to: String?
    public let senderId: String?
    public let text: String?
    public let parts: Int?
    public let status: String?
    public let trafficType: String?
    public let createdAt: Date?
    public let sentAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, to, text, parts, status
        case senderId = "sender_id"
        case trafficType = "traffic_type"
        case createdAt = "created_at"
        case sentAt = "sent_at"
    }
}

// MARK: - Countries

public struct Country: Decodable {
    public let iso2: String?
    public let name: String?
    public let dialCode: String?
    public let currency: String?
    public let status: String?
    public let pricePerMessage: Money?
    public let senderKinds: [String]?
    public let providersAvailable: Int?

    enum CodingKeys: String, CodingKey {
        case iso2, name, currency, status
        case dialCode = "dial_code"
        case pricePerMessage = "price_per_message"
        case senderKinds = "sender_kinds"
        case providersAvailable = "providers_available"
    }
}

public struct Carrier: Decodable {
    public let id: String
    public let name: String?
    public let mccMnc: [String]?
    public let prefixes: [String]?

    enum CodingKeys: String, CodingKey {
        case id, name, prefixes
        case mccMnc = "mcc_mnc"
    }
}

public struct Route: Decodable {
    public let provider: String?
    public let carrier: String?
    public let health: String?
    public let cost: String?
    public let currency: String?
    public let priority: Int?
    public let sellPrice: Money?
    public let p50Ms: Int?

    enum CodingKeys: String, CodingKey {
        case provider, carrier, health, cost, currency, priority
        case sellPrice = "sell_price"
        case p50Ms = "p50_ms"
    }
}
