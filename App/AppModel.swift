import Foundation
import Observation
import ServiceManagement
import TransormaCore

/// Main-actor state for the companion app. The shared store remains the source of truth
/// because Mail can change it in a different process.
@MainActor
@Observable
final class AppModel {
    private(set) var snapshot = StoreSnapshot()
    private(set) var error: String?
    private(set) var storageReady = false
    private(set) var startsAtLogin = false
    let canManageLoginItem: Bool

    private let store: SharedStore?
    private let worker: UnsubscribeWorker?
    private let temporaryDirectory: URL?
    private var catchUpSignal: AsyncStream<Void>.Continuation?

    var pendingUnsubscribeCount: Int {
        snapshot.jobs.count { $0.status == .pending || $0.status == .processing }
    }

    var protectionStatus: String {
        guard storageReady else { return "Protection is unavailable" }
        guard snapshot.settings.enabled else { return "Protection is paused" }
        switch pendingUnsubscribeCount {
        case 0: return "Protection enabled · waiting for Mail"
        case 1: return "1 unsubscribe request remaining"
        case let count: return "\(count) unsubscribe requests remaining"
        }
    }

    init(
        store: SharedStore?, worker: UnsubscribeWorker? = nil, canManageLoginItem: Bool = false,
        temporaryDirectory: URL? = nil
    ) {
        self.store = store
        self.worker = worker
        self.canManageLoginItem = canManageLoginItem
        self.temporaryDirectory = temporaryDirectory
        refresh()
    }

    deinit {
        if let temporaryDirectory { try? FileManager.default.removeItem(at: temporaryDirectory) }
    }

    static func live() -> AppModel {
        do {
            let store = try SharedStore.appGroup()
            return AppModel(store: store, worker: UnsubscribeWorker(store: store), canManageLoginItem: true)
        } catch {
            return AppModel(store: nil, canManageLoginItem: true)
        }
    }

    /// Previews and UI tests have private, disposable storage and cannot process mail.
    static func preview() -> AppModel {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TransormaPreview-" + UUID().uuidString, isDirectory: true)
        return AppModel(store: try? SharedStore(directory: directory), temporaryDirectory: directory)
    }

    /// The application delegate owns and cancels this task, so work survives window closure.
    func run() async {
        guard let worker, catchUpSignal == nil else { return }
        let (events, signal) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        catchUpSignal = signal
        defer {
            signal.finish()
            catchUpSignal = nil
        }
        signal.yield(())
        await withTaskGroup(of: Void.self) { tasks in
            // Poll shared storage for Mail's writes and due retries. Events also
            // wake this loop immediately on Mail launch, Mac wake, or settings changes.
            tasks.addTask {
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(15)) } catch { return }
                    await self.refresh()
                    signal.yield(())
                }
            }
            for await _ in events {
                guard !Task.isCancelled else { break }
                refresh()
                while !Task.isCancelled {
                    let processed = await worker.drain(limit: 1)
                    refresh()
                    if processed == 0 { break }
                }
            }
            tasks.cancelAll()
        }
    }

    func requestCatchUp() { catchUpSignal?.yield(()) }

    func refresh() {
        if canManageLoginItem { startsAtLogin = SMAppService.mainApp.status == .enabled }
        guard let store else {
            error = "Shared protection storage is unavailable. Use a signed build with the Transorma App Group enabled."
            storageReady = false
            return
        }
        do {
            snapshot = try store.snapshot()
            storageReady = true
            error = nil
        } catch {
            self.error =
                "Protection state could not be read. Automatic processing is paused until storage is available."
            storageReady = false
        }
    }

    @discardableResult
    func updateSettings(_ change: (inout ProtectionSettings) -> Void) -> Bool {
        guard let store else {
            refresh()
            return false
        }
        do {
            try store.updateSettings(change)
            snapshot = try store.snapshot()
            storageReady = true
            error = nil
            requestCatchUp()
            return true
        } catch {
            self.error = "Your change could not be saved. Please try again."
            storageReady = false
            return false
        }
    }

    func clearHistory() {
        guard let store else {
            refresh()
            return
        }
        do {
            try store.clearHistory()
            refresh()
        } catch {
            self.error = "Activity could not be cleared."
            storageReady = false
        }
    }

    func setLogin(_ enabled: Bool) {
        guard canManageLoginItem else { return }
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            startsAtLogin = SMAppService.mainApp.status == .enabled
            error = nil
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch {
            self.error =
                "Login access could not be updated. Check System Settings → General → Login Items & Extensions."
        }
    }
}
