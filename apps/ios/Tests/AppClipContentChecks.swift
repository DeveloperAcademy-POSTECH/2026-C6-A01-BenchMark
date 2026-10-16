import Foundation

@main struct AppClipContentChecks {
    static func main() async throws {
        let base = URL(string: CommandLine.arguments[1])!
        let config = ClipConfiguration(publicHost: "clip.test", apiBase: base,
            assetHosts: ["127.0.0.1"], allowsLocalHTTP: true)
        func route(_ path: String) throws -> ClipRoute {
            try ClipRoute.parse(URL(string: "https://clip.test" + path)!, host: "clip.test")
        }
        let parsed = try route("/benches/demo-bench")
        precondition(parsed == .bench("demo-bench"))
        for link in ["http://clip.test/benches/x", "https://evil.test/benches/x", "https://clip.test/benches/x/",
                     "https://user@clip.test/benches/x", "https://clip.test:444/benches/x",
                     "https://clip.test/benches/%2F", "https://clip.test/benches/x?other=y"] {
            do { _ = try ClipRoute.parse(URL(string: link)!, host: "clip.test"); fatalError("Accepted invalid link") }
            catch ClipError.invalidLink {}
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = ClipContentClient(configuration: config, directory: directory)
        let story = try await client.story(for: route("/benches/demo-bench"))
        precondition(story.title.contains("테스트"))
        _ = try await client.story(for: route("/stories/demo-story"))
        for id in ["missing", "private", "wrong", "oversize"] {
            do { _ = try await client.story(for: .bench(id)); fatalError("Accepted invalid story") }
            catch {}
        }
        let image = try await client.asset(story.images[0], model: false)
        precondition(FileManager.default.fileExists(atPath: image.path))
        let asset = story.character!.asset
        let file = try await client.asset(asset, model: true)
        let cached = try await client.asset(asset, model: true)
        precondition(file == cached)
        do {
            _ = try await client.asset(ClipAsset(url: asset.url, sha256: String(repeating: "0", count: 64)), model: true)
            fatalError("Accepted wrong checksum")
        } catch ClipError.integrity {}
        do {
            _ = try await client.asset(ClipAsset(url: URL(string: "https://untrusted.invalid/a.usdz")!, sha256: asset.sha256), model: true)
            fatalError("Accepted untrusted host")
        } catch ClipError.assetURL {}
        do {
            _ = try await client.asset(ClipAsset(url: base.appendingPathComponent("assets/redirect.usdz"), sha256: asset.sha256), model: true)
            fatalError("Followed redirect")
        } catch ClipError.invalidResponse {}
        let pending = Task { try await client.story(for: .bench("slow")) }
        try await Task.sleep(for: .milliseconds(150))
        pending.cancel()
        do { _ = try await pending.value; fatalError("Ignored cancellation") } catch {}
        print("PASS: invocation validation, story identity/privacy, remote image/model, checksum/cache, size cap, host/redirect rejection and cancellation")
    }
}
