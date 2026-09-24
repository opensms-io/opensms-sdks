import Foundation

#if canImport(CryptoKit)
import CryptoKit
#endif

/// Webhook signature verification. Mirrors the server
/// (`internal/webhooks/signature.go`): header
/// `X-OpenSMS-Signature: t=<unix>,v1=<hex>` where
/// `v1 = hex(HMAC-SHA256(secret, "<t>.<raw body>"))`, keyed with the full
/// `whsec_...` secret as UTF-8 bytes.
///
/// Needs no API key, so a webhook receiver can use it directly:
///
/// ```swift
/// let event = try OpensmsWebhooks.constructEvent(payload: body, header: sig, secret: secret)
/// ```
public enum OpensmsWebhooks {
    /// The header the API signs deliveries with.
    public static let signatureHeader = "X-OpenSMS-Signature"
    /// Default accepted clock skew in seconds.
    public static let defaultTolerance: TimeInterval = 300

    enum Outcome: Equatable { case valid, invalid, expired }

    /// Returns `true` when `header` is a valid, unexpired signature of
    /// `payload` (the exact raw bytes received) under `secret`.
    public static func verifySignature(
        payload: Data,
        header: String,
        secret: String,
        toleranceSeconds: TimeInterval = defaultTolerance,
        now: Date = Date()
    ) -> Bool {
        check(payload: payload, header: header, secret: secret, tolerance: toleranceSeconds, now: now) == .valid
    }

    /// String convenience for ``verifySignature(payload:header:secret:toleranceSeconds:now:)``.
    public static func verifySignature(
        payload: String,
        header: String,
        secret: String,
        toleranceSeconds: TimeInterval = defaultTolerance,
        now: Date = Date()
    ) -> Bool {
        verifySignature(payload: Data(payload.utf8), header: header, secret: secret,
                        toleranceSeconds: toleranceSeconds, now: now)
    }

    /// Verify, then decode the event envelope. Throws ``OpensmsError`` with
    /// `status == 0` and `code` `invalid_signature` or `expired_signature`.
    public static func constructEvent(
        payload: Data,
        header: String,
        secret: String,
        toleranceSeconds: TimeInterval = defaultTolerance,
        now: Date = Date()
    ) throws -> WebhookEvent {
        switch check(payload: payload, header: header, secret: secret, tolerance: toleranceSeconds, now: now) {
        case .invalid:
            throw OpensmsError(status: 0, code: "invalid_signature", message: "OpenSMS: invalid webhook signature")
        case .expired:
            throw OpensmsError(status: 0, code: "expired_signature", message: "OpenSMS: webhook signature timestamp is outside the tolerance")
        case .valid:
            do {
                return try makeDecoder().decode(WebhookEvent.self, from: payload)
            } catch {
                throw OpensmsError(status: 0, code: "invalid_payload", message: "OpenSMS: webhook payload is not a valid event: \(error)")
            }
        }
    }

    /// String convenience for ``constructEvent(payload:header:secret:toleranceSeconds:now:)``.
    public static func constructEvent(
        payload: String,
        header: String,
        secret: String,
        toleranceSeconds: TimeInterval = defaultTolerance,
        now: Date = Date()
    ) throws -> WebhookEvent {
        try constructEvent(payload: Data(payload.utf8), header: header, secret: secret,
                           toleranceSeconds: toleranceSeconds, now: now)
    }

    // MARK: Internals

    static func check(payload: Data, header: String, secret: String, tolerance: TimeInterval, now: Date) -> Outcome {
        if secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || tolerance < 0 { return .invalid }
        guard let values = parseHeader(header),
              let tText = values["t"], let v1 = values["v1"],
              let timestamp = Int64(tText) else { return .invalid }
        let skew = now.timeIntervalSince1970 - Double(timestamp)
        if abs(skew) > tolerance { return .expired }
        guard let want = decodeHex(v1), want.count == 32 else { return .invalid }
        var message = Data(tText.utf8)
        message.append(UInt8(ascii: "."))
        message.append(payload)
        let got = hmacSHA256(key: Data(secret.utf8), message: message)
        return constantTimeEqual(got, want) ? .valid : .invalid
    }

    /// Split on `,`, trim each part, split on the first `=`; reject empty keys
    /// or values, duplicates, and anything but exactly `t` and `v1`.
    static func parseHeader(_ header: String) -> [String: String]? {
        var values: [String: String] = [:]
        for part in header.split(separator: ",", omittingEmptySubsequences: false) {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let eq = trimmed.firstIndex(of: "=") else { return nil }
            let key = String(trimmed[..<eq])
            let value = String(trimmed[trimmed.index(after: eq)...])
            if key.isEmpty || value.isEmpty || values[key] != nil { return nil }
            values[key] = value
        }
        guard values.count == 2, values["t"] != nil, values["v1"] != nil else { return nil }
        return values
    }

    static func decodeHex(_ text: String) -> [UInt8]? {
        let chars = Array(text.utf8)
        guard chars.count % 2 == 0 else { return nil }
        var out: [UInt8] = []
        out.reserveCapacity(chars.count / 2)
        var i = 0
        while i < chars.count {
            guard let hi = nibble(chars[i]), let lo = nibble(chars[i + 1]) else { return nil }
            out.append(hi << 4 | lo)
            i += 2
        }
        return out
    }

    private static func nibble(_ c: UInt8) -> UInt8? {
        switch c {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return c - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return c - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): return c - UInt8(ascii: "A") + 10
        default: return nil
        }
    }

    static func constantTimeEqual(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<a.count { diff |= a[i] ^ b[i] }
        return diff == 0
    }

    /// HMAC-SHA256 (CryptoKit where available, portable fallback elsewhere).
    static func hmacSHA256(key: Data, message: Data) -> [UInt8] {
        #if canImport(CryptoKit)
        let mac = HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: key))
        return Array(mac)
        #else
        return PortableHMAC.sha256(key: Array(key), message: Array(message))
        #endif
    }
}

/// Dependency-free HMAC-SHA256 (RFC 2104 / FIPS 180-4) for platforms without
/// CryptoKit (Linux). Always compiled so the unit tests exercise it too.
enum PortableHMAC {
    static func sha256(key: [UInt8], message: [UInt8]) -> [UInt8] {
        let blockSize = 64
        var k = key.count > blockSize ? digest(key) : key
        k += [UInt8](repeating: 0, count: blockSize - k.count)
        let ipad = k.map { $0 ^ 0x36 }
        let opad = k.map { $0 ^ 0x5c }
        return digest(opad + digest(ipad + message))
    }

    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
    ]

    static func digest(_ input: [UInt8]) -> [UInt8] {
        var h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                           0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
        var msg = input
        let bitLength = UInt64(input.count) * 8
        msg.append(0x80)
        while msg.count % 64 != 56 { msg.append(0) }
        for i in (0..<8).reversed() { msg.append(UInt8(truncatingIfNeeded: bitLength >> (UInt64(i) * 8))) }

        func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }
        var w = [UInt32](repeating: 0, count: 64)
        for chunk in stride(from: 0, to: msg.count, by: 64) {
            for i in 0..<16 {
                let j = chunk + i * 4
                w[i] = UInt32(msg[j]) << 24 | UInt32(msg[j + 1]) << 16 | UInt32(msg[j + 2]) << 8 | UInt32(msg[j + 3])
            }
            for i in 16..<64 {
                let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
                let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }
            var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7]
            for i in 0..<64 {
                let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                let ch = (e & f) ^ (~e & g)
                let t1 = hh &+ s1 &+ ch &+ k[i] &+ w[i]
                let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let t2 = s0 &+ maj
                hh = g; g = f; f = e; e = d &+ t1
                d = c; c = b; b = a; a = t1 &+ t2
            }
            h[0] = h[0] &+ a; h[1] = h[1] &+ b; h[2] = h[2] &+ c; h[3] = h[3] &+ d
            h[4] = h[4] &+ e; h[5] = h[5] &+ f; h[6] = h[6] &+ g; h[7] = h[7] &+ hh
        }
        var out: [UInt8] = []
        for v in h { for s in stride(from: 24, through: 0, by: -8) { out.append(UInt8(truncatingIfNeeded: v >> UInt32(s))) } }
        return out
    }
}
