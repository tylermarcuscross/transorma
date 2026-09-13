import SwiftUI

@main
struct TransormaApp: App {
    static let mainWindowID = "main"

    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var lifecycle
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: AppModel

    init() {
        #if TRANSORMA_DEVELOPMENT
            _model = State(initialValue: AppModel.preview())
        #elseif DEBUG
            _model = State(
                initialValue: ProcessInfo.processInfo.arguments.contains("--ui-testing")
                    ? AppModel.preview() : AppModel.live())
        #else
            _model = State(initialValue: AppModel.live())
        #endif
    }

    var body: some Scene {
        Window("Transorma", id: Self.mainWindowID) {
            ContentView()
                .environment(model)
                .onAppear { lifecycle.start(model) }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.refresh() }
                }
        }
        .defaultSize(width: 1040, height: 800)

        MenuBarExtra {
            MenuBarView()
                .environment(model)
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
    private var processingTask: Task<Void, Never>?

    func start(_ model: AppModel) {
        guard processingTask == nil else { return }
        processingTask = Task { await model.run() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        processingTask?.cancel()
        processingTask = nil
    }
}
