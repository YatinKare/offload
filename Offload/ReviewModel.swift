import SwiftUI
import Photos
import UniformTypeIdentifiers

@MainActor final class ReviewModel: ObservableObject {
    @Published var assets: [PHAsset] = []
    @Published var image: UIImage?
    @Published var index = 0
    @Published var seconds = 5
    @Published var paused = false
    @Published var busy = false
    @Published var ready = false
    @Published var error: String?
    @Published var message = "Connect your drive to begin."
    @Published var root: URL?
    @Published var receipts: [Receipt] = []
    @Published var kept = 0
    @Published var showRemoval = false
    let simulation: Bool
    var current: PHAsset? { assets.indices.contains(index) ? assets[index] : nil }
    var finished: Bool { ready && current == nil }
    var archivedBytes: Int64 { receipts.reduce(0) { $0 + $1.bytes } }
    var history: [(Int, Bool)] = []
    var imageRequest: PHImageRequestID?
    private var loadingImage = false
    private var fixtureIDs: [String] = []
    private var accessURL: URL?
    private let stateURL = URL.documentsDirectory.appendingPathComponent("receipts.json")
    init() {
        #if targetEnvironment(simulator)
        simulation = ProcessInfo.processInfo.arguments.contains("--uitesting")
        #else
        simulation = false
        #endif
        if !simulation, let data = try? Data(contentsOf: stateURL), let saved = try? JSONDecoder().decode([Receipt].self, from: data) { receipts = saved }
    }
    func save() throws { if !simulation { try JSONEncoder().encode(receipts).write(to: stateURL, options: .atomic) } }
    func chooseDrive(_ url: URL) {
        guard !busy else { return }
        do {
            if let accessURL { accessURL.stopAccessingSecurityScopedResource(); self.accessURL = nil }
            if url.startAccessingSecurityScopedResource() { accessURL = url }
            try ArchiveStore.validate(url, simulation: false)
            // Ensure the selected destination supports a complete write/read cycle.
            let probe = url.appendingPathComponent(".offload-\(UUID().uuidString)")
            let data = Data(UUID().uuidString.utf8)
            try data.write(to: probe, options: .withoutOverwriting)
            defer { try? FileManager.default.removeItem(at: probe) }
            guard try Data(contentsOf: probe) == data else { throw ArchiveFailure.message("Drive write test failed.") }
            root = url; message = "External drive connected"
        } catch {
            root = nil; self.error = error.localizedDescription
        }
    }
    func connectTestDrive() {
        #if targetEnvironment(simulator)
        guard simulation else { return }
        let url = URL.documentsDirectory.appendingPathComponent("TestDrive")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        root = url; message = "Simulator folder • not a USB drive"
        #endif
    }
    func disconnectTestDrive() {
        #if targetEnvironment(simulator)
        guard simulation else { return }; root = nil; message = "Test drive disconnected"
        #endif
    }
    func load() async {
        busy = true; defer { busy = false }
        let permission = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard permission == .authorized || permission == .limited else { error = "Allow photo access in Settings to review your library."; return }
        #if targetEnvironment(simulator)
        if simulation {
            do { try await seed() } catch { self.error = error.localizedDescription; return }
        }
        #endif
        let options = PHFetchOptions(); options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
        let all = PHAsset.fetchAssets(with: options)
        var loaded: [PHAsset] = []
        let archived = Set(receipts.map(\.assetID))
        all.enumerateObjects { asset, _, _ in
            if !archived.contains(asset.localIdentifier) && (!self.simulation || self.fixtureIDs.contains(asset.localIdentifier)) { loaded.append(asset) }
        }
        assets = loaded; index = 0; ready = true; display()
    }
    func display() {
        if let imageRequest { PHImageManager.default().cancelImageRequest(imageRequest) }
        image = nil; seconds = 5; loadingImage = true
        guard let asset = current else { loadingImage = false; return }
        let id = asset.localIdentifier
        let options = PHImageRequestOptions(); options.isNetworkAccessAllowed = true; options.deliveryMode = .highQualityFormat
        imageRequest = PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 1200, height: 1600), contentMode: .aspectFit, options: options) { image, info in
            Task { @MainActor in
                guard self.current?.localIdentifier == id else { return }
                self.image = image
                if info?[PHImageResultIsDegradedKey] as? Bool != true { self.loadingImage = false }
            }
        }
    }
    func tick(active: Bool) {
        guard active, ready, !paused, !busy, !loadingImage, current != nil else { return }
        if seconds > 1 { seconds -= 1 } else { keep(timedOut: true) }
    }
    func keep(timedOut: Bool = false) {
        guard current != nil, !busy else { return }
        history.append((index, false)); kept += 1; index += 1
        message = timedOut ? "Time’s up. Kept on your phone." : "Kept on your phone."
        display()
    }
    func undo() {
        guard !busy, let last = history.popLast() else { return }
        if !last.1 { kept -= 1 }
        // An undo returns to review; existing verified copies stay on disk.
        if last.1, let asset = assets[safe: last.0] { receipts.removeAll { $0.assetID == asset.localIdentifier }; try? save() }
        index = last.0; message = "Back for another look. Existing copies stay on the drive."; display()
    }
    func archive() async {
        guard !busy, let asset = current else { return }
        guard let root else { error = "Connect an external drive first. Your photo stays on your phone."; return }
        busy = true; defer { busy = false }
        do {
            let receipt = try await ArchiveStore.export(asset, root: root, simulation: simulation)
            receipts.append(receipt)
            do { try save() } catch { receipts.removeLast(); throw error }
            history.append((index, true)); index += 1
            message = "Copied and SHA-256 verified. Still on your phone."; display()
        } catch { self.error = error.localizedDescription; message = "Archive failed. Photo kept on phone." }
    }
    func removeVerified() async {
        guard !busy, let root, !receipts.isEmpty else { error = "Reconnect your archive drive first."; return }
        busy = true; defer { busy = false }
        do {
            var deleting: [PHAsset] = []
            for receipt in receipts {
                try ArchiveStore.verify(receipt, root: root, simulation: simulation)
                guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [receipt.assetID], options: nil).firstObject else { continue }
                guard asset.modificationDate == receipt.modified else { throw ArchiveFailure.message("A photo was edited after archiving. Archive it again before removing it.") }
                let actual = PHAssetResource.assetResources(for: asset)
                guard actual.count == receipt.resources.count,
                      zip(actual, receipt.resources).allSatisfy({ $0.originalFilename == $1.name && $0.type.rawValue == $1.type }) else {
                    throw ArchiveFailure.message("Photo resources changed. Removal blocked.")
                }
                deleting.append(asset)
            }
            try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.deleteAssets(deleting as NSArray) }
            receipts = []; try save(); message = "Removed from library. Archive remains on your drive."
        } catch { self.error = "Removal blocked: \(error.localizedDescription)" }
    }
    #if targetEnvironment(simulator)
    func seed() async throws {
        // Test code is unreachable on physical devices, even with launch arguments.
        let colors: [UIColor] = [.systemTeal, .systemOrange, .systemIndigo]
        var photos: [Data] = []
        for (i, color) in colors.enumerated() {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 1200)).image { ctx in
                color.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 900, height: 1200))
                UIColor.black.withAlphaComponent(0.15).setFill()
                for j in 0..<9 { ctx.fill(CGRect(x: j * 120 - 80, y: 500 - (j % 3) * 80, width: 100, height: 800)) }

            }
            photos.append(image.jpegData(compressionQuality: 0.9)!)
        }
        var identifiers: [String] = []
        try await PHPhotoLibrary.shared().performChanges {
            for (i, data) in photos.enumerated() {
                let request = PHAssetCreationRequest.forAsset(); request.creationDate = Date().addingTimeInterval(Double(-i * 100))
                let options = PHAssetResourceCreationOptions(); options.originalFilename = "Offload-Test.jpg"
                request.addResource(with: .photo, data: data, options: options)
                if let id = request.placeholderForCreatedAsset?.localIdentifier { identifiers.append(id) }
            }
        }
        fixtureIDs = identifiers
    }
    func corruptTestCopy() {
        guard simulation, let receipt = receipts.first, let entry = receipt.resources.first, let root else { return }
        try? Data("corrupted".utf8).write(to: root.appendingPathComponent(receipt.folder).appendingPathComponent(entry.file))
        message = "Test archive corrupted"
    }
    #endif
}
extension Array { subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil } }
