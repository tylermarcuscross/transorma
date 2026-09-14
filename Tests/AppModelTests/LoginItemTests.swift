import Foundation
import ServiceManagement
import Testing
import TransormaCore

@testable import Transorma

@MainActor
struct LoginItemTests {
    @Test func firstLaunchEnablesLoginOnlyOnce() {
        withLoginItem { item, service, defaults in
            item.applyDefaultOnce()
            #expect(item.isEnabled)
            #expect(service.registrationCount == 1)

            LoginItem(service: service, defaults: defaults).applyDefaultOnce()
            #expect(service.registrationCount == 1)
        }
    }

    @Test func optingOutBeforeOrAfterSetupSurvivesRelaunch() {
        for configureFirst in [false, true] {
            withLoginItem { item, service, defaults in
                if configureFirst { item.applyDefaultOnce() }
                item.setEnabled(false)
                let registrations = service.registrationCount

                let relaunched = LoginItem(service: service, defaults: defaults)
                relaunched.applyDefaultOnce()
                #expect(!relaunched.isEnabled)
                #expect(service.registrationCount == registrations)
            }
        }
    }

    @Test func existingRegistrationAndApprovalAreRespected() {
        for status in [SMAppService.Status.enabled, .requiresApproval] {
            withLoginItem { item, service, _ in
                service.status = status
                item.applyDefaultOnce()
                #expect(item.status == status)
                #expect(service.registrationCount == 0)
            }
        }
    }

    @Test func systemSettingsOptOutIsNotOverridden() {
        withLoginItem { item, service, defaults in
            item.applyDefaultOnce()
            service.status = .requiresApproval
            item.refresh()
            #expect(!item.isEnabled)
            #expect(item.requiresApproval)

            let relaunched = LoginItem(service: service, defaults: defaults)
            relaunched.applyDefaultOnce()
            relaunched.setEnabled(true)
            #expect(relaunched.requiresApproval)
            #expect(service.registrationCount == 1)

            service.status = .enabled
            relaunched.refresh()
            #expect(relaunched.isEnabled)
            #expect(!relaunched.requiresApproval)
        }
    }

    @Test func registrationFailureDoesNotRetryUntilRequested() {
        withLoginItem { item, service, defaults in
            service.rejectRegistration = true
            item.applyDefaultOnce()
            #expect(!item.isEnabled)
            #expect(item.error != nil)
            item.refresh()
            #expect(item.error != nil)

            let relaunched = LoginItem(service: service, defaults: defaults)
            relaunched.applyDefaultOnce()
            #expect(service.registrationCount == 1)
            service.rejectRegistration = false
            relaunched.setEnabled(true)
            #expect(service.registrationCount == 2)
            #expect(relaunched.isEnabled)
            #expect(relaunched.error == nil)
        }
    }

    @Test func failedUnregistrationKeepsTheActualSystemState() {
        withLoginItem { item, service, _ in
            item.applyDefaultOnce()
            service.rejectUnregistration = true
            item.setEnabled(false)
            #expect(item.isEnabled)
            #expect(item.error != nil)
            item.refresh()
            #expect(item.error != nil)
            service.rejectUnregistration = false
            item.setEnabled(false)
            #expect(!item.isEnabled)
            #expect(item.error == nil)
        }
    }

    @Test func appStartupRequiresUsableStorageAndDoesNotEnableProtection() throws {
        try withLoginItem { item, service, _ in
            AppModel(store: nil, loginItem: item).configureLoginAtFirstLaunch()
            #expect(service.registrationCount == 0)

            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let model = AppModel(store: try SharedStore(directory: directory), loginItem: item)
            model.configureLoginAtFirstLaunch()
            #expect(model.startsAtLogin)
            #expect(!model.snapshot.settings.enabled)
            model.setLogin(false)
            model.refresh()
            #expect(!model.startsAtLogin)
        }
    }

    private func withLoginItem(_ body: (LoginItem, TestLoginService, UserDefaults) throws -> Void) rethrows {
        let suite = "TransormaLoginTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = TestLoginService()
        try body(LoginItem(service: service, defaults: defaults), service, defaults)
    }
}

@MainActor
private final class TestLoginService: LoginItemService {
    var status = SMAppService.Status.notRegistered
    var registrationCount = 0
    var rejectRegistration = false
    var rejectUnregistration = false

    func register() throws {
        registrationCount += 1
        if rejectRegistration { throw CocoaError(.fileWriteNoPermission) }
        status = .enabled
    }

    func unregister() throws {
        if rejectUnregistration { throw CocoaError(.fileWriteNoPermission) }
        status = .notRegistered
    }
}
