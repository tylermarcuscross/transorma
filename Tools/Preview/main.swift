import AppKit
import SwiftUI

/// Renders only this app's own view, using temporary settings and no unsubscribe worker.
@main
struct PreviewRenderer {
    @MainActor static func main() {
        guard CommandLine.arguments.contains("--ui-testing"), CommandLine.arguments.count >= 3 else { return }
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 920), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        let hosting = NSHostingView(rootView: ContentView().environmentObject(ProtectionModel()))
        window.contentView = hosting
        window.title = "Transorma Preview"
        window.center()
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            hosting.layoutSubtreeIfNeeded()
            if let image = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
                hosting.cacheDisplay(in: hosting.bounds, to: image)
                if let data = image.representation(using: .png, properties: [:]) { try? data.write(to: output) }
            }
            app.terminate(nil)
        }
        app.run()
    }
}
