import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Binding var section: Section

    enum Section: String, CaseIterable, Identifiable {
        case settings = "Settings"
        case activity = "Activity"

        var id: Self { self }

        var symbol: String {
            switch self {
            case .settings: "gearshape"
            case .activity: "clock.arrow.circlepath"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $section) { item in
                Label(item.rawValue, systemImage: item.symbol)
                    .tag(item)
            }
            .navigationTitle("Transorma")
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            VStack(spacing: 0) {
                if model.isPreview {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Development preview", systemImage: "hammer")
                            .font(.headline)
                        Text("This build does not unsubscribe or move email. Use a signed build for Apple Mail.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 32).padding(.top, 24).frame(maxWidth: 820)
                    .accessibilityIdentifier("preview-notice")
                }
                if let error = model.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout).padding().frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 32).padding(.top, 32).frame(maxWidth: 820)
                }
                switch section {
                case .settings:
                    ScrollView {
                        SettingsView()
                            .padding(32).frame(maxWidth: 820, alignment: .leading).frame(maxWidth: .infinity)
                    }
                case .activity: ActivityView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(section.rawValue)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 820, minHeight: 640)
        .tint(.accentColor)
    }
}

#Preview {
    @Previewable @State var model = AppModel.preview()
    @Previewable @State var section: ContentView.Section = .settings
    ContentView(section: $section).environment(model)
}
