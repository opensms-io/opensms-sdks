import Foundation

/// The `countries` resource (public catalog). Accessed as `opensms.countries`.
public final class Countries {
    private let http: Transport
    init(_ http: Transport) { self.http = http }

    public func list() async throws -> [Country] {
        try await http.request("GET", "/v1/countries")
    }

    public func carriers(_ iso2: String) async throws -> [Carrier] {
        try await http.request("GET", "/v1/countries/\(try idSeg(iso2, "iso2"))/carriers")
    }

    public func routes(_ iso2: String) async throws -> [Route] {
        try await http.request("GET", "/v1/countries/\(try idSeg(iso2, "iso2"))/routes")
    }

    public func compliance(_ iso2: String) async throws -> CountryRules {
        try await http.request("GET", "/v1/countries/\(try idSeg(iso2, "iso2"))/compliance")
    }
}
