// Created by 이돈혁

import Foundation

protocol StoryRepository: Sendable {
    func fetchPublicStory(storyID: String) async throws -> Story?
    func fetchPublicStoryCard(storyID: String) async throws -> StoryCard?
}

/// Public reads deliberately never use an owner or operator session.
struct RealStoryRepository: StoryRepository {
    private let key: String?
    private let transport: APIClient
    init(key: String? = nil, session: URLSession = .shared) {
        self.key = key
        transport = APIClient(session: session, approvedHost: "kfzfzarslqdqmrazohej.supabase.co")
    }

    private struct Record: Decodable {
        let id: UUID; let userId: UUID; let regionId: String
        let title: String; let body: String; let theme: String; let emotion: String
        let cucumberName: String; let status: String; let createdAt: String
    }
    private struct Profile: Decodable { let id: UUID; let nickname: String }
    private struct Region: Decodable { let id: String; let name: String }
    private enum Failure: Error { case configuration, unavailable, invalidResponse }

    private func publicKey() throws -> String {
        var value = key ?? ProcessInfo.processInfo.environment["OI_SUPABASE_PUBLISHABLE_KEY"] ?? ""
        if value.isEmpty, let url = Bundle.main.url(forResource: "Service.local", withExtension: "plist") {
            struct Configuration: Decodable { let publishableKey: String }
            value = try PropertyListDecoder().decode(Configuration.self, from: Data(contentsOf: url)).publishableKey
        }
        guard !value.isEmpty, !value.contains(where: { $0.isWhitespace }) else { throw Failure.configuration }
        if value.hasPrefix("sb_publishable_") { return value }
        let pieces = value.split(separator: ".")
        guard pieces.count == 3 else { throw Failure.configuration }
        var payload = String(pieces[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let claims = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              claims["role"] as? String == "anon", claims["ref"] as? String == "kfzfzarslqdqmrazohej" else { throw Failure.configuration }
        return value
    }

    private func rows<T: Decodable>(_ table: String, id: String, as: T.Type) async throws -> [T] {
        var components = URLComponents()
        components.scheme = "https"; components.host = "kfzfzarslqdqmrazohej.supabase.co"
        components.path = "/rest/v1/\(table)"
        components.queryItems = [URLQueryItem(name: "select", value: "*"), URLQueryItem(name: "id", value: "eq.\(id)"), URLQueryItem(name: "limit", value: "1")]
        if table == "oi_stories" { components.queryItems?.append(URLQueryItem(name: "status", value: "eq.published")) }
        guard let url = components.url else { throw Failure.configuration }
        var request = URLRequest(url: url); request.timeoutInterval = 30
        let key = try publicKey()
        request.setValue(key, forHTTPHeaderField: "apikey")
        if key.hasPrefix("ey") { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        let data = try await transport.send(request)
        try Task.checkCancellation()
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([T].self, from: data)
    }

    func fetchPublicStory(storyID: String) async throws -> Story? {
        guard let id = UUID(uuidString: storyID) else { return nil }
        guard let row = try await rows("oi_stories", id: id.uuidString, as: Record.self).first else { return nil }
        guard row.id == id, row.status == "published" else { throw Failure.invalidResponse }
        let profiles = try await rows("oi_profiles", id: row.userId.uuidString, as: Profile.self)
        let regions = try await rows("oi_regions", id: row.regionId, as: Region.self)
        let parser = ISO8601DateFormatter(); parser.formatOptions = [.withInternetDateTime,.withFractionalSeconds]
        let fractional = parser.date(from: row.createdAt); parser.formatOptions = [.withInternetDateTime]
        guard let date = fractional ?? parser.date(from: row.createdAt) else { throw Failure.invalidResponse }
        return Story(storyID: id.uuidString, donorID: row.userId, donorDisplayName: profiles.first?.nickname ?? "농부",
            title: row.title, content: row.body, publishedAt: date,
            location: StoryLocation(locationID: row.regionId, displayName: regions.first?.name ?? "장소 확인 중"),
            tags: [row.theme,row.emotion], cucumberID: id.uuidString, cucumberName: row.cucumberName)
    }

    func fetchPublicStoryCard(storyID: String) async throws -> StoryCard? {
        guard let story = try await fetchPublicStory(storyID: storyID) else { return nil }
        return StoryCard(cardID: story.storyID, storyID: story.storyID, imageURL: nil)
    }
}
