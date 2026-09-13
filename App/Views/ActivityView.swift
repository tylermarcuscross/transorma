import SwiftUI
import TransormaCore

struct ActivityView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
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
