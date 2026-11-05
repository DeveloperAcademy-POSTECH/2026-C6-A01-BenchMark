// Created by 이돈혁

import Foundation

@MainActor
protocol OiAuthenticating {
    func signIn(api: OiServiceAPI) async throws -> OiSession
}

struct OiServiceAPI {
    static let projectHost = "kfzfzarslqdqmrazohej.supabase.co"
    static let authenticationCallback = "kr.ac.postech.benchmark://auth/callback"
    private static let resolveCardRequestRPC = "oi_resolve_card_request"
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
        var key = ProcessInfo.processInfo.environment["OI_SUPABASE_PUBLISHABLE_KEY"]
            ?? Bundle.main.object(forInfoDictionaryKey: "OI_SUPABASE_PUBLISHABLE_KEY") as? String ?? ""
        if key.isEmpty || key.contains("$(") {
            struct Configuration: Decodable { let publishableKey: String }
            if let url = Bundle.main.url(forResource: "Service.local", withExtension: "plist") {
                key = try PropertyListDecoder().decode(Configuration.self, from: Data(contentsOf: url)).publishableKey
            }
        }
        return try Self(key: key)
    }

    func request(_ path: String, method: String = "GET", token: String? = nil,
                 body: Data? = nil, contentType: String = "application/json", prefer: String? = nil,
                 timeout: TimeInterval = 30) async throws -> Data {
        guard let url = URL(string: "https://\(Self.projectHost)/\(path)") else { throw OiServiceError.configuration }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
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
            case 404 where path == "rest/v1/rpc/\(Self.resolveCardRequestRPC)": throw OiServiceError.conflict
            case 409: throw OiServiceError.conflict
            case 400, 422: throw OiServiceError.invalidInput
            case 429: throw OiServiceError.server("요청이 많습니다. 잠시 후 다시 시도해 주세요.")
            default: throw OiServiceError.unavailable
            }
        }
    }

    func reviewSchoolEvidence(_ data: Data, contentType: String, token: String) async throws -> OiSchoolEvidenceReview {
        let response: Data
        do {
            response = try await request("functions/v1/analyze-school-evidence", method: "POST", token: token,
                                         body: data, contentType: contentType, timeout: 70)
        } catch OiServiceError.unavailable {
            throw OiServiceError.server("학교 증빙을 분석하지 못했어요. 잠시 후 다시 시도해 주세요.")
        }
        let review = try decoder.decode(OiSchoolEvidenceReview.self, from: response)
        guard review.reviewType == "school_affiliation", review.humanReviewRequired,
              !review.affiliationVerified, !review.authenticityVerified else {
            throw OiServiceError.server("학교 증빙 검토 응답을 확인할 수 없어요.")
        }
        return review
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

    /// Use the public role even when an owner/operator session exists.
    func publishedStory(_ id: UUID) async throws -> OiLiveStory {
        let records = try await rows("oi_stories", query: "id=eq.\(id.uuidString)&status=eq.published", as: OiLiveStory.self)
        try Task.checkCancellation()
        guard let story = records.first, story.id == id, story.status == "published" else { throw OiServiceError.unavailable }
        return story
    }

    /// Nearby AR must never include an owner's drafts or hidden stories.
    func publishedStories() async throws -> [OiLiveStory] {
        let records = try await rows("oi_stories", query: "status=eq.published&order=id.asc", as: OiLiveStory.self)
        try Task.checkCancellation()
        return records.filter { $0.status == "published" }
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

    func cardRequests(token: String) async throws -> [OiCardRequest] {
        try await cardRequestRPC("oi_card_requests", payload: [:], token: token, as: [OiCardRequest].self)
    }

    func sendCardRequest(storyID: UUID, requestID: UUID, token: String) async throws -> OiCardRequest.Status {
        let receipt = try await cardRequestRPC("oi_request_card",
            payload: ["p_story_id": storyID.uuidString, "p_request_id": requestID.uuidString],
            token: token, as: OiCardRequestReceipt.self)
        // An existing pending request for this story may have a different ID.
        guard receipt.storyId == storyID else { throw OiServiceError.unavailable }
        return receipt.status
    }

    func resolveCardRequest(_ id: UUID, accept: Bool, token: String) async throws -> OiCardRequest {
        let response = try await cardRequestRPC(Self.resolveCardRequestRPC,
            payload: ["p_request_id": id.uuidString, "p_decision": accept ? "accept" : "reject"],
            token: token, as: OiCardRequest.self)
        guard response.id == id, response.status == (accept ? .accepted : .rejected) else {
            throw OiServiceError.unavailable
        }
        return response
    }

    private func cardRequestRPC<Value: Decodable>(_ function: String, payload: [String: String],
                                                   token: String, as type: Value.Type) async throws -> Value {
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await request("rest/v1/rpc/\(function)", method: "POST", token: token, body: body)
        let requestDecoder = JSONDecoder()
        requestDecoder.keyDecodingStrategy = .convertFromSnakeCase
        requestDecoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso.date(from: value) { return date }
            iso.formatOptions = [.withInternetDateTime]
            if let date = iso.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid request timestamp")
        }
        return try requestDecoder.decode(Value.self, from: data)
    }

    func session(grant: String, payload: [String: String]) async throws -> OiSession {
        let data: Data
        do { data = try await request("auth/v1/token?grant_type=\(grant)", method: "POST", body: JSONSerialization.data(withJSONObject: payload)) }
        catch OiServiceError.invalidInput where grant == "refresh_token" { throw OiServiceError.signInRequired }
        catch OiServiceError.invalidInput where grant == "pkce" || grant == "id_token" { throw OiServiceError.authenticationFailed }
        var session = try decoder.decode(OiSession.self, from: data)
        session.expiresAt = Date().timeIntervalSince1970 + session.expiresIn
        return session
    }

    func signOutCurrentSession(token: String) async throws {
        _ = try await request("auth/v1/logout?scope=local", method: "POST", token: token)
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

    func schoolProfile(owner: UUID, token: String) async throws -> OiProfile {
        let data = try await request("rest/v1/rpc/oi_school_profile", method: "POST", token: token, body: Data("{}".utf8))
        let profile = try decoder.decode(OiProfile.self, from: data)
        guard profile.id == owner else { throw OiServiceError.unavailable }
        return profile
    }

    func updateSchoolProfile(owner: UUID, schoolID: String, admissionYear: Int, department: String?, token: String) async throws -> OiProfile {
        let body = try JSONSerialization.data(withJSONObject: [
            "p_school_id": schoolID,
            "p_admission_year": admissionYear,
            "p_department": department as Any? ?? NSNull()
        ])
        let data = try await request("rest/v1/rpc/oi_update_school_profile", method: "POST", token: token, body: body)
        let profile = try decoder.decode(OiProfile.self, from: data)
        guard profile.id == owner, profile.schoolId == schoolID,
              profile.admissionYear == admissionYear, profile.department == department else { throw OiServiceError.unavailable }
        return profile
    }

    func updateFarmName(owner: UUID, farmName: String, token: String) async throws -> OiProfile {
        let body = try JSONSerialization.data(withJSONObject: ["farm_name": farmName])
        let data = try await request("rest/v1/oi_profiles?id=eq.\(owner.uuidString)", method: "PATCH", token: token,
            body: body, prefer: "return=representation")
        let profiles = try decoder.decode([OiProfile].self, from: data)
        guard profiles.count == 1, let profile = profiles.first, profile.id == owner,
              profile.farmName == farmName else { throw OiServiceError.unavailable }
        return profile
    }

    func updateProfile(owner: UUID, nickname: String?, schoolID: String?, token: String) async throws -> OiProfile {
        var patch: [String: String] = [:]
        if let nickname { patch["nickname"] = nickname }
        if let schoolID { patch["school_id"] = schoolID }
        guard !patch.isEmpty else { throw OiServiceError.invalidInput }
        let body = try JSONSerialization.data(withJSONObject: patch)
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
