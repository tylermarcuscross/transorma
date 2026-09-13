import Foundation
import Testing
import TransormaCore

@testable import Transorma

@MainActor
struct AppModelTests {
    @Test func settingsArePersistedAndKeepEntriesAreNormalized() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SharedStore(directory: directory)
        let model = AppModel(store: store)

        #expect(model.storageReady)
        #expect(!model.snapshot.settings.enabled)
        #expect(model.updateSettings { $0.enabled = true })
        #expect(try store.snapshot().settings.enabled)

        #expect(model.keep("  News@Example.COM \n"))
        #expect(model.keep("news@example.com"))
        #expect(model.snapshot.settings.allowedSenders == ["news@example.com"])
        #expect(try store.snapshot().settings.allowedSenders == ["news@example.com"])

        model.removeKeptSender("news@example.com")
        #expect(try store.snapshot().settings.allowedSenders.isEmpty)
    }

    @Test func successfulChangeClearsValidationError() throws {
        let model = AppModel.preview()

        #expect(!model.keep("invalid address"))
        #expect(model.error != nil)
        #expect(model.keep("example.com"))
        #expect(model.error == nil)
    }

    @Test func unavailableStorageCannotReportASuccessfulKeep() {
        let model = AppModel(store: nil)

        #expect(!model.storageReady)
        #expect(!model.keep("example.com"))
        #expect(model.error != nil)
        #expect(model.snapshot.settings.allowedSenders.isEmpty)

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

        #expect(first.keep("example.com"))
        #expect(second.snapshot.settings.allowedSenders.isEmpty)
        #expect(!first.canManageLoginItem)
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
}
