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
        let settings = try store.snapshot().settings
        guard settings.enabled, !settings.allows(job.sender), job.kind != .web || settings.useIntelligence else {
            throw MailError.paused
        }
        return settings
    }

    private func process(_ job: UnsubscribeJob) async {
        do {
            _ = try authorized(job)
            guard let url = job.url else { throw MailError.unsafeURL }
            try URLPolicy.validate(url)
            if job.kind == .oneClick {
                let response = try await transport.send(
                    HTTPRequest(url: url, method: "POST", body: Data("List-Unsubscribe=One-Click".utf8)))
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
                request.method + request.url.absoluteString
                + UnsubscribeJob.digest(String(decoding: request.body ?? Data(), as: UTF8.self))
            guard seen.insert(key).inserted else { throw MailError.unsupportedPage }
            let response = try await transport.send(request)
            if (300...399).contains(response.status) {
                guard let location = response.headers["location"],
                    let next = URL(string: location, relativeTo: request.url)?.absoluteURL
                else { throw MailError.unsupportedPage }
                // POST can only become GET for an explicit 303. Never replay a POST across redirects.
                guard request.method == "GET" || response.status == 303 else { throw MailError.unsupportedPage }
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
            guard !page.blocked, !page.actions.isEmpty,
                let id = try await intelligence.chooseAction(on: page, allowPrivateCloud: settings.usePrivateCloud),
                let action = page.actions.first(where: { $0.id == id })
            else { throw MailError.unsupportedPage }
            _ = try authorized(job)
            request = action.request
        }
        throw MailError.unsupportedPage
    }
}
