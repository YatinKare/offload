import Foundation
import CryptoKit
import Photos
import Darwin

struct ArchivedResource: Codable {
    let file: String
    let name: String
    let type: Int
    let sha256: String
    let bytes: Int64
}
struct Receipt: Codable, Identifiable {
    let id: String
    let assetID: String
    let modified: Date?
    let folder: String
    let resources: [ArchivedResource]
    let date: Date
    var bytes: Int64 { resources.reduce(0) { $0 + $1.bytes } }
}
enum ArchiveFailure: LocalizedError, Equatable {
    case message(String)
    case photoChanged
    case photoUnavailable
    case changedDuringCheck
    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        case .photoChanged: return "This photo differs from the saved copy. Archive it again, or keep it on your phone."
        case .photoUnavailable: return "Allow access to this photo in Settings, or keep the archive only."
        case .changedDuringCheck: return "The photo changed while checking. Try checking it again."
        }
    }
}
struct ArchiveStore {
    static func digest(_ url: URL) throws -> (String, Int64) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256(); var size: Int64 = 0
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data); size += Int64(data.count)
        }
        return (hasher.finalize().map { String(format: "%02x", $0) }.joined(), size)
    }
    static func validate(_ root: URL, simulation: Bool) throws {
        guard root.isFileURL else { throw ArchiveFailure.message("Select a folder on your USB drive.") }
        #if targetEnvironment(simulator)
        if simulation { guard FileManager.default.fileExists(atPath: root.path) else { throw ArchiveFailure.message("Test drive disconnected.") }; return }
        #endif
        var fresh = root; fresh.removeAllCachedResourceValues()
        let values = try fresh.resourceValues(forKeys: [.volumeIsInternalKey, .volumeIsLocalKey, .isUbiquitousItemKey, .isDirectoryKey])
        // iOS LiveFiles USB mounts may omit volumeIsInternal. Check the opened
        // mount itself in that case; never interpret missing metadata as approval.
        let mount = mountedFilesystem(root)
        let external = values.volumeIsInternal == false || (
            values.volumeIsInternal == nil && root.pathComponents.contains("LiveFiles") &&
            mount?.type == "lifs" && mount?.isLocal == true && mount?.isPhoneFilesystem == false
        )
        let accepted = external && values.volumeIsLocal == true &&
            values.isUbiquitousItem != true && values.isDirectory == true
        guard accepted else {
            throw ArchiveFailure.message("External drive could not be confirmed. Choose a folder under your USB drive in Files, not On My iPhone or iCloud. Unknown storage is blocked.")
        }
    }
    private struct MountedFilesystem {
        let type: String
        let isLocal: Bool
        let isPhoneFilesystem: Bool
    }
    private static func mountedFilesystem(_ root: URL) -> MountedFilesystem? {
        func inspect(_ url: URL, _ result: inout statfs) -> Bool {
            let descriptor = url.withUnsafeFileSystemRepresentation { path in path.map { Darwin.open($0, O_RDONLY | O_DIRECTORY) } ?? -1 }
            guard descriptor >= 0 else { return false }
            defer { Darwin.close(descriptor) }
            return Darwin.fstatfs(descriptor, &result) == 0
        }
        var selected = statfs()
        var phone = statfs()
        guard inspect(root, &selected), inspect(URL.documentsDirectory, &phone) else { return nil }
        let capacity = MemoryLayout.size(ofValue: selected.f_fstypename)
        let type = withUnsafePointer(to: &selected.f_fstypename) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { String(cString: $0) }
        }
        return MountedFilesystem(
            type: type,
            isLocal: selected.f_flags & UInt32(MNT_LOCAL) != 0,
            isPhoneFilesystem: selected.f_fsid.val.0 == phone.f_fsid.val.0 && selected.f_fsid.val.1 == phone.f_fsid.val.1
        )
    }
    static func export(_ asset: PHAsset, root: URL, simulation: Bool, progress: @escaping @Sendable (ArchiveStage) -> Void = { _ in }) async throws -> Receipt {
        try validate(root, simulation: simulation)
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--slow-archive") {
            try await Task.sleep(nanoseconds: 8_000_000_000)
        }
        #endif
        let resources = PHAssetResource.assetResources(for: asset)
        guard !resources.isEmpty else { throw ArchiveFailure.message("No original resources available.") }
        let id = UUID().uuidString
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: temp) }
        let destination = root.appendingPathComponent("Offload", isDirectory: true).appendingPathComponent(id, isDirectory: true)
        var entries: [ArchivedResource] = []
        for (index, resource) in resources.enumerated() {
            let name = "\(index)-\(URL(fileURLWithPath: resource.originalFilename).lastPathComponent)"
            let source = temp.appendingPathComponent(name)
            progress(.preparing)
            let options = PHAssetResourceRequestOptions(); options.isNetworkAccessAllowed = true
            options.progressHandler = { _ in progress(.downloading) }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                PHAssetResourceManager.default().writeData(for: resource, toFile: source, options: options) { error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
            }
            try validate(root, simulation: simulation)
            try Task.checkCancellation()
            let hash = try digest(source)
            progress(.copying)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            // UUID folders prevent overwriting any existing archive.
            let output = destination.appendingPathComponent(name)
            let coordinator = NSFileCoordinator()
            var coordinationError: NSError?; var copyError: Error?
            coordinator.coordinate(writingItemAt: output, options: .forReplacing, error: &coordinationError) { target in
                do { try FileManager.default.copyItem(at: source, to: target)
                    let handle = try FileHandle(forWritingTo: target); try handle.synchronize(); try handle.close()
                } catch { copyError = error }
            }
            if let error = coordinationError ?? copyError as NSError? { throw error }
            progress(.verifying)
            let copied = try digest(output)
            guard hash == copied, hash.1 > 0 else { throw ArchiveFailure.message("Copy verification failed. The photo stays on your phone.") }
            entries.append(ArchivedResource(file: name, name: resource.originalFilename, type: resource.type.rawValue, sha256: hash.0, bytes: hash.1))
        }
        let receipt = Receipt(id: id, assetID: asset.localIdentifier, modified: asset.modificationDate, folder: "Offload/" + id, resources: entries, date: Date())
        try JSONEncoder().encode(receipt).write(to: destination.appendingPathComponent("receipt.json"), options: .atomic)
        try verify(receipt, root: root, simulation: simulation)
        return receipt
    }
    /// Compare the current PhotoKit resources, not just their metadata timestamp.
    static func verifyOriginal(_ receipt: Receipt) async throws -> Date? {
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--slow-check") { try await Task.sleep(nanoseconds: 8_000_000_000) }
        #endif
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [receipt.assetID], options: nil).firstObject else { throw ArchiveFailure.photoUnavailable }
        let resources = PHAssetResource.assetResources(for: asset)
        guard resources.count == receipt.resources.count else { throw ArchiveFailure.photoChanged }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: temp) }
        var actual: [String] = []
        for (index, resource) in resources.enumerated() {
            try Task.checkCancellation()
            let file = temp.appendingPathComponent(String(index))
            let options = PHAssetResourceRequestOptions(); options.isNetworkAccessAllowed = true
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                PHAssetResourceManager.default().writeData(for: resource, toFile: file, options: options) { error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
            }
            try Task.checkCancellation()
            let hash = try digest(file)
            actual.append(resourceKey(resource.originalFilename, resource.type.rawValue, hash.0, hash.1))
        }
        let expected = receipt.resources.map { resourceKey($0.name, $0.type, $0.sha256, $0.bytes) }
        guard actual.sorted() == expected.sorted() else { throw ArchiveFailure.photoChanged }
        guard let fresh = PHAsset.fetchAssets(withLocalIdentifiers: [receipt.assetID], options: nil).firstObject else { throw ArchiveFailure.photoUnavailable }
        guard fresh.modificationDate == asset.modificationDate else { throw ArchiveFailure.changedDuringCheck }
        return fresh.modificationDate
    }
    private static func resourceKey(_ name: String, _ type: Int, _ hash: String, _ bytes: Int64) -> String {
        // Length-prefix names to avoid ambiguous delimiters; retain duplicates.
        return "\(name.utf8.count):\(name)\(type):\(hash):\(bytes)"
    }
    static func verify(_ receipt: Receipt, root: URL, simulation: Bool) throws {
        try validate(root, simulation: simulation)
        for entry in receipt.resources {
            let url = root.appendingPathComponent(receipt.folder).appendingPathComponent(entry.file)
            let actual = try digest(url)
            guard actual.0 == entry.sha256, actual.1 == entry.bytes else {
                throw ArchiveFailure.message("The saved copy is missing or changed. Archive this photo again.")
            }
        }
    }
}
