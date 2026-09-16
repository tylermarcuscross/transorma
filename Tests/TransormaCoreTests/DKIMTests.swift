import CryptoKit
import Foundation
import Security
import Testing

@testable import TransormaCore

@Test func unsignedContentDispositionCannotHideSignedMessageContent() async throws {
    let fixture = try SignedFixture(body: "Your receipt. Shop now. Save today.")
    let altered = Data("Content-Disposition: attachment\r\n".utf8) + fixture.raw
    let message = try MailDocument(raw: altered)
    #expect(message.content.html.isEmpty)
    await #expect(throws: MailError.invalidSignature) {
        try await DKIMVerifier(resolver: fixture.dns).verify(message)
    }
}

@Test(arguments: ["inline", "attachment"])
func aSignedContentDispositionIsAcceptedButDuplicatesAreRejected(disposition: String) async throws {
    let fixture = try SignedFixture(contentDisposition: disposition)
    let verifier = DKIMVerifier(resolver: fixture.dns)
    let verified = try await verifier.verify(MailDocument(raw: fixture.raw))
    #expect(verified.covers("content-disposition"))
    let duplicate = try MailDocument(raw: Data("Content-Disposition: inline\r\n".utf8) + fixture.raw)
    await #expect(throws: MailError.invalidSignature) { try await verifier.verify(duplicate) }
}

@Test func resolverCancellationStopsSignatureFallback() async throws {
    let fixture = try SignedFixture()
    let message = try MailDocument(raw: fixture.raw)
    let signature = try #require(message.headers.first(where: { $0.name == "dkim-signature" }))
    let multipleSignatures = try MailDocument(raw: signature.raw + Data([13, 10]) + fixture.raw)
    let resolver = CancellingDNS()
    await #expect(throws: CancellationError.self) {
        try await DKIMVerifier(resolver: resolver).verify(multipleSignatures)
    }
    #expect(await resolver.requests == 1)
}

@Test func cancelledVerificationRejectsALateDNSResult() async throws {
    let fixture = try SignedFixture()
    let message = try MailDocument(raw: fixture.raw)
    let gate = AsyncGate()
    let verifier = DKIMVerifier(resolver: SuspendedDNS(record: fixture.dns.record, gate: gate))
    let task = Task { try await verifier.verify(message) }
    await gate.waitUntilWaiting()
    task.cancel()
    await gate.open()
    await #expect(throws: CancellationError.self) { try await task.value }
}

private actor CancellingDNS: TXTResolving {
    private(set) var requests = 0
    func records(for name: String) async throws -> [String] {
        requests += 1
        throw CancellationError()
    }
}

private struct SuspendedDNS: TXTResolving {
    let record: String
    let gate: AsyncGate
    func records(for name: String) async throws -> [String] {
        await gate.wait()
        return [record]
    }
}

@Test(
    arguments: ["rsa-sha256", "ed25519-sha256"],
    ["simple/simple", "relaxed/relaxed", "relaxed/simple", "simple/relaxed"])
func validatesRealSignatures(algorithm: String, canonicalization: String) async throws {
    let fixture = try SignedFixture(
        subject: "Summer sale:\r\n\t40% off", body: "Save today.\r\nCafé sale.\r\nShop now.",
        algorithm: algorithm, canonicalization: canonicalization)
    for newline in ["\r\n", "\n"] {
        let raw = Data(
            String(decoding: fixture.raw, as: UTF8.self).replacingOccurrences(of: "\r\n", with: newline).utf8)
        let verified = try await DKIMVerifier(resolver: fixture.dns).verify(MailDocument(raw: raw))
        #expect(verified.signingDomain == "store.example.com")
        #expect(verified.covers("list-unsubscribe-post"))
    }
}

@Test(arguments: ["body", "link", "from", "duplicate", "length"], ["\r\n", "\n"])
func rejectsTampering(change: String, newline: String) async throws {
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
        try await DKIMVerifier(resolver: fixture.dns).verify(
            MailDocument(raw: Data(modified.replacingOccurrences(of: "\r\n", with: newline).utf8)))
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
