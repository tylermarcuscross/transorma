import Foundation

public actor UnsubscribeWorker {
    private let store: SharedStore
    private let transport: any HTTPTransport
    private let intelligence: any MailIntelligence
    private var running = false

    public init(
        store: SharedStore, transport: any HTTPTransport = PublicHTTPSClient(),
        intelligence: any MailIntelligence = AppleIntelligence()
    ) {
        self.store = store
        self.transport = transport
        self.intelligence = intelligence
    }

    /// Called on Mail activity and periodically by the companion app. Both use exclusive persisted claims.
    public func drain(limit: Int = 3) async {
        guard !running else { return }
        running = true
        defer { running = false }
        for _ in 0..<limit {
            guard !Task.isCancelled, let job = try? store.claim() else { return }
            await process(job)
        }
    }

    private func authorized(_ job: UnsubscribeJob) throws -> ProtectionSettings {
        try Task.checkCancellation()
        return try store.authorize(job)
    }

    private func send(_ request: HTTPRequest, for job: UnsubscribeJob) async throws -> HTTPResponse {
        let store = store
        return try await transport.send(request) {
            _ = try store.authorize(job)
        }
    }

    private func process(_ job: UnsubscribeJob) async {
        do {
            _ = try authorized(job)
            guard let url = job.url else { throw MailError.unsafeURL }
            try URLPolicy.validate(url)
            if job.kind == .oneClick {
                let response = try await send(
                    HTTPRequest(url: url, method: .post, body: Data("List-Unsubscribe=One-Click".utf8)), for: job)
                if (200...299).contains(response.status) {
                    try store.finish(
                        job, status: .accepted,
                        detail: "The sender accepted the unsubscribe request. Future delivery is not guaranteed.")
                } else if response.status == 429 || (500...599).contains(response.status) {
                    try store.finish(
                        job, status: .failed, detail: "The sender is temporarily unavailable.", retry: true)
                } else {
                    try store.finish(
                        job, status: .unsupported,
                        detail: "The sender did not accept the one-click request. Redirects are not followed.")
                }
            } else {
                try await navigate(job, initialURL: url)
            }
        } catch MailError.staleClaim {
            try? store.finish(
                job, status: .uncertain,
                detail: "Processing outlived its claim; no further requests were sent.")
        } catch MailError.paused {
            try? store.finish(
                job, status: .cancelled,
                detail: "Stopped by protection settings. An already-sent request cannot be recalled.")
        } catch MailError.unsafeURL {
            try? store.finish(
                job, status: .unsupported, detail: "The unsubscribe destination did not pass network safety checks.")
        } catch MailError.unsupportedPage {
            try? store.finish(
                job, status: .unsupported, detail: "This unsubscribe flow requires unsupported interactions.")
        } catch {
            // Transport errors after sending a request cannot establish whether the server acted.
            try? store.finish(
                job, status: .uncertain,
                detail: "Processing was interrupted or the response could not be verified. No automatic replay.")
        }
    }

    private func navigate(_ job: UnsubscribeJob, initialURL: URL) async throws {
        var request = HTTPRequest(url: initialURL)
        var seen = Set<String>()
        let deadline = Date.now.addingTimeInterval(90)
        for _ in 0..<5 {
            let settings = try authorized(job)
            guard Date.now < deadline else { throw MailError.unsupportedPage }
            try URLPolicy.validate(request.url, sameHost: initialURL.host)
            let key =
                request.method.rawValue + request.url.absoluteString
                + UnsubscribeJob.digest(String(decoding: request.body ?? Data(), as: UTF8.self))
            guard seen.insert(key).inserted else { throw MailError.unsupportedPage }
            let response = try await send(request, for: job)
            if (300...399).contains(response.status) {
                guard let location = response.headers["location"],
                    let next = URL(string: location, relativeTo: request.url)?.absoluteURL
                else { throw MailError.unsupportedPage }
                // POST can only become GET for an explicit 303. Never replay a POST across redirects.
                guard request.method == .get || response.status == 303 else { throw MailError.unsupportedPage }
                try URLPolicy.validate(next, sameHost: initialURL.host)
                request = HTTPRequest(url: next)
                continue
            }
            guard response.status == 200,
                (response.headers["content-type"] ?? "").lowercased().hasPrefix("text/html"),
                let html = String(data: response.body, encoding: .utf8)
            else { throw MailError.unsupportedPage }
            let page = try UnsubscribePage(html: html, baseURL: request.url)
            if page.confirmsUnsubscribe && !page.blocked {
                try store.finish(job, status: .confirmed, detail: "The unsubscribe page reported completion.")
                return
            }
            let store = store
            let authorizePrivateCloud: (@Sendable () throws -> Void)? =
                settings.usePrivateCloud
                ? { @Sendable in
                    let current = try store.authorize(job)
                    guard current.usePrivateCloud else { throw MailError.paused }
                } : nil
            guard !page.blocked, !page.actions.isEmpty,
                let id = try await intelligence.chooseAction(on: page, authorizePrivateCloud: authorizePrivateCloud),
                let action = page.actions.first(where: { $0.id == id })
            else { throw MailError.unsupportedPage }
            _ = try authorized(job)
            request = action.request
        }
        throw MailError.unsupportedPage
    }
}
