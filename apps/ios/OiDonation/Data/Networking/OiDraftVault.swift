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

struct OiEvidenceOperation: Codable, Equatable {
    var requestID: UUID
    var uploadID: UUID
    var contentType: String
    var fileExtension: String
    var previousStatus: String?
    var previousPath: String?
    var phase: String
    var failure: String?

    func objectPath(owner: UUID) -> String {
        "\(owner.uuidString.lowercased())/\(requestID.uuidString.lowercased())/\(uploadID.uuidString.lowercased()).\(fileExtension)"
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
        let folder = try ownerDirectory(owner)
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("draft-") && $0.pathExtension == "json" }
            .map { try JSONDecoder().decode(OiLocalDraft.self, from: Data(contentsOf: $0)) }
            .sorted { $0.id.uuidString < $1.id.uuidString }
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
