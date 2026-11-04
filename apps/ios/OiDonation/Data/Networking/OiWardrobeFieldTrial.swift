import Foundation

/// Device-only test snapshot. Never used as a public story or sent to the API.
struct OiWardrobeFieldTrial: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var latitude: Double
    var longitude: Double
    var heading: Double
    var look: OiWardrobeLook
    var savedAt = Date()
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static let heightMeters = 1.5
    var isValid: Bool {
        !name.isEmpty && name.count <= 60 && latitude.isFinite && longitude.isFinite && heading.isFinite &&
        (-90...90).contains(latitude) && (-180...180).contains(longitude) && (0..<360).contains(heading) &&
        look.artwork.isValid && [look.topColor, look.bottomColor, look.shoeColor].allSatisfy { $0 <= 0xFFFFFF }
    }
}

struct OiWardrobeFieldTrialRepository {
    let url: URL
    private struct Document: Codable { var version = 1; var trial: OiWardrobeFieldTrial }
    private static let maximumBytes = 12 * 1024 * 1024
    init(url: URL = URL.applicationSupportDirectory.appending(path: "OiDonation/wardrobe-field-trial-v1.json")) { self.url = url }

    func load() throws -> OiWardrobeFieldTrial? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= Self.maximumBytes else { throw Failure.unreadable }
        do {
            let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url))
            guard document.version == 1, document.trial.isValid else { throw Failure.unreadable }
            return document.trial
        } catch { throw Failure.unreadable }
    }
    func save(_ trial: OiWardrobeFieldTrial) throws {
        // A damaged snapshot must be explicitly deleted, never silently replaced.
        _ = try load()
        guard trial.isValid else { throw Failure.invalid }
        let data = try JSONEncoder().encode(Document(trial: trial))
        guard data.count <= Self.maximumBytes else { throw Failure.invalid }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
        var target = url, values = URLResourceValues()
        values.isExcludedFromBackup = true
        try target.setResourceValues(values)
    }
    func remove() throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
    enum Failure: LocalizedError {
        case unreadable, invalid
        var errorDescription: String? {
            switch self {
            case .unreadable: "저장된 테스트를 읽지 못했어요. 다시 시도하거나 테스트를 삭제해 주세요. 원본은 보존됩니다."
            case .invalid: "위치·방향·사진 용량을 확인해 주세요."
            }
        }
    }
}
