import Foundation

/// The `pricing` resource. Accessed as `opensms.pricing`.
public final class Pricing {
    private let http: Transport
    init(_ http: Transport) { self.http = http }

    /// Price list. `product` is `sms` (default), `lookup` or `number_monthly`.
    public func get(product: String? = nil, country: String? = nil) async throws -> PriceList {
        try await http.request("GET", "/v1/pricing", query: [("product", product), ("country", country)])
    }
}
