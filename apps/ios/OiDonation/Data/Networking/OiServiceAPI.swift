// Created by 이돈혁

import Foundation

struct OiServiceAPI {
    static let projectHost = "kfzfzarslqdqmrazohej.supabase.co"
    private let key: String
    private let transport: APIClient
    private let decoder: JSONDecoder

    init(key: String, session: URLSession = .shared) throws {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-.")
        guard !key.isEmpty, key.rangeOfCharacter(from: allowed.inverted) == nil,
              !key.hasPrefix("sb_secret_"), !key.contains("$(") else { throw OiServiceError.configuration }
        if key.hasPrefix("ey"), let payload = key.split(separator: ".").dropFirst().first {
            var encoded = String(payload).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
            guard let data = Data(base64Encoded: encoded),
                  let claims = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  claims["role"] as? String == "anon", claims["ref"] as? String == "kfzfzarslqdqmrazohej" else {
                throw OiServiceError.configuration
            }
        } else if !key.hasPrefix("sb_publishable_") { throw OiServiceError.configuration }
        self.key = key
        transport = APIClient(session: session, approvedHost: Self.projectHost)
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    static func configured() throws -> Self {
        let key = ProcessInfo.processInfo.environment["OI_SUPABASE_PUBLISHABLE_KEY"]
            ?? Bundle.main.object(forInfoDictionaryKey: "OI_SUPABASE_PUBLISHABLE_KEY") as? String ?? ""
        return try Self(key: key)
    }

    func request(_ path: String, method: String = "GET", token: String? = nil,
                 body: Data? = nil, contentType: String = "application/json", prefer: String? = nil) async throws -> Data {
        guard let url = URL(string: "https://\(Self.projectHost)/\(path)") else { throw OiServiceError.configuration }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue(key, forHTTPHeaderField: "apikey")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        else if key.hasPrefix("ey") { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        request.httpBody = body
        do { return try await transport.send(request) }
        catch APIError.httpStatus(let status) {
            switch status {
            case 401: throw OiServiceError.signInRequired
            case 403: throw OiServiceError.server("권한이 없거나 작성 승인이 만료됐습니다. 검토 상태를 확인해 주세요.")
            case 409: throw OiServiceError.conflict
            case 400, 422: throw OiServiceError.invalidInput
            case 429: throw OiServiceError.server("요청이 많습니다. 잠시 후 다시 시도해 주세요.")
            default: throw OiServiceError.unavailable
            }
        }
    }

    func rows<Value: Decodable & Identifiable>(_ table: String, query: String = "", token: String? = nil, as type: Value.Type) async throws -> [Value] {
        var values: [Value] = []
        var seen: Set<Value.ID> = []
        var offset = 0
        while true {
            let suffix = query.isEmpty ? "" : "&\(query)"
            let data = try await request("rest/v1/\(table)?select=*&limit=200&offset=\(offset)\(suffix)", token: token)
            let page = try decoder.decode([Value].self, from: data)
            values += page.filter { seen.insert($0.id).inserted }
            if page.count < 200 { return values }
            offset += page.count
        }
    }

    func collectionMetrics(token: String?) async throws -> [OiCollectionMetric] {
        var values: [OiCollectionMetric] = []
        var offset = 0
        while true {
            let data = try await request("rest/v1/rpc/oi_collection_metrics?order=story_id.asc&limit=200&offset=\(offset)", method: "POST", token: token, body: Data("{}".utf8))
            let page = try decoder.decode([OiCollectionMetric].self, from: data)
            values += page
            if page.count < 200 { return values }
            offset += page.count
        }
    }

    func mutate<Value: Decodable>(_ action: String, payload: [String: Any], token: String, as type: Value.Type) async throws -> Value {
        let body = try JSONSerialization.data(withJSONObject: ["p_action": action, "p_payload": payload])
        let data = try await request("rest/v1/rpc/oi_mutate", method: "POST", token: token, body: body)
        return try decoder.decode(Value.self, from: data)
    }

    func session(grant: String, payload: [String: String]) async throws -> OiSession {
        let data: Data
        do { data = try await request("auth/v1/token?grant_type=\(grant)", method: "POST", body: JSONSerialization.data(withJSONObject: payload)) }
        catch OiServiceError.invalidInput where grant == "refresh_token" { throw OiServiceError.signInRequired }
        var session = try decoder.decode(OiSession.self, from: data)
        session.expiresAt = Date().timeIntervalSince1970 + session.expiresIn
        return session
    }

    func upload(bucket: String, path: String, data: Data, contentType: String, token: String) async throws {
        let escaped = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        do { _ = try await request("storage/v1/object/\(bucket)/\(escaped)", method: "POST", token: token, body: data, contentType: contentType) }
        catch let failure as OiServiceError {
            switch failure {
            case .conflict, .invalidInput:
                do {
                    let existing = try await request("storage/v1/object/authenticated/\(bucket)/\(escaped)", token: token)
                    guard existing == data else { throw failure }
                } catch { throw failure }
            default: throw failure
            }
        }
    }

    func updateProfile(owner: UUID, nickname: String, token: String) async throws -> OiProfile {
        let body = try JSONSerialization.data(withJSONObject: ["nickname":nickname])
        let data = try await request("rest/v1/oi_profiles?id=eq.\(owner.uuidString)", method: "PATCH", token: token,
            body: body, prefer: "return=representation")
        let profiles = try decoder.decode([OiProfile].self, from: data)
        guard profiles.count == 1, let profile = profiles.first, profile.id == owner else { throw OiServiceError.unavailable }
        return profile
    }

    func capabilities(token: String) async throws -> OiCapabilities {
        let data = try await request("rest/v1/rpc/oi_capabilities", method: "POST", token: token, body: Data("{}".utf8))
        return try decoder.decode(OiCapabilities.self, from: data)
    }

    func signedURL(bucket: String, path: String, token: String?) async throws -> URL {
        struct SignedResponse: Decodable { let signedURL: String }
        let escaped = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        let data = try await request("storage/v1/object/sign/\(bucket)/\(escaped)", method: "POST", token: token, body: Data("{\"expiresIn\":300}".utf8))
        let value = try JSONDecoder().decode(SignedResponse.self, from: data)
        guard let url = URL(string: "https://\(Self.projectHost)/storage/v1\(value.signedURL)"),
              url.host == Self.projectHost, url.scheme == "https" else { throw OiServiceError.unavailable }
        return url
    }
}
