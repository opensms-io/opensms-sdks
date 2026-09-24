import Foundation

/// The `sandbox` resource. Accessed as `opensms.sandbox`.
public final class Sandbox {
    private let http: Transport
    init(_ http: Transport) { self.http = http }

    /// Sandbox sends as the mock carrier saw them, including rendered OTP codes.
    public func listMessages(_ params: ListParams = ListParams()) async throws -> Page<SandboxMessage> {
        try await http.request("GET", "/v1/sandbox/messages", query: params.query)
    }
}
