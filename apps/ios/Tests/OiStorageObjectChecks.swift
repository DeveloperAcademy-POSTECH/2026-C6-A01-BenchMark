//
//  OiStorageObjectChecks.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/19/26.
//

import Foundation

// URLProtocol callbacks run on URLSession queues; all fixture state is lock protected.
private final class StorageFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []
    private var status = 200
    private var bytes = Data(repeating: 0xA7, count: 1024 * 1024)
    private var headers = ["ETag": "\"original\""]
    private var gate: DispatchSemaphore?

    func configure(status: Int = 200, bytes: Data = Data([1, 2, 3]),
                   headers: [String: String] = ["ETag": "\"original\""], gate: DispatchSemaphore? = nil) {
        lock.lock(); defer { lock.unlock() }
        self.status = status; self.bytes = bytes; self.headers = headers; self.gate = gate
    }
    func respond(_ request: URLRequest) -> (Int, Data, [String: String]) {
        lock.lock()
        requests.append(request)
        let result = (status, bytes, headers), gate = gate
        lock.unlock()
        if let gate { precondition(gate.wait(timeout: .now() + 5) == .success, "Fixture transfer timed out") }
        return result
    }
    var received: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return requests
    }
}

private final class StorageProtocol: URLProtocol {
    static let fixture = StorageFixture()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, bytes, headers) = Self.fixture.respond(request)
        if status == 0 {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else {
            preconditionFailure("Invalid fixture response")
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: bytes)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct OiStorageObjectChecks {
    static func main() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StorageProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let transport = APIClient(session: session, approvedHost: "storage.example.test")
        let fixture = StorageProtocol.fixture
        let firstURL = URL(string: "https://storage.example.test/object/sign/media/photo.png?token=first")!
        let nextURL = URL(string: "https://storage.example.test/object/sign/media/photo.png?token=renewed")!
        let original = Data((0..<65536).flatMap { _ in [UInt8(0), 32, 127, 255] })
        let cache = OiStorageObjectCache()
        func read(_ cache: OiStorageObjectCache = cache, path: String = "photo.png", token: String? = "account-a",
                  url: URL = nextURL) async throws -> Data {
            try await cache.data(url: url, bucket: "media", path: path, token: token, transport: transport)
        }

        fixture.configure(bytes: original)
        let first = try await read(url: firstURL)
        precondition(first == original && fixture.received.last?.value(forHTTPHeaderField: "If-None-Match") == nil)
        fixture.configure(status: 304, bytes: Data(), headers: [:])
        for _ in 0..<9 {
            let reused = try await read()
            precondition(reused == original, "Revalidation must preserve every original byte")
            precondition(fixture.received.last?.url == nextURL)
            precondition(fixture.received.last?.value(forHTTPHeaderField: "If-None-Match") == "\"original\"")
        }
        print("PASS: renewed signed URLs reuse exact original bytes; 10 unchanged reads transfer 1 image body (90% fewer body bytes)")

        let replacement = Data([0x89, 0x50, 0x4e, 0x47, 255, 0, 1, 2])
        fixture.configure(bytes: replacement, headers: ["ETag": "\"replacement\""])
        let changed = try await read()
        precondition(changed == replacement)
        fixture.configure(status: 304, bytes: Data(), headers: [:])
        let updated = try await read()
        precondition(updated == replacement && fixture.received.last?.value(forHTTPHeaderField: "If-None-Match") == "\"replacement\"")
        for token: String? in ["account-b", nil] {
            fixture.configure(bytes: original)
            _ = try await read(token: token)
            precondition(fixture.received.last?.value(forHTTPHeaderField: "If-None-Match") == nil,
                         "Other accounts and anonymous reads must not reuse private entries")
        }
        print("PASS: replaced content refreshes immediately; account and anonymous cache scopes stay separate")

        func jwt(subject: UUID, revision: Int) throws -> String {
            let payload = try JSONSerialization.data(withJSONObject: ["sub": subject.uuidString, "exp": revision])
                .base64EncodedString().replacingOccurrences(of: "=", with: "")
                .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            return "fixture.\(payload).fixture"
        }
        let subject = UUID(), rotating = OiStorageObjectCache()
        fixture.configure(bytes: original)
        _ = try await read(rotating, token: jwt(subject: subject, revision: 1))
        fixture.configure(status: 304, bytes: Data(), headers: [:])
        let rotated = try await read(rotating, token: jwt(subject: subject, revision: 2))
        precondition(rotated == original && fixture.received.last?.value(forHTTPHeaderField: "If-None-Match") != nil)
        fixture.configure(bytes: replacement)
        _ = try await read(rotating, token: jwt(subject: UUID(), revision: 2))
        precondition(fixture.received.last?.value(forHTTPHeaderField: "If-None-Match") == nil)
        print("PASS: token refresh keeps validated bytes for the same subject while other subjects remain isolated")

        for status in [401, 403, 404, 500] {
            fixture.configure(status: status)
            do { _ = try await read(); preconditionFailure("HTTP errors must never return stale private bytes") }
            catch APIError.httpStatus(let actual) { precondition(actual == status) }
            fixture.configure(bytes: original)
            _ = try await read()
            precondition(fixture.received.last?.value(forHTTPHeaderField: "If-None-Match") == nil)
        }
        fixture.configure(status: 304, bytes: Data(), headers: [:])
        do { _ = try await read(path: "uncached.png"); preconditionFailure("304 without cached bytes must fail") }
        catch APIError.invalidResponse {}
        print("PASS: authorization/deletion/server failures evict stale entries; unsolicited 304 is rejected")

        fixture.configure(status: 0)
        do { _ = try await read(); preconditionFailure("Offline reads cannot fall back to private cached bytes") }
        catch let error as URLError { precondition(error.code == .notConnectedToInternet) }
        fixture.configure(bytes: original)
        _ = try await read()
        precondition(fixture.received.last?.value(forHTTPHeaderField: "If-None-Match") == nil)
        print("PASS: network failure never returns stale artwork and a later read retries normally")

        for headers in [["Cache-Control": "private, no-store", "ETag": "\"private\""],
                        ["ETag": "W/\"weak\""], [:]] {
            let uncached = OiStorageObjectCache()
            fixture.configure(bytes: original, headers: headers)
            _ = try await read(uncached)
            _ = try await read(uncached)
            precondition(fixture.received.last?.value(forHTTPHeaderField: "If-None-Match") == nil)
        }
        print("PASS: no-store, weak validators and missing validators retain ordinary full-download behavior")

        let bounded = OiStorageObjectCache(byteLimit: 4, countLimit: 1)
        fixture.configure(bytes: Data([1, 2, 3]))
        _ = try await read(bounded, path: "a")
        _ = try await read(bounded, path: "b")
        _ = try await read(bounded, path: "a")
        precondition(fixture.received.last?.value(forHTTPHeaderField: "If-None-Match") == nil)
        fixture.configure(bytes: original)
        _ = try await read(bounded)
        _ = try await read(bounded)
        precondition(fixture.received.last?.value(forHTTPHeaderField: "If-None-Match") == nil)
        let expired = OiStorageObjectCache(lifetime: 0)
        fixture.configure()
        _ = try await read(expired)
        _ = try await read(expired)
        precondition(fixture.received.last?.value(forHTTPHeaderField: "If-None-Match") == nil)
        print("PASS: count/byte limits, oversized objects and expired entries fall back safely")

        let shared = OiStorageObjectCache(), gate = DispatchSemaphore(value: 0)
        fixture.configure(bytes: original, gate: gate)
        let before = fixture.received.count
        let cancelled = Task { try await read(shared) }
        for _ in 0..<1000 where fixture.received.count == before { try await Task.sleep(for: .milliseconds(1)) }
        precondition(fixture.received.count == before + 1)
        let surviving = Task { try await read(shared) }
        try await Task.sleep(for: .milliseconds(50))
        cancelled.cancel()
        gate.signal()
        do { _ = try await cancelled.value; preconditionFailure("Cancelled callers must not receive bytes") }
        catch is CancellationError {}
        let survivor = try await surviving.value
        precondition(survivor == original && fixture.received.count == before + 1,
                     "Concurrent readers share a single transfer; cancellation cannot break another reader")
        fixture.configure(status: 304, bytes: Data(), headers: [:])
        let afterCancellation = try await read(shared)
        precondition(afterCancellation == original)
        print("PASS: concurrent readers share one transfer; one cancelled reader preserves the surviving reader")

        let abandoned = OiStorageObjectCache(), abandonedGate = DispatchSemaphore(value: 0)
        fixture.configure(bytes: original, gate: abandonedGate)
        let abandonedCount = fixture.received.count
        let onlyReader = Task { try await read(abandoned) }
        for _ in 0..<1000 where fixture.received.count == abandonedCount { try await Task.sleep(for: .milliseconds(1)) }
        precondition(fixture.received.count == abandonedCount + 1)
        onlyReader.cancel()
        abandonedGate.signal()
        do { _ = try await onlyReader.value; preconditionFailure("An abandoned transfer must cancel") }
        catch is CancellationError {}
        fixture.configure(bytes: replacement)
        let retry = try await read(abandoned)
        precondition(retry == replacement && fixture.received.count == abandonedCount + 2)
        print("PASS: the last cancelled reader releases shared work; the next request can retry")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("oi-storage-disk-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        fixture.configure(bytes: original)
        _ = try await read(OiStorageObjectCache(byteLimit: 0, directory: directory))
        fixture.configure(status: 304, bytes: Data(), headers: [:])
        let reopened = try await read(OiStorageObjectCache(byteLimit: 0, directory: directory))
        precondition(reopened == original, "Reopening the app must preserve original bytes across renewed signed URLs")
        precondition(fixture.received.last?.value(forHTTPHeaderField: "If-None-Match") == "\"original\"")
        fixture.configure(bytes: replacement)
        _ = try await read(OiStorageObjectCache(directory: directory), token: "account-b")
        precondition(fixture.received.last?.value(forHTTPHeaderField: "If-None-Match") == nil)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        precondition(files.count == 2)
        for file in files {
            let value = try Data(contentsOf: file)
            precondition(value.range(of: Data("account-a".utf8)) == nil && value.range(of: Data("?token=".utf8)) == nil,
                         "Raw credentials and signed URLs must never be persisted")
        }
        print("PASS: original bytes survive cache reopening; disk scopes isolate accounts without storing credentials or URLs")

        for file in files { try Data("damaged".utf8).write(to: file) }
        fixture.configure(bytes: original)
        _ = try await read(OiStorageObjectCache(directory: directory))
        precondition(fixture.received.last?.value(forHTTPHeaderField: "If-None-Match") == nil)
        fixture.configure(status: 304, bytes: Data(), headers: ["Cache-Control": "no-store"])
        let stillValid = try await read(OiStorageObjectCache(directory: directory))
        precondition(stillValid == original)
        fixture.configure(bytes: original)
        _ = try await read(OiStorageObjectCache(directory: directory))
        precondition(fixture.received.last?.value(forHTTPHeaderField: "If-None-Match") == nil,
                     "A no-store revalidation must remove the disk entry")
        _ = try await read(OiStorageObjectCache(lifetime: 0, directory: directory))
        precondition(fixture.received.last?.value(forHTTPHeaderField: "If-None-Match") == nil)
        print("PASS: damaged/expired disk entries retry remotely and no-store removes persisted bytes")

        let boundedDirectory = directory.appendingPathComponent("bounded")
        let diskLimit = original.count * 2 + 4096
        let boundedDisk = OiStorageObjectCache(byteLimit: 0, directory: boundedDirectory, diskByteLimit: diskLimit)
        for path in ["one", "two", "three", "four"] { _ = try await read(boundedDisk, path: path) }
        let retained = try FileManager.default.contentsOfDirectory(at: boundedDirectory, includingPropertiesForKeys: [.fileSizeKey])
        let diskSize = try retained.reduce(0) { try $0 + ($1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
        precondition(diskSize <= diskLimit && retained.count == 2)
        let unavailable = directory.appendingPathComponent("not-a-directory")
        try Data([0]).write(to: unavailable)
        let unpersisted = try await read(OiStorageObjectCache(directory: unavailable))
        precondition(unpersisted == original, "A disk cache failure cannot break a successful image download")
        print("PASS: disk cache stays within its byte limit and unavailable persistence preserves network behavior")

        let oldGeneration = await boundedDisk.generation()
        try await boundedDisk.clear()
        let cleared = try FileManager.default.contentsOfDirectory(at: boundedDirectory, includingPropertiesForKeys: nil)
        precondition(cleared.isEmpty)
        let beforeReset = fixture.received.count
        do {
            _ = try await boundedDisk.data(url: firstURL, bucket: "media", path: "one", token: "account-a",
                                           transport: transport, generation: oldGeneration)
            preconditionFailure("A signed URL issued before logout cannot repopulate the cache")
        } catch is CancellationError {}
        precondition(fixture.received.count == beforeReset)
        print("PASS: logout clears persisted bytes and rejects late work from the prior cache generation")

        let replayDirectory = directory.appendingPathComponent("replay")
        var bodyBytes = 0
        for visit in 0..<10 {
            let replay = OiStorageObjectCache(byteLimit: original.count * 2, countLimit: 2, directory: replayDirectory)
            for index in 0..<35 {
                let bytes = original + Data([UInt8(index)])
                let etag = "\"asset-\(index)\""
                if visit == 0 {
                    fixture.configure(bytes: bytes, headers: ["ETag": etag])
                    bodyBytes += bytes.count
                } else { fixture.configure(status: 304, bytes: Data(), headers: [:]) }
                let received = try await read(replay, path: "asset-\(index)")
                precondition(received == bytes, "Disk-backed replay must preserve all artwork despite memory eviction and reopening")
                if visit > 0 { precondition(fixture.received.last?.value(forHTTPHeaderField: "If-None-Match") == etag) }
            }
        }
        let baselineBytes = (original.count + 1) * 35 * 10
        precondition(bodyBytes * 10 == baselineBytes)
        print("PASS: 35-asset/10-visit replay transfers 90% fewer body bytes across memory eviction and app reopening")
    }
}
