import Darwin
import Foundation
import Network
import Security

/// Pins the connection to a validated public IP while verifying TLS against the original hostname.
/// No cookies, credentials, referrers, proxy auto-configuration, or implicit redirects are sent.
public struct PublicHTTPSClient: HTTPTransport {
    public init() {}
    public func send(_ request: HTTPRequest, authorize: @escaping @Sendable () throws -> Void) async throws
        -> HTTPResponse
    {
        try Task.checkCancellation()
        try authorize()
        try URLPolicy.validate(request.url)
        guard let host = request.url.host,
            (request.body?.count ?? 0) <= 32_000
        else { throw MailError.unsafeURL }
        let addresses = try await Self.resolve(host)
        guard !addresses.isEmpty, addresses.allSatisfy(URLPolicy.isPublicAddress), let address = addresses.first else {
            throw MailError.unsafeURL
        }
        try Task.checkCancellation()
        let exchange = HTTPSExchange(host: host, address: address)
        let wire = try Self.encode(request)
        return try await withTaskCancellationHandler {
            try await exchange.run(wire, authorize: authorize)
        } onCancel: {
            exchange.cancel()
        }
    }

    static func resolve(_ host: String) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                var hints = addrinfo()
                hints.ai_family = AF_UNSPEC
                hints.ai_socktype = SOCK_STREAM
                var answer: UnsafeMutablePointer<addrinfo>?
                guard getaddrinfo(host, "443", &hints, &answer) == 0, let first = answer else {
                    continuation.resume(throwing: MailError.dnsFailure)
                    return
                }
                defer { freeaddrinfo(first) }
                var addresses: [String] = []
                var cursor: UnsafeMutablePointer<addrinfo>? = first
                while let entry = cursor {
                    var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(
                        entry.pointee.ai_addr, entry.pointee.ai_addrlen, &buffer, socklen_t(buffer.count), nil, 0,
                        NI_NUMERICHOST) == 0
                    {
                        addresses.append(
                            String(
                                decoding: buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self
                            ))
                    }
                    cursor = entry.pointee.ai_next
                }
                continuation.resume(returning: Array(Set(addresses)).sorted())
            }
        }
    }

    static func encode(_ request: HTTPRequest) throws -> Data {
        guard let components = URLComponents(url: request.url, resolvingAgainstBaseURL: false),
            let host = components.host
        else { throw MailError.unsafeURL }
        var target = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        if let query = components.percentEncodedQuery { target += "?" + query }
        guard !target.utf8.contains(where: { $0 < 33 || $0 == 127 }), !host.contains("\r"), !host.contains("\n") else {
            throw MailError.unsafeURL
        }
        var wire =
            "\(request.method.rawValue) \(target) HTTP/1.1\r\nHost: \(host)\r\nUser-Agent: Transorma/1.0\r\nAccept: text/html, text/plain\r\nAccept-Encoding: identity\r\nConnection: close\r\n"
        if request.method == .post {
            wire += "Content-Type: application/x-www-form-urlencoded\r\nContent-Length: \(request.body?.count ?? 0)\r\n"
        }
        return Data((wire + "\r\n").utf8) + (request.body ?? Data())
    }
}

private final class HTTPSExchange: @unchecked Sendable {
    // Every mutable field is confined to queue, including cancellation before run begins.
    private let queue = DispatchQueue(label: "me.tylercross.transorma.https")
    private let connection: NWConnection
    private var continuation: CheckedContinuation<HTTPResponse, any Error>?
    private var result: Result<HTTPResponse, any Error>?
    private var response = Data()
    private var started = false

    init(host: String, address: String) {
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_tls_server_name(tls.securityProtocolOptions, host)
        sec_protocol_options_add_tls_application_protocol(tls.securityProtocolOptions, "http/1.1")
        sec_protocol_options_set_verify_block(
            tls.securityProtocolOptions,
            { _, trust, completion in
                let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
                SecTrustSetPolicies(secTrust, SecPolicyCreateSSL(true, host as CFString))
                completion(SecTrustEvaluateWithError(secTrust, nil))
            }, queue)
        let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        connection = NWConnection(host: NWEndpoint.Host(address), port: 443, using: parameters)
    }

    func run(_ data: Data, authorize: @escaping @Sendable () throws -> Void) async throws -> HTTPResponse {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                if let result = self.result {
                    continuation.resume(with: result)
                    return
                }
                self.continuation = continuation
                self.connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        guard !self.started, self.result == nil else { return }
                        do { try authorize() } catch {
                            self.finish(.failure(error))
                            return
                        }
                        self.started = true
                        self.connection.send(
                            content: data,
                            completion: .contentProcessed { error in
                                if error != nil {
                                    self.finish(.failure(MailError.networkFailure))
                                } else {
                                    self.receive()
                                }
                            })
                    case .failed: self.finish(.failure(MailError.networkFailure))
                    case .cancelled: self.finish(.failure(CancellationError()))
                    default: break
                    }
                }
                self.connection.start(queue: self.queue)
                self.queue.asyncAfter(deadline: .now() + 12) { self.finish(.failure(MailError.networkFailure)) }
            }
        }
    }

    func cancel() { queue.async { self.finish(.failure(CancellationError())) } }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, complete, error in
            guard self.result == nil else { return }
            if let data { self.response += data }
            guard self.response.count <= 300_000 else {
                self.finish(.failure(MailError.oversizedResponse))
                return
            }
            if error != nil {
                self.finish(.failure(MailError.networkFailure))
                return
            }
            if complete { self.finish(Result { try HTTPDecoder.decode(self.response) }) } else { self.receive() }
        }
    }

    private func finish(_ result: Result<HTTPResponse, any Error>) {
        guard self.result == nil else { return }
        self.result = result
        connection.stateUpdateHandler = nil
        connection.cancel()
        continuation?.resume(with: result)
        continuation = nil
    }
}

enum HTTPDecoder {
    static func decode(_ data: Data) throws -> HTTPResponse {
        guard let separator = data.range(of: Data([13, 10, 13, 10])), separator.lowerBound <= 16_384,
            let head = String(data: data[..<separator.lowerBound], encoding: .utf8)
        else { throw MailError.networkFailure }
        let lines = head.components(separatedBy: "\r\n")
        let statusLine = lines[0].components(separatedBy: " ")
        guard statusLine.count >= 2, ["HTTP/1.1", "HTTP/1.0"].contains(statusLine[0]),
            let status = Int(statusLine[1]), (200...599).contains(status)
        else { throw MailError.networkFailure }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":"), line.first != " ", line.first != "\t" else {
                throw MailError.networkFailure
            }
            let key = String(line[..<colon]).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if headers[key] != nil && ["content-length", "transfer-encoding", "location", "content-type"].contains(key)
            {
                throw MailError.networkFailure
            }
            headers[key] = value
        }
        guard headers["content-encoding"] == nil || headers["content-encoding"] == "identity" else {
            throw MailError.unsupportedPage
        }
        var body = Data(data[separator.upperBound...])
        if let transfer = headers["transfer-encoding"] {
            guard transfer.lowercased() == "chunked", headers["content-length"] == nil else {
                throw MailError.networkFailure
            }
            body = try decodeChunks(body)
        } else if let rawLength = headers["content-length"] {
            guard let length = Int(rawLength), length == body.count else { throw MailError.networkFailure }
        }
        return HTTPResponse(status: status, headers: headers, body: body)
    }

    static func decodeChunks(_ data: Data) throws -> Data {
        var offset = data.startIndex
        var output = Data()
        while let end = data.range(of: Data([13, 10]), in: offset..<data.endIndex) {
            guard end.lowerBound - offset <= 100,
                let line = String(data: data[offset..<end.lowerBound], encoding: .ascii),
                let size = line.split(separator: ";", omittingEmptySubsequences: false).first,
                !size.isEmpty,
                size.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
                let length = Int(size, radix: 16), length <= 300_000
            else { throw MailError.networkFailure }
            offset = end.upperBound
            if length == 0 {
                // Trailers are unsupported. Require the final empty line and reject extra bytes.
                guard data[offset...] == Data([13, 10]) else { throw MailError.networkFailure }
                return output
            }
            guard length <= data.endIndex - offset - 2,
                data[(offset + length)..<(offset + length + 2)] == Data([13, 10])
            else { throw MailError.networkFailure }
            output += data[offset..<(offset + length)]
            offset += length + 2
        }
        throw MailError.networkFailure
    }
}
