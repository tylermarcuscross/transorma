import MailKit
import TransormaCore

final class MessageActionHandler: NSObject, MEMessageActionHandler, @unchecked Sendable {
    // All dependencies are immutable, thread-safe services; Mail can invoke the handler concurrently.
    static let shared = MessageActionHandler()
    private let store: SharedStore?
    private let engine: ProtectionEngine?
    private let worker: UnsubscribeWorker?

    override init() {
        #if TRANSORMA_DEVELOPMENT
            // Local UI builds never attach a worker to a mailbox, even if manually enabled in Mail.
            let store: SharedStore? = nil
        #else
            let store = try? SharedStore.appGroup()
        #endif
        self.store = store
        engine = store.map { ProtectionEngine(store: $0) }
        worker = store.map { UnsubscribeWorker(store: $0) }
        super.init()
    }

    var requiredHeaders: [String] {
        ["List-Unsubscribe", "List-Unsubscribe-Post", "List-ID", "DKIM-Signature", "Auto-Submitted"]
    }

    func decideAction(for message: MEMessage, completionHandler: @escaping (MEMessageActionDecision?) -> Void) {
        guard message.state == .received, message.encryptionState != .encrypted,
            let store, let engine, let worker
        else {
            completionHandler(nil)
            return
        }
        try? store.heartbeat()
        guard let settings = try? store.snapshot().settings, settings.enabled else {
            completionHandler(nil)
            return
        }
        guard let raw = message.rawData else {
            completionHandler(.invokeAgainWithBody)
            return
        }
        let completion = MessageDecisionGate(store: store) { shouldTrash in
            completionHandler(shouldTrash ? .action(.moveToTrash) : nil)
        }
        let assessment = Task {
            let candidate = await engine.prepare(raw: raw)
            if completion.resolve(candidate) { await worker.drain() }
        }
        // Complete exactly once, even when inference doesn't promptly observe cancellation.
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 20) {
            if completion.resolve(nil) { assessment.cancel() }
        }
    }
}
