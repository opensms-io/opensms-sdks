import Foundation

/// A type-erased JSON value for free-form shapes (`metadata`, `attributes`,
/// webhook `payload`, `variables`). Decodes any JSON and re-encodes it
/// faithfully. Supports literals, so `["sdk": "swift", "n": 1]` is a `JSONValue`.
public enum JSONValue: Codable, Equatable, Hashable {
    case string(String)
    case int(Int)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? c.decode(Int.self) {
            self = .int(i)
        } else if let d = try? c.decode(Double.self) {
            self = .number(d)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let o = try? c.decode([String: JSONValue].self) {
            self = .object(o)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .int(let i): try c.encode(i)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .object(let o): try c.encode(o)
        case .array(let a): try c.encode(a)
        case .null: try c.encodeNil()
        }
    }

    /// Member lookup on an object value.
    public subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    /// Element lookup on an array value.
    public subscript(index: Int) -> JSONValue? {
        if case .array(let a) = self, a.indices.contains(index) { return a[index] }
        return nil
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var intValue: Int? {
        switch self {
        case .int(let i): return i
        case .number(let d) where d.rounded() == d: return Int(d)
        default: return nil
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .int(let i): return Double(i)
        case .number(let d): return d
        default: return nil
        }
    }

    public var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }

    public var isNull: Bool { self == .null }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral,
    ExpressibleByDictionaryLiteral, ExpressibleByArrayLiteral, ExpressibleByNilLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .int(value) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(nilLiteral: ()) { self = .null }
}

/// An open string-keyed JSON map.
public typealias JSONObject = [String: JSONValue]

// MARK: - Dates

/// A datetime input: a native `Date` (serialized as RFC 3339 UTC) or a string
/// passed through verbatim (for example `"2026-09-01"`). String literals work
/// directly: `dateFrom: "2026-09-01"`.
public enum DateTimeInput: ExpressibleByStringLiteral, Equatable {
    case date(Date)
    case string(String)

    public init(stringLiteral value: String) { self = .string(value) }

    /// The wire form.
    public var wireValue: String {
        switch self {
        case .string(let s): return s
        case .date(let d): return formatRFC3339(d)
        }
    }

    var json: JSONValue { .string(wireValue) }
}

/// Format a date as RFC 3339 UTC, for example `2026-09-24T10:00:00Z`.
func formatRFC3339(_ date: Date) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    f.timeZone = TimeZone(identifier: "UTC")
    return f.string(from: date)
}

/// Parse an RFC 3339 timestamp with any number of fractional digits and any
/// offset (the API mixes `+03:00`, `+00:00` and `Z`).
func parseRFC3339(_ text: String) -> Date? {
    var base = text
    var fraction = 0.0
    if let dot = text.firstIndex(of: ".") {
        var end = text.index(after: dot)
        while end < text.endIndex, text[end].isNumber { end = text.index(after: end) }
        fraction = Double("0" + text[dot..<end]) ?? 0
        base = String(text[..<dot]) + String(text[end...])
    }
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    guard let date = f.date(from: base) else { return nil }
    return date.addingTimeInterval(fraction)
}

/// The JSON decoder every response goes through.
func makeDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { d in
        let c = try d.singleValueContainer()
        let text = try c.decode(String.self)
        guard let date = parseRFC3339(text) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid RFC 3339 date: \(text)")
        }
        return date
    }
    return decoder
}

// MARK: - Body helpers

extension Optional where Wrapped == String {
    var json: JSONValue? { map(JSONValue.string) }
}

extension Optional where Wrapped == Int {
    var json: JSONValue? { map(JSONValue.int) }
}

extension Optional where Wrapped == Bool {
    var json: JSONValue? { map(JSONValue.bool) }
}

extension Optional where Wrapped == [String] {
    var json: JSONValue? { map { .array($0.map(JSONValue.string)) } }
}

extension Optional where Wrapped == [String: String] {
    var json: JSONValue? { map { .object($0.mapValues(JSONValue.string)) } }
}

extension Optional where Wrapped == JSONObject {
    var json: JSONValue? { map(JSONValue.object) }
}

extension Optional where Wrapped == DateTimeInput {
    var json: JSONValue? { map { $0.json } }
}
