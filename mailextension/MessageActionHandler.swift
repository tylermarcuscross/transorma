//
//  MessageActionHandler.swift
//  mailextension
//
//  Created by Tyler Cross on 8/6/25.
//

import MailKit
import TransormaCore

final class MessageActionHandler: NSObject, MEMessageActionHandler, @unchecked Sendable {
    static let shared = MessageActionHandler()
    private let store: SharedStore?
    private let engine: ProtectionEngine?
    private let worker: UnsubscribeWorker?

    override init() {
        let store = try? SharedStore.appGroup()
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
        let completion = CompletionOnce(completionHandler)
        let assessment = Task {
            let result = await engine.assess(raw: raw)
            completion.finish(result.shouldTrash ? .action(.moveToTrash) : nil)
            await worker.drain()
        }
        // Complete exactly once, even when inference doesn't promptly observe cancellation.
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 20) {
            if completion.finish(nil) { assessment.cancel() }
        }
    }
}

private final class CompletionOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var callback: ((MEMessageActionDecision?) -> Void)?
    init(_ callback: @escaping (MEMessageActionDecision?) -> Void) { self.callback = callback }
    @discardableResult func finish(_ decision: MEMessageActionDecision?) -> Bool {
        lock.lock()
        let callback = self.callback
        self.callback = nil
        lock.unlock()
        callback?(decision)
        return callback != nil
    }
}
