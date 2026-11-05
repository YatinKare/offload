import SwiftUI
import Photos

struct ArchiveView: View {
    @ObservedObject var model: ReviewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showDrive = false
    var body: some View {
        NavigationStack {
            List {
                if model.items.isEmpty {
                    ContentUnavailableView("Archive is empty", systemImage: "tray")
                }
                ForEach(model.items) { item in
                    NavigationLink {
                        ArchiveDetailView(model: model, id: item.id)
                    } label: {
                        HStack(spacing: 14) {
                            ArchivePhoto(assetID: item.id).frame(width: 64, height: 72).clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(photoTitle(item.id, fallback: item.receipt?.resources.first?.name, compact: true)).lineLimit(1)
                                Text(model.checkingIDs.contains(item.id) ? "Checking" : item.status).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if item.isPending || model.checkingIDs.contains(item.id) { ProgressView() }
                            else if item.phase == .saved { Image(systemName: "checkmark.circle").foregroundStyle(.green) }
                            else { Image(systemName: "exclamationmark.circle").foregroundStyle(.orange) }
                        }
                    }.accessibilityIdentifier("archiveItem")
                }
                if model.pendingCount > 0 {
                    Section {
                        Text(model.root == nil ? "Connect your archive drive to continue." : "Keep Offload open while copying. Your decisions are saved if you leave.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let notice = model.archiveNotice { Section { Text(notice).font(.subheadline).accessibilityIdentifier("archiveNotice") } }
            }
            .navigationTitle("Archive").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button { showDrive = true } label: { Image(systemName: "externaldrive") }.accessibilityLabel("Manage drive") }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                if model.removalBusy {
                    Button("Cancel check") { model.cancelChecks() }.padding().accessibilityIdentifier("cancelCheck")
                } else if model.hasCheckableCopies {
                    Button(model.root == nil ? "Connect drive" : "Verify & remove") {
                        if model.root == nil { showDrive = true } else { model.prepareRemoval() }
                    }.buttonStyle(.borderedProminent).padding().accessibilityIdentifier("verifyArchive")
                }
            }
            .sheet(isPresented: $showDrive) { DriveView(model: model) }
            .alert("Remove \(model.removableCount) verified \(model.removableCount == 1 ? "photo" : "photos")?", isPresented: $model.showRemoval) {
                Button("Cancel", role: .cancel) {}
                Button("Remove from Photos", role: .destructive) { model.removeVerified() }.accessibilityIdentifier("confirmRemoval")
            } message: {
                Text("Copies checked on your drive. iCloud deletion syncs across devices. Recently Deleted may hold the originals for 30 days before space is freed. Items needing attention stay in the list.")
            }
        }
        .onAppear { model.refreshArchiveStatuses() }
        .onDisappear { model.cancelChecks() }
    }
}

private struct ArchiveDetailView: View {
    @ObservedObject var model: ReviewModel
    let id: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        List {
            if let item = model.item(id) {
                ArchivePhoto(assetID: id).frame(maxWidth: .infinity).frame(height: 300).listRowInsets(EdgeInsets())
                Section {
                    Text(photoTitle(id, fallback: item.receipt?.resources.first?.name))
                    HStack {
                        Text(model.checkingIDs.contains(id) ? "Checking" : item.status)
                        Spacer()
                        if item.isPending || model.checkingIDs.contains(id) { ProgressView() }
                    }.accessibilityIdentifier("itemStatus")
                    if let issue = item.issue { Text(issue).font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("itemIssue") }
                }
                Section {
                    if item.receipt != nil {
                        Button("Check copy") { model.checkItem(id) }.disabled(item.isPending || model.removalBusy || model.root == nil).accessibilityIdentifier("checkCopy")
                    }
                    Button(item.receipt == nil ? "Retry copy" : "Archive again") { model.archiveAgain(id) }
                        .disabled(item.isPending || model.removalBusy).accessibilityIdentifier("archiveAgain")
                    Button("Keep on phone") { model.keepOnPhone(id); dismiss() }
                        .disabled(model.removalBusy).accessibilityIdentifier("keepArchivedOnPhone")
                } footer: { Text("Keeping removes this item from the list. The original and any drive copy stay where they are.") }
            }
        }.navigationTitle("Photo").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.removalBusy { ToolbarItem(placement: .topBarTrailing) { Button("Cancel check") { model.cancelChecks() }.accessibilityIdentifier("cancelCheck") } }
        }
    }
}

private func photoTitle(_ id: String, fallback: String?, compact: Bool = false) -> String {
    if let date = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject?.creationDate {
        return date.formatted(date: .abbreviated, time: compact ? .omitted : .shortened)
    }
    return fallback ?? "Photo unavailable"
}

private struct ArchivePhoto: View {
    let assetID: String
    @State private var image: UIImage?
    @State private var request: PHImageRequestID?
    var body: some View {
        ZStack {
            Color.secondary.opacity(0.08)
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else { Image(systemName: "photo").foregroundStyle(.secondary) }
        }
        .accessibilityElement(children: .ignore).accessibilityLabel("Archived photo preview").accessibilityIdentifier("archivePreview")
        .task(id: assetID) {
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject else { return }
            let options = PHImageRequestOptions(); options.isNetworkAccessAllowed = true; options.deliveryMode = .opportunistic
            request = PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 800, height: 1000), contentMode: .aspectFit, options: options) { result, _ in
                Task { @MainActor in image = result }
            }
        }
        .onDisappear { if let request { PHImageManager.default().cancelImageRequest(request) } }
    }
}
