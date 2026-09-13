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
        guard let worker else { return }
        while !Task.isCancelled {
            await worker.drain()
            guard !Task.isCancelled else { return }
            refresh()
            do {
                try await Task.sleep(for: .seconds(15))
            } catch {
                return
            }
        }
    }

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
            return true
        } catch {
            self.error = "Your change could not be saved. Please try again."
            storageReady = false
            return false
        }
    }

    @discardableResult
    func keep(_ entry: String) -> Bool {
        let entry = entry.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard entry.count <= 254, entry.contains("."), !entry.contains(where: \.isWhitespace), !entry.contains("/"),
            entry.range(of: #"^[a-z0-9._%+\-]+(?:@[a-z0-9.\-]+)?$"#, options: .regularExpression) != nil
        else {
            error = "Enter an email address or domain, such as news@example.com or example.com."
            return false
        }
        return updateSettings { if !$0.allowedSenders.contains(entry) { $0.allowedSenders.append(entry) } }
    }

    func removeKeptSender(_ entry: String) {
        updateSettings { $0.allowedSenders.removeAll { $0 == entry } }
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
