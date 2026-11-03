// Created by 이돈혁

import Foundation

@main struct OiDraftRecoveryChecks {
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "oi-draft-recovery-\(UUID().uuidString)")
        defer {
            do { try FileManager.default.removeItem(at: directory) }
            catch { preconditionFailure("Draft recovery test cleanup failed") }
        }
        let owner = UUID(), other = UUID()
        let vault = OiDraftVault(directory: directory)
        var draft = OiStoryDraft(); draft.title = "Preserved draft"
        let record = OiLocalDraft(draft: draft, version: 1)
        try await vault.save(record, owner: owner)
        let folder = directory.appending(path: owner.uuidString)
        let corruptID = UUID()
        let corrupt = folder.appending(path: "draft-\(corruptID.uuidString).json")
        let original = Data("{unreadable-json".utf8)
        try original.write(to: corrupt)

        let listing = try await vault.listing(owner: owner)
        precondition(listing.drafts == [record])
        precondition(listing.unreadableFiles == [corrupt.lastPathComponent])
        let preservedAfterListing = try Data(contentsOf: corrupt)
        precondition(preservedAfterListing == original)
        let unrelated = try await vault.listing(owner: other)
        precondition(unrelated.drafts.isEmpty && unrelated.unreadableFiles.isEmpty)

        do {
            _ = try await vault.load(owner: owner, id: corruptID)
            preconditionFailure("Unreadable draft unexpectedly restored")
        } catch is DecodingError {}
        var replacement = OiStoryDraft(); replacement.id = corruptID
        do {
            try await vault.save(OiLocalDraft(draft: replacement), owner: owner)
            preconditionFailure("Unreadable original was overwritten")
        } catch is DecodingError {}
        let preservedAfterSave = try Data(contentsOf: corrupt)
        precondition(preservedAfterSave == original)

        try JSONEncoder().encode(OiLocalDraft(draft: replacement)).write(to: corrupt)
        let recovered = try await vault.load(owner: owner, id: corruptID)
        precondition(recovered?.id == corruptID)

        let unreadableDirectory = folder.appending(path: "draft-\(UUID().uuidString).json")
        try FileManager.default.createDirectory(at: unreadableDirectory, withIntermediateDirectories: false)
        do {
            _ = try await vault.listing(owner: owner)
            preconditionFailure("File-system failure was silently skipped")
        } catch is CocoaError {}
        print("PASS: corrupt draft isolation, explicit warning metadata, owner isolation, original preservation, recovery retry, and file-system error propagation")
    }
}
