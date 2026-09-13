import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var section: Section = .protection
    @State private var keepEntry = ""

    private enum Section: String, CaseIterable, Identifiable {
        case protection = "Protection"
        case activity = "Activity"
        case keep = "Keep list"
        case privacy = "Privacy"

        var id: Self { self }

        var symbol: String {
            switch self {
            case .protection: "shield.lefthalf.filled"
            case .activity: "clock.arrow.circlepath"
            case .keep: "heart"
            case .privacy: "lock"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $section) { item in
                Label(item.rawValue, systemImage: item.symbol)
                    .foregroundStyle(section == item ? Color.white : Color.primary)
                    .tag(item)
            }
            .navigationTitle("Transorma")
            .safeAreaInset(edge: .bottom) {
                Label("A quieter inbox.", systemImage: "envelope.badge.shield.half.filled")
                    .font(.caption).foregroundStyle(.secondary).padding()
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let error = model.error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.callout).padding().frame(maxWidth: .infinity, alignment: .leading)
                            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    }
                    switch section {
                    case .protection: ProtectionView()
                    case .activity: ActivityView()
                    case .keep: KeepListView(keepEntry: $keepEntry)
                    case .privacy: PrivacyView()
                    }
                }
                .padding(32).frame(maxWidth: 820, alignment: .leading).frame(maxWidth: .infinity)
            }
            .navigationTitle(section.rawValue)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 820, minHeight: 640)
        .tint(.teal)
    }
}

#Preview {
    @Previewable @State var model = AppModel.preview()
    ContentView().environment(model)
}
