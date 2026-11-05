//
//  OiDraftRecoveryChecks.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/3/26.
//

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

        let firstPhoto = UUID(), lockedPhoto = UUID()
        var pendingDiscard = OiStoryDraft()
        pendingDiscard.title = "Discard with an interrupted photo cleanup"
        let discardRecord = OiLocalDraft(draft: pendingDiscard, photos: [firstPhoto, lockedPhoto], version: 1)
        try await vault.saveAttachment(Data([1]), owner: owner, id: firstPhoto)
        try await vault.saveAttachment(Data([2]), owner: owner, id: lockedPhoto)
        try await vault.save(discardRecord, owner: owner)
        let firstAttachment = folder.appending(path: "attachment-\(firstPhoto.uuidString)")
        let lockedAttachment = folder.appending(path: "attachment-\(lockedPhoto.uuidString)")
        let files = FileManager.default
        let reopened = OiDraftVault(directory: directory)
        let interrupted: Bool
        do {
            try files.setAttributes([.immutable: true], ofItemAtPath: lockedAttachment.path)
            defer {
                if files.fileExists(atPath: lockedAttachment.path) {
                    do { try files.setAttributes([.immutable: false], ofItemAtPath: lockedAttachment.path) }
                    catch { preconditionFailure("Could not unlock the owned test attachment") }
                }
            }
            do {
                try await vault.discard(owner: owner, id: discardRecord.id)
                interrupted = false
            } catch is OiDraftDiscardCleanupError {
                interrupted = true
            }
            precondition(interrupted && !files.fileExists(atPath: firstAttachment.path) && files.fileExists(atPath: lockedAttachment.path))
            let afterFailure = try await reopened.listing(owner: owner)
            precondition(!afterFailure.drafts.contains { $0.id == discardRecord.id })
            precondition(afterFailure.unreadableFiles.isEmpty && afterFailure.pendingDiscardCount == 1)
            do {
                _ = try await reopened.load(owner: owner, id: discardRecord.id)
                preconditionFailure("Opening the same draft must report the unfinished cleanup after relaunch")
            } catch is OiDraftDiscardCleanupError {}
            do {
                try await reopened.save(discardRecord, owner: owner)
                preconditionFailure("A stale save resurrected a partially discarded draft")
            } catch is OiDraftDiscardCleanupError {}
        }
        let afterRetry = try await reopened.listing(owner: owner)
        precondition(afterRetry.pendingDiscardCount == 0)
        try await reopened.discard(owner: owner, id: discardRecord.id)
        precondition(!files.fileExists(atPath: lockedAttachment.path))
        let freshRecord = OiLocalDraft(draft: pendingDiscard)
        try await reopened.save(freshRecord, owner: owner)
        let fresh = try await reopened.load(owner: owner, id: freshRecord.id)
        precondition(fresh == freshRecord, "A legitimate same-ID draft can be saved once cleanup succeeds")
        print("PASS: interrupted discard hides the draft, rejects stale save, and resumes same-ID cleanup after reopen")

        let unreadableDirectory = folder.appending(path: "draft-\(UUID().uuidString).json")
        try FileManager.default.createDirectory(at: unreadableDirectory, withIntermediateDirectories: false)
        do {
            _ = try await vault.listing(owner: owner)
            preconditionFailure("File-system failure was silently skipped")
        } catch is CocoaError {}
        print("PASS: corrupt draft isolation, explicit warning metadata, owner isolation, original preservation, recovery retry, and file-system error propagation")
    }
}
