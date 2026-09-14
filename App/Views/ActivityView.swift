import SwiftUI
import TransormaCore

struct ActivityView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.snapshot.jobs.isEmpty {
            Text("No activity yet")
                .font(.title3).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(
                        "The last seven days of unsubscribe requests. An accepted request means the sender’s server accepted it; delivery may take time to stop."
                    )
                    .foregroundStyle(.secondary)
                    Text("Queued requests resume automatically when Transorma runs, including after the Mac wakes.")
                        .font(.callout).foregroundStyle(.secondary)
                    if model.pendingUnsubscribeCount > 0 {
                        Label(model.protectionStatus, systemImage: "tray.full")
                            .font(.callout.weight(.medium))
                    }
                    ForEach(model.snapshot.jobs.sorted { $0.createdAt > $1.createdAt }) { job in
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(job.sender).font(.headline).textSelection(.enabled)
                                    Spacer()
                                    Text(job.status.label).font(.caption).foregroundStyle(.secondary)
                                }
                                Text(job.detail).font(.callout).foregroundStyle(.secondary)
                                Text(job.updatedAt, format: .dateTime.month().day().hour().minute()).font(.caption)
                                    .foregroundStyle(.tertiary)
                            }.padding(8)
                        }
                    }
                    Button("Clear completed activity") { model.clearHistory() }
                }
                .padding(32).frame(maxWidth: 820, alignment: .leading).frame(maxWidth: .infinity)
            }
        }
    }

}

extension JobStatus {
    fileprivate var label: String {
        switch self {
        case .pending: "Waiting"
        case .processing: "Unsubscribing"
        case .accepted: "Request accepted"
        case .confirmed: "Unsubscribe confirmed"
        case .unsupported: "Could not finish automatically"
        case .uncertain: "Outcome unknown"
        case .failed: "Request failed"
        case .cancelled: "Cancelled"
        }
    }
}
