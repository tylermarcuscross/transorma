import Foundation

@testable import TransormaCore

struct FakeIntelligence: MailIntelligence {
    var available = true
    var marketing = true
    var choice: Int? = 0
    var beforeClassification: @Sendable () async -> Void = {}
    var beforeChoice: @Sendable () async -> Void = {}

    func isMarketing(subject: String, text: String) async throws -> Bool {
        await beforeClassification()
        return marketing
    }

    func chooseAction(
        on page: UnsubscribePage, authorizePrivateCloud: (@Sendable () throws -> Void)?
    ) async throws -> Int? {
        await beforeChoice()
        return choice
    }
}

actor FakeTransport: HTTPTransport {
    private var responses: [HTTPResponse]
    private(set) var requests: [HTTPRequest] = []
    private let beforeSend: @Sendable () async throws -> Void

    init(_ responses: [HTTPResponse], beforeSend: @escaping @Sendable () async throws -> Void = {}) {
        self.responses = responses
        self.beforeSend = beforeSend
    }

    func send(_ request: HTTPRequest, authorize: @escaping @Sendable () throws -> Void) async throws -> HTTPResponse {
        try await beforeSend()
        try authorize()
        requests.append(request)
        guard !responses.isEmpty else { throw MailError.networkFailure }
        return responses.removeFirst()
    }
}

struct TestStore: Sendable {
    let directory: URL
    let store: SharedStore

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "transorma-tests-" + UUID().uuidString)
        store = try SharedStore(directory: directory)
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}

/// Lets tests change persisted state while a model or transport is suspended, without sleeps.
actor AsyncGate {
    private var isOpen = false
    private var blocked: [CheckedContinuation<Void, Never>] = []
    private var observers: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            blocked.append(continuation)
            for observer in observers where blocked.count >= observer.count { observer.continuation.resume() }
            observers.removeAll { blocked.count >= $0.count }
        }
    }

    func waitUntilWaiting(count: Int = 1) async {
        guard blocked.count < count, !isOpen else { return }
        await withCheckedContinuation { observers.append((count, $0)) }
    }

    func open() {
        isOpen = true
        for continuation in blocked { continuation.resume() }
        blocked.removeAll()
        for observer in observers { observer.continuation.resume() }
        observers.removeAll()
    }
}
