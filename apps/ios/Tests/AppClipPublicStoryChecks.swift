// Created by 이돈혁

import Foundation

@MainActor
enum AppClipPublicStoryChecks {
    private enum CheckFailure: Error {
        case failed(String)
    }

    static func run() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PublicStoryFixtureProtocol.self]
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let repository = RealStoryRepository(key: "sb_publishable_visual-test", session: session)
        let fixtures: [(suffix: String, filename: String?)] = [
            ("001", "61272"),
            ("002", "0e35d"),
            ("003", "9ac42"),
            ("004", "aeb3a"),
            ("005", nil),
            ("006", nil)
        ]

        for fixture in fixtures {
            let id = "00000000-0000-4000-8000-000000000\(fixture.suffix)"
            guard let story = try await repository.fetchPublicStory(storyID: id) else {
                throw CheckFailure.failed("Published fixture must load: \(id)")
            }
            try require(story.storyID == id, "Repository must preserve the public story ID")
            try require(story.title == "Story title \(fixture.suffix)", "Story title must decode independently")
            try require(story.cucumberName == "Cucumber name \(fixture.suffix)", "Cucumber name must decode independently")
            try require(story.title != story.cucumberName, "Story title must not replace the cucumber name")

            if let filename = fixture.filename {
                guard let expected = Bundle.main.url(forResource: filename, withExtension: "png"),
                      let actual = story.cucumberImageURL else {
                    throw CheckFailure.failed("Original preset PNG must be packaged: \(filename).png")
                }
                try require(actual.isFileURL, "Preset image must use a local bundle file URL")
                try require(actual.standardizedFileURL == expected.standardizedFileURL,
                            "Server preset must select its exact original PNG")
                try require(FileManager.default.fileExists(atPath: actual.path), "Mapped preset PNG must exist")
            } else {
                try require(story.cucumberImageURL == nil, "Unknown or missing preset must not invent an image URL")
            }

            guard let card = try await repository.fetchPublicStoryCard(storyID: id) else {
                throw CheckFailure.failed("Published fixture must provide its card identity")
            }
            try require(card.storyID == id && card.cardID == id, "Card identity must remain linked to the public story")
            try require(card.imageURL == nil, "Existing contract must not substitute a preview or fake card bitmap")
        }
        print("PASS: public repository preset mapping, packaged PNGs, distinct names, unknown/missing preset, honest nil card image")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw CheckFailure.failed(message) }
    }
}

private final class PublicStoryFixtureProtocol: URLProtocol {
    nonisolated private static let approvedHost = "kfzfzarslqdqmrazohej.supabase.co"

    nonisolated override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == "https" && request.url?.host?.lowercased() == approvedHost
    }

    nonisolated override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    nonisolated override func startLoading() {
        do {
            guard let url = request.url, request.httpMethod == "GET",
                  url.scheme == "https", url.host?.lowercased() == Self.approvedHost,
                  request.value(forHTTPHeaderField: "apikey") == "sb_publishable_visual-test",
                  let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                                 headerFields: ["Content-Type": "application/json"]) else {
                throw URLError(.unsupportedURL)
            }
            let data = try Self.fixtureData(for: url)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    nonisolated override func stopLoading() {}

    nonisolated private static func fixtureData(for url: URL) throws -> Data {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let filter = components.queryItems?.first(where: { $0.name == "id" })?.value,
              filter.hasPrefix("eq.") else { throw URLError(.unsupportedURL) }
        let id = String(filter.dropFirst(3))
        let rows: [[String: Any]]
        switch url.path {
        case "/rest/v1/oi_stories":
            let presets = [
                "00000000-0000-4000-8000-000000000001": "OiCats",
                "00000000-0000-4000-8000-000000000002": "OiGardener",
                "00000000-0000-4000-8000-000000000003": "OiWizard",
                "00000000-0000-4000-8000-000000000004": "OiTraveler",
                "00000000-0000-4000-8000-000000000005": "UnknownPreset"
            ]
            guard presets[id] != nil || id == "00000000-0000-4000-8000-000000000006" else {
                throw URLError(.unsupportedURL)
            }
            let suffix = String(id.suffix(3))
            var story: [String: Any] = [
                "id": id,
                "user_id": "00000000-0000-4000-8000-000000000100",
                "region_id": "fixture-region",
                "title": "Story title \(suffix)",
                "body": "Synthetic public story body",
                "theme": "Fixture theme",
                "emotion": "Fixture emotion",
                "cucumber_name": "Cucumber name \(suffix)",
                "status": "published",
                "created_at": "2026-11-02T00:00:00Z"
            ]
            if let preset = presets[id] { story["cucumber_asset"] = preset }
            rows = [story]
        case "/rest/v1/oi_profiles":
            guard id == "00000000-0000-4000-8000-000000000100" else { throw URLError(.unsupportedURL) }
            rows = [["id": id, "nickname": "Fixture donor"]]
        case "/rest/v1/oi_regions":
            guard id == "fixture-region" else { throw URLError(.unsupportedURL) }
            rows = [["id": id, "name": "Fixture region"]]
        default:
            throw URLError(.unsupportedURL)
        }
        return try JSONSerialization.data(withJSONObject: rows)
    }
}
