import Foundation

public struct HTTPRequest: Sendable {
    public enum Method: String, Sendable {
        case get = "GET"
        case post = "POST"
    }

    public var url: URL
    public var method: Method
    public var body: Data?
    public init(url: URL, method: Method = .get, body: Data? = nil) {
        self.url = url
        self.method = method
        self.body = body
    }
}

public struct HTTPResponse: Sendable {
    public let status: Int
    public let headers: [String: String]
    public let body: Data
    public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.headers = headers
        self.body = body
    }
}

public protocol HTTPTransport: Sendable {
    /// Revalidate ownership/consent immediately before transmitting, after asynchronous connection setup.
    func send(_ request: HTTPRequest, authorize: @escaping @Sendable () throws -> Void) async throws -> HTTPResponse
}

extension HTTPTransport {
    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        try await send(request, authorize: {})
    }
}
