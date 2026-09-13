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
