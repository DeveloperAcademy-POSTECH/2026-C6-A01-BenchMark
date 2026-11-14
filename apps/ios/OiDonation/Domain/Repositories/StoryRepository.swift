// Created by 이돈혁

import Foundation

struct PublicStorySummary: Identifiable, Decodable, Sendable {
    let id: UUID
    let userId: UUID
    let title: String
    let cucumberName: String
}

protocol StoryRepository: Sendable {
    func fetchPublicStories(offset: Int) async throws -> [PublicStorySummary]
    func fetchPublicStory(storyID: String) async throws -> Story?
    func fetchPublicStoryCard(storyID: String) async throws -> StoryCard?
    /// Story linked to an NFC postcard tag, or nil when the tag is unknown, retired or its story is not public (#291).
    func fetchNFCPostcardStoryID(tag: String) async throws -> String?
    /// Images and donor line for the scratch postcard of a published story (#291).
    func fetchPublicPostcardDetails(storyID: String) async throws -> PublicPostcardDetails?
}

extension StoryRepository {
    func fetchPublicStories(offset: Int) async throws -> [PublicStorySummary] { [] }
}

/// Public reads deliberately never use an owner or operator session.
/// What the App Clip needs beyond `Story` to draw a scratch postcard.
struct PublicPostcardDetails: Sendable {
    /// Approved postcard preview, or the legacy original when no preview exists.
    let frontURL: URL?
    /// Postcard back rendered with the front; nil for stories submitted by older app versions.
    let backURL: URL?
    /// First story photo, used only when no approved postcard front exists.
    let coverPhotoURL: URL?
    /// "26학번 디벨로퍼학과 신수리" when the author filled in the public donor search fields.
    let donorLine: String?
    /// Approved sticker-free window from a format-3 snapshot.
    var coverURL: URL? = nil
}

extension StoryRepository {
    func fetchNFCPostcardStoryID(tag: String) async throws -> String? { nil }
    func fetchPublicPostcardDetails(storyID: String) async throws -> PublicPostcardDetails? { nil }

    /// Revalidate publication and tag assignment immediately before recording a collection.
    func canCollectNFCPostcard(tag: String, storyID: String) async throws -> Bool {
        guard AppClipLink.isValidPostcardTag(tag), let expected = UUID(uuidString: storyID),
              let story = try await fetchPublicStory(storyID: storyID), UUID(uuidString: story.storyID) == expected else { return false }
        try Task.checkCancellation()
        let current = try await fetchNFCPostcardStoryID(tag: tag)
        try Task.checkCancellation()
        return current.flatMap(UUID.init(uuidString:)) == expected
    }
}

struct RealStoryRepository: StoryRepository {
    private let key: String?
    private let transport: APIClient
    init(key: String? = nil, session: URLSession = .shared) {
        self.key = key
        transport = APIClient(session: session, approvedHost: "kfzfzarslqdqmrazohej.supabase.co")
    }

    private struct Record: Decodable {
        struct Appearance: Decodable { let id: UUID }
        let id: UUID; let userId: UUID; let regionId: String
        let title: String; let body: String; let theme: String; let emotion: String
        let cucumberName: String; let status: String; let createdAt: String
        let cucumberAsset: String?
        let storageOwnerId: UUID?
        let cucumberAppearance: Appearance?
        let cardSnapshotId: UUID?
        let cardSnapshotFormat: Int?
    }
    private struct Profile: Decodable {
        let id: UUID; let nickname: String
        // Owner-entered public donor search fields; empty when not provided.
        let publicName: String?; let department: String?; let admissionYear: String?
    }
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

    func fetchPublicStories(offset: Int) async throws -> [PublicStorySummary] {
        guard offset >= 0 else { throw Failure.invalidResponse }
        var components = URLComponents(string: "https://kfzfzarslqdqmrazohej.supabase.co/rest/v1/oi_stories")!
        components.queryItems = [
            URLQueryItem(name: "select", value: "id,user_id,title,cucumber_name"),
            URLQueryItem(name: "status", value: "eq.published"),
            URLQueryItem(name: "order", value: "created_at.desc,id.asc"),
            URLQueryItem(name: "limit", value: "20"),
            URLQueryItem(name: "offset", value: String(offset))
        ]
        var request = URLRequest(url: components.url!); request.timeoutInterval = 30
        let key = try publicKey()
        request.setValue(key, forHTTPHeaderField: "apikey")
        if key.hasPrefix("ey") { request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization") }
        let data = try await transport.send(request)
        try Task.checkCancellation()
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([PublicStorySummary].self, from: data)
    }

    private func publishedRecord(storyID: String) async throws -> Record? {
        guard let id = UUID(uuidString: storyID) else { return nil }
        guard let row = try await rows("oi_stories", id: id.uuidString, as: Record.self).first else { return nil }
        guard row.id == id, row.status == "published" else { throw Failure.invalidResponse }
        guard await MainActor.run(body: { !OiContentSafetyStore.shared.isBlocked(row.userId) }) else { return nil }
        return row
    }

    func fetchPublicStory(storyID: String) async throws -> Story? {
        guard let row = try await publishedRecord(storyID: storyID) else { return nil }
        let id = row.id
        let profiles = try await rows("oi_profiles", id: row.userId.uuidString, as: Profile.self)
        let regions = try await rows("oi_regions", id: row.regionId, as: Region.self)
        let parser = ISO8601DateFormatter(); parser.formatOptions = [.withInternetDateTime,.withFractionalSeconds]
        let fractional = parser.date(from: row.createdAt); parser.formatOptions = [.withInternetDateTime]
        guard let date = fractional ?? parser.date(from: row.createdAt) else { throw Failure.invalidResponse }
        let portraitURL: URL?
        if let appearance = row.cucumberAppearance {
            let path = "\((row.storageOwnerId ?? row.userId).uuidString.lowercased())/\(id.uuidString.lowercased())/appearance/\(appearance.id.uuidString.lowercased())/portrait.png"
            portraitURL = try? await publishedArtworkURL(path: path)
        } else { portraitURL = cucumberImageURL(for: row.cucumberAsset) }
        try Task.checkCancellation()
        guard await MainActor.run(body: { !OiContentSafetyStore.shared.isBlocked(row.userId) }) else { return nil }
        return Story(storyID: id.uuidString, donorID: row.userId, donorDisplayName: profiles.first?.nickname ?? "농부",
            title: row.title, content: row.body, publishedAt: date,
            location: StoryLocation(locationID: row.regionId, displayName: regions.first?.name ?? "장소 확인 중"),
            tags: [row.theme,row.emotion], cucumberID: id.uuidString, cucumberName: row.cucumberName,
            cucumberImageURL: portraitURL, hasCustomCucumberImage: row.cucumberAppearance != nil)
    }

    private func publishedArtworkURL(path: String) async throws -> URL {
        struct SignedResponse: Decodable { let signedURL: String }
        let prefix = "/object/sign/oi-story-media/\(path)"
        let base = "https://\(transport.approvedHost)/storage/v1"
        guard let endpoint = URL(string: base + prefix) else { throw Failure.configuration }
        var request = URLRequest(url: endpoint); request.httpMethod = "POST"
        let key = try publicKey()
        request.setValue(key, forHTTPHeaderField: "apikey")
        if key.hasPrefix("ey") { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{\"expiresIn\":300}".utf8)
        let data = try await transport.send(request)
        let response = try JSONDecoder().decode(SignedResponse.self, from: data)
        guard response.signedURL.hasPrefix(prefix + "?"), let url = URL(string: base + response.signedURL) else { throw Failure.invalidResponse }
        return url
    }

    private func cucumberImageURL(for asset: String?) -> URL? {
        guard let asset else { return nil }
        let resourceName: String
        switch asset {
        case "OiCats": resourceName = "61272"
        case "OiGardener": resourceName = "0e35d"
        case "OiWizard": resourceName = "9ac42"
        case "OiTraveler": resourceName = "aeb3a"
        default: return nil
        }
        return Bundle.main.url(forResource: resourceName, withExtension: "png")
    }

    func fetchPublicStoryCard(storyID: String) async throws -> StoryCard? {
        guard let row = try await publishedRecord(storyID: storyID) else { return nil }
        let imageURL: URL?
        if let snapshot = row.cardSnapshotId {
            let path = StoryCard.artworkPath(owner: row.storageOwnerId ?? row.userId, story: row.id, snapshot: snapshot)
            imageURL = try await publishedArtworkURL(path: path)
        } else { imageURL = nil }
        try Task.checkCancellation()
        guard await MainActor.run(body: { !OiContentSafetyStore.shared.isBlocked(row.userId) }) else { return nil }
        var card = StoryCard(cardID: row.id.uuidString, storyID: row.id.uuidString, imageURL: imageURL)
        if [2, 3].contains(row.cardSnapshotFormat ?? 1), let snapshot = row.cardSnapshotId {
            let owner = row.storageOwnerId ?? row.userId
            card.backImageURL = try await publishedArtworkURL(path: StoryCard.artworkPath(owner: owner, story: row.id, snapshot: snapshot, part: .back))
            card.frontPreviewURL = try await publishedArtworkURL(path: StoryCard.artworkPath(owner: owner, story: row.id, snapshot: snapshot, part: .frontPreview))
            card.backPreviewURL = try await publishedArtworkURL(path: StoryCard.artworkPath(owner: owner, story: row.id, snapshot: snapshot, part: .backPreview))
        }
        try Task.checkCancellation()
        guard await MainActor.run(body: { !OiContentSafetyStore.shared.isBlocked(row.userId) }) else { return nil }
        return card
    }

    // MARK: - NFC postcard (#291)

    private func authorized(_ url: URL, method: String = "GET", body: Data? = nil) throws -> URLRequest {
        var request = URLRequest(url: url); request.timeoutInterval = 30; request.httpMethod = method
        let key = try publicKey()
        request.setValue(key, forHTTPHeaderField: "apikey")
        if key.hasPrefix("ey") { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = body; request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return request
    }

    func fetchNFCPostcardStoryID(tag: String) async throws -> String? {
        guard AppClipLink.isValidPostcardTag(tag),
              let url = URL(string: "https://\(transport.approvedHost)/rest/v1/rpc/oi_nfc_postcard") else { return nil }
        let body = try JSONEncoder().encode(["p_tag": tag])
        let data = try await transport.send(try authorized(url, method: "POST", body: body))
        try Task.checkCancellation()
        // The function returns a bare JSON string (story UUID) or null.
        guard let value = try JSONDecoder().decode(String?.self, from: data) else { return nil }
        guard let id = UUID(uuidString: value) else { throw Failure.invalidResponse }
        return id.uuidString
    }

    func fetchPublicPostcardDetails(storyID: String) async throws -> PublicPostcardDetails? {
        guard let row = try await publishedRecord(storyID: storyID) else { return nil }
        let owner = row.storageOwnerId ?? row.userId
        var frontURL: URL?, backURL: URL?, coverURL: URL?
        if let snapshot = row.cardSnapshotId {
            if row.cardSnapshotFormat == 3 {
                coverURL = try? await publishedArtworkURL(path: StoryCard.artworkPath(owner: owner, story: row.id, snapshot: snapshot, part: .cover))
            }
            let isDuplex = [2, 3].contains(row.cardSnapshotFormat ?? 1)
            frontURL = try await publishedArtworkURL(path: StoryCard.artworkPath(owner: owner, story: row.id,
                snapshot: snapshot, part: isDuplex ? .frontPreview : .front))
            if isDuplex {
                // A failed format-2 back must be retried, never replaced by an unreviewed fallback.
                backURL = try await publishedArtworkURL(path: StoryCard.artworkPath(owner: owner, story: row.id,
                    snapshot: snapshot, part: .backPreview))
            }
        }
        var components = URLComponents()
        components.scheme = "https"; components.host = transport.approvedHost; components.path = "/rest/v1/oi_story_media"
        components.queryItems = [
            URLQueryItem(name: "select", value: "object_path"),
            URLQueryItem(name: "story_id", value: "eq.\(row.id.uuidString.lowercased())"),
            URLQueryItem(name: "order", value: "position.asc"),
            URLQueryItem(name: "limit", value: "1")
        ]
        guard let mediaURL = components.url else { throw Failure.configuration }
        struct Media: Decodable { let objectPath: String }
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let media = try decoder.decode([Media].self, from: try await transport.send(try authorized(mediaURL)))
        var coverPhotoURL: URL?
        if let path = media.first?.objectPath { coverPhotoURL = try await publishedArtworkURL(path: path) }
        let profile = try await rows("oi_profiles", id: row.userId.uuidString, as: Profile.self).first
        try Task.checkCancellation()
        guard await MainActor.run(body: { !OiContentSafetyStore.shared.isBlocked(row.userId) }) else { return nil }
        return PublicPostcardDetails(frontURL: frontURL, backURL: backURL, coverPhotoURL: coverPhotoURL,
                                     donorLine: profile.flatMap(Self.donorLine), coverURL: coverURL)
    }

    private static func donorLine(_ profile: Profile) -> String? {
        let name = profile.publicName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return nil }
        let year = (profile.admissionYear ?? "").suffix(2)
        let department = profile.department?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return [year.isEmpty ? "" : "\(year)학번", department, name].filter { !$0.isEmpty }.joined(separator: " ")
    }
}
