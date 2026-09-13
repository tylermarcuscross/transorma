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

@Test func malformedHeadersFailClosed() {
    #expect(throws: (any Error).self) { try MailDocument(raw: Data("From: sender@example.com\n\nBody".utf8)) }
}

@Test func quotedPrintableUnsubscribeIsDecoded() throws {
    let message = try MailDocument(
        raw: Data(
            "Content-Type: text/html; charset=utf-8\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\n<a href=3D\"https://shop.example/u?token=3Dabc\">Unsubscribe</a>"
                .utf8))
    #expect(message.content.html.contains("token=abc"))
}
