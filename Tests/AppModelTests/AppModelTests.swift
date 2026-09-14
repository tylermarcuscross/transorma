import Foundation
import Testing
import TransormaCore

@testable import Transorma

@MainActor
struct AppModelTests {
    @Test func startupCatchesUpAcrossMoreThanOneOldWorkerBatch() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = try SharedStore(directory: directory)
        try writer.updateSettings { $0.enabled = true }
        for index in 0..<12 { try enqueue(index, in: writer) }
        let store = try SharedStore(directory: directory)
        let transport = RecordingTransport()
        let model = AppModel(store: store, worker: UnsubscribeWorker(store: store, transport: transport))

        try await withThrowingTaskGroup(of: Void.self) { tasks in
            tasks.addTask { await model.run() }
            defer { tasks.cancelAll() }
            try await waitUntil { model.snapshot.jobs.filter { $0.status == .accepted }.count == 12 }
            #expect(await transport.requestCount == 12)
            #expect(model.pendingUnsubscribeCount == 0)
            #expect(model.protectionStatus == "Protection enabled · waiting for Mail")
        }
    }

    @Test func aCatchUpSignalResumesWorkAddedByAnotherProcess() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SharedStore(directory: directory)
        try store.updateSettings { $0.enabled = true }
        try enqueue(0, in: store)
        let transport = RecordingTransport()
        let model = AppModel(store: store, worker: UnsubscribeWorker(store: store, transport: transport))

        try await withThrowingTaskGroup(of: Void.self) { tasks in
            tasks.addTask { await model.run() }
            defer { tasks.cancelAll() }
            try await waitUntil { model.snapshot.jobs.first?.status == .accepted }
            // Let the empty pass settle into its event wait. The regression must
            // complete well before the 15-second fallback poll.
            try await Task.sleep(for: .milliseconds(50))
            try enqueue(1, in: SharedStore(directory: directory))
            model.requestCatchUp()
            model.requestCatchUp()
            try await waitUntil { model.snapshot.jobs.filter { $0.status == .accepted }.count == 2 }
            #expect(await transport.requestCount == 2)
        }
    }

    @Test func catchUpStatusReflectsPendingWorkAndConsent() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SharedStore(directory: directory)
        try store.updateSettings { $0.enabled = true }
        try enqueue(0, in: store)
        try enqueue(1, in: store)
        _ = try #require(try store.claim())
        let model = AppModel(store: store)

        #expect(model.pendingUnsubscribeCount == 2)
        #expect(model.protectionStatus == "2 unsubscribe requests remaining")
        #expect(model.updateSettings { $0.enabled = false })
        #expect(model.protectionStatus == "Protection is paused")
        try Data("invalid state".utf8).write(to: directory.appendingPathComponent("state.json"))
        model.refresh()
        #expect(model.protectionStatus == "Protection is unavailable")
    }

    @Test func settingsArePersisted() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SharedStore(directory: directory)
        let model = AppModel(store: store)

        #expect(model.storageReady)
        #expect(!model.snapshot.settings.enabled)
        #expect(model.updateSettings { $0.enabled = true })
        #expect(try store.snapshot().settings.enabled)

        #expect(model.updateSettings { $0.useIntelligence = false })
        #expect(!model.snapshot.settings.useIntelligence)
        #expect(!(try store.snapshot().settings.useIntelligence))
    }

    @Test func unavailableStorageCannotReportASuccessfulChange() {
        let model = AppModel(store: nil)

        #expect(!model.storageReady)
        #expect(!model.updateSettings { $0.enabled = true })
        #expect(model.error != nil)
        #expect(!model.snapshot.settings.enabled)

        model.clearHistory()
        #expect(model.error != nil)
    }

    @Test func refreshRecoversFromStorageFailure() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SharedStore(directory: directory)
        let model = AppModel(store: store)
        let stateFile = directory.appendingPathComponent("state.json")

        try Data("not valid state".utf8).write(to: stateFile)
        model.refresh()
        #expect(!model.storageReady)
        #expect(model.error != nil)

        try FileManager.default.removeItem(at: stateFile)
        model.refresh()
        #expect(model.storageReady)
        #expect(model.error == nil)
    }

    @Test func previewInstancesHaveIndependentStorageAndNoBackgroundWorker() async {
        let first = AppModel.preview()
        let second = AppModel.preview()

        #expect(first.isPreview)
        #expect(first.protectionStatus == "Preview activation is off")
        #expect(first.updateSettings { $0.enabled = true })
        #expect(first.protectionStatus == "Preview activation is on")
        #expect(!second.snapshot.settings.enabled)
        #expect(!first.canManageLoginItem)
        first.configureLoginAtFirstLaunch()
        first.setLogin(true)
        #expect(!first.startsAtLogin)
        await first.run()
    }

    @Test func processingLoopStopsWhenItsOwnerCancels() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SharedStore(directory: directory)
        let model = AppModel(store: store, worker: UnsubscribeWorker(store: store))
        let task = Task { await model.run() }

        await Task.yield()
        task.cancel()
        await task.value
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("TransormaModelTests-" + UUID().uuidString)
    }

    private func enqueue(_ index: Int, in store: SharedStore) throws {
        try store.enqueue(
            UnsubscribeJob(
                sender: "offers@store.example.com", kind: .oneClick,
                url: #require(URL(string: "https://store.example.com/u/\(index)"))))
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition() {
            try #require(ContinuousClock.now < deadline, "Automatic catch-up did not make progress.")
            try await Task.sleep(for: .milliseconds(1))
        }
    }
}

private actor RecordingTransport: HTTPTransport {
    private(set) var requestCount = 0

    func send(_ request: HTTPRequest, authorize: @escaping @Sendable () throws -> Void) async throws -> HTTPResponse {
        try authorize()
        requestCount += 1
        return HTTPResponse(status: 200)
    }
}
