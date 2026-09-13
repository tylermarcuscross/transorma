import SwiftUI
import TransormaCore

struct ProtectionView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
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
