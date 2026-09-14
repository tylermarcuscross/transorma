import Foundation
import Observation
import ServiceManagement

@MainActor
protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemService {}

/// macOS owns the enabled state. Only the decision to apply the initial default is stored locally.
@MainActor
@Observable
final class LoginItem {
    private(set) var status: SMAppService.Status
    private(set) var error: String?

    private let service: any LoginItemService
    private let defaults: UserDefaults
    private static let configuredKey = "hasConfiguredLoginItem"

    var isEnabled: Bool { status == .enabled }
    var requiresApproval: Bool { status == .requiresApproval }

    init(service: any LoginItemService = SMAppService.mainApp, defaults: UserDefaults = .standard) {
        self.service = service
        self.defaults = defaults
        status = service.status
    }

    func applyDefaultOnce() {
        refresh()
        guard !defaults.bool(forKey: Self.configuredKey) else { return }
        // Record the attempt before registration, including failures. Relaunching
        // must not override an opt-out or repeatedly request a denied registration.
        defaults.set(true, forKey: Self.configuredKey)
        guard status == .notRegistered else { return }
        setEnabled(true)
    }

    func setEnabled(_ enabled: Bool) {
        defaults.set(true, forKey: Self.configuredKey)
        error = nil
        refresh()
        do {
            if enabled {
                if status != .enabled && status != .requiresApproval { try service.register() }
            } else if status != .notRegistered {
                try service.unregister()
            }
        } catch {
            self.error = "Login launch could not be updated. Check Login Items in System Settings, then try again."
        }
        refresh()
    }

    func refresh() {
        let current = service.status
        if current != status { error = nil }
        status = current
    }

    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
