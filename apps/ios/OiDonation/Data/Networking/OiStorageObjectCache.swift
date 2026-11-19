//
//  OiStorageObjectCache.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/19/26.
//

import CryptoKit
import Foundation

/// Retains original bytes only. Every read still needs a new authorized URL and
/// a server response; cached artwork is never an offline or permission fallback.
actor OiStorageObjectCache {
    private struct Key: Hashable {
        let host: String
        let bucket: String
        let path: String
        let credential: SHA256.Digest
    }
    private struct Entry {
        let data: Data
        let etag: String
        let accessed: Date
    }
    private struct Pending {
        let id: UUID
        let task: Task<Data, Error>
        var waiters: Set<UUID>
    }
    private struct DiskEntry: Codable {
        let data: Data
        let etag: String
        let digest: Data
    }
    private let byteLimit: Int
    private let countLimit: Int
    private let lifetime: TimeInterval
    private let now: @Sendable () -> Date
    private let directory: URL?
    private let diskByteLimit: Int
    private var entries: [Key: Entry] = [:]
    private var pending: [Key: Pending] = [:]
    private var byteCount = 0
    private var epoch = UUID()

    init(byteLimit: Int = 32 * 1024 * 1024, countLimit: Int = 16,
         lifetime: TimeInterval = 86400, directory: URL? = nil, diskByteLimit: Int = 128 * 1024 * 1024,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.byteLimit = max(0, byteLimit)
        self.countLimit = max(0, countLimit)
        self.lifetime = lifetime
        self.now = now
        self.directory = directory
        self.diskByteLimit = max(0, diskByteLimit)
    }

    func generation() -> UUID { epoch }

    func clear() throws {
        epoch = UUID()
        pending.values.forEach { $0.task.cancel() }; pending.removeAll()
        entries.removeAll(); byteCount = 0
        guard let directory, FileManager.default.fileExists(atPath: directory.path) else { return }
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            where file.pathExtension == "plist" {
            try FileManager.default.removeItem(at: file)
        }
    }

    func data(url: URL, bucket: String, path: String, token: String?, transport: APIClient,
              generation: UUID? = nil) async throws -> Data {
        try Task.checkCancellation()
        if let generation, generation != epoch { throw CancellationError() }
        let credential = Self.credentialScope(token)
        let key = Key(host: url.host?.lowercased() ?? "", bucket: bucket, path: path, credential: credential)
        let waiter = UUID()
        let work: Pending
        if var existing = pending[key] {
            existing.waiters.insert(waiter)
            pending[key] = existing
            work = existing
        } else {
            for (key, entry) in entries where now().timeIntervalSince(entry.accessed) >= lifetime {
                invalidate(key)
            }
            let id = UUID(), cached = entries[key] ?? readDisk(key)
            // Shared transfer lifetime belongs to its waiters, not its first caller.
            let task = Task { try await download(url: url, key: key, id: id, cached: cached, transport: transport) }
            work = Pending(id: id, task: task, waiters: [waiter])
            pending[key] = work
        }
        return try await withTaskCancellationHandler {
            defer { release(waiter, key: key, id: work.id) }
            let data = try await work.task.value
            try Task.checkCancellation()
            return data
        } onCancel: {
            Task { await self.release(waiter, key: key, id: work.id) }
        }
    }

    private func release(_ waiter: UUID, key: Key, id: UUID) {
        guard var work = pending[key], work.id == id else { return }
        work.waiters.remove(waiter)
        if work.waiters.isEmpty {
            pending[key] = nil
            work.task.cancel()
        } else { pending[key] = work }
    }

    private func download(url: URL, key: Key, id: UUID, cached: Entry?, transport: APIClient) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        if let cached { request.setValue(cached.etag, forHTTPHeaderField: "If-None-Match") }
        do {
            let (data, response) = try await transport.response(request)
            try Task.checkCancellation()
            guard pending[key]?.id == id else { throw CancellationError() }
            if response.statusCode == 304 {
                guard let cached else { throw APIError.invalidResponse }
                if allowsStorage(response) {
                    store(Entry(data: cached.data, etag: cached.etag, accessed: now()), key: key, revalidated: true)
                } else { invalidate(key) }
                return cached.data
            }
            guard (200..<300).contains(response.statusCode) else { throw APIError.httpStatus(response.statusCode) }
            invalidate(key)
            if response.statusCode == 200, allowsStorage(response), !data.isEmpty,
               let etag = response.value(forHTTPHeaderField: "ETag"), !etag.isEmpty, !etag.hasPrefix("W/") {
                store(Entry(data: data, etag: etag, accessed: now()), key: key)
            }
            return data
        } catch {
            if pending[key]?.id == id { invalidate(key) }
            throw error
        }
    }

    private func allowsStorage(_ response: HTTPURLResponse) -> Bool {
        let directives = response.value(forHTTPHeaderField: "Cache-Control")?.lowercased().split(separator: ",") ?? []
        return !directives.contains { $0.trimmingCharacters(in: .whitespaces).split(separator: "=").first == "no-store" }
    }

    private static func credentialScope(_ token: String?) -> SHA256.Digest {
        guard let token else { return SHA256.hash(data: Data("anonymous".utf8)) }
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count == 3 {
            var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
            if let data = Data(base64Encoded: payload),
               let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let raw = claims["sub"] as? String, let subject = UUID(uuidString: raw) {
                // This is a cache partition, never authorization. A fresh server-issued
                // URL and a successful HTTP revalidation are still required on every read.
                return SHA256.hash(data: Data("subject/\(subject.uuidString.lowercased())".utf8))
            }
        }
        return SHA256.hash(data: Data("credential/\(token)".utf8))
    }

    private func remove(_ key: Key) {
        if let entry = entries.removeValue(forKey: key) { byteCount -= entry.data.count }
    }

    private func store(_ entry: Entry, key: Key, revalidated: Bool = false) {
        writeDisk(entry, key: key, revalidated: revalidated)
        remove(key)
        guard countLimit > 0, entry.data.count <= byteLimit else { return }
        while entries.count >= countLimit || byteCount + entry.data.count > byteLimit {
            guard let oldest = entries.min(by: { $0.value.accessed < $1.value.accessed })?.key else { break }
            remove(oldest)
        }
        entries[key] = entry
        byteCount += entry.data.count
    }

    private func file(_ key: Key) -> URL? {
        guard let directory else { return nil }
        let value = "\(key.host.utf8.count):\(key.host)\(key.bucket.utf8.count):\(key.bucket)\(key.path.utf8.count):\(key.path)\(key.credential)"
        let hash = SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash).appendingPathExtension("plist")
    }

    private func invalidate(_ key: Key) {
        remove(key)
        if let file = file(key) { try? FileManager.default.removeItem(at: file) }
    }

    private func readDisk(_ key: Key) -> Entry? {
        guard let file = file(key), diskByteLimit > 0 else { return nil }
        do {
            let attributes = try file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            guard let date = attributes.contentModificationDate, now().timeIntervalSince(date) < lifetime,
                  let size = attributes.fileSize, size <= diskByteLimit else { invalidate(key); return nil }
            let entry = try PropertyListDecoder().decode(DiskEntry.self, from: Data(contentsOf: file))
            guard !entry.data.isEmpty, !entry.etag.isEmpty, !entry.etag.hasPrefix("W/"),
                  Data(SHA256.hash(data: entry.data)) == entry.digest else { invalidate(key); return nil }
            return Entry(data: entry.data, etag: entry.etag, accessed: date)
        } catch {
            // Cache I/O never makes otherwise available remote artwork unavailable.
            invalidate(key)
            return nil
        }
    }

    private func writeDisk(_ entry: Entry, key: Key, revalidated: Bool) {
        guard let directory, let file = file(key), entry.data.count <= diskByteLimit, diskByteLimit > 0 else { return }
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            if revalidated, manager.fileExists(atPath: file.path) {
                try manager.setAttributes([.modificationDate: now()], ofItemAtPath: file.path)
                return
            }
            let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
            let data = try encoder.encode(DiskEntry(data: entry.data, etag: entry.etag, digest: Data(SHA256.hash(data: entry.data))))
            guard data.count <= diskByteLimit else { return }
            let files = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])
            var total = data.count
            let existing = files.filter { $0 != file }.compactMap { url -> (URL, Int, Date)? in
                guard url.pathExtension == "plist", let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                      let size = values.fileSize, let date = values.contentModificationDate else { return nil }
                return (url, size, date)
            }.sorted { $0.2 > $1.2 }
            for (url, size, date) in existing {
                if now().timeIntervalSince(date) >= lifetime || total + size > diskByteLimit {
                    try manager.removeItem(at: url)
                } else { total += size }
            }
            var options: Data.WritingOptions = [.atomic]
            #if os(iOS)
            options.insert(.completeFileProtectionUntilFirstUserAuthentication)
            #endif
            try data.write(to: file, options: options)
            try manager.setAttributes([.modificationDate: now(), .posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch {
            // Disk pressure or unavailable file protection only disables persistence.
        }
    }
}
