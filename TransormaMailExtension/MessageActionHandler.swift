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
            let store: SharedStore?
            do {
                store = try SharedStore.appGroup()
            } catch {
                TransormaLog.storage.error("Extension cannot open its App Group; mail will be preserved.")
                store = nil
            }
        #endif
        self.store = store
        engine = store.map { ProtectionEngine(store: $0) }
        worker = store.map { UnsubscribeWorker(store: $0) }
        super.init()
        TransormaLog.lifecycle.notice(
            "Mail handler initialized build=\(TransormaLog.build, privacy: .public) storage_ready=\(store != nil)")
        do { try store?.recordExtensionStart() } catch {
            TransormaLog.storage.error("Could not record extension startup.")
        }
    }

    var requiredHeaders: [String] {
        ["List-Unsubscribe", "List-Unsubscribe-Post", "List-ID", "DKIM-Signature", "Auto-Submitted"]
    }

    func decideAction(for message: MEMessage, completionHandler: @escaping (MEMessageActionDecision?) -> Void) {
        let domain = message.fromAddress.addressString?.split(separator: "@").last.map(String.init)
        let trace = MessageTrace(store: store, senderDomain: domain, source: .mail)
        trace.record(.received)
        func preserve(_ event: ProcessingEvent) {
            trace.record(event)
            completionHandler(nil)
        }
        #if TRANSORMA_DEVELOPMENT
            preserve(.preview)
            return
        #else
            guard message.state == .received else {
                preserve(.notReceived)
                return
            }
            guard message.encryptionState != .encrypted else {
                preserve(.encrypted)
                return
            }
            guard let store, let engine, let worker else {
                preserve(.storageUnavailable)
                return
            }
            do {
                guard try store.snapshot().settings.enabled else {
                    preserve(.paused)
                    return
                }
            } catch {
                preserve(.storageUnavailable)
                return
            }
            guard let raw = message.rawData else {
                trace.record(.awaitingBody)
                completionHandler(.invokeAgainWithBody)
                return
            }
            // Catch-up messages use the same download callback as newly arriving mail.
            // The deadline includes any wait behind other assessments in the burst.
            let deadline = ContinuousClock.now.advanced(by: .seconds(20))
            let completion = MessageDecisionGate(store: store, deadline: deadline, trace: trace) { shouldTrash in
                completionHandler(shouldTrash ? .action(.moveToTrash) : nil)
            }
            let assessment = Task {
                let candidate = await engine.prepare(raw: raw, deadline: deadline, trace: trace)
                if completion.resolve(candidate) { await worker.drain() }
            }
            // Complete exactly once, even when inference doesn't promptly observe cancellation.
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 20) {
                if completion.resolve(nil, timedOut: true) { assessment.cancel() }
            }
        #endif
    }
}
