import Foundation

public enum MarketingPolicy {
    public static func isCandidate(subject: String, text: String, hasUnsubscribe: Bool) -> Bool {
        guard hasUnsubscribe else { return false }
        let subject = subject.lowercased()
        let text = text.lowercased()
        let protected = [
            "receipt", "invoice", "order confirmation", "order #", "order number", "your order", "your purchase",
            "payment", "statement", "verification", "verify your", "security", "password", "sign-in", "sign in",
            "login",
            "one-time", "authentication", "shipping", "delivery update", "tracking number", "appointment",
            "reservation",
            "booking confirmation", "account alert", "account update", "renewal", "subscription expires", "refund",
            "prescription", "test results", "medical", "legal notice", "privacy policy", "terms of service",
        ]
        guard !subject.hasPrefix("re:"), !subject.hasPrefix("fwd:"), !subject.hasPrefix("fw:"),
            !protected.contains(where: { subject.contains($0) || text.contains($0) })
        else { return false }
        // A list header alone includes many important newsletters and account notices.
        let promotion = [
            "sale", "discount", "% off", "shop now", "special offer", "limited time", "save today", "coupon",
            "promo code", "new arrivals", "clearance",
        ]
        let signals = promotion.filter { subject.contains($0) || text.contains($0) }
        return signals.count >= 2
    }
}

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

    public func assess(raw: Data) async -> MailAssessment {
        guard activeCount < 2 else { return .keep }
        activeCount += 1
        defer { activeCount -= 1 }
        do {
            let settings = try store.snapshot().settings
            guard settings.enabled else { return .keep }
            let message = try MailDocument(raw: raw)
            guard let sender = message.sender, !settings.allows(sender),
                message.single("auto-submitted") == nil || message.single("auto-submitted")?.lowercased() == "no"
            else { return .keep }
            let content = message.content
            let text = content.text + " " + UnsubscribePage.visibleText(in: content.html)
            let subject = HeaderText.decode(message.single("subject") ?? "")
            let headerLinks = message.single("list-unsubscribe").map(MailDocument.headerURLs) ?? []
            let bodyLinks = UnsubscribePage.emailLinks(in: content.html)
            let candidates = Array(Set((headerLinks + bodyLinks).filter { (try? URLPolicy.validate($0)) != nil }))
            guard MarketingPolicy.isCandidate(subject: subject, text: text, hasUnsubscribe: !candidates.isEmpty) else {
                return .keep
            }
            let verified = try await verifier.verify(message)
            try Task.checkCancellation()
            if settings.useIntelligence && intelligence.available {
                guard try await intelligence.isMarketing(subject: subject, text: text) else { return .keep }
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
                else { return .keep }
                job = UnsubscribeJob(sender: sender, kind: .web, url: url)
            }
            try store.enqueue(job)
            return MailAssessment(shouldTrash: true, explanation: "Verified promotional mail; unsubscribe queued")
        } catch { return .keep }
    }
}

enum HeaderText {
    static func decode(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"=\?([^?]+)\?([bBqQ])\?([^?]*)\?="#) else { return text }
        var result = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            let ns = text as NSString
            let charset = ns.substring(with: match.range(at: 1)).lowercased()
            let mode = ns.substring(with: match.range(at: 2)).lowercased()
            let raw = ns.substring(with: match.range(at: 3))
            let data =
                mode == "b"
                ? Data(base64Encoded: raw)
                : MIMEParser.quotedPrintable(Data(raw.replacingOccurrences(of: "_", with: " ").utf8))
            let encoding: String.Encoding = charset == "iso-8859-1" ? .isoLatin1 : .utf8
            if let data, let decoded = String(data: data, encoding: encoding),
                let range = Range(match.range, in: result)
            {
                result.replaceSubrange(range, with: decoded)
            }
        }
        return result
    }
}
