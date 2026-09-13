import Foundation
import Testing

@testable import TransormaCore

@Test func actionPayloadRedactsVisibleIdentifiersAndExcludesRequestSecrets() throws {
    let url = try #require(URL(string: "https://store.example.com/u?token=private-base-token"))
    let html = """
        <p>Mail preferences for recipient@example.com</p>
        <a href='/finish?token=private-link-token'>Unsubscribe recipient@example.com at https://store.example.com/private-label-token</a>
        <form action='/submit' method=post>
          <input type=hidden name=token value=private-form-token>
          <button type=submit>Unsubscribe subscriber+campaign@example.net</button>
        </form>
        """
    let page = try UnsubscribePage(html: html, baseURL: url)
    #expect(page.actions.count == 2)
    let payload = try AppleIntelligence.actionPayload(for: page)
    let fields = try #require(try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: String])

    #expect(fields["pageText"]?.contains("Mail preferences for [redacted]") == true)
    #expect(fields["actions"]?.contains("ID 0: Unsubscribe [redacted] at [redacted]") == true)
    #expect(fields["actions"]?.contains("ID 1: Unsubscribe [redacted]") == true)
    for secret in [
        "recipient@example.com", "subscriber+campaign@example.net", "private-base-token", "private-link-token",
        "private-label-token", "private-form-token",
    ] {
        #expect(!payload.contains(secret))
    }
}
