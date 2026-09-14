import SwiftUI

struct MenuBarView: View {
    @Binding var section: ContentView.Section
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            Button("Open Transorma") {
                openWindow(id: TransormaApp.mainWindowID)
                NSApplication.shared.activate()
            }
            .keyboardShortcut("n")
            Divider()
            Button("Settings…") {
                section = .settings
                openWindow(id: TransormaApp.mainWindowID)
                NSApplication.shared.activate()
            }
            .keyboardShortcut(",")
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}

/// Keep the same shortcuts available in the app's standard menus when the status menu is closed.
struct MainWindowCommands: Commands {
    @Binding var section: ContentView.Section
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Transorma", action: openMainWindow)
                .keyboardShortcut("n")
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                section = .settings
                openMainWindow()
            }
            .keyboardShortcut(",")
        }
    }

    private func openMainWindow() {
        openWindow(id: TransormaApp.mainWindowID)
        NSApplication.shared.activate()
    }
}
