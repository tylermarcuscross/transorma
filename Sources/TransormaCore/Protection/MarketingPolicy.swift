import Foundation

public enum MarketingPolicy {
    public static func isCandidate(
        subject: String, text: String, hasUnsubscribe: Bool, usingIntelligence: Bool = false
    ) -> Bool {
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
            "prescription", "test results", "medical", "legal notice",
        ]
        guard !subject.hasPrefix("re:"), !subject.hasPrefix("fwd:"), !subject.hasPrefix("fw:"),
            !protected.contains(where: { subject.contains($0) || text.contains($0) })
        else { return false }
        let policyTopics = ["privacy policy", "terms of service"]
        guard !policyTopics.contains(where: { subject.contains($0) || (!usingIntelligence && text.contains($0)) })
        else { return false }
        if usingIntelligence { return true }
        let promotion = [
            "sale", "discount", "% off", "shop now", "special offer", "limited time", "save today", "coupon",
            "promo code", "new arrivals", "clearance",
        ]
        let signals = promotion.filter { subject.contains($0) || text.contains($0) }
        return signals.count >= 2
    }
}
