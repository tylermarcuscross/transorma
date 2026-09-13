import SwiftUI

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            Text(status)
            Divider()
            Button("Open Transorma") {
                openWindow(id: TransormaApp.mainWindowID)
                NSApplication.shared.activate()
            }
            Toggle(
                "Automatic Protection",
                isOn: Binding(
                    get: { model.snapshot.settings.enabled },
                    set: { enabled in model.updateSettings { $0.enabled = enabled } })
            )
            .disabled(!model.storageReady)
            Divider()
            Button("Quit Transorma") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .onAppear { model.refresh() }
    }

    private var status: String {
        guard model.storageReady else { return "Protection is unavailable" }
        return model.snapshot.settings.enabled ? "Protection is enabled" : "Protection is paused"
    }
}
