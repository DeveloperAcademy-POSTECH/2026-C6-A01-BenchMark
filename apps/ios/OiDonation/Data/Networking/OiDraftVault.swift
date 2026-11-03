// Created by 이돈혁

import Foundation

struct OiLocalDraft: Codable, Identifiable, Equatable {
    var draft: OiStoryDraft
    var photos: [UUID] = []
    var uploadedPhotos: [UUID] = []
    var version = 0
    var submitted = false
    var id: UUID { draft.id }
}

struct OiDraftListing {
    let drafts: [OiLocalDraft]
    let unreadableFiles: [String]
}

private struct OiUnreadableDraftsError: LocalizedError {
    let count: Int
    var errorDescription: String? { "기기 초안 \(count)개를 읽지 못했습니다. 원본은 그대로 보관했습니다." }
}

struct OiEvidenceOperation: Codable, Equatable {
    var requestID: UUID
    var uploadID: UUID
    var contentType: String
    var fileExtension: String
    var previousStatus: String?
    var previousPath: String?
    var phase: String
    var failure: String?
    var storageOwnerID: UUID? = nil

    func objectPath(owner: UUID) -> String {
        "\((storageOwnerID ?? owner).uuidString.lowercased())/\(requestID.uuidString.lowercased())/\(uploadID.uuidString.lowercased()).\(fileExtension)"
    }
}

actor OiDraftVault {
    private let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? URL.applicationSupportDirectory.appending(path: "oi-private-drafts", directoryHint: .isDirectory)
    }

    private func ownerDirectory(_ owner: UUID) throws -> URL {
        let url = directory.appending(path: owner.uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = url
        try mutable.setResourceValues(values)
        return url
    }

    private func write(_ data: Data, to url: URL) throws {
        #if os(iOS)
        try data.write(to: url, options: [.atomic,.completeFileProtection])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }

    func load(owner: UUID, id: UUID) throws -> OiLocalDraft? {
        let url = try ownerDirectory(owner).appending(path: "draft-\(id.uuidString).json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(OiLocalDraft.self, from: Data(contentsOf: url))
    }

    func save(_ record: OiLocalDraft, owner: UUID) throws {
        if let current = try load(owner: owner, id: record.id), current.version > record.version { return }
        let url = try ownerDirectory(owner).appending(path: "draft-\(record.id.uuidString).json")
        try write(JSONEncoder().encode(record), to: url)
    }

    func list(owner: UUID) throws -> [OiLocalDraft] {
        let result = try listing(owner: owner)
        guard result.unreadableFiles.isEmpty else { throw OiUnreadableDraftsError(count: result.unreadableFiles.count) }
        return result.drafts
    }

    func listing(owner: UUID) throws -> OiDraftListing {
        let folder = try ownerDirectory(owner)
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("draft-") && $0.pathExtension == "json" }
        var drafts: [OiLocalDraft] = []
        var unreadableFiles: [String] = []
        for file in files {
            // File-system failures must remain visible; only decoding failures are isolated.
            let data = try Data(contentsOf: file)
            do { drafts.append(try JSONDecoder().decode(OiLocalDraft.self, from: data)) }
            catch is DecodingError { unreadableFiles.append(file.lastPathComponent) }
        }
        return OiDraftListing(drafts: drafts.sorted { $0.id.uuidString < $1.id.uuidString },
                              unreadableFiles: unreadableFiles.sorted())
    }

    /// Copies account-scoped drafts after a verified server merge. Originals are never removed.
    func adoptDrafts(from owners: Set<UUID>, into target: UUID) throws -> Int {
        var unresolved = 0
        for owner in owners where owner != target {
            do {
                if var operation = try evidence(owner: owner), ["failed", "prepared", "uploading", "submitting"].contains(operation.phase) {
                    if let current = try evidence(owner: target) {
                        if current.uploadID != operation.uploadID { unresolved += 1 }
                    } else {
                        operation.storageOwnerID = operation.storageOwnerID ?? owner
                        let data = try attachment(owner: owner, id: operation.uploadID)
                        let destination = try ownerDirectory(target).appending(path: "attachment-\(operation.uploadID.uuidString)")
                        if FileManager.default.fileExists(atPath: destination.path), try Data(contentsOf: destination) != data {
                            throw OiServiceError.conflict
                        }
                        try saveAttachment(data, owner: target, id: operation.uploadID)
                        try saveEvidence(operation, owner: target)
                    }
                }
            } catch { unresolved += 1 }
            let sourceDirectory = try ownerDirectory(owner)
            let markerURL = sourceDirectory.appending(path: "adopted-drafts.json")
            var markers: [String: Int] = [:]
            if FileManager.default.fileExists(atPath: markerURL.path) {
                markers = try JSONDecoder().decode([String: Int].self, from: Data(contentsOf: markerURL))
            }
            let listing = try listing(owner: owner)
            unresolved += listing.unreadableFiles.count
            for record in listing.drafts {
                let marker = "\(target.uuidString)/\(record.id.uuidString)"
                if let adoptedVersion = markers[marker], adoptedVersion >= record.version { continue }
                do {
                    if let existing = try load(owner: target, id: record.id) {
                        if existing != record {
                            unresolved += 1; continue
                        }
                    } else {
                        var attachments: [(UUID, Data)] = []
                        for photoID in record.photos {
                            let data = try attachment(owner: owner, id: photoID)
                            let destination = try ownerDirectory(target).appending(path: "attachment-\(photoID.uuidString)")
                            if FileManager.default.fileExists(atPath: destination.path), try Data(contentsOf: destination) != data {
                                throw OiServiceError.conflict
                            }
                            attachments.append((photoID, data))
                        }
                        for (photoID, data) in attachments { try saveAttachment(data, owner: target, id: photoID) }
                        try save(record, owner: target)
                    }
                    markers[marker] = record.version
                    try write(JSONEncoder().encode(markers), to: markerURL)
                } catch { unresolved += 1 }
            }
        }
        return unresolved
    }

    func attachment(owner: UUID, id: UUID) throws -> Data {
        try Data(contentsOf: ownerDirectory(owner).appending(path: "attachment-\(id.uuidString)"))
    }

    func saveAttachment(_ data: Data, owner: UUID, id: UUID) throws {
        guard !data.isEmpty, data.count <= 10_485_760 else { throw OiServiceError.invalidInput }
        try write(data, to: ownerDirectory(owner).appending(path: "attachment-\(id.uuidString)"))
    }

    func discard(owner: UUID, id: UUID) throws {
        guard let record = try load(owner: owner, id: id) else { return }
        for photoID in record.photos {
            let url = try ownerDirectory(owner).appending(path: "attachment-\(photoID.uuidString)")
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
        try FileManager.default.removeItem(at: ownerDirectory(owner).appending(path: "draft-\(id.uuidString).json"))
    }

    func evidence(owner: UUID) throws -> OiEvidenceOperation? {
        let url = try ownerDirectory(owner).appending(path: "evidence.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(OiEvidenceOperation.self, from: Data(contentsOf: url))
    }

    func saveEvidence(_ operation: OiEvidenceOperation, owner: UUID) throws {
        try write(JSONEncoder().encode(operation), to: ownerDirectory(owner).appending(path: "evidence-\(operation.uploadID.uuidString).json"))
        try write(JSONEncoder().encode(operation), to: ownerDirectory(owner).appending(path: "evidence.json"))
    }
}
