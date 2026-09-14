import SwiftUI
import TransormaCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle(isOn: setting(\.enabled)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Protect my inbox").font(.headline)
                            Text("Automatically unsubscribe and move matched marketing to Trash.").font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }.toggleStyle(.switch).disabled(!model.storageReady).accessibilityIdentifier("protection-toggle")
                    Divider()
                    Text(
                        "Transorma contacts unsubscribe websites automatically as Mail downloads messages, including mail that arrived while Mail was closed. Uncertain messages stay in your inbox."
                    )
                    .font(.callout).foregroundStyle(.secondary)
                    Label(
                        model.protectionStatus,
                        systemImage: model.snapshot.settings.enabled ? "checkmark.shield" : "pause.circle"
                    )
                    .font(.callout.weight(.medium)).foregroundStyle(
                        model.snapshot.settings.enabled ? .primary : .secondary)
                }.padding(12)
            }
            GroupBox("Connect to Apple Mail") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("1. Open Mail → Settings → Extensions.")
                    Text("2. Enable Transorma and allow access to message contents.")
                    Text("3. Open Mail to check messages that arrived while it was closed.")
                    Text(
                        "Catch-up happens automatically as Mail downloads messages. Keep Transorma running in the menu bar to finish queued unsubscribes. Previously downloaded messages are not rescanned."
                    )
                    .foregroundStyle(.secondary)
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
            .disabled(!model.storageReady)
            Toggle(
                "Open Transorma at login to resume queued unsubscribes",
                isOn: Binding(get: { model.startsAtLogin }, set: { model.setLogin($0) })
            )
            .font(.callout)
            .disabled(!model.canManageLoginItem)
            Text(
                "You can recover messages from Mail’s Trash until Mail deletes them. Unsubscribing cannot be undone here; to receive a list again, subscribe on its website."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func setting(_ keyPath: WritableKeyPath<ProtectionSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.snapshot.settings[keyPath: keyPath] },
            set: { value in model.updateSettings { $0[keyPath: keyPath] = value } })
    }
}
