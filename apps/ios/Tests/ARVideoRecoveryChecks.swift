//
//  ARVideoRecoveryChecks.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/3/26.
//

import Foundation

@main
struct ARVideoRecoveryChecks {
    private enum Failure: Error { case exportFailed, checkFailed(String) }

    static func main() async {
        do { try await checkPreservation() }
        catch {
            print("FAIL: \(error)")
            exit(1)
        }
    }

    private static func checkPreservation() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "oi-video-recovery-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ARVideoRecoveryStore(directory: directory.appending(path: "PrivateOriginals"))
        let bytes = Data("completed-screen-recording".utf8)

        for cancelled in [false, true] {
            let original = try store.recordingURL()
            try bytes.write(to: original)
            var unexpectedlyExported = false
            do {
                _ = try await store.export(original) { _ in
                    if cancelled { throw CancellationError() }
                    throw Failure.exportFailed
                }
                unexpectedlyExported = true
            } catch is CancellationError { try require(cancelled) }
            catch Failure.exportFailed { try require(!cancelled) }
            try require(!unexpectedlyExported, "Failed exports must throw")
            let preserved = try Data(contentsOf: original)
            try require(preserved == bytes, "Export failures must preserve the completed original")
            let reopened = ARVideoRecoveryStore(directory: directory.appending(path: "PrivateOriginals"))
            let pending = try reopened.pendingRecordings()
            try require(pending.contains(original), "Recovery must survive creating a new recorder/store")
        }

        let successfulOriginal = try store.recordingURL()
        try bytes.write(to: successfulOriginal)
        let cropped = directory.appending(path: "cropped.mp4")
        let exported = try await store.export(successfulOriginal) { _ in
            try Data("cropped-video".utf8).write(to: cropped)
            return cropped
        }
        try require(exported == cropped && FileManager.default.fileExists(atPath: cropped.path))
        try require(!FileManager.default.fileExists(atPath: successfulOriginal.path), "Only successful export removes the original")

        let incomplete = try store.recordingURL()
        try bytes.write(to: incomplete)
        var acceptedMissingOutput = false
        do {
            _ = try await store.export(incomplete) { _ in directory.appending(path: "missing.mp4") }
            acceptedMissingOutput = true
        } catch { }
        try require(!acceptedMissingOutput, "A missing output must not count as an exported video")
        let incompleteBytes = try Data(contentsOf: incomplete)
        try require(incompleteBytes == bytes)

        let foreign = directory.appending(path: "unrelated.mov")
        try bytes.write(to: foreign)
        var rejectedForeignFile = false
        do { try store.discard(foreign) }
        catch { rejectedForeignFile = true }
        try require(rejectedForeignFile, "Recovery cleanup must reject unrelated files")
        let foreignBytes = try Data(contentsOf: foreign)
        try require(foreignBytes == bytes)
        try store.discard(incomplete)
        try require(!FileManager.default.fileExists(atPath: incomplete.path))
        print("PASS: completed originals survive export failure/cancellation and store recreation; successful exports clean up; missing output and unrelated deletion are rejected")
    }

    private static func require(_ condition: Bool, _ message: String = "Unexpected recovery state") throws {
        if !condition { throw Failure.checkFailed(message) }
    }
}
