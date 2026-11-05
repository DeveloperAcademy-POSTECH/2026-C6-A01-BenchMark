//
//  ARVideoRecoveryStore.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/3/26.
//

import Foundation

/// Keeps ReplayKit originals private until cropped export succeeds or the user deletes them.
struct ARVideoRecoveryStore {
    private let directory: URL

    init(directory: URL = URL.applicationSupportDirectory.appending(path: "ARVideoRecovery", directoryHint: .isDirectory)) {
        self.directory = directory.standardizedFileURL.resolvingSymlinksInPath()
    }

    func recordingURL() throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var privateDirectory = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try privateDirectory.setResourceValues(values)
        return directory.appending(path: "\(UUID().uuidString).mov")
    }

    func pendingRecordings() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]).filter { url in
                guard owns(url) else { return false }
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                return values.isRegularFile == true && values.isSymbolicLink != true && (values.fileSize ?? 0) > 0
            }.map(\.standardizedFileURL).sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func export(_ original: URL, using operation: (URL) async throws -> URL) async throws -> URL {
        guard owns(original) else { throw Failure.invalidOriginal }
        let output = try await operation(original)
        guard output.standardizedFileURL != original.standardizedFileURL,
              FileManager.default.fileExists(atPath: output.path) else { throw Failure.missingExport }
        try discard(original)
        return output
    }

    func discard(_ original: URL) throws {
        guard owns(original) else { throw Failure.invalidOriginal }
        try FileManager.default.removeItem(at: original)
    }

    private func owns(_ url: URL) -> Bool {
        url.standardizedFileURL.deletingLastPathComponent().resolvingSymlinksInPath().path == directory.path
            && url.pathExtension == "mov"
            && UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil
    }

    private enum Failure: Error { case invalidOriginal, missingExport }
}
