import SwiftUI
import TransormaCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var showsDiagnostics = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            GroupBox {
                Toggle(isOn: setting(\.enabled)) {
                    Text(model.isPreview ? "Preview activation" : "Activate Transorma")
                        .font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.switch)
                .disabled(!model.storageReady)
                .accessibilityIdentifier("protection-toggle")
                .padding(12)
            }
            mailSetup
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
            .disabled(!model.storageReady)
            loginSettings
            Button("Diagnostics…") { showsDiagnostics = true }
                .accessibilityIdentifier("open-diagnostics")
            Text(
                "You can recover messages from Mail’s Trash until Mail deletes them. Unsubscribing cannot be undone here; to receive a list again, subscribe on its website."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
        .sheet(isPresented: $showsDiagnostics) { DiagnosticsView().environment(model) }
    }

    private var loginSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(
                "Open Transorma at login to resume queued unsubscribes",
                isOn: Binding(get: { model.startsAtLogin }, set: { model.setLogin($0) })
            )
            .font(.callout)
            .disabled(!model.canManageLoginItem)
            .accessibilityIdentifier("login-toggle")

            if let loginItem = model.loginItem {
                if loginItem.requiresApproval {
                    Text("Allow Transorma in Login Items to open it automatically.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if let error = loginItem.error {
                    Text(error).font(.caption).foregroundStyle(.secondary)
                }
                if loginItem.requiresApproval || loginItem.error != nil {
                    Button("Open Login Settings") { loginItem.openSettings() }
                        .font(.callout)
                }
            } else {
                Text("Login launch is disabled in this development build.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var mailSetup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    Image(systemName: "envelope.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 44, height: 44)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Connect to Apple Mail").font(.headline)
                        Text("Mail → Settings → Extensions")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Link(destination: URL(string: "mail-pref-pane://extensionspref")!) {
                        Text("Open Mail Settings")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("open-mail-settings")
                    .help("Open Extensions settings in Apple Mail")
                }

                VStack(alignment: .leading, spacing: 16) {
                    setupStep("1", title: "Enable Transorma", detail: "Select the checkbox next to Transorma.")
                    setupStep(
                        "2", title: "Allow message access",
                        detail: "Allow access to message contents when Mail asks.")
                }

                Text("Transorma automatically contacts unsubscribe websites and moves matched marketing to Trash.")
                    .font(.callout).foregroundStyle(.secondary)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Label(
                        model.protectionStatus,
                        systemImage: model.isPreview
                            ? "hammer" : (model.snapshot.settings.enabled ? "checkmark.shield" : "pause.circle")
                    )
                    .font(.callout.weight(.medium)).foregroundStyle(.secondary)
                    if let last = model.snapshot.lastMailActivity {
                        Text("Last activity from Mail: \(last.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    DisclosureGroup("How background processing works") {
                        Text(
                            "Catch-up happens as Mail downloads messages, including mail that arrived while it was closed. Keep Transorma running in the menu bar to finish queued unsubscribes. Previously downloaded messages are not rescanned, and uncertain messages stay in your inbox."
                        )
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                    }
                    .font(.callout)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        }
    }

    private func setupStep(_ number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func setting(_ keyPath: WritableKeyPath<ProtectionSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.snapshot.settings[keyPath: keyPath] },
            set: { value in model.updateSettings { $0[keyPath: keyPath] = value } })
    }
}
