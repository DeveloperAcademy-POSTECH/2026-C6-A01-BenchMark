//
//  OiServiceAPI.swift
//  OiDonation
//
//  Created by 이돈혁 on 10/28/26.
//

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
            case 403: throw OiServiceError.server("현재 계정에서 이 요청을 처리할 수 없어요. 새로고침해 상태를 다시 확인해 주세요.")
            case 404 where path == "rest/v1/rpc/\(Self.resolveCardRequestRPC)": throw OiServiceError.conflict
            case 404 where path == "rest/v1/rpc/oi_review_evidence": throw OiEvidenceReviewError.serverNotReady
            case 404 where path == "rest/v1/rpc/oi_operator_audit": throw OiAuditError.notDeployed
            case 409: throw OiServiceError.conflict
            case 400, 422: throw OiServiceError.invalidInput
            case 429: throw OiServiceError.server("요청이 많습니다. 잠시 후 다시 시도해 주세요.")
            default: throw OiServiceError.unavailable
            }
        }
    }

    func reportContent(story: UUID, reason: String, detail: String, token: String) async throws -> OiContentReportReceipt {
        let body = try JSONSerialization.data(withJSONObject: ["p_story": story.uuidString, "p_reason": reason, "p_detail": detail])
        let data = try await request("rest/v1/rpc/oi_report_content", method: "POST", token: token, body: body)
        return try decoder.decode(OiContentReportReceipt.self, from: data)
    }

    func contentReports(offset: Int, token: String) async throws -> [OiContentReport] {
        let data = try await request("rest/v1/rpc/oi_content_reports", method: "POST", token: token,
            body: JSONSerialization.data(withJSONObject: ["p_offset": offset]))
        return try decoder.decode([OiContentReport].self, from: data)
    }

    func reviewContent(report: UUID, action: String, note: String, token: String) async throws {
        let data = try await request("rest/v1/rpc/oi_review_content", method: "POST", token: token,
            body: JSONSerialization.data(withJSONObject: ["p_report": report.uuidString, "p_action": action, "p_note": note]))
        let receipt = try decoder.decode(OiContentReportReceipt.self, from: data)
        guard receipt.id == report, receipt.status == action else { throw OiServiceError.conflict }
    }

    func accountDeletionStatus(token: String) async throws -> OiAccountDeletionStatus {
        let data = try await request("rest/v1/rpc/oi_account_deletion_status", method: "POST", token: token, body: Data("{}".utf8))
        return try decoder.decode(OiAccountDeletionStatus.self, from: data)
    }

    func deleteAccount(_ account: UUID, token: String, proof: OiSession) async throws -> OiAccountDeletionReceipt {
        let body = try JSONSerialization.data(withJSONObject: ["account_id": account.uuidString,
            "consent": true, "proof": proof.accessToken])
        let data = try await request("functions/v1/delete-account", method: "POST", token: token, body: body, timeout: 50)
        let receipt = try decoder.decode(OiAccountDeletionReceipt.self, from: data)
        guard receipt.deleted, receipt.deletedMemberIds.contains(account),
              receipt.deletedMemberIds.contains(proof.user.id) else { throw OiServiceError.conflict }
        return receipt
    }

    func reviewDonationEvidence(_ evidence: OiEvidence, token: String) async throws -> OiDonationEvidenceReview {
        let response: Data
        do {
            response = try await request("functions/v1/analyze-donation-evidence", method: "POST", token: token,
                body: JSONEncoder().encode(["evidence_id": evidence.id.uuidString]), timeout: 70)
        } catch OiServiceError.unavailable {
            throw OiServiceError.server("증빙은 접수됐지만 AI 검사를 완료하지 못했어요. AI 검사만 다시 시도해 주세요.")
        }
        let review = try decoder.decode(OiDonationEvidenceReview.self, from: response)
        guard review.reviewType == "donation_evidence", review.evidenceId == evidence.id,
              review.submittedAt == evidence.submittedAt, review.humanReviewRequired,
              !review.authenticityVerified, review.summary?.isConsistent ?? true else { throw OiServiceError.conflict }
        if review.summary?.sufficientEvidence == true {
            guard review.assessment.verdict == .noObviousSigns, review.assessment.readability == .readable,
                  review.assessment.findings.isEmpty else { throw OiServiceError.conflict }
        }
        return review
    }

    func reviewSchoolEvidence(_ data: Data, contentType: String, token: String) async throws -> OiSchoolEvidenceOutcome {
        let response: Data
        do {
            response = try await request("functions/v1/analyze-school-evidence", method: "POST", token: token,
                                         body: data, contentType: contentType, timeout: 70)
        } catch OiServiceError.unavailable {
            throw OiServiceError.server("학교 증빙을 분석하지 못했어요. 잠시 후 다시 시도해 주세요.")
        }
        let review = try decoder.decode(OiSchoolEvidenceReview.self, from: response)
        guard review.reviewType == "school_affiliation", review.humanReviewRequired,
              !review.affiliationVerified, !review.authenticityVerified,
              let summary = review.summary, let outcome = OiSchoolEvidenceOutcome(reviewOutcome: summary.outcome) else {
            throw OiServiceError.server("AI 자료 확인 결과를 읽지 못했어요. 다시 시도해 주세요.")
        }
        return outcome
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

    func operatorAudit(_ query: OiAuditQuery, after cursor: OiAuditCursor?, token: String) async throws -> OiAuditPage {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var payload: [String: Any] = ["p_from": formatter.string(from: query.from),
            "p_until": formatter.string(from: query.until), "p_category": query.category.rawValue,
            "p_limit": OiAuditQuery.pageSize]
        if let cursor { payload["p_cursor_at"] = cursor.createdAt; payload["p_cursor_id"] = cursor.id }
        let data = try await request("rest/v1/rpc/oi_operator_audit", method: "POST", token: token,
                                     body: JSONSerialization.data(withJSONObject: payload))
        let page: OiAuditPage
        do { page = try decoder.decode(OiAuditPage.self, from: data) }
        catch { throw OiAuditError.invalidPage }
        try page.validate(query: query, after: cursor)
        return page
    }

    func mutate<Value: Decodable>(_ action: String, payload: [String: Any], token: String, as type: Value.Type) async throws -> Value {
        let body = try JSONSerialization.data(withJSONObject: ["p_action": action, "p_payload": payload])
        let data = try await request("rest/v1/rpc/oi_mutate", method: "POST", token: token, body: body)
        return try decoder.decode(Value.self, from: data)
    }

    func cardRequests(token: String) async throws -> [OiCardRequest] {
        try await cardRequestRPC("oi_card_requests", payload: [:], token: token, as: [OiCardRequest].self)
    }

    func reviewEvidence(_ review: OiEvidenceReview, token: String) async throws -> OiEvidence {
        guard try await capabilities(token: token).independentStoryCreation == true else {
            throw OiEvidenceReviewError.serverNotReady
        }
        let row = review.snapshot
        let payload: [String: Any] = ["id": row.id.uuidString, "status": review.decision.rawValue,
            "review_note": review.note, "expected_status": row.status,
            "expected_object_path": row.objectPath as Any? ?? NSNull(),
            "expected_submitted_at": row.submittedAt as Any? ?? NSNull(),
            "expected_reviewed_at": row.reviewedAt as Any? ?? NSNull()]
        let body = try JSONSerialization.data(withJSONObject: ["p_payload": payload])
        let data = try await request("rest/v1/rpc/oi_review_evidence", method: "POST", token: token, body: body)
        return try decoder.decode(OiEvidence.self, from: data)
    }

    /// Original evidence never enters the shared URL cache or a signed-link viewer.
    func evidenceDocument(path: String, token: String) async throws -> OiEvidenceDocument {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = transport.session.configuration.protocolClasses
        config.urlCache = nil; config.httpCookieStorage = nil
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let escaped = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        guard let url = URL(string: "https://\(Self.projectHost)/storage/v1/object/authenticated/oi-evidence/\(escaped)") else {
            throw OiEvidenceReviewError.invalidDocument
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.timeoutInterval = 30
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let data = try await APIClient(session: session, approvedHost: Self.projectHost).send(request)
            try Task.checkCancellation()
            return try OiEvidenceDocument(data: data)
        } catch APIError.httpStatus(401) { throw OiServiceError.signInRequired }
        catch APIError.httpStatus(403) { throw OiOperatorStoryError.accessDenied }
    }

    // Only the evidence ID is sent; the existing server owns external analysis.
    func analyzeEvidence(_ snapshot: OiEvidence, token: String) async throws -> OiEvidenceAnalysis {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = transport.session.configuration.protocolClasses
        configuration.urlCache = nil; configuration.httpCookieStorage = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        guard let url = URL(string: "https://\(Self.projectHost)/functions/v1/analyze-evidence") else { throw OiServiceError.configuration }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "POST"; request.timeoutInterval = 75
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["evidence_id": snapshot.id.uuidString.lowercased()])
        do {
            let (data, response) = try await APIClient(session: session, approvedHost: Self.projectHost).response(request)
            try Task.checkCancellation()
            if response.statusCode != 200 {
                struct Failure: Decodable { let error: String }
                let code = (try? JSONDecoder().decode(Failure.self, from: data))?.error
                switch response.statusCode {
                case 401: throw OiServiceError.signInRequired
                case 403: throw OiOperatorStoryError.accessDenied
                case 404 where code == "evidence_not_found": throw OiEvidenceReviewError.missing
                case 404: throw OiEvidenceAnalysisError.notDeployed
                case 409: throw OiServiceError.conflict
                case 413, 415, 422: throw OiEvidenceAnalysisError.documentUnavailable
                case 429: throw OiEvidenceAnalysisError.busy
                case 503 where code == "analysis_not_configured": throw OiEvidenceAnalysisError.notConfigured
                case 504: throw OiEvidenceAnalysisError.timeout
                default: throw OiEvidenceAnalysisError.unavailable
                }
            }
            guard data.count <= 64 * 1024 else { throw OiEvidenceAnalysisError.invalidResult }
            let result: OiEvidenceAnalysis
            do { result = try decoder.decode(OiEvidenceAnalysis.self, from: data) }
            catch { throw OiEvidenceAnalysisError.invalidResult }
            try result.validate(for: snapshot)
            return result
        } catch URLError.timedOut { throw OiEvidenceAnalysisError.timeout }
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
        let storyMedia = bucket == "oi-story-media"
        do {
            _ = try await request("storage/v1/object/\(bucket)/\(escaped)", method: "POST", token: token,
                                  body: data, contentType: contentType, timeout: storyMedia ? 60 : 30)
        } catch {
            let timedOut = (error as? URLError)?.code == .timedOut
            switch error {
            case OiServiceError.conflict, OiServiceError.invalidInput: break
            case _ where storyMedia && timedOut: break
            default: throw error
            }
            // The server can commit a file before the upload response reaches the app.
            let existing = try? await request("storage/v1/object/authenticated/\(bucket)/\(escaped)", token: token)
            try Task.checkCancellation()
            guard existing == data else {
                if timedOut {
                    throw OiServiceError.server("이미지 전송을 확인하지 못했어요. 초안을 저장했으니 연결을 확인한 뒤 다시 요청해 주세요.")
                }
                throw error
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
              profile.schoolAdmissionYear == admissionYear, profile.schoolDepartment == department else { throw OiServiceError.unavailable }
        return profile
    }

    func farmerOutfit(owner: UUID, token: String) async throws -> OiFarmerOutfit? {
        let data = try await request("rest/v1/rpc/oi_farmer_outfit", method: "POST", token: token, body: Data("{}".utf8))
        let receipt = try decoder.decode(OiFarmerOutfitReceipt.self, from: data)
        guard receipt.accountId == owner, receipt.outfit?.isValid ?? true else { throw OiServiceError.unavailable }
        return receipt.outfit
    }

    func saveFarmerOutfit(owner: UUID, outfit: OiFarmerOutfit, token: String) async throws -> OiFarmerOutfit {
        guard outfit.isValid else { throw OiServiceError.invalidInput }
        let value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(outfit))
        let body = try JSONSerialization.data(withJSONObject: ["p_outfit": value])
        let data = try await request("rest/v1/rpc/oi_save_farmer_outfit", method: "POST", token: token, body: body)
        let receipt = try decoder.decode(OiFarmerOutfitReceipt.self, from: data)
        guard receipt.accountId == owner, receipt.outfit == outfit else { throw OiServiceError.unavailable }
        return outfit
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

    func updateProfile(owner: UUID, nickname: String?, schoolID: String?, academicInfo: OiPublicAcademicInfo? = nil, token: String) async throws -> OiProfile {
        var patch: [String: String] = [:]
        if let nickname { patch["nickname"] = nickname }
        if let schoolID { patch["school_id"] = schoolID }
        if let academicInfo {
            let info = academicInfo.cleaned
            guard info.isValid else { throw OiServiceError.invalidInput }
            patch["public_name"] = info.name
            patch["department"] = info.department
            patch["admission_year"] = info.admissionYear
        }
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

    func downloadSignedObject(bucket: String, path: String, token: String?) async throws -> Data {
        let url = try await signedURL(bucket: bucket, path: path, token: token)
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        return try await transport.send(request)
    }
}
