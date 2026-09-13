import SwiftUI
import ServiceManagement
import TransormaCore

@MainActor
final class ProtectionModel: ObservableObject {
    @Published private(set) var snapshot = StoreSnapshot()
    @Published private(set) var error: String?
    @Published private(set) var storageReady = false
    @Published var startsAtLogin = SMAppService.mainApp.status == .enabled
    private let store: SharedStore?
    private let worker: UnsubscribeWorker?
    private var task: Task<Void, Never>?

    init() {
        do {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                let previewStore = try SharedStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("TransormaPreview-" + UUID().uuidString))
                let previewSnapshot = try previewStore.snapshot()
                store = previewStore
                worker = nil
                snapshot = previewSnapshot
                storageReady = true
                return
            }
            #endif
            let store = try SharedStore.appGroup()
            let snapshot = try store.snapshot()
            self.store = store
            worker = UnsubscribeWorker(store: store)
            self.snapshot = snapshot
            storageReady = true
        } catch {
            store = nil; worker = nil
            self.error = "Shared protection storage is unavailable. Use a signed build with the Transorma App Group enabled."
        }
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.worker?.drain()
                self.refresh()
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    func refresh() {
        guard let store else { return }
        do { snapshot = try store.snapshot(); storageReady = true }
        catch { self.error = "Protection state could not be read. Automatic processing is paused until storage is available."; storageReady = false }
    }

    func update(_ change: (inout ProtectionSettings) -> Void) {
        guard let store else { return }
        do {
            var settings = try store.snapshot().settings
            change(&settings)
            try store.setSettings(settings)
            snapshot = try store.snapshot()
            error = nil
        } catch { self.error = "Your change could not be saved. Please try again." }
    }

    func keep(_ entry: String) {
        let entry = entry.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard entry.count <= 254, entry.contains("."), !entry.contains(where: \.isWhitespace), !entry.contains("/"),
              entry.range(of: #"^[a-z0-9._%+\-]+(?:@[a-z0-9.\-]+)?$"#, options: .regularExpression) != nil else {
            error = "Enter an email address or domain, such as news@example.com or example.com."
            return
        }
        update { if !$0.allowedSenders.contains(entry) { $0.allowedSenders.append(entry) } }
    }

    func clearHistory() {
        do { try store?.clearHistory(); refresh() }
        catch { self.error = "Activity could not be cleared." }
    }

    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            startsAtLogin = SMAppService.mainApp.status == .enabled
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch { self.error = "Login access could not be updated. Check System Settings → General → Login Items & Extensions." }
    }
}
