import Foundation

/// Common analytics query. Use `range` (`"7d"`, 1 to 366 days) or `from`/`to`, not both.
public struct AnalyticsQuery {
    public var currency: String?
    public var range: String?
    public var from: DateTimeInput?
    public var to: DateTimeInput?
    /// `day|hour`
    public var bucket: String?

    public init(currency: String? = nil, range: String? = nil, from: DateTimeInput? = nil, to: DateTimeInput? = nil, bucket: String? = nil) {
        self.currency = currency
        self.range = range
        self.from = from
        self.to = to
        self.bucket = bucket
    }

    var query: [(String, String?)] {
        [("currency", currency), ("range", range), ("from", from?.wireValue), ("to", to?.wireValue), ("bucket", bucket)]
    }
}

/// The `analytics` resource. Accessed as `opensms.analytics`.
public final class Analytics {
    private let http: Transport
    init(_ http: Transport) { self.http = http }

    public func overview(_ q: AnalyticsQuery = AnalyticsQuery()) async throws -> AnalyticsMetrics {
        try await http.request("GET", "/v1/analytics/overview", query: q.query)
    }

    public func byCountry(_ q: AnalyticsQuery = AnalyticsQuery()) async throws -> [AnalyticsMetrics] {
        try await http.request("GET", "/v1/analytics/by-country", query: q.query)
    }

    public func byCarrier(_ q: AnalyticsQuery = AnalyticsQuery()) async throws -> [AnalyticsMetrics] {
        try await http.request("GET", "/v1/analytics/by-carrier", query: q.query)
    }

    public func bySenderId(_ q: AnalyticsQuery = AnalyticsQuery()) async throws -> [AnalyticsMetrics] {
        try await http.request("GET", "/v1/analytics/by-sender-id", query: q.query)
    }

    public func timeseries(_ q: AnalyticsQuery = AnalyticsQuery()) async throws -> [AnalyticsMetrics] {
        try await http.request("GET", "/v1/analytics/timeseries", query: q.query)
    }
}
