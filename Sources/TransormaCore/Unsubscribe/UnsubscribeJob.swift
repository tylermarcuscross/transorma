import CryptoKit
import Foundation

public enum JobKind: String, Codable, Sendable { case oneClick, web }
public enum JobStatus: String, Codable, Sendable {
    case pending, processing, accepted, confirmed, unsupported, uncertain, failed, cancelled
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
