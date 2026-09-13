import CryptoKit
import Foundation
import Security
import Testing

@testable import TransormaCore

struct FixtureDNS: TXTResolving {
    let record: String
    func records(for name: String) async throws -> [String] { [record] }
}

struct SignedFixture {
    let raw: Data
    let dns: FixtureDNS

    init(
        subject: String = "Summer sale: 40% off", body: String = "Save today. Shop now for our limited time sale.",
        oneClick: Bool = true, algorithm: String = "ed25519-sha256", canonicalization: String = "relaxed/relaxed"
    ) throws {
        var fields = [
            "From: Store <offers@store.example.com>", "To: recipient@example.net", "Subject: \(subject)",
            "Content-Type: text/html; charset=utf-8",
        ]
        if oneClick {
            fields += [
                "List-Unsubscribe: <https://store.example.com/unsubscribe?token=recipient>",
                "List-Unsubscribe-Post: List-Unsubscribe=One-Click",
            ]
        }
        let rawBody = Data((body + "\r\n").utf8)
        let relaxedHeader = canonicalization.hasPrefix("relaxed")
        let relaxedBody = canonicalization.hasSuffix("relaxed")
        let bodyHash = Data(SHA256.hash(data: DKIMVerifier.canonicalBody(rawBody, relaxed: relaxedBody)))
            .base64EncodedString()
        let names = fields.map { $0.components(separatedBy: ":")[0].lowercased() }.joined(separator: ":")
        let dkim =
            "DKIM-Signature: v=1; a=\(algorithm); c=\(canonicalization); d=store.example.com; s=test; h=\(names); bh=\(bodyHash); b="
        var signed = Data()
        for field in fields {
            signed += DKIMVerifier.canonicalHeader(Data(field.utf8), relaxed: relaxedHeader) + Data([13, 10])
        }
        signed += DKIMVerifier.canonicalHeader(Data(dkim.utf8), relaxed: relaxedHeader)
        let signature: Data
        if algorithm == "ed25519-sha256" {
            let key = Curve25519.Signing.PrivateKey()
            dns = FixtureDNS(record: "v=DKIM1; k=ed25519; p=" + key.publicKey.rawRepresentation.base64EncodedString())
            signature = try key.signature(for: Data(SHA256.hash(data: signed)))
        } else {
            let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 2048]
            let key = try #require(SecKeyCreateRandomKey(attributes as CFDictionary, nil))
            let publicKey = try #require(SecKeyCopyPublicKey(key))
            let publicData = try #require(SecKeyCopyExternalRepresentation(publicKey, nil)) as Data
            dns = FixtureDNS(record: "v=DKIM1; k=rsa; p=" + publicData.base64EncodedString())
            signature =
                try #require(SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA256, signed as CFData, nil))
                as Data
        }
        raw =
            Data((([dkim + signature.base64EncodedString()] + fields).joined(separator: "\r\n") + "\r\n\r\n").utf8)
            + rawBody
    }
}

@Test(
    arguments: ["rsa-sha256", "ed25519-sha256"],
    ["simple/simple", "relaxed/relaxed", "relaxed/simple", "simple/relaxed"])
func validatesRealSignatures(algorithm: String, canonicalization: String) async throws {
    let fixture = try SignedFixture(algorithm: algorithm, canonicalization: canonicalization)
    let verified = try await DKIMVerifier(resolver: fixture.dns).verify(MailDocument(raw: fixture.raw))
    #expect(verified.signingDomain == "store.example.com")
    #expect(verified.covers("list-unsubscribe-post"))
}

@Test(arguments: ["body", "link", "from", "duplicate", "length"])
func rejectsTampering(change: String) async throws {
    let fixture = try SignedFixture()
    let original = String(decoding: fixture.raw, as: UTF8.self)
    let modified: String =
        switch change {
        case "body": original + "Added text"
        case "link": original.replacingOccurrences(of: "token=recipient", with: "token=victim")
        case "from": original.replacingOccurrences(of: "offers@store.example.com", with: "offers@bank.example.com")
        case "duplicate": "List-Unsubscribe: <https://evil.example.com/u>\r\n" + original
        default: original.replacingOccurrences(of: "v=1;", with: "v=1; l=0;")
        }
    await #expect(throws: (any Error).self) {
        try await DKIMVerifier(resolver: fixture.dns).verify(MailDocument(raw: Data(modified.utf8)))
    }
}

@Test func ignoresForgedAuthenticationResults() async throws {
    let message = try MailDocument(
        raw: Data(
            "From: offers@store.example.com\r\nSubject: Sale\r\nAuthentication-Results: mx.example; dkim=pass\r\n\r\nShop now"
                .utf8))
    await #expect(throws: (any Error).self) { try await DKIMVerifier(resolver: FixtureDNS(record: "")).verify(message) }
}

@Test func canonicalizationMatchesPublishedRules() {
    #expect(
        DKIMVerifier.canonicalHeader(Data("SUBJect :  A\t B\r\n C  ".utf8), relaxed: true)
            == Data("subject :A B C".utf8))
    #expect(
        DKIMVerifier.canonicalBody(Data(" C \t\r\nD \t E\r\n\r\n".utf8), relaxed: true) == Data(" C\r\nD E\r\n".utf8))
    #expect(DKIMVerifier.canonicalBody(Data(), relaxed: true).isEmpty)
    #expect(DKIMVerifier.canonicalBody(Data(), relaxed: false) == Data([13, 10]))
}
