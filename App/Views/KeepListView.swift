import SwiftUI

struct KeepListView: View {
    @Environment(AppModel.self) private var model
    @Binding var keepEntry: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Make room for mail you want.").font(.title2.bold())
            Text(
                "Senders and domains here always stay in your inbox. Adding one also cancels pending unsubscribe requests for it."
            ).foregroundStyle(.secondary)
            HStack {
                TextField("Email address or domain", text: $keepEntry).textFieldStyle(.roundedBorder)
                    .onSubmit(addKeepEntry)
                Button("Add", action: addKeepEntry).disabled(keepEntry.isEmpty || !model.storageReady)
            }
            ForEach(model.snapshot.settings.allowedSenders, id: \.self) { entry in
                HStack {
                    Label(entry, systemImage: "heart.fill").foregroundStyle(.teal)
                    Spacer()
                    Button("Remove") { model.removeKeptSender(entry) }
                }.padding(12).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func addKeepEntry() {
        if model.keep(keepEntry) { keepEntry = "" }
    }
}
