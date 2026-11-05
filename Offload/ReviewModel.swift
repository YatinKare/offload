import SwiftUI
import Photos

@MainActor final class ReviewModel: ObservableObject {
    @Published var assets: [PHAsset] = []
    @Published var image: UIImage?
    @Published var index = 0
    @Published var seconds = 5
    @Published var paused = false
    @Published var busy = false
    @Published var ready = false
    @Published var error: String?
    @Published var root: URL?
    @Published private(set) var items: [ArchiveItem] = []
    @Published var kept = 0
    @Published var showRemoval = false
    @Published private(set) var processingID: String?
    @Published private(set) var checkingIDs: Set<String> = []
    @Published private(set) var removalBusy = false
    @Published private(set) var archiveNotice: String?
    let simulation: Bool
    var current: PHAsset? { assets[safe: index] }
    var finished: Bool { ready && current == nil }
    var receipts: [Receipt] { items.compactMap(\.receipt) }
    var pendingCount: Int { items.filter(\.isPending).count }
    var problemCount: Int { items.filter { [.failed, .needsReview, .unavailable].contains($0.phase) }.count }
    var canChangeDrive: Bool { processingID == nil && !removalBusy }
    var removableCount: Int { removalIDs.count }
    var hasCheckableCopies: Bool { items.contains { $0.receipt != nil && !$0.isPending } }
    var history: [(Int, Bool)] = []
    private var imageRequest: PHImageRequestID?
    private var loadingImage = false
    private var remainingTime: TimeInterval = 5
    private var lastTick = Date()
    private var fixtureIDs: [String] = []
    private var accessURL: URL?
    private let journal = ArchiveJournal(directory: .documentsDirectory)
    private let worker = ArchiveWorker()
    private var pumpTask: Task<Void, Never>?
    private var operationTask: Task<Void, Never>?
    private var operationToken = UUID()
    private var removalIDs: [String] = []

    init() {
        #if targetEnvironment(simulator)
        simulation = ProcessInfo.processInfo.arguments.contains("--uitesting")
        if simulation && ProcessInfo.processInfo.arguments.contains("--reset-session") { journal.resetTestSession() }
        #else
        simulation = false
        #endif
        do { items = try journal.load() }
        catch { self.error = "Couldn't open the archive list. Existing copies remain on your drive." }
    }
    func item(_ id: String) -> ArchiveItem? { items.first { $0.id == id } }
    private func save() throws { try journal.save(items) }
    func chooseDrive(_ url: URL) {
        guard canChangeDrive else { return }
        do {
            if let accessURL { accessURL.stopAccessingSecurityScopedResource(); self.accessURL = nil }
            if url.startAccessingSecurityScopedResource() { accessURL = url }
            try ArchiveStore.validate(url, simulation: false)
            let probe = url.appendingPathComponent(".offload-\(UUID().uuidString)")
            let data = Data(UUID().uuidString.utf8)
            try data.write(to: probe, options: .withoutOverwriting)
            defer { try? FileManager.default.removeItem(at: probe) }
            guard try Data(contentsOf: probe) == data else { throw ArchiveFailure.message("Drive write test failed.") }
            root = url; scheduleCopies()
        } catch { root = nil; self.error = error.localizedDescription }
    }
    func connectTestDrive() {
        #if targetEnvironment(simulator)
        guard simulation else { return }
        let url = URL.documentsDirectory.appendingPathComponent("TestDrive")
        let disconnected = url.appendingPathExtension("disconnected")
        if !FileManager.default.fileExists(atPath: url.path), FileManager.default.fileExists(atPath: disconnected.path) { try? FileManager.default.moveItem(at: disconnected, to: url) }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        root = url; setTestDriveWritable(true); scheduleCopies()
        #endif
    }
    func disconnectTestDrive() {
        #if targetEnvironment(simulator)
        guard simulation else { return }
        if let root { try? FileManager.default.moveItem(at: root, to: root.appendingPathExtension("disconnected")) }
        root = nil
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
        let classified = Set(items.map(\.id))
        all.enumerateObjects { asset, _, _ in
            if !classified.contains(asset.localIdentifier) && (!self.simulation || self.fixtureIDs.contains(asset.localIdentifier)) { loaded.append(asset) }
        }
        assets = loaded; index = 0; ready = true; display()
    }
    private func display() {
        if let imageRequest { PHImageManager.default().cancelImageRequest(imageRequest) }
        image = nil; seconds = 5; remainingTime = 5; lastTick = Date(); loadingImage = true
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
        let now = Date(); let elapsed = min(now.timeIntervalSince(lastTick), 0.25); lastTick = now
        guard active, ready, !paused, !busy, !loadingImage, current != nil else { return }
        remainingTime = max(0, remainingTime - elapsed)
        let value = Int(ceil(remainingTime)); if seconds != value { seconds = value }
        if remainingTime == 0 { keep() }
    }
    func keep() {
        guard current != nil, !busy else { return }
        history.append((index, false)); kept += 1; index += 1; display()
    }
    func undo() {
        guard !busy, let last = history.last else { return }
        let previous = items
        if last.1, let asset = assets[safe: last.0] { items.removeAll { $0.id == asset.localIdentifier } }
        do { try save() } catch { items = previous; self.error = "Couldn't save this choice. Try again."; return }
        history.removeLast()
        if !last.1 { kept -= 1 }
        index = last.0; display()
    }
    /// Commit the decision and advance immediately; copying is a separate job.
    func archive() {
        guard !busy, let asset = current else { return }
        guard root != nil else { error = "Connect a drive to archive."; return }
        let previous = items
        items.removeAll { $0.id == asset.localIdentifier }
        items.append(ArchiveItem(assetID: asset.localIdentifier))
        do { try save() } catch { items = previous; self.error = "Couldn't save this choice. Your photo stays here."; return }
        history.append((index, true)); index += 1; display(); scheduleCopies()
    }
    func archiveAgain(_ id: String) {
        guard !removalBusy, let position = items.firstIndex(where: { $0.id == id }) else { return }
        let previous = items
        items[position].jobID = UUID().uuidString
        items[position].phase = .queued; items[position].stage = nil; items[position].issue = nil
        do { try save() } catch { items = previous; self.error = "Couldn't save this choice. Try again."; return }
        scheduleCopies()
    }
    func keepOnPhone(_ id: String) {
        guard !removalBusy else { return }
        let previous = items; items.removeAll { $0.id == id }
        do { try save() } catch { items = previous; self.error = "Couldn't save this choice. Try again."; return }
        kept += 1
    }
    private func scheduleCopies() {
        guard pumpTask == nil, root != nil, items.contains(where: { $0.phase == .queued }) else { return }
        pumpTask = Task { [weak self] in await self?.processCopies() }
    }
    private func processCopies() async {
        defer { processingID = nil; pumpTask = nil }
        while let drive = root, let position = items.firstIndex(where: { $0.phase == .queued }) {
            let job = items[position]
            items[position].phase = .copying; items[position].stage = .preparing; processingID = job.id
            do { try save() } catch { self.error = "Couldn't save the archive queue."; items[position].phase = .failed; return }
            do {
                let receipt = try await worker.export(assetID: job.id, root: drive, simulation: simulation) { [weak self] stage in
                    Task { @MainActor in
                        guard let self, let i = self.items.firstIndex(where: { $0.id == job.id && $0.jobID == job.jobID }), self.items[i].phase == .copying else { return }
                        if self.items[i].stage != stage { self.items[i].stage = stage }
                    }
                }
                // Undo/Keep or a new job for the same photo must not be overwritten.
                guard let i = items.firstIndex(where: { $0.id == job.id && $0.jobID == job.jobID }) else { continue }
                let previous = items[i]
                items[i].receipt = receipt; items[i].phase = .saved; items[i].stage = nil; items[i].issue = nil
                do { try save() }
                catch { items[i] = previous; items[i].phase = .failed; items[i].issue = "Couldn't save the archive record. Retry to make a tracked copy." }
            } catch {
                let available = await worker.driveAvailable(drive, simulation: simulation)
                if !available { root = nil }
                if let i = items.firstIndex(where: { $0.id == job.id && $0.jobID == job.jobID }) {
                    items[i].phase = !available ? .queued : (error as? ArchiveFailure) == .photoUnavailable ? .unavailable : .failed
                    items[i].stage = nil
                    items[i].issue = available ? error.localizedDescription : "Reconnect your archive drive to continue."
                    try? save()
                }
            }
        }
    }
    func refreshArchiveStatuses() {
        for i in items.indices where !items[i].isPending && items[i].receipt != nil {
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [items[i].id], options: nil).firstObject else {
                items[i].phase = .unavailable; items[i].issue = ArchiveFailure.photoUnavailable.localizedDescription; continue
            }
            if asset.modificationDate != items[i].receipt?.modified && items[i].phase == .saved {
                items[i].phase = .needsReview; items[i].issue = "Check this photo, or archive its current version again."
            }
        }
        try? save()
    }
    func checkItem(_ id: String) { beginCheck(ids: [id], forRemoval: false) }
    func prepareRemoval() { beginCheck(ids: items.filter { $0.receipt != nil && !$0.isPending }.map(\.id), forRemoval: true) }
    private func beginCheck(ids: [String], forRemoval: Bool) {
        guard !removalBusy else { return }
        guard let drive = root else { archiveNotice = "Connect the drive containing your copies."; return }
        guard !ids.isEmpty else { return }
        archiveNotice = nil; removalIDs = []; removalBusy = true
        let token = UUID(); operationToken = token
        operationTask = Task { [weak self] in await self?.performChecks(ids: ids, drive: drive, forRemoval: forRemoval, token: token) }
    }
    private func performChecks(ids: [String], drive: URL, forRemoval: Bool, token: UUID) async {
        defer { finishOperation(token) }
        var matches: [String] = []
        for id in ids {
            guard !Task.isCancelled, token == operationToken, let receipt = item(id)?.receipt, item(id)?.isPending == false else { continue }
            checkingIDs = [id]
            do {
                let checked = try await worker.check(receipt, root: drive, simulation: simulation)
                try Task.checkCancellation()
                guard token == operationToken, let i = items.firstIndex(where: { $0.id == id && $0.receipt?.id == receipt.id && !$0.isPending }) else { continue }
                items[i].receipt = checked; items[i].phase = .saved; items[i].issue = nil; matches.append(id)
            } catch is CancellationError { return }
            catch { if token == operationToken { markProblem(id, error) } }
        }
        guard !Task.isCancelled, token == operationToken else { return }
        do { try save() } catch { archiveNotice = "Couldn't save the checks. Try again."; return }
        if forRemoval {
            removalIDs = matches
            if matches.isEmpty { archiveNotice = "Review the items needing attention below." }
            else { showRemoval = true }
        }
    }
    func removeVerified() {
        guard !removalBusy, let drive = root, !removalIDs.isEmpty else { return }
        let ids = removalIDs; removalBusy = true; archiveNotice = nil
        let token = UUID(); operationToken = token
        operationTask = Task { [weak self] in await self?.performRemoval(ids: ids, drive: drive, token: token) }
    }
    private func performRemoval(ids: [String], drive: URL, token: UUID) async {
        defer { finishOperation(token) }
        var deleting: [PHAsset] = []
        do {
            // Check again after the app confirmation; never trust a stale result.
            for id in ids {
                try Task.checkCancellation()
                guard token == operationToken, let receipt = item(id)?.receipt, item(id)?.isPending == false else { throw CancellationError() }
                checkingIDs = [id]
                do {
                    let checked = try await worker.check(receipt, root: drive, simulation: simulation)
                    try Task.checkCancellation()
                    guard token == operationToken, let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject,
                          asset.modificationDate == checked.modified else { throw ArchiveFailure.changedDuringCheck }
                    deleting.append(asset)
                } catch is CancellationError { throw CancellationError() }
                catch { markProblem(id, error); throw error }
            }
            try Task.checkCancellation()
            guard token == operationToken else { return }
            try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.deleteAssets(deleting as NSArray) }
            items.removeAll { ids.contains($0.id) }; removalIDs = []; try save()
            archiveNotice = "Removed from Photos. Copies remain on your drive."
        } catch is CancellationError { }
        catch { if token == operationToken { archiveNotice = "Removal stopped. Review the item needing attention."; try? save() } }
    }
    private func markProblem(_ id: String, _ error: Error) {
        guard let i = items.firstIndex(where: { $0.id == id && !$0.isPending }) else { return }
        items[i].phase = (error as? ArchiveFailure) == .photoUnavailable ? .unavailable : .needsReview
        items[i].issue = error.localizedDescription
    }
    func cancelChecks() {
        operationTask?.cancel(); operationTask = nil; operationToken = UUID()
        removalBusy = false; checkingIDs = []; removalIDs = []; showRemoval = false
    }
    private func finishOperation(_ token: UUID) {
        guard token == operationToken else { return }
        removalBusy = false; checkingIDs = []; operationTask = nil
    }
    #if targetEnvironment(simulator)
    func seed() async throws {
        // Test code is unreachable on physical devices, even with launch arguments.
        let fixtureFile = URL.documentsDirectory.appendingPathComponent("test-fixtures.json")
        if let data = try? Data(contentsOf: fixtureFile), let saved = try? JSONDecoder().decode([String].self, from: data) { fixtureIDs = saved; return }
        let colors: [UIColor] = [.systemTeal, .systemOrange, .systemIndigo]
        var photos: [Data] = []
        for color in colors {
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
        try JSONEncoder().encode(identifiers).write(to: fixtureFile, options: .atomic)
    }
    func makeLegacyTestIndex() {
        guard simulation else { return }
        let old = receipts.map { receipt in
            Receipt(id: receipt.id, assetID: receipt.assetID, modified: Date(timeIntervalSince1970: 1), folder: receipt.folder, resources: receipt.resources, date: receipt.date)
        }
        try? JSONEncoder().encode(old).write(to: URL.documentsDirectory.appendingPathComponent("receipts.json"), options: .atomic)
        try? FileManager.default.removeItem(at: URL.documentsDirectory.appendingPathComponent("archive-items.json"))
    }
    func staleTestReceiptDate() {
        guard simulation, let i = items.firstIndex(where: { $0.receipt != nil }), let receipt = items[i].receipt else { return }
        items[i].receipt = Receipt(id: receipt.id, assetID: receipt.assetID, modified: Date(timeIntervalSince1970: 1), folder: receipt.folder, resources: receipt.resources, date: receipt.date)
        try? save()
    }
    func editTestPhoto() async {
        guard simulation, let id = items.first?.id, let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return }
        do {
            let input: PHContentEditingInput = try await withCheckedThrowingContinuation { continuation in
                asset.requestContentEditingInput(with: nil) { input, _ in
                    if let input { continuation.resume(returning: input) } else { continuation.resume(throwing: ArchiveFailure.photoUnavailable) }
                }
            }
            let output = PHContentEditingOutput(contentEditingInput: input)
            let image = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 1200)).image { context in
                UIColor.systemPink.setFill(); context.fill(CGRect(x: 0, y: 0, width: 900, height: 1200))
            }
            try image.jpegData(compressionQuality: 0.9)!.write(to: output.renderedContentURL)
            output.adjustmentData = PHAdjustmentData(formatIdentifier: "dev.offload.tests", formatVersion: "1", data: Data("edit".utf8))
            try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest(for: asset).contentEditingOutput = output }
            refreshArchiveStatuses()
        } catch { self.error = error.localizedDescription }
    }
    func setTestDriveWritable(_ writable: Bool) {
        guard simulation, let root else { return }
        for url in [root, root.appendingPathComponent("Offload")] {
            try? FileManager.default.setAttributes([.posixPermissions: writable ? 0o755 : 0o555], ofItemAtPath: url.path)
        }
    }
    func corruptTestCopy() {
        guard simulation, let receipt = receipts.first, let entry = receipt.resources.first, let root else { return }
        try? Data("corrupted".utf8).write(to: root.appendingPathComponent(receipt.folder).appendingPathComponent(entry.file))

    }
    #endif
}
extension Array { subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil } }
