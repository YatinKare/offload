import Foundation
import Photos

/// File IO and source verification run away from the UI actor.
actor ArchiveWorker {
    func export(assetID: String, root: URL, simulation: Bool, progress: @escaping @Sendable (ArchiveStage) -> Void) async throws -> Receipt {
        let accessing = root.startAccessingSecurityScopedResource()
        defer { if accessing { root.stopAccessingSecurityScopedResource() } }
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject else { throw ArchiveFailure.photoUnavailable }
        return try await ArchiveStore.export(asset, root: root, simulation: simulation, progress: progress)
    }
    func check(_ receipt: Receipt, root: URL, simulation: Bool) async throws -> Receipt {
        let accessing = root.startAccessingSecurityScopedResource()
        defer { if accessing { root.stopAccessingSecurityScopedResource() } }
        try Task.checkCancellation()
        try ArchiveStore.verify(receipt, root: root, simulation: simulation)
        let modified = try await ArchiveStore.verifyOriginal(receipt)
        try Task.checkCancellation()
        return Receipt(id: receipt.id, assetID: receipt.assetID, modified: modified, folder: receipt.folder, resources: receipt.resources, date: receipt.date)
    }
    func driveAvailable(_ root: URL, simulation: Bool) -> Bool {
        (try? ArchiveStore.validate(root, simulation: simulation)) != nil
    }
}
