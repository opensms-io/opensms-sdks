import Foundation

/// Parameters for ``SenderIds/create(_:)``.
public struct CreateSenderIdParams {
    public var value: String
    /// `alphanumeric|numeric`
    public var kind: String
    public var countries: [String]
    /// Uploaded document ids (certificate, signatory-id, authorization).
    public var documents: [String]
    public var useCase: String?
    public var sampleMessage: String?
    public var draftId: String?
    public var draftVersion: Int?
    public var quoteId: String?

    public init(
        value: String,
        kind: String,
        countries: [String],
        documents: [String],
        useCase: String? = nil,
        sampleMessage: String? = nil,
        draftId: String? = nil,
        draftVersion: Int? = nil,
        quoteId: String? = nil
    ) {
        self.value = value
        self.kind = kind
        self.countries = countries
        self.documents = documents
        self.useCase = useCase
        self.sampleMessage = sampleMessage
        self.draftId = draftId
        self.draftVersion = draftVersion
        self.quoteId = quoteId
    }
}

/// Parameters for ``SenderIds/update(_:_:)``.
public struct UpdateSenderIdParams {
    public var useCase: String
    public var countries: [String]
    public var documents: [String]
    public var sampleMessage: String?

    public init(useCase: String, countries: [String], documents: [String], sampleMessage: String? = nil) {
        self.useCase = useCase
        self.countries = countries
        self.documents = documents
        self.sampleMessage = sampleMessage
    }
}

/// Parameters for ``SenderIds/createDraft(_:)`` and ``SenderIds/updateDraft(_:_:)``.
public struct SenderIdDraftParams {
    /// Required by ``SenderIds/updateDraft(_:_:)`` (optimistic lock); ignored by create.
    public var version: Int?
    /// `onboarding|application` (create only).
    public var source: String?
    public var value: String?
    public var kind: String?
    public var countries: [String]?
    public var useCase: String?
    public var sampleMessage: String?
    public var documents: [String]?

    public init(
        version: Int? = nil,
        source: String? = nil,
        value: String? = nil,
        kind: String? = nil,
        countries: [String]? = nil,
        useCase: String? = nil,
        sampleMessage: String? = nil,
        documents: [String]? = nil
    ) {
        self.version = version
        self.source = source
        self.value = value
        self.kind = kind
        self.countries = countries
        self.useCase = useCase
        self.sampleMessage = sampleMessage
        self.documents = documents
    }

    var fields: [(String, JSONValue?)] {
        [
            ("value", value.json),
            ("kind", kind.json),
            ("countries", countries.json),
            ("use_case", useCase.json),
            ("sample_message", sampleMessage.json),
            ("documents", documents.json)
        ]
    }
}

/// The `senderIds` resource. Accessed as `opensms.senderIds`.
public final class SenderIds {
    private let http: Transport
    init(_ http: Transport) { self.http = http }

    public func list(_ params: ListParams = ListParams()) async throws -> Page<SenderId> {
        try await http.request("GET", "/v1/sender-ids", query: params.query)
    }

    public func get(_ id: String) async throws -> SenderId {
        try await http.request("GET", "/v1/sender-ids/\(try idSeg(id))")
    }

    /// Register a sender ID. May charge fees (see ``quote(countries:)``), so it is never retried.
    public func create(_ params: CreateSenderIdParams) async throws -> SenderId {
        let body = RequestBody.json([
            ("value", .string(params.value)),
            ("kind", .string(params.kind)),
            ("countries", Optional(params.countries).json),
            ("documents", Optional(params.documents).json),
            ("use_case", params.useCase.json),
            ("sample_message", params.sampleMessage.json),
            ("draft_id", params.draftId.json),
            ("draft_version", params.draftVersion.json),
            ("quote_id", params.quoteId.json)
        ])
        return try await http.request("POST", "/v1/sender-ids", body: body)
    }

    /// Amend a sender ID application.
    public func update(_ id: String, _ params: UpdateSenderIdParams) async throws -> SenderId {
        let body = RequestBody.json([
            ("use_case", .string(params.useCase)),
            ("countries", Optional(params.countries).json),
            ("documents", Optional(params.documents).json),
            ("sample_message", params.sampleMessage.json)
        ])
        return try await http.request("PATCH", "/v1/sender-ids/\(try idSeg(id))", body: body)
    }

    public func delete(_ id: String) async throws {
        try await http.requestVoid("DELETE", "/v1/sender-ids/\(try idSeg(id))")
    }

    /// Check whether a value is valid and available.
    public func check(value: String, country: String? = nil) async throws -> SenderIdCheck {
        try await http.request("GET", "/v1/sender-ids/check", query: [("value", value), ("country", country)])
    }

    /// Registration fee quote; sends `countries=KE,NG`.
    public func quote(countries: [String]) async throws -> SenderIdQuote {
        try await http.request("GET", "/v1/sender-ids/quote", query: [("countries", countries.joined(separator: ","))])
    }

    /// Uploaded sender documents (upload and download are console only).
    public func listDocuments() async throws -> [SenderDocument] {
        let envelope: ItemsEnvelope<SenderDocument> = try await http.request("GET", "/v1/sender-documents")
        return envelope.items
    }

    public func listDrafts(_ params: ListParams = ListParams()) async throws -> Page<SenderIdDraft> {
        try await http.request("GET", "/v1/sender-id-drafts", query: params.query)
    }

    /// Create a draft. Never retried.
    public func createDraft(_ params: SenderIdDraftParams) async throws -> SenderIdDraft {
        let body = RequestBody.json([("source", params.source.json)] + params.fields)
        return try await http.request("POST", "/v1/sender-id-drafts", body: body)
    }

    public func getDraft(_ id: String) async throws -> SenderIdDraft {
        try await http.request("GET", "/v1/sender-id-drafts/\(try idSeg(id))")
    }

    /// Update a draft. `params.version` must be the current version (409 on mismatch).
    public func updateDraft(_ id: String, _ params: SenderIdDraftParams) async throws -> SenderIdDraft {
        guard let version = params.version else {
            throw OpensmsArgumentError("OpenSMS: `version` is required to update a draft.")
        }
        let body = RequestBody.json([("version", .int(version))] + params.fields)
        return try await http.request("PATCH", "/v1/sender-id-drafts/\(try idSeg(id))", body: body)
    }

    public func deleteDraft(_ id: String) async throws {
        try await http.requestVoid("DELETE", "/v1/sender-id-drafts/\(try idSeg(id))")
    }
}
