import Foundation

public actor ProtectionEngine {
    private let store: SharedStore
    private let verifier: DKIMVerifier
    private let intelligence: any MailIntelligence
    private var activeCount = 0
    private var waiting: [WaitingAssessment] = []
    private var waitingBytes = 0

    private struct WaitingAssessment {
        let id: UUID
        let byteCount: Int
        let deadline: ContinuousClock.Instant
        let continuation: CheckedContinuation<Bool, Never>
        let timeout: Task<Void, Never>
    }

    var pendingAssessmentCount: Int { waiting.count }

    public init(
        store: SharedStore, verifier: DKIMVerifier = DKIMVerifier(),
        intelligence: any MailIntelligence = AppleIntelligence()
    ) {
        self.store = store
        self.verifier = verifier
        self.intelligence = intelligence
    }

    /// Verifies and prepares an unsubscribe request without writing state or touching the sender's server.
    /// The MailKit adapter commits it only while its message decision is still open.
    public func prepare(
        raw: Data, deadline: ContinuousClock.Instant = .now.advanced(by: .seconds(20)),
        trace: MessageTrace = MessageTrace()
    ) async -> UnsubscribeJob? {
        func preserve(_ event: ProcessingEvent) -> UnsubscribeJob? {
            trace.record(event)
            return nil
        }
        trace.record(.assessing)
        guard raw.count <= 2_000_000 else { return preserve(.oversizedMessage) }
        guard await acquireSlot(byteCount: raw.count, deadline: deadline) else { return preserve(.expiredOrBusy) }
        defer { releaseSlot() }
        var stage = ProcessingEvent.assessing
        do {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { return preserve(.deadlineExpired) }
            let settings = try store.snapshot().settings
            guard settings.enabled else { return preserve(.paused) }
            let message = try MailDocument(raw: raw)
            guard let sender = message.sender else { return preserve(.malformedMessage) }
            guard !settings.allows(sender) else { return preserve(.senderExcluded) }
            guard message.single("auto-submitted") == nil || message.single("auto-submitted")?.lowercased() == "no"
            else { return preserve(.automatedMessage) }
            let content = message.content
            let text = content.text + " " + UnsubscribePage.visibleText(in: content.html)
            let subject = HeaderText.decode(message.single("subject") ?? "")
            let headerLinks = message.single("list-unsubscribe").map(MailDocument.headerURLs) ?? []
            let bodyLinks = UnsubscribePage.emailLinks(in: content.html)
            let candidates = Array(Set((headerLinks + bodyLinks).filter { (try? URLPolicy.validate($0)) != nil }))
            let usingIntelligence = settings.useIntelligence && intelligence.available
            if let reason = MarketingPolicy.rejectionReason(
                subject: subject, text: text, hasUnsubscribe: !candidates.isEmpty,
                usingIntelligence: usingIntelligence)
            {
                return preserve(reason)
            }
            stage = .verifyingSignature
            trace.record(stage)
            let verified = try await verifier.verify(message)
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { return preserve(.deadlineExpired) }
            if usingIntelligence {
                stage = .classifying
                trace.record(stage)
                guard try await intelligence.isMarketing(subject: subject, text: text) else {
                    return preserve(.modelRejected)
                }
            }
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { return preserve(.deadlineExpired) }
            var job: UnsubscribeJob
            if let url = message.oneClickURL, verified.covers("list-unsubscribe"),
                verified.covers("list-unsubscribe-post")
            {
                try URLPolicy.validate(url)
                job = UnsubscribeJob(sender: sender, kind: .oneClick, url: url)
                trace.record(.preparingOneClick)
            } else {
                // One unambiguous signed URL, or one explicit link in the fully signed body.
                guard settings.useIntelligence, intelligence.available, candidates.count == 1,
                    let url = candidates.first
                else { return preserve(.ambiguousUnsubscribe) }
                job = UnsubscribeJob(sender: sender, kind: .web, url: url)
                trace.record(.preparingWeb)
            }
            job.traceID = trace.id
            return job
        } catch is CancellationError {
            return preserve(.cancelled)
        } catch let error as MailError {
            switch error {
            case .malformedMessage: return preserve(.malformedMessage)
            case .unsupportedSignature: return preserve(.unsupportedSignature)
            case .invalidSignature: return preserve(.invalidSignature)
            case .dnsFailure: return preserve(.dnsFailure)
            case .unavailable: return preserve(.modelUnavailable)
            case .storageUnavailable, .corruptStore: return preserve(.storageUnavailable)
            default: return preserve(stage == .classifying ? .modelFailed : .assessmentFailed)
            }
        } catch {
            return preserve(stage == .classifying ? .modelFailed : .assessmentFailed)
        }
    }

    /// Mail may deliver a burst after reopening. Wait fairly within each callback's
    /// deadline instead of dropping every message beyond the two active assessments.
    private func acquireSlot(byteCount: Int, deadline: ContinuousClock.Instant) async -> Bool {
        guard !Task.isCancelled, ContinuousClock.now < deadline else { return false }
        if activeCount < 2 {
            activeCount += 1
            return true
        }
        guard waiting.count < 32, waitingBytes + byteCount <= 8_000_000 else { return false }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: false)
                    return
                }
                let timeout = Task { [weak self] in
                    do { try await Task.sleep(until: deadline, clock: .continuous) } catch { return }
                    await self?.cancelWaiting(id)
                }
                waiting.append(
                    WaitingAssessment(
                        id: id, byteCount: byteCount, deadline: deadline, continuation: continuation, timeout: timeout))
                waitingBytes += byteCount
            }
        } onCancel: {
            Task { await self.cancelWaiting(id) }
        }
    }

    private func cancelWaiting(_ id: UUID) {
        guard let index = waiting.firstIndex(where: { $0.id == id }) else { return }
        let assessment = waiting.remove(at: index)
        waitingBytes -= assessment.byteCount
        assessment.timeout.cancel()
        assessment.continuation.resume(returning: false)
    }

    private func releaseSlot() {
        activeCount -= 1
        while !waiting.isEmpty {
            let assessment = waiting.removeFirst()
            waitingBytes -= assessment.byteCount
            assessment.timeout.cancel()
            guard ContinuousClock.now < assessment.deadline else {
                assessment.continuation.resume(returning: false)
                continue
            }
            activeCount += 1
            assessment.continuation.resume(returning: true)
            break
        }
    }
}
