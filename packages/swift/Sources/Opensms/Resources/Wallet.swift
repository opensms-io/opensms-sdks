import Foundation

/// Parameters for ``Wallet/createTopup(_:idempotencyKey:)``.
public struct CreateTopupParams {
    /// Decimal string, for example `"100"`.
    public var amount: String
    public var currency: String
    /// `card|mobile_money|bank_transfer`
    public var channel: String
    public var email: String

    public init(amount: String, currency: String, channel: String, email: String) {
        self.amount = amount
        self.currency = currency
        self.channel = channel
        self.email = email
    }
}

/// The `wallet` resource. Accessed as `opensms.wallet`.
public final class Wallet {
    private let http: Transport
    init(_ http: Transport) { self.http = http }

    /// Balances for the key's environment.
    public func balances() async throws -> [WalletBalance] {
        let envelope: DataEnvelope<WalletBalance> = try await http.request("GET", "/v1/wallet")
        return envelope.data
    }

    /// Ledger entries, newest first. Page manually: pass the smallest `id`
    /// seen as `before`; stop when fewer than `limit` rows come back.
    public func ledger(limit: Int? = nil, before: Int? = nil) async throws -> [LedgerEntry] {
        let envelope: DataEnvelope<LedgerEntry> = try await http.request(
            "GET", "/v1/wallet/ledger", query: [("limit", limit.q), ("before", before.q)]
        )
        return envelope.data
    }

    /// Start a payment-provider top-up (live keys only).
    public func createTopup(_ params: CreateTopupParams, idempotencyKey: String? = nil) async throws -> Topup {
        let body = RequestBody.json([
            ("amount", .string(params.amount)),
            ("currency", .string(params.currency)),
            ("channel", .string(params.channel)),
            ("email", .string(params.email))
        ])
        return try await http.request("POST", "/v1/wallet/topups", body: body, idempotencyKey: idempotency(idempotencyKey))
    }
}
