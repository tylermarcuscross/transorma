import CMailSystem
import Foundation

/// Uses the system's configured DNS, never a hardcoded third-party resolver.
public struct SystemTXTResolver: TXTResolving {
    public init() {}
    public func records(for name: String) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                var buffer = [CChar](repeating: 0, count: 8192)
                let length = transorma_query_txt(name, &buffer, buffer.count)
                guard length > 0 else {
                    continuation.resume(throwing: MailError.dnsFailure)
                    return
                }
                let text = String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
                continuation.resume(returning: text.components(separatedBy: "\n").filter { !$0.isEmpty })
            }
        }
    }
}
