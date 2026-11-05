import SwiftUI
import UniformTypeIdentifiers

struct DriveView: View {
    @ObservedObject var model: ReviewModel
    @Environment(\.dismiss) private var dismiss
    @State private var picker = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(model.root?.lastPathComponent ?? "Not connected", systemImage: "externaldrive")
                    Button("Choose drive") { picker = true }.disabled(!model.canChangeDrive)
                } header: { Text("Archive drive") } footer: {
                    if !model.canChangeDrive { Text("Wait for the current copy or check before changing drives.") }
                }
                if !model.items.isEmpty {
                    Section {
                        Label("\(model.receipts.count) saved", systemImage: "checkmark.shield")
                        if model.pendingCount > 0 { Label("\(model.pendingCount) waiting", systemImage: "clock") }
                    }
                }
            }
            .navigationTitle("Drive").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .fileImporter(isPresented: $picker, allowedContentTypes: [.folder]) { result in
                switch result { case .success(let url): model.chooseDrive(url); case .failure(let error): model.error = error.localizedDescription }
            }
            .alert("Couldn't finish", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
        }.presentationDetents([.medium, .large])
    }
}
