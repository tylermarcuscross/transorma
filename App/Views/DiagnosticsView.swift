import SwiftUI
import TransormaCore

struct DiagnosticsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private var entries: [DiagnosticEntry] {
        (model.snapshot.diagnostics?.entries ?? []).reversed()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Diagnostics").font(.title2.bold())
                Spacer()
                Button("Refresh") { model.refresh() }
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                row("App", "Build \(TransormaLog.build) · \(model.isPreview ? "Preview" : "Mail-enabled")")
                row("Shared storage", model.storageReady ? "Available" : "Unavailable")
                row("Protection", model.snapshot.settings.enabled ? "Activated" : "Paused")
                row("Extension started", timestamp(model.snapshot.diagnostics?.extensionStartedAt))
                row("Extension build", model.snapshot.diagnostics?.extensionBuild ?? "Not observed")
                row("Last Mail callback", timestamp(model.snapshot.lastMailActivity))
                row("Callbacks recorded", String(model.snapshot.diagnostics?.callbackCount ?? 0))
            }
            if model.snapshot.lastMailActivity == nil {
                Label(
                    "No Mail callback has been recorded. Check Mail’s extension settings and Console for launch failures.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.callout).foregroundStyle(.secondary)
            }
            Text("Recent processing events").font(.headline)
            Text(
                "Callbacks include Mail’s initial header delivery and its follow-up with the body. A Trash action is a request to Mail, not confirmation of a move."
            )
            .font(.caption).foregroundStyle(.secondary)
            if entries.isEmpty {
                Text("No processing events yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(entries) { entry in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(entry.senderDomain ?? "Unknown sender").fontWeight(.medium)
                            Spacer()
                            Text(entry.date, format: .dateTime.hour().minute().second())
                                .foregroundStyle(.secondary)
                        }
                        Text(entry.event.explanation).font(.callout)
                        Text("\(entry.event.rawValue) · \(entry.elapsedMilliseconds) ms · \(entry.traceID.uuidString)")
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }.padding(.vertical, 4)
                }
                .listStyle(.inset)
            }
            HStack {
                Button("Open Console") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Console.app"))
                }
                Text("Filter by subsystem: \(TransormaLog.subsystem)")
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Text(
                "Up to 300 events from the last seven days stay on this Mac. Sender domains appear here only; system logs contain event codes and trace IDs, without email content or unsubscribe tokens."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24).frame(width: 740, height: 650)
        .onAppear { model.refresh() }
        .accessibilityIdentifier("diagnostics-view")
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }

    private func timestamp(_ date: Date?) -> String {
        date?.formatted(date: .abbreviated, time: .standard) ?? "Not observed"
    }
}
