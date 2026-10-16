import Foundation
import CryptoKit

/// Refuse redirects rather than letting a trusted API/CDN redirect to an unknown host.
nonisolated final class ClipNoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

actor ClipContentClient {
    let configuration: ClipConfiguration
    private let session: URLSession
    private let directory: URL

    init(configuration: ClipConfiguration, directory: URL? = nil) {
        self.configuration = configuration
        let settings = URLSessionConfiguration.ephemeral
        settings.timeoutIntervalForRequest = 30
        settings.timeoutIntervalForResource = 120
        settings.httpShouldSetCookies = false
        settings.urlCache = nil
        session = URLSession(configuration: settings, delegate: ClipNoRedirects(), delegateQueue: nil)
        self.directory = directory ?? FileManager.default.temporaryDirectory.appendingPathComponent("oi-clip-content", isDirectory: true)
    }

    func story(for route: ClipRoute) async throws -> ClipStory {
        let path: String
        switch route {
        case .bench(let id): path = "v1/benches/\(id)/story"
        case .story(let id): path = "v1/stories/\(id)"
        }
        let url = configuration.apiBase.appendingPathComponent(path)
        let data = try await transfer(url, hosts: Set([configuration.apiBase.host!.lowercased()]), maximum: 512_000)
        let story = try JSONDecoder().decode(ClipStory.self, from: data)
        try story.validate(route: route, configuration: configuration)
        return story
    }

    func asset(_ asset: ClipAsset, model: Bool,
               progress: @escaping @Sendable (Double?) -> Void = { _ in }) async throws -> URL {
        guard configuration.permits(asset.url, hosts: configuration.assetHosts) else { throw ClipError.assetURL }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let key = SHA256.hash(data: Data((asset.url.absoluteString + (asset.sha256 ?? "")).utf8))
            .map { String(format: "%02x", $0) }.joined()
        let target = directory.appendingPathComponent(key).appendingPathExtension(model ? "usdz" : "image")
        if let existing = try? Data(contentsOf: target, options: .mappedIfSafe),
           (try? validate(existing, asset: asset, model: model)) != nil { return target }
        let data = try await transfer(asset.url, hosts: configuration.assetHosts,
                                      maximum: model ? 80_000_000 : 8_000_000, progress: progress)
        try Task.checkCancellation()
        try validate(data, asset: asset, model: model)
        try pruneCache(keeping: target, incoming: data.count)
        try data.write(to: target, options: .atomic)
        return target
    }

    private func validate(_ data: Data, asset: ClipAsset, model: Bool) throws {
        guard data.count <= (model ? 80_000_000 : 8_000_000), !data.isEmpty else { throw ClipError.tooLarge }
        if model {
            guard data.prefix(4) == Data([0x50, 0x4b, 0x03, 0x04]), asset.sha256 != nil else { throw ClipError.integrity }
        }
        if let expected = asset.sha256 {
            let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard expected == actual else { throw ClipError.integrity }
        }
    }

    private func pruneCache(keeping target: URL, incoming: Int) throws {
        let files = try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])
            .filter { $0 != target }.sorted {
                ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
                < ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
            }
        var total = files.reduce(incoming) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        for file in files {
            let values = try file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            if total > 160_000_000 || (values.contentModificationDate ?? .distantPast) < Date().addingTimeInterval(-86400) {
                total -= values.fileSize ?? 0
                try FileManager.default.removeItem(at: file)
            }
        }
    }

    private func transfer(_ url: URL, hosts: Set<String>, maximum: Int,
                          progress: @escaping @Sendable (Double?) -> Void = { _ in }) async throws -> Data {
        guard configuration.permits(url, hosts: hosts) else { throw ClipError.assetURL }
        let (bytes, response) = try await session.bytes(from: url)
        defer { bytes.task.cancel() }
        guard let response = response as? HTTPURLResponse else { throw ClipError.invalidResponse }
        if response.statusCode == 404 { throw ClipError.unavailable }
        guard response.statusCode == 200 else { throw ClipError.invalidResponse }
        guard response.expectedContentLength <= maximum else { throw ClipError.tooLarge }
        var data = Data()
        var lastProgress = 0
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < maximum else { throw ClipError.tooLarge }
            data.append(byte)
            if data.count - lastProgress >= 65_536 {
                lastProgress = data.count
                progress(response.expectedContentLength > 0 ? Double(data.count) / Double(response.expectedContentLength) : nil)
            }
        }
        progress(1)
        return data
    }
}
