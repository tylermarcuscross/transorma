//
//  MailExtension.swift
//  mailextension
//
//  Created by Tyler Cross on 8/6/25.
//

import MailKit

final class MailExtension: NSObject, MEExtension {
    func handlerForMessageActions() -> MEMessageActionHandler {
        return MessageActionHandler.shared
    }

}
