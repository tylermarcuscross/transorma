import Foundation

/// Coordinates the Mail deadline with persistence: a completed/expired decision cannot enqueue work.
public final class MessageDecisionGate: @unchecked Sendable {
    // The lock protects the callback and the entire synchronous commit. The callback is removed
    // exactly once and invoked outside the lock, so reentrant platform callbacks cannot deadlock.
    private let lock = NSLock()
    private let store: SharedStore
    private let deadline: ContinuousClock.Instant
    private let trace: MessageTrace?
    private var completion: ((Bool) -> Void)?

    public init(
        store: SharedStore,
        deadline: ContinuousClock.Instant = .now.advanced(by: .seconds(20)),
        trace: MessageTrace? = nil,
        completion: @escaping (Bool) -> Void
    ) {
        self.store = store
        self.deadline = deadline
        self.trace = trace
        self.completion = completion
    }

    /// Returns whether this caller owned the decision. Duplicate list requests may still be trashed.
    @discardableResult
    public func resolve(_ candidate: UnsubscribeJob?, timedOut: Bool = false) -> Bool {
        lock.lock()
        guard let completion else {
            lock.unlock()
            return false
        }
        self.completion = nil
        var shouldTrash = false
        var event: ProcessingEvent?
        if let candidate, ContinuousClock.now < deadline, !Task.isCancelled {
            do {
                event = try store.enqueue(candidate) ? .queued : .duplicate
                shouldTrash = true
            } catch MailError.paused {
                event = .paused
            } catch MailError.queueFull {
                event = .queueFull
            } catch {
                // An inaccessible, full, or newly disabled queue preserves the message.
                event = .storageUnavailable
            }
        } else if timedOut || ContinuousClock.now >= deadline {
            event = .deadlineExpired
        } else if Task.isCancelled {
            event = .cancelled
        }
        lock.unlock()
        completion(shouldTrash)
        if let event { trace?.record(event) }
        if shouldTrash { trace?.record(.trashRequested) }
        return true
    }
}
