import Foundation

public struct ProtectionSettings: Codable, Sendable, Equatable {
    public var enabled = false
    public var useIntelligence = true
    public var usePrivateCloud = false
    public var allowedSenders: [String] = []
    public init() {}

    public func allows(_ sender: String) -> Bool {
        let address = sender.lowercased()
        let domain = address.split(separator: "@").last.map(String.init) ?? ""
        return allowedSenders.contains {
            let entry = $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return entry.contains("@") ? address == entry : domain == entry || domain.hasSuffix("." + entry)
        }
    }

    public func permits(_ job: UnsubscribeJob) -> Bool {
        enabled && !allows(job.sender) && (job.kind != .web || useIntelligence)
    }
}
