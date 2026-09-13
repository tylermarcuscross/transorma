import Foundation

public actor ProtectionEngine {
    private let store: SharedStore
    private let verifier: DKIMVerifier
    private let intelligence: any MailIntelligence
    private var activeCount = 0

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
    public func prepare(raw: Data) async -> UnsubscribeJob? {
        guard activeCount < 2 else { return nil }
        activeCount += 1
        defer { activeCount -= 1 }
        do {
            let settings = try store.snapshot().settings
            guard settings.enabled else { return nil }
            let message = try MailDocument(raw: raw)
            guard let sender = message.sender, !settings.allows(sender),
                message.single("auto-submitted") == nil || message.single("auto-submitted")?.lowercased() == "no"
            else { return nil }
            let content = message.content
            let text = content.text + " " + UnsubscribePage.visibleText(in: content.html)
            let subject = HeaderText.decode(message.single("subject") ?? "")
            let headerLinks = message.single("list-unsubscribe").map(MailDocument.headerURLs) ?? []
            let bodyLinks = UnsubscribePage.emailLinks(in: content.html)
            let candidates = Array(Set((headerLinks + bodyLinks).filter { (try? URLPolicy.validate($0)) != nil }))
            guard MarketingPolicy.isCandidate(subject: subject, text: text, hasUnsubscribe: !candidates.isEmpty) else {
                return nil
            }
            let verified = try await verifier.verify(message)
            try Task.checkCancellation()
            if settings.useIntelligence && intelligence.available {
                guard try await intelligence.isMarketing(subject: subject, text: text) else { return nil }
            }
            try Task.checkCancellation()
            let job: UnsubscribeJob
            if let url = message.oneClickURL, verified.covers("list-unsubscribe"),
                verified.covers("list-unsubscribe-post")
            {
                try URLPolicy.validate(url)
                job = UnsubscribeJob(sender: sender, kind: .oneClick, url: url)
            } else {
                // One unambiguous signed URL, or one explicit link in the fully signed body.
                guard settings.useIntelligence, intelligence.available, candidates.count == 1,
                    let url = candidates.first
                else { return nil }
                job = UnsubscribeJob(sender: sender, kind: .web, url: url)
            }
            return job
        } catch { return nil }
    }
}
