import Foundation

/// A durable archive decision. A queued decision is not a verified backup.
struct ArchiveItem: Codable, Identifiable {
    enum Phase: String, Codable { case queued, copying, saved, failed, needsReview, unavailable }
    let id: String
    var jobID: String
    var receipt: Receipt?
    var phase: Phase
    var issue: String?
    var created: Date
    var stage: ArchiveStage?

    init(assetID: String, receipt: Receipt? = nil) {
        id = assetID; jobID = UUID().uuidString; self.receipt = receipt
        phase = receipt == nil ? .queued : .saved
        created = receipt?.date ?? Date()
    }
    var isPending: Bool { phase == .queued || phase == .copying }
    var status: String {
        switch phase {
        case .queued: return "Waiting"
        case .copying: return stage?.title ?? "Preparing"
        case .saved: return "Saved"
        case .failed: return "Couldn't copy"
        case .needsReview: return "Check needed"
        case .unavailable: return "Photo unavailable"
        }
    }
}

enum ArchiveStage: String, Codable, Sendable {
    case preparing, downloading, copying, verifying
    var title: String {
        switch self {
        case .preparing: return "Preparing"
        case .downloading: return "Downloading"
        case .copying: return "Copying"
        case .verifying: return "Verifying"
        }
    }
}

struct ArchiveJournal {
    let directory: URL
    private var file: URL { directory.appendingPathComponent("archive-items.json") }
    func load() throws -> [ArchiveItem] {
        if FileManager.default.fileExists(atPath: file.path) {
            return try JSONDecoder().decode([ArchiveItem].self, from: Data(contentsOf: file)).map {
                var item = $0
                if item.phase == .copying { item.phase = .queued; item.stage = nil }
                return item
            }
        }
        // Migrate the existing receipt index without altering copies on the drive.
        let legacy = directory.appendingPathComponent("receipts.json")
        guard FileManager.default.fileExists(atPath: legacy.path) else { return [] }
        return try JSONDecoder().decode([Receipt].self, from: Data(contentsOf: legacy)).map { ArchiveItem(assetID: $0.assetID, receipt: $0) }
    }
    func save(_ items: [ArchiveItem]) throws {
        try JSONEncoder().encode(items).write(to: file, options: .atomic)
    }
    #if targetEnvironment(simulator)
    func resetTestSession() {
        for name in ["archive-items.json", "receipts.json", "test-fixtures.json"] {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }
    #endif
}
