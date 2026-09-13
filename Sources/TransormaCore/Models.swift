import Foundation
import CryptoKit

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
}

public enum JobKind: String, Codable, Sendable { case oneClick, web }
public enum JobStatus: String, Codable, Sendable {
    case pending, processing, accepted, confirmed, unsupported, uncertain, failed, cancelled
    public var label: String {
        switch self {
        case .pending: "Waiting"
        case .processing: "Unsubscribing"
        case .accepted: "Request accepted"
        case .confirmed: "Unsubscribe confirmed"
        case .unsupported: "Could not finish automatically"
        case .uncertain: "Outcome unknown"
        case .failed: "Request failed"
        case .cancelled: "Cancelled"
        }
    }
}

public struct UnsubscribeJob: Codable, Sendable, Identifiable {
    public let id: String
    public let sender: String
    public let kind: JobKind
    public var url: URL?
    public let createdAt: Date
    public var updatedAt: Date
    public var status: JobStatus = .pending
    public var attempts = 0
    public var nextAttempt: Date
    public var detail = "Marketing message detected; unsubscribe queued."

    public init(sender: String, kind: JobKind, url: URL, now: Date = .now) {
        id = Self.digest(sender.lowercased() + "\n" + url.absoluteString)
        self.sender = sender.lowercased()
        self.kind = kind
        self.url = url
        createdAt = now
        updatedAt = now
        nextAttempt = now
    }

    public static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

public enum MailError: Error, Sendable {
    case malformedMessage, unsupportedSignature, invalidSignature, dnsFailure
    case unsafeURL, networkFailure, oversizedResponse, unsupportedPage, unavailable
    case storageUnavailable, corruptStore, queueFull, paused
}

public struct MailAssessment: Sendable {
    public let shouldTrash: Bool
    public let explanation: String
    public init(shouldTrash: Bool, explanation: String) {
        self.shouldTrash = shouldTrash
        self.explanation = explanation
    }
    public static let keep = MailAssessment(shouldTrash: false, explanation: "No automatic action")
}
