// Created by 이돈혁

import Foundation

@main
struct OiDraftAdoptionChecks {
    private enum Failure: Error { case assertion(String) }

    static func main() async {
        do {
            let failures = try await runChecks()
            if failures > 0 { exit(1) }
        } catch {
            print("FAIL: draft adoption checks: \(error)")
            exit(1)
        }
    }

    private static func runChecks() async throws -> Int {
        let root = FileManager.default.temporaryDirectory.appending(path: "oi-draft-adoption-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer {
            if FileManager.default.fileExists(atPath: root.path) {
                do { try FileManager.default.removeItem(at: root) }
                catch { print("FAIL: draft adoption fixture cleanup: \(error)") }
            }
        }
        let cases: [(String, (URL) async throws -> Void)] = [
            ("draft and photo copy preserves source bytes", checkCopy),
            ("discarded adopted draft is not resurrected", checkDiscardMarker),
            ("different target drafts are preserved and reported", checkTargetConflicts),
            ("damaged sources remain intact and do not hide readable drafts", checkDamagedSource),
            ("evidence attachment and index preserve storage owner", checkEvidenceCopy),
            ("conflicting target evidence remains intact", checkEvidenceConflict),
        ]
        var failures = 0
        for (name, check) in cases {
            do {
                try await check(root.appending(path: UUID().uuidString))
                print("PASS: \(name)")
            } catch {
                failures += 1
                print("FAIL: \(name): \(error)")
            }
        }
        try FileManager.default.removeItem(at: root)
        return failures
    }

    private static func checkCopy(_ directory: URL) async throws {
        let vault = OiDraftVault(directory: directory)
        let source = UUID(), target = UUID(), photo = UUID()
        var draft = OiStoryDraft(); draft.title = "Source draft"; draft.body = "Unsubmitted source content"
        let record = OiLocalDraft(draft: draft, photos: [photo], uploadedPhotos: [photo], version: 3, submitted: false)
        let photoBytes = Data("source-photo-fixture".utf8)
        try await vault.saveAttachment(photoBytes, owner: source, id: photo)
        try await vault.save(record, owner: source)
        let original = try Data(contentsOf: draftURL(directory, owner: source, id: record.id))

        let unresolved = try await vault.adoptDrafts(from: [source, target], into: target)
        let copied = try await vault.load(owner: target, id: record.id)
        let copiedPhoto = try await vault.attachment(owner: target, id: photo)
        let retainedPhoto = try await vault.attachment(owner: source, id: photo)
        let retained = try Data(contentsOf: draftURL(directory, owner: source, id: record.id))
        try require(unresolved == 0 && copied == record, "Readable draft metadata was not copied exactly")
        try require(copiedPhoto == photoBytes && retainedPhoto == photoBytes && retained == original, "Source or copied bytes changed")
    }

    private static func checkDiscardMarker(_ directory: URL) async throws {
        let vault = OiDraftVault(directory: directory)
        let source = UUID(), target = UUID(), photo = UUID()
        var draft = OiStoryDraft(); draft.title = "User will discard canonical copy"
        let record = OiLocalDraft(draft: draft, photos: [photo], version: 1)
        let bytes = Data("retained-source-photo".utf8)
        try await vault.saveAttachment(bytes, owner: source, id: photo)
        try await vault.save(record, owner: source)
        _ = try await vault.adoptDrafts(from: [source], into: target)
        try await vault.discard(owner: target, id: record.id)

        let reopened = OiDraftVault(directory: directory)
        let unresolved = try await reopened.adoptDrafts(from: [source], into: target)
        let restored = try await reopened.load(owner: target, id: record.id)
        let sourceDraft = try await reopened.load(owner: source, id: record.id)
        let sourcePhoto = try await reopened.attachment(owner: source, id: photo)
        try require(unresolved == 0 && restored == nil, "A discarded canonical draft was resurrected")
        try require(sourceDraft == record && sourcePhoto == bytes, "Discard removed the original source")
        let targetPhoto = directory.appending(path: target.uuidString).appending(path: "attachment-\(photo.uuidString)")
        try require(!FileManager.default.fileExists(atPath: targetPhoto.path), "A discarded target photo was copied back")
    }

    private static func checkTargetConflicts(_ directory: URL) async throws {
        let vault = OiDraftVault(directory: directory)
        for targetVersion in [2, 5] {
            let source = UUID(), target = UUID()
            var draft = OiStoryDraft(); draft.title = "Source content"
            let sourceRecord = OiLocalDraft(draft: draft, version: 2)
            draft.title = "Different canonical content"
            let targetRecord = OiLocalDraft(draft: draft, version: targetVersion)
            try await vault.save(sourceRecord, owner: source)
            try await vault.save(targetRecord, owner: target)
            let originalTarget = try Data(contentsOf: draftURL(directory, owner: target, id: draft.id))
            let originalSource = try Data(contentsOf: draftURL(directory, owner: source, id: draft.id))
            for _ in 0..<2 {
                let unresolved = try await vault.adoptDrafts(from: [source], into: target)
                try require(unresolved > 0, "An unresolved target conflict was marked as adopted")
            }
            let preservedTarget = try Data(contentsOf: draftURL(directory, owner: target, id: draft.id))
            let preservedSource = try Data(contentsOf: draftURL(directory, owner: source, id: draft.id))
            try require(preservedTarget == originalTarget && preservedSource == originalSource, "Draft conflict overwrote original bytes")
        }
    }

    private static func checkDamagedSource(_ directory: URL) async throws {
        let vault = OiDraftVault(directory: directory)
        let source = UUID(), target = UUID()
        var draft = OiStoryDraft(); draft.title = "Readable source"
        let readable = OiLocalDraft(draft: draft)
        try await vault.save(readable, owner: source)
        let damaged = draftURL(directory, owner: source, id: UUID())
        let bytes = Data("{damaged-source-record".utf8)
        try bytes.write(to: damaged)
        var incomplete = OiStoryDraft(); incomplete.title = "Missing photo"
        let missingPhoto = OiLocalDraft(draft: incomplete, photos: [UUID()])
        try await vault.save(missingPhoto, owner: source)

        let unresolved = try await vault.adoptDrafts(from: [source], into: target)
        let copied = try await vault.load(owner: target, id: readable.id)
        let notCopied = try await vault.load(owner: target, id: missingPhoto.id)
        let retained = try Data(contentsOf: damaged)
        let retainedMissingPhoto = try await vault.load(owner: source, id: missingPhoto.id)
        try require(unresolved >= 2 && copied == readable && notCopied == nil, "Damaged or incomplete drafts were hidden or partially adopted")
        try require(retained == bytes && retainedMissingPhoto == missingPhoto, "Damaged source was removed or overwritten")
    }

    private static func checkEvidenceCopy(_ directory: URL) async throws {
        let vault = OiDraftVault(directory: directory)
        for inheritedOwner in [nil, UUID()] as [UUID?] {
            let source = UUID(), target = UUID()
            let operation = evidence(storageOwner: inheritedOwner)
            let bytes = Data("private-evidence-fixture".utf8)
            try await vault.saveAttachment(bytes, owner: source, id: operation.uploadID)
            try await vault.saveEvidence(operation, owner: source)
            let sourceIndex = directory.appending(path: source.uuidString).appending(path: "evidence.json")
            let originalIndex = try Data(contentsOf: sourceIndex)
            let originalPath = operation.objectPath(owner: source)
            let unresolved = try await vault.adoptDrafts(from: [source], into: target)
            let copied = try await vault.evidence(owner: target)
            let targetBytes = try await vault.attachment(owner: target, id: operation.uploadID)
            let retainedBytes = try await vault.attachment(owner: source, id: operation.uploadID)
            let retainedIndex = try Data(contentsOf: sourceIndex)
            try require(unresolved == 0 && copied?.uploadID == operation.uploadID && copied?.requestID == operation.requestID, "Pending evidence identity changed")
            try require(copied?.storageOwnerID == (inheritedOwner ?? source) && copied?.objectPath(owner: target) == originalPath, "Evidence storage prefix changed to the canonical account")
            try require(targetBytes == bytes && retainedBytes == bytes && retainedIndex == originalIndex, "Evidence source or copied bytes changed")
            let targetHistory = directory.appending(path: target.uuidString).appending(path: "evidence-\(operation.uploadID.uuidString).json")
            let history = try JSONDecoder().decode(OiEvidenceOperation.self, from: Data(contentsOf: targetHistory))
            try require(history == copied, "Evidence operation history and active index disagree")
        }
    }

    private static func checkEvidenceConflict(_ directory: URL) async throws {
        let vault = OiDraftVault(directory: directory)
        let source = UUID(), target = UUID()
        let sourceOperation = evidence(storageOwner: nil)
        let targetOperation = evidence(storageOwner: target)
        let sourceBytes = Data("source-evidence".utf8), targetBytes = Data("canonical-evidence".utf8)
        try await vault.saveAttachment(sourceBytes, owner: source, id: sourceOperation.uploadID)
        try await vault.saveEvidence(sourceOperation, owner: source)
        try await vault.saveAttachment(targetBytes, owner: target, id: targetOperation.uploadID)
        try await vault.saveEvidence(targetOperation, owner: target)
        let targetIndex = directory.appending(path: target.uuidString).appending(path: "evidence.json")
        let originalIndex = try Data(contentsOf: targetIndex)
        let unresolved = try await vault.adoptDrafts(from: [source], into: target)
        let current = try await vault.evidence(owner: target)
        let retainedTarget = try await vault.attachment(owner: target, id: targetOperation.uploadID)
        let retainedSource = try await vault.attachment(owner: source, id: sourceOperation.uploadID)
        let retainedIndex = try Data(contentsOf: targetIndex)
        try require(unresolved > 0 && current == targetOperation, "Conflicting pending evidence was silently replaced")
        try require(retainedIndex == originalIndex && retainedTarget == targetBytes && retainedSource == sourceBytes, "Evidence conflict changed original bytes")
    }

    private static func evidence(storageOwner: UUID?) -> OiEvidenceOperation {
        OiEvidenceOperation(requestID: UUID(), uploadID: UUID(), contentType: "image/png", fileExtension: "png",
                            previousStatus: nil, previousPath: nil, phase: "uploading", failure: nil, storageOwnerID: storageOwner)
    }

    private static func draftURL(_ directory: URL, owner: UUID, id: UUID) -> URL {
        directory.appending(path: owner.uuidString).appending(path: "draft-\(id.uuidString).json")
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure.assertion(message) }
    }
}
