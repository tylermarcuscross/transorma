// Published interoperability vector: RFC 8463, Appendix A.
// Copyright (c) 2018 IETF Trust and the persons identified as the document authors.
// See Docs/THIRD_PARTY_NOTICES.md for the Simplified BSD license for these code components.
import Foundation
import Testing

@testable import TransormaCore

@Test(arguments: ["ed25519", "rsa"])
func validatesPublishedRFC8463Signature(algorithm: String) async throws {
    let signature: String
    let key: String
    if algorithm == "ed25519" {
        signature = """
            DKIM-Signature: v=1; a=ed25519-sha256; c=relaxed/relaxed;
             d=football.example.com; i=@football.example.com;
             q=dns/txt; s=brisbane; t=1528637909; h=from : to :
             subject : date : message-id : from : subject : date;
             bh=2jUSOH9NhtVGCQWNr9BrIAPreKQjO6Sn7XIkfJVOzv8=;
             b=/gCrinpcQOoIfuHNQIbq4pgh9kyIK3AQUdt9OdqQehSwhEIug4D11Bus
             Fa3bT3FY5OsU7ZbnKELq+eXdp1Q1Dw==
            """
        key = "v=DKIM1; k=ed25519; p=11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo="
    } else {
        signature = """
            DKIM-Signature: v=1; a=rsa-sha256; c=relaxed/relaxed;
             d=football.example.com; i=@football.example.com;
             q=dns/txt; s=test; t=1528637909; h=from : to : subject :
             date : message-id : from : subject : date;
             bh=2jUSOH9NhtVGCQWNr9BrIAPreKQjO6Sn7XIkfJVOzv8=;
             b=F45dVWDfMbQDGHJFlXUNB2HKfbCeLRyhDXgFpEL8GwpsRe0IeIixNTe3
             DhCVlUrSjV4BwcVcOF6+FF3Zo9Rpo1tFOeS9mPYQTnGdaSGsgeefOsk2Jz
             dA+L10TeYt9BgDfQNZtKdN1WO//KgIqXP7OdEFE4LjFYNcUxZQ4FADY+8=
            """
        key =
            "v=DKIM1; k=rsa; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDkHlOQoBTzWRiGs5V6NpP3idY6Wk08a5qhdR6wy5bdOKb2jLQiY/J16JYi0Qvx/byYzCNb3W91y3FutACDfzwQ/BC/e/8uBsCR+yz1Lxj+PL6lHvqMKrM3rG4hstT5QjvHO9PzoxZyVYLzBfO2EeC3Ip3G+2kryOTIKT+l/K4w3QIDAQAB"
    }
    let message =
        signature + "\n" + """
            From: Joe SixPack <joe@football.example.com>
            To: Suzie Q <suzie@shopping.example.net>
            Subject: Is dinner ready?
            Date: Fri, 11 Jul 2003 21:00:37 -0700 (PDT)
            Message-ID: <20030712040037.46341.5F8J@football.example.com>

            Hi.

            We lost the game.  Are you hungry yet?

            Joe.
            """ + "\n\n"
    let parsed = try MailDocument(raw: Data(message.replacingOccurrences(of: "\n", with: "\r\n").utf8))
    let verified = try await DKIMVerifier(resolver: FixtureDNS(record: key)).verify(parsed)
    #expect(verified.signingDomain == "football.example.com")
}
