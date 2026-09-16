import Foundation
import OSLog

/// Closed event codes keep subjects, addresses, message bodies, and URLs out of system logs.
public enum ProcessingEvent: String, Codable, Sendable {
    case received, awaitingBody, assessing, verifyingSignature, classifying, preparingOneClick, preparingWeb
    case notReceived, encrypted, preview, paused, senderExcluded, automatedMessage, noUnsubscribe
    case protectedContent, insufficientPromotionSignals, malformedMessage, invalidSender, oversizedMessage
    case invalidSignature, unsupportedSignature, dnsFailure, modelRejected, modelUnavailable, modelFailed
    case ambiguousUnsubscribe, expiredOrBusy, cancelled, queueFull, storageUnavailable, assessmentFailed
    case queued, duplicate, trashRequested, deadlineExpired

    public var explanation: String {
        switch self {
        case .received: "Mail called the extension."
        case .awaitingBody: "Requested the full message from Mail; waiting for its next callback."
        case .assessing: "Assessing the message."
        case .verifyingSignature: "Verifying the sender's DKIM signature."
        case .classifying: "Classifying with on-device Apple Intelligence."
        case .preparingOneClick: "Verified marketing with a signed one-click unsubscribe."
        case .preparingWeb: "Verified marketing with a supported unsubscribe page."
        case .notReceived: "Preserved: this is not a received message."
        case .encrypted: "Preserved: the message is encrypted."
        case .preview: "Preserved: this is a development preview."
        case .paused: "Preserved: protection is paused."
        case .senderExcluded: "Preserved: the sender is excluded by saved settings."
        case .automatedMessage: "Preserved: an Auto-Submitted header marks automated mail."
        case .noUnsubscribe: "Preserved: no supported HTTPS unsubscribe route."
        case .protectedContent: "Preserved: reply, policy notice, or protected transactional wording."
        case .insufficientPromotionSignals:
            "Preserved: intelligence is off or unavailable and promotion keywords are insufficient."
        case .malformedMessage: "Preserved: the message structure could not be parsed."
        case .invalidSender: "Preserved: the From header did not identify one supported sender address."
        case .oversizedMessage: "Preserved: the message exceeds the 2 MB assessment limit."
        case .invalidSignature: "Preserved: DKIM verification or required signed-header coverage failed."
        case .unsupportedSignature: "Preserved: no supported DKIM signature."
        case .dnsFailure: "Preserved: the signing key could not be retrieved from DNS."
        case .modelRejected: "Preserved: the model did not classify the message as marketing."
        case .modelUnavailable: "Preserved: the model became unavailable during assessment."
        case .modelFailed: "Preserved: model assessment failed."
        case .ambiguousUnsubscribe: "Preserved: unsubscribe routes are ambiguous or need unavailable page assistance."
        case .expiredOrBusy: "Preserved: the assessment deadline or queue capacity was exceeded."
        case .cancelled: "Preserved: assessment was cancelled."
        case .queueFull: "Preserved: the unsubscribe queue is full."
        case .storageUnavailable: "Preserved: shared storage could not be accessed."
        case .assessmentFailed: "Preserved: assessment failed unexpectedly."
        case .queued: "Unsubscribe request saved to the queue."
        case .duplicate: "This unsubscribe is already recorded; no duplicate request was added."
        case .trashRequested: "Returned a Trash action to Mail; Mail does not report whether the move completed."
        case .deadlineExpired: "Preserved: Mail's decision deadline expired."
        }
    }
}

public struct DiagnosticEntry: Codable, Sendable, Identifiable {
    public let id: UUID
    public let traceID: UUID
    public let date: Date
    public let event: ProcessingEvent
    public let elapsedMilliseconds: Int
    public let senderDomain: String?
}

public struct DiagnosticState: Codable, Sendable {
    public var extensionStartedAt: Date?
    public var extensionBuild: String?
    public var callbackCount = 0
    public var entries: [DiagnosticEntry] = []
}

public enum TransormaLog {
    public static let subsystem = "me.tylercross.transorma"
    public static let lifecycle = Logger(subsystem: subsystem, category: "Lifecycle")
    public static let pipeline = Logger(subsystem: subsystem, category: "MailPipeline")
    public static let worker = Logger(subsystem: subsystem, category: "Unsubscribe")
    public static let storage = Logger(subsystem: subsystem, category: "Storage")
    public static let build = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "unknown"
}

/// One callback or diagnostic replay. Replay traces never write to the live app's store.
public final class MessageTrace: Sendable {
    public enum Source: String, Sendable { case mail, replay }
    public let id: UUID
    private let started = ContinuousClock.now
    private let store: SharedStore?
    private let senderDomain: String?
    private let source: Source

    public init(id: UUID = UUID(), store: SharedStore? = nil, senderDomain: String? = nil, source: Source = .replay) {
        self.id = id
        self.store = store
        self.senderDomain = senderDomain.map { String($0.prefix(253)) }
        self.source = source
    }

    public func record(_ event: ProcessingEvent) {
        let duration = started.duration(to: .now).components
        let milliseconds = Int(duration.seconds * 1000 + duration.attoseconds / 1_000_000_000_000_000)
        TransormaLog.pipeline.notice(
            "trace=\(self.id.uuidString, privacy: .public) source=\(self.source.rawValue, privacy: .public) event=\(event.rawValue, privacy: .public) elapsed_ms=\(milliseconds)"
        )
        guard let store else { return }
        do {
            try store.recordDiagnostic(
                DiagnosticEntry(
                    id: UUID(), traceID: id, date: .now, event: event,
                    elapsedMilliseconds: milliseconds, senderDomain: senderDomain))
        } catch {
            // Diagnostics must never change a mail decision or hide an existing queue.
            TransormaLog.storage.error("Could not persist a diagnostic event; inspect the system log.")
        }
    }
}
