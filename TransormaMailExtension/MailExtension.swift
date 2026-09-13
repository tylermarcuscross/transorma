import MailKit

final class MailExtension: NSObject, MEExtension {
    func handlerForMessageActions() -> MEMessageActionHandler {
        MessageActionHandler.shared
    }
}
