import Foundation

/// The `compliance` resource. Accessed as `opensms.compliance`.
public final class Compliance {
    private let http: Transport
    init(_ http: Transport) { self.http = http }

    public func listCountries() async throws -> [CountryRules] {
        try await http.request("GET", "/v1/compliance/countries")
    }

    public func getCountry(_ iso2: String) async throws -> CountryRules {
        try await http.request("GET", "/v1/compliance/countries/\(try idSeg(iso2, "iso2"))")
    }

    public func listContentRules() async throws -> [ContentRule] {
        try await http.request("GET", "/v1/content-rules")
    }
}
