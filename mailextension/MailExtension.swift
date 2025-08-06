//
//  MailExtension.swift
//  mailextension
//
//  Created by Tyler Cross on 8/6/25.
//

import MailKit

class MailExtension: NSObject, MEExtension {
    func handlerForContentBlocker() -> MEContentBlocker {
        // Use a shared instance for all messages, since there's
        // no state associated with a content blocker.
        return ContentBlocker.shared
    }

    func handlerForMessageActions() -> MEMessageActionHandler {
        // Use a shared instance for all messages, since there's
        // no state associated with performing actions.
        return MessageActionHandler.shared
    }

    func handler(for session: MEComposeSession) -> MEComposeSessionHandler {
        // Create a unique instance, since each compose window is separate.
        return ComposeSessionHandler()
    }

    func handlerForMessageSecurity() -> MEMessageSecurityHandler {
        // Use a shared instance for all messages, since there's
        // no state associated with the security handler.
        return MessageSecurityHandler.shared
    }

}

