import Foundation

struct CampusSharedOi: Codable, Identifiable, Hashable {
    let id: UUID
    let storyID: String
    let campusID: String
    let model: String
    let latitude: Double
    let longitude: Double
    let heightMeters: Double
    let headingDegrees: Double
    let displayName: String
    let title: String
    let story: String
    let status: String
    let revision: Int
    let updatedAt: String

    var placement: CampusPlacement {
        CampusPlacement(id: id, storyID: storyID, latitude: latitude, longitude: longitude,
                        heightMeters: heightMeters, headingDegrees: headingDegrees)
    }
    var statusLabel: String {
        switch status { case "published": "공개 중"; case "pending": "공개 검토 대기"; default: "비공개" }
    }
    func validated() throws -> Self {
        _ = try placement.validated()
        guard UUID(uuidString: storyID) == id, campusID == "postech", model == "helmet-oi",
              !title.isEmpty, title.utf16.count <= 80, !story.isEmpty, story.utf16.count <= 2000,
              !displayName.isEmpty, displayName.utf16.count <= 40,
              ["pending", "published", "hidden"].contains(status), revision > 0
        else { throw CampusSharedError.invalidResponse }
        return self
    }
}

struct CampusSharedDraft: Encodable {
    let id: UUID
    let campusID = "postech"
    let model = "helmet-oi"
    let latitude: Double
    let longitude: Double
    let heightMeters: Double
    let headingDegrees: Double
    let displayName: String
    let title: String
    let story: String
    var revision: Int?
}

struct CampusWriterCredential: Codable {
    let writerID: UUID
    let token: String
    let expiresAt: String
    var isValid: Bool {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = format.date(from: expiresAt) ?? ISO8601DateFormatter().date(from: expiresAt)
        return token.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil && (date ?? .distantPast) > Date()
    }
}

enum CampusSharedError: LocalizedError {
    case unconfigured, invalidResponse, unauthorized, unavailable, conflict, rejected(String), server(String), keychain
    var errorDescription: String? {
        switch self {
        case .unconfigured: "공유 서버 주소가 아직 설정되지 않았어요. 팀원의 배포 주소를 연결한 뒤 이용할 수 있어요."
        case .invalidResponse: "서버 응답을 확인하지 못했어요. 다시 시도해 주세요."
        case .unauthorized: "작성 권한이 만료되었거나 취소되었어요. 운영진에게 코드 재발급을 요청해 주세요."
        case .unavailable: "공개되지 않았거나 삭제된 오이예요. 목록을 새로고침해 주세요."
        case .conflict: "내용이 바뀌었어요. 내 오이 목록을 새로고침한 뒤 다시 시도해 주세요."
        case .server(let message), .rejected(let message): message
        case .keychain: "작성 권한을 안전하게 저장하지 못했어요. 운영진에게 코드 재발급을 요청해 주세요."
        }
    }
}

/// All endpoints are relative to one HTTPS origin. Credentials never follow redirects.
final class CampusSharedAPI {
    let origin: URL?
    private struct Failure: Decodable { let error: String }
    private let session: URLSession
    private let redirectGuard = CampusRedirectGuard()

    static func approvedOrigin(_ value: String) -> URL? {
        guard let parts = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/", let url = parts.url else { return nil }
        return url
    }
    init(origin: URL? = CampusSharedAPI.approvedOrigin(Bundle.main.object(forInfoDictionaryKey: "OI_CAMPUS_API_ORIGIN") as? String ?? ""), session: URLSession? = nil) {
        self.origin = origin
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.urlCache = nil
        self.session = session ?? URLSession(configuration: configuration, delegate: redirectGuard, delegateQueue: nil)
    }
    private func request<T: Decodable>(_ path: String, method: String = "GET", token: String? = nil, body: Data? = nil) async throws -> T {
        guard let origin else { throw CampusSharedError.unconfigured }
        guard let url = URL(string: path, relativeTo: origin)?.absoluteURL,
              url.scheme == origin.scheme, url.host == origin.host, url.port == origin.port else { throw CampusSharedError.invalidResponse }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (stream, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, response.url == url else { throw CampusSharedError.invalidResponse }
        guard response.expectedContentLength <= 2_000_000 else { throw CampusSharedError.invalidResponse }
        var data = Data()
        for try await byte in stream {
            guard data.count < 2_000_000 else { throw CampusSharedError.invalidResponse }
            data.append(byte)
        }
        try Task.checkCancellation()
        switch http.statusCode {
        case 200...299: return try JSONDecoder().decode(T.self, from: data)
        case 401: throw CampusSharedError.unauthorized
        case 404: throw CampusSharedError.unavailable
        case 409: throw CampusSharedError.conflict
        default:
            let message = (try? JSONDecoder().decode(Failure.self, from: data))?.error
            let description = message.map { String($0.prefix(200)) } ?? "서버에 연결하지 못했어요. 다시 시도해 주세요."
            if [400, 413, 415, 429].contains(http.statusCode) { throw CampusSharedError.rejected(description) }
            throw CampusSharedError.server(description)
        }
    }
    func list(mine: Bool = false, token: String? = nil) async throws -> [CampusSharedOi] {
        struct Page: Decodable { let items: [CampusSharedOi]; let nextCursor: String? }
        var items: [CampusSharedOi] = [], cursor: String?, seen = Set<String>()
        repeat {
            let path = "/api/campus/" + (mine ? "mine" : "ois") + (cursor.map { "?cursor=" + $0 } ?? "")
            let page: Page = try await request(path, token: mine ? token : nil)
            guard page.items.count <= 200 else { throw CampusSharedError.invalidResponse }
            for item in page.items {
                _ = try item.validated()
                guard mine || item.status == "published" else { throw CampusSharedError.invalidResponse }
                items.append(item)
            }
            cursor = page.nextCursor
            if let cursor {
                guard UUID(uuidString: cursor) != nil, seen.insert(cursor).inserted, items.count <= 10_000 else { throw CampusSharedError.invalidResponse }
            }
        } while cursor != nil
        guard Set(items.map(\.id)).count == items.count else { throw CampusSharedError.invalidResponse }
        return items
    }
    func story(_ id: UUID, token: String? = nil) async throws -> CampusSharedOi {
        let item: CampusSharedOi = try await request("/api/campus/ois/" + id.uuidString, token: token)
        guard item.id == id else { throw CampusSharedError.invalidResponse }
        return try item.validated()
    }
    func redeem(_ code: String) async throws -> CampusWriterCredential {
        try await request("/api/campus/session", method: "POST", body: JSONEncoder().encode(["code": code]))
    }
    func save(_ draft: CampusSharedDraft, token: String) async throws {
        struct Saved: Decodable { let id: UUID }
        let path = "/api/campus/ois" + (draft.revision == nil ? "" : "/" + draft.id.uuidString)
        let result: Saved = try await request(path, method: draft.revision == nil ? "POST" : "PUT", token: token, body: JSONEncoder().encode(draft))
        guard result.id == draft.id else { throw CampusSharedError.invalidResponse }
    }
    func remove(_ item: CampusSharedOi, token: String) async throws {
        struct Removed: Decodable { let ok: Bool }
        let result: Removed = try await request("/api/campus/ois/" + item.id.uuidString, method: "DELETE", token: token, body: JSONEncoder().encode(["revision": item.revision]))
        guard result.ok else { throw CampusSharedError.invalidResponse }
    }
}

private final class CampusRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
