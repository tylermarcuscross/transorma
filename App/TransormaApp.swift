import SwiftUI

@main
struct TransormaApp: App {
    static let mainWindowID = "main"

    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var lifecycle
    @Environment(\.scenePhase) private var scenePhase
    @State private var section: ContentView.Section = .settings

    var body: some Scene {
        let model = lifecycle.model
        Window("Transorma", id: Self.mainWindowID) {
            ContentView(section: $section)
                .environment(model)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.refresh() }
                }
        }
        .defaultSize(width: 1040, height: 800)
        .commands { MainWindowCommands(section: $section) }

        MenuBarExtra {
            MenuBarView(section: $section)
        } label: {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .accessibilityLabel("Transorma")
                .accessibilityIdentifier("transorma-menu-bar")
        }
    }
}

/// SwiftUI window tasks end when their window closes. The application owns processing
/// instead, allowing queued unsubscribes to continue until the user quits Transorma.
@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    let model: AppModel
    private var processingTask: Task<Void, Never>?

    override init() {
        #if TRANSORMA_DEVELOPMENT
            model = AppModel.preview()
        #elseif DEBUG
            model = ProcessInfo.processInfo.arguments.contains("--ui-testing") ? AppModel.preview() : AppModel.live()
        #else
            model = AppModel.live()
        #endif
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self, selector: #selector(resumeQueuedWork), name: NSWorkspace.didWakeNotification, object: nil)
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didActivateApplicationNotification] {
            center.addObserver(self, selector: #selector(mailBecameAvailable), name: name, object: nil)
        }
        processingTask = Task { await model.run() }
    }

    @objc private func resumeQueuedWork(_ notification: Notification) {
        model.requestCatchUp()
    }

    @objc private func mailBecameAvailable(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
            app.bundleIdentifier == "com.apple.mail"
        else { return }
        model.requestCatchUp()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        processingTask?.cancel()
        processingTask = nil
    }
}
