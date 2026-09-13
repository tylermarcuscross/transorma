//
//  ContentView.swift
//  transorma
//
//  Created by Tyler Cross on 8/6/25.
//

import SwiftUI
import TransormaCore

struct ContentView: View {
    @EnvironmentObject private var model: ProtectionModel
    @StateObject private var navigation = NavigationState()
    enum Section: String, CaseIterable, Identifiable {
        case overview = "Protection"
        case activity = "Activity"
        case keep = "Keep list"
        case privacy = "Privacy"
        var id: Self { self }
        var symbol: String {
            switch self {
            case .overview: "shield.lefthalf.filled"
            case .activity: "clock.arrow.circlepath"
            case .keep: "heart"
            case .privacy: "lock"
            }
        }
    }

    @MainActor private final class NavigationState: ObservableObject {
        @Published var section: Section = .overview
        @Published var keepEntry = ""
    }

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $navigation.section) { item in
                Label(item.rawValue, systemImage: item.symbol)
                    .foregroundStyle(navigation.section == item ? Color.white : Color.primary)
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
                    switch navigation.section {
                    case .overview: overview
                    case .activity: activity
                    case .keep: keepList
                    case .privacy: privacy
                    }
                }
                .padding(32).frame(maxWidth: 820, alignment: .leading).frame(maxWidth: .infinity)
            }
            .navigationTitle(navigation.section.rawValue)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 820, minHeight: 640)
        .tint(.teal)
        .onAppear { model.start() }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 18) {
                Image(systemName: "envelope.badge.shield.half.filled")
                    .font(.system(size: 38, weight: .light)).foregroundStyle(.teal)
                    .frame(width: 80, height: 80).background(.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 22))
                VStack(alignment: .leading, spacing: 6) {
                    Text("Less marketing. More mail.").font(.largeTitle.bold())
                    Text("Automatic unsubscribe for Apple Mail.").foregroundStyle(.secondary)
                }
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle(isOn: setting(\.enabled)) {
                        Text("Protect my inbox").font(.headline)
                        Text("Automatically unsubscribe and move matched marketing to Trash.").font(.callout)
                            .foregroundStyle(.secondary)
                    }.toggleStyle(.switch).disabled(!model.storageReady).accessibilityIdentifier("protection-toggle")
                    Divider()
                    Text(
                        "Turning this on authorizes Transorma to contact unsubscribe websites on your behalf, without asking for each message. It processes new mail as Apple Mail receives it. Uncertain messages stay in your inbox."
                    )
                    .font(.callout).foregroundStyle(.secondary)
                    Label(
                        model.snapshot.settings.enabled
                            ? "Protection enabled · waiting for incoming mail" : "Protection is paused",
                        systemImage: model.snapshot.settings.enabled ? "checkmark.shield" : "pause.circle"
                    )
                    .font(.callout.weight(.medium)).foregroundStyle(
                        model.snapshot.settings.enabled ? .teal : .secondary)
                }.padding(12)
            }
            GroupBox("Connect to Apple Mail") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("1. Open Mail → Settings → Extensions.")
                    Text("2. Enable Transorma and allow access to message contents.")
                    Text("3. Leave Apple Mail running to process incoming messages.")
                    if let last = model.snapshot.lastMailActivity {
                        Text("Last activity from Mail: \(last.formatted(date: .abbreviated, time: .shortened))").font(
                            .caption
                        ).foregroundStyle(.secondary)
                    } else {
                        Text("No activity from the extension yet.").font(.caption).foregroundStyle(.secondary)
                    }
                }.font(.callout).frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }
            GroupBox("Apple Intelligence") {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle(
                        "Use Apple Intelligence for extra checks and unsubscribe pages",
                        isOn: setting(\.useIntelligence))
                    Text(
                        AppleIntelligence.onDeviceAvailable
                            ? "On-device model available. Transorma can interpret supported unsubscribe pages, including confirmation forms."
                            : "The on-device model is unavailable. Standard unsubscribe processing still works. Enable Apple Intelligence in System Settings to use page assistance."
                    )
                    .font(.callout).foregroundStyle(.secondary)
                    Divider()
                    Toggle("Allow Private Cloud Compute for harder pages", isOn: setting(\.usePrivateCloud))
                        .disabled(
                            !AppleIntelligence.hasPrivateCloudEntitlement || !model.snapshot.settings.useIntelligence)
                    Text(
                        AppleIntelligence.hasPrivateCloudEntitlement
                            ? "When needed, a limited excerpt of page text and action labels can be sent to Apple’s Private Cloud Compute. URLs and email addresses are redacted; other page text may contain personal information."
                            : "Private Cloud Compute is not available in this build. It requires Apple’s developer entitlement."
                    )
                    .font(.callout).foregroundStyle(.secondary)
                }.padding(12)
            }
            Toggle(
                "Open Transorma at login to resume queued unsubscribes",
                isOn: Binding(get: { model.startsAtLogin }, set: { model.setLogin($0) })
            )
            .font(.callout)
            Text(
                "You can recover messages from Mail’s Trash until Mail deletes them. Unsubscribing cannot be undone here; to receive a list again, subscribe on its website."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var activity: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Working quietly in the background.").font(.title2.bold())
            Text(
                "The last seven days of unsubscribe requests. An accepted request means the sender’s server accepted it; delivery may take time to stop."
            )
            .foregroundStyle(.secondary)
            if model.snapshot.jobs.isEmpty {
                ContentUnavailableView(
                    "No unsubscribe activity yet", systemImage: "tray",
                    description: Text("Activity appears here when Transorma detects a supported marketing message."))
            } else {
                ForEach(model.snapshot.jobs.sorted { $0.createdAt > $1.createdAt }) { job in
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(job.sender).font(.headline).textSelection(.enabled)
                                Spacer()
                                Text(job.status.label).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(job.detail).font(.callout).foregroundStyle(.secondary)
                            HStack {
                                Text(job.updatedAt, format: .dateTime.month().day().hour().minute()).font(.caption)
                                    .foregroundStyle(.tertiary)
                                Spacer()
                                Button("Always keep this sender") { model.keep(job.sender) }.buttonStyle(.link)
                            }
                        }.padding(8)
                    }
                }
                Button("Clear completed activity") { model.clearHistory() }
            }
        }
    }

    private var keepList: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Make room for mail you want.").font(.title2.bold())
            Text(
                "Senders and domains here always stay in your inbox. Adding one also cancels pending unsubscribe requests for it."
            ).foregroundStyle(.secondary)
            HStack {
                TextField("Email address or domain", text: $navigation.keepEntry).textFieldStyle(.roundedBorder)
                    .onSubmit(addKeepEntry)
                Button("Add", action: addKeepEntry).disabled(navigation.keepEntry.isEmpty || !model.storageReady)
            }
            ForEach(model.snapshot.settings.allowedSenders, id: \.self) { entry in
                HStack {
                    Label(entry, systemImage: "heart.fill").foregroundStyle(.teal)
                    Spacer()
                    Button("Remove") { model.update { $0.allowedSenders.removeAll { $0 == entry } } }
                }.padding(12).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Your mail stays yours.", systemImage: "lock.shield").font(.title2.bold())
            Text(
                "Transorma reads message contents only to identify supported marketing and find unsubscribe actions. It does not store message bodies or subjects. Classification runs on your Mac."
            )
            Text(
                "Unsubscribe requests contact the sender’s website using the link in the message. That link can identify your email address. DNS lookups use your Mac’s configured resolver. Transorma does not use your browser cookies or login sessions."
            )
            Text(
                "Pending requests store a sender address and unsubscribe link in the app’s protected shared storage. Links are deleted after processing. Activity, pending work, and request fingerprints used to prevent duplicates expire after seven days and are removed when Transorma next runs. There are no analytics, advertising, or developer-operated servers."
            )
            Text(
                "Private Cloud Compute is optional and off by default. If enabled in an entitled build, limited text from an unsubscribe page and action labels may be sent to Apple. Email addresses and URLs are redacted from that text; other personal information on the page may remain."
            )
            Text(
                "Pause protection at any time to stop new work and cancel pending requests. Requests already sent cannot be recalled. Clear completed activity from the Activity tab."
            )
            Divider()
            Text("What Transorma can handle").font(.headline)
            Text(
                "Verified English-language promotions with standard one-click unsubscribe, plus supported links and simple confirmation forms. Messages without a verifiable signature or with unclear intent stay in Mail. Pages requiring login, JavaScript, CAPTCHA, or ambiguous preference changes may remain unresolved."
            )
            Text(
                "Apple Mail controls delivery and Trash retention. The extension cannot scan your existing inbox or guarantee that a sender honors an unsubscribe request."
            )
            Link(
                "About Apple’s Private Cloud Compute",
                destination: URL(string: "https://security.apple.com/private-cloud-compute/")!)
        }.font(.body).lineSpacing(4)
    }

    private func setting(_ keyPath: WritableKeyPath<ProtectionSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.snapshot.settings[keyPath: keyPath] },
            set: { value in model.update { $0[keyPath: keyPath] = value } })
    }

    private func addKeepEntry() {
        model.keep(navigation.keepEntry)
        if model.error == nil { navigation.keepEntry = "" }
    }
}
