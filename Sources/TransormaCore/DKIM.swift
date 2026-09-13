import Foundation
import CryptoKit
import Security
import CMailSystem

public protocol TXTResolving: Sendable {
    func records(for name: String) async throws -> [String]
}

/// Uses the system's configured DNS, never a hardcoded third-party resolver.
public struct SystemTXTResolver: TXTResolving {
    public init() {}
    public func records(for name: String) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                var buffer = [CChar](repeating: 0, count: 8192)
                let length = transorma_query_txt(name, &buffer, buffer.count)
                guard length > 0 else { continuation.resume(throwing: MailError.dnsFailure); return }
                let text = String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
                continuation.resume(returning: text.components(separatedBy: "\n").filter { !$0.isEmpty })
            }
        }
    }
}

public struct VerifiedMessage: Sendable {
    public let signingDomain: String
    public let signedHeaders: Set<String>
    public func covers(_ name: String) -> Bool { signedHeaders.contains(name.lowercased()) }
}

public struct DKIMVerifier: Sendable {
    private let resolver: any TXTResolving
    public init(resolver: any TXTResolving = SystemTXTResolver()) { self.resolver = resolver }

    public func verify(_ message: MailDocument, now: Date = .now) async throws -> VerifiedMessage {
        guard let sender = message.sender, let domain = sender.split(separator: "@").last.map(String.init) else {
            throw MailError.invalidSignature
        }
        for header in message.headers.filter({ $0.name == "dkim-signature" }).prefix(3) {
            do {
                let tags = try Self.tags(header.value)
                guard tags["v"] == "1", tags["l"] == nil,
                      let signingDomain = tags["d"]?.lowercased(), signingDomain == domain,
                      let selector = tags["s"], Self.validDNSName(selector), Self.validDNSName(signingDomain),
                      let algorithm = tags["a"], ["rsa-sha256", "ed25519-sha256"].contains(algorithm),
                      tags["q"] == nil || tags["q"] == "dns/txt",
                      let signedList = tags["h"], let bodyHash = tags["bh"], let signature = tags["b"],
                      let signatureData = Self.base64(signature) else { continue }
                if let expires = tags["x"] { guard let time = TimeInterval(expires), time > now.timeIntervalSince1970 else { continue } }
                if let created = tags["t"] { guard let time = TimeInterval(created), time <= now.timeIntervalSince1970 + 300 else { continue } }
                if let identity = tags["i"] {
                    guard let identityDomain = identity.split(separator: "@").last.map(String.init),
                          identityDomain == signingDomain || identityDomain.hasSuffix("." + signingDomain) else { continue }
                }
                let signed = signedList.lowercased().split(separator: ":").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                // All fields used for classification must be signed; duplicates cannot reinterpret a valid signature.
                let required = ["from", "subject", "content-type", "content-transfer-encoding", "list-id", "list-unsubscribe", "list-unsubscribe-post"]
                guard signed.contains("from"), signed.contains("subject"),
                      required.allSatisfy({ message.values($0).count <= 1 && (message.values($0).isEmpty || signed.contains($0)) }) else { continue }
                let canon = (tags["c"] ?? "simple/simple").components(separatedBy: "/")
                let headerMode = canon[0]
                let bodyMode = canon.count == 2 ? canon[1] : "simple"
                guard canon.count <= 2, ["simple", "relaxed"].contains(headerMode), ["simple", "relaxed"].contains(bodyMode),
                      Self.base64(bodyHash) == Data(SHA256.hash(data: Self.canonicalBody(message.body, relaxed: bodyMode == "relaxed"))) else { continue }
                var used = Set<Int>()
                var signedData = Data()
                for name in signed {
                    if let index = message.headers.indices.reversed().first(where: { !used.contains($0) && message.headers[$0].name == name }) {
                        used.insert(index)
                        signedData += Self.canonicalHeader(message.headers[index].raw, relaxed: headerMode == "relaxed") + Data([13, 10])
                    }
                }
                let emptied = try Self.emptySignature(header.raw)
                signedData += Self.canonicalHeader(emptied, relaxed: headerMode == "relaxed")
                let records = try await resolver.records(for: selector + "._domainkey." + signingDomain)
                let keys = records.compactMap { try? Self.tags($0) }.filter { $0["p"] != nil }
                guard keys.count == 1, let keyTags = keys.first,
                      keyTags["v"] == nil || keyTags["v"] == "DKIM1",
                      let encodedKey = keyTags["p"], let keyData = Self.base64(encodedKey), !keyData.isEmpty,
                      !(keyTags["t"] ?? "").split(separator: ":").contains("y"),
                      keyTags["h"] == nil || (keyTags["h"] ?? "").split(separator: ":").contains("sha256"),
                      keyTags["s"] == nil || (keyTags["s"] ?? "").split(separator: ":").contains(where: { $0 == "*" || $0 == "email" }) else { continue }
                let valid: Bool
                if algorithm == "ed25519-sha256" {
                    guard keyTags["k"] == "ed25519" else { continue }
                    let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
                    valid = key.isValidSignature(signatureData, for: Data(SHA256.hash(data: signedData)))
                } else {
                    guard keyTags["k"] == nil || keyTags["k"] == "rsa" else { continue }
                    let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPublic]
                    guard let key = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, nil),
                          SecKeyGetBlockSize(key) >= 128 else { continue }
                    valid = SecKeyVerifySignature(key, .rsaSignatureMessagePKCS1v15SHA256, signedData as CFData, signatureData as CFData, nil)
                }
                if valid { return VerifiedMessage(signingDomain: signingDomain, signedHeaders: Set(signed)) }
            } catch { continue }
        }
        throw MailError.invalidSignature
    }

    static func validDNSName(_ value: String) -> Bool {
        value.utf8.count <= 253 && value.split(separator: ".", omittingEmptySubsequences: false).allSatisfy {
            !$0.isEmpty && $0.utf8.count <= 63 && $0.first != "-" && $0.last != "-" && $0.utf8.allSatisfy {
                (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
            }
        }
    }

    static func tags(_ field: String) throws -> [String: String] {
        var result: [String: String] = [:]
        for part in field.components(separatedBy: ";") {
            if part.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            guard let equal = part.firstIndex(of: "=") else { throw MailError.invalidSignature }
            let key = part[..<equal].trimmingCharacters(in: .whitespacesAndNewlines)
            guard result[key] == nil, !key.isEmpty else { throw MailError.invalidSignature }
            result[key] = part[part.index(after: equal)...].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    static func base64(_ value: String) -> Data? {
        Data(base64Encoded: value.filter { !" \t\r\n".contains($0) })
    }

    static func canonicalHeader(_ raw: Data, relaxed: Bool) -> Data {
        guard relaxed, let colon = raw.firstIndex(of: 58) else { return raw }
        let name = String(decoding: raw[..<colon], as: UTF8.self).lowercased()
        let value = Array(raw[raw.index(after: colon)...]).filter { $0 != 13 && $0 != 10 }
        return Data((name + ":").utf8) + compressWhitespace(Data(value), trimLeading: true)
    }

    static func canonicalBody(_ raw: Data, relaxed: Bool) -> Data {
        var lines = MailDocument.splitLines(raw)
        if relaxed { lines = lines.map { compressWhitespace($0, trimLeading: false) } }
        while lines.last?.isEmpty == true { lines.removeLast() }
        if lines.isEmpty { return relaxed ? Data() : Data([13, 10]) }
        return lines.reduce(into: Data()) { $0 += $1 + Data([13, 10]) }
    }

    static func compressWhitespace(_ raw: Data, trimLeading: Bool) -> Data {
        var output = Data()
        var pending = false
        for byte in raw {
            if byte == 32 || byte == 9 { pending = true }
            else {
                if pending && (!trimLeading || !output.isEmpty) { output.append(32) }
                output.append(byte)
                pending = false
            }
        }
        return output
    }

    static func emptySignature(_ raw: Data) throws -> Data {
        // DKIM headers are ASCII. Preserve folding and all other tag octets, including under simple canonicalization.
        let bytes = Array(raw)
        guard let colon = bytes.firstIndex(of: 58) else { throw MailError.invalidSignature }
        var start = colon + 1
        while start < bytes.count {
            let end = bytes[start...].firstIndex(of: 59) ?? bytes.count
            if let equal = bytes[start..<end].firstIndex(of: 61) {
                let key = String(decoding: bytes[start..<equal], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                if key == "b" { return Data(bytes[...equal]) + Data(bytes[end...]) }
            }
            start = end + 1
        }
        throw MailError.invalidSignature
    }
}
