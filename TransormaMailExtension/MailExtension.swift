import MailKit
import TransormaCore

final class MailExtension: NSObject, MEExtension {
    // MEExtension imports as MainActor, but Mail instantiates and calls this
    // non-UI entry point on its XPC queue. These methods must not assert a UI executor.
    nonisolated override init() {
        super.init()
        TransormaLog.lifecycle.notice(
            "Mail extension principal initialized build=\(TransormaLog.build, privacy: .public)")
    }

    nonisolated func handlerForMessageActions() -> MEMessageActionHandler {
        MessageActionHandler.shared
    }
}
