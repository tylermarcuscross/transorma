import Foundation
import Testing

@testable import TransormaCore

@Test func oneClickRequiresAnUnambiguousHTTPSHeader() throws {
    let raw =
        "From: Store <offers@store.example>\r\nSubject: Sale\r\nList-Unsubscribe: <mailto:unsubscribe@store.example>,\r\n <https://store.example/unsubscribe?t=abc>\r\nList-Unsubscribe-Post: List-Unsubscribe=One-Click\r\n\r\nSave today"
    let message = try MailDocument(raw: Data(raw.utf8))
    #expect(message.sender == "offers@store.example")
    #expect(message.oneClickURL?.host == "store.example")
    let duplicate = raw.replacingOccurrences(of: "Subject: Sale", with: "List-Unsubscribe: <https://other.example/u>")
    #expect(try MailDocument(raw: Data(duplicate.utf8)).oneClickURL == nil)
}

@Test(arguments: ["\r\n", "\n"])
func localAndNetworkLineEndingsParseIdentically(newline: String) throws {
    let raw = [
        "From: Sender <sender@example.com>", "Subject: TEST", "\tfolded subject",
        "Content-Type: text/plain; charset=utf-8", "", "First line.", "Café.", "",
    ].joined(separator: newline)
    let message = try MailDocument(raw: Data(raw.utf8))
    #expect(message.sender == "sender@example.com")
    #expect(message.single("subject") == "TEST\tfolded subject")
    #expect(message.body == Data("First line.\r\nCafé.\r\n".utf8))
    #expect(message.content.text == "First line.\r\nCafé.\r\n")
}

@Test func localLineEndingsPreserveNonUTF8Octets() throws {
    let raw = Data("Content-Type: text/plain; charset=iso-8859-1\n\n".utf8) + Data([0xE9, 10])
    let message = try MailDocument(raw: raw)
    #expect(message.body == Data([0xE9, 13, 10]))
    #expect(message.content.text == "é\r\n")
}

@Test func localLineEndingsDecodeMultipartAndSoftBreaks() throws {
    let raw = [
        "From: sender@example.com", "Content-Type: multipart/alternative; boundary=parts", "",
        "--parts", "Content-Type: text/plain", "", "Plain text.", "--parts",
        "Content-Type: text/html", "Content-Transfer-Encoding: quoted-printable", "",
        "<a href=3D\"https://store.example/u?=", "token=3Dabc\">Unsubscribe</a>", "--parts--", "",
    ].joined(separator: "\n")
    let message = try MailDocument(raw: Data(raw.utf8))
    #expect(message.content.text.contains("Plain text."))
    #expect(message.content.html.contains("https://store.example/u?token=abc"))
}

@Test(arguments: [
    "From: sender@example.com\r\nSubject: TEST\n\nBody",
    "From: sender@example.com\r\nSubject: TEST\r\n folded\nBad: header\r\n\r\nBody",
    "From: sender@example.com\r\n\r\nMixed\nbody",
    "From: sender@example.com\rSubject: TEST\r\rBody",
    "From: sender@example.com\r\n\r\nBody\r",
    "Invalid header\n\nBody",
    " orphaned continuation\n\nBody",
])
func malformedHeadersFailClosed(raw: String) {
    #expect(throws: MailError.malformedMessage) { try MailDocument(raw: Data(raw.utf8)) }
}

@Test func lineEndingExpansionRespectsMessageLimit() {
    let raw = Data("From: sender@example.com\n\n".utf8) + Data(repeating: 10, count: 1_000_000)
    #expect(raw.count < 2_000_000)
    #expect(throws: MailError.malformedMessage) { try MailDocument(raw: raw) }
}

@Test func quotedPrintableUnsubscribeIsDecoded() throws {
    let message = try MailDocument(
        raw: Data(
            "Content-Type: text/html; charset=utf-8\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\n<a href=3D\"https://shop.example/u?token=3Dabc\">Unsubscribe</a>"
                .utf8))
    #expect(message.content.html.contains("token=abc"))
}
