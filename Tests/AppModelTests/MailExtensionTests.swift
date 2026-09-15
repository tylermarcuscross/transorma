import Foundation
import MailKit
import Testing

@Test func mailCanConstructItsPrincipalAndHandlerOffTheMainActor() async {
    // Compile the actual MailKit adapter sources in the isolated test target.
    // No real Mail connection, App Group, or unsubscribe worker is used.
    await Task.detached {
        let principal = MailExtension()
        let handler = principal.handlerForMessageActions()
        #expect(handler === MessageActionHandler.shared)
        #expect(MessageActionHandler.shared.requiredHeaders.contains("DKIM-Signature"))
    }.value
}
