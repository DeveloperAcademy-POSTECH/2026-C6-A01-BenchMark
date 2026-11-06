//
//  OiRemoteStoreTests.swift
//  OiDonationTests
//
//  Created by 이돈혁 on 10/28/26.
//

import XCTest
import SwiftUI
import UIKit
import RealityKit
@testable import OiDonation

final class OiStoreURLProtocol: URLProtocol {
    static var handle: ((URLRequest, OiStoreURLProtocol) -> Void)?
    private let lock = NSLock()
    private var stopped = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.handle?(request, self) }
    override func stopLoading() { lock.lock(); stopped = true; lock.unlock() }
    func respond(_ status: Int, _ data: Data) {
        lock.lock(); let canceled = stopped; lock.unlock()
        guard !canceled, let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}

final class OiTestBackend {
    static let owner = UUID(uuidString: "b1000000-0000-4000-8000-000000000001") ?? UUID()
    static let other = UUID(uuidString: "b1000000-0000-4000-8000-000000000002") ?? UUID()
    static let grant = UUID(uuidString: "b1000000-0000-4000-8000-000000000010") ?? UUID()
    private let lock = NSLock()
    struct State {
        var unapprovedDraftsEnabled: Bool?
        var hasWritingGrant = true
        var nickname = "Owner A"
        var farmName: String? = "오이"
        var otherFarmName = "다른밭"
        var profilePatchBodies: [[String: Any]] = []
        var failFarmWrite = false
        var mismatchedFarmReceipt = false
        var holdFarmWrite = false
        var publicName = ""
        var department = ""
        var admissionYear = ""
        var schoolID: String?
        var schoolProfileEnabled = false
        var farmerOutfitEnabled = false
        var farmerOutfit: [String: Any]?
        var otherFarmerOutfit: [String: Any]?
        var farmerOutfitReads = 0
        var farmerOutfitWrites = 0
        var farmerOutfitPayloads: [[String: Any]] = []
        var failFarmerOutfitWrite = false
        var mismatchedFarmerOutfitReceipt = false
        var omitsFarmerOutfitReceiptField = false
        var holdFarmerOutfitWrite = false
        var schoolMetadataSchoolID: String? = "postech"
        var includesSecondSchool = false
        var schoolAdmissionYear: Int?
        var schoolDepartment: String?
        var schoolProfileReads = 0
        var schoolProfileWrites = 0
        var failSchoolProfileWrite = false
        var mismatchedSchoolProfileReceipt = false
        var failReads = false
        var isOperator = false
        var failCapabilities = false
        var reviewCount = 0
        var failAfterReview = false
        var loseReviewResponse = false
        var holdReviewResponse = false
        var ignoreStoryStatusFilter = false
        var evidenceReviewCount = 0
        var evidenceRPCMissing = false
        var holdEvidenceRead = false
        var history: [[String: Any]] = []
        var failHistoryReads = false
        var holdHistoryRead = false
        var revokeOnDocumentRead = false
        var analysisStatus = 200
        var analysisError = "analysis_unavailable"
        var analysisResult: [String: Any] = [:]
        var analysisBodies: [[String: Any]] = []
        var holdAnalysis = false
        var changeEvidenceAfterAnalysis = false
        var revokeAfterAnalysis = false
        var auditRecords: [[String: Any]] = []
        var auditBodies: [[String: Any]] = []
        var auditStatus = 200
        var holdAuditRead = false
        var failRefreshToken = false
        var failLogout = false
        var logoutScopes: [String?] = []
        var cardSendResponse: [String: String] = [:]
        var cardSendPayloads: [[String: String]] = []
        var holdCardSend = false
        var loseEvidenceResponse = false
        var holdOwnerRead = false
        var holdPostMergeRead = false
        var mergeConfirmCount = 0
        var didHold: (() -> Void)?
        var held: (OiStoreURLProtocol, Data)?
        var story: [String:Any]?
        var paths: [String] = []
        var uploads: [String:Data] = [:]
        var evidence: [String:Any]?
        var requestIDs: Set<String> = []
        var submittedTitle: String?
        var canonicalAccountID: UUID?
        var refreshSucceeds = false
        var refreshRequestCount = 0
        var grantOwnerQueries: [String] = []
    }
    private var state = State()

    func configure(_ update: (inout State) -> Void) { lock.lock(); defer { lock.unlock() }; update(&state) }
    func snapshot() -> State { lock.lock(); defer { lock.unlock() }; return state }
    func releaseHeldRead() {
        let value = snapshot().held
        configure { $0.held = nil; $0.holdOwnerRead = false; $0.holdPostMergeRead = false; $0.holdReviewResponse = false; $0.holdEvidenceRead = false; $0.holdHistoryRead = false; $0.holdAnalysis = false; $0.holdAuditRead = false; $0.holdCardSend = false; $0.holdFarmWrite = false; $0.holdFarmerOutfitWrite = false }
        value?.0.respond(200, value?.1 ?? Data())
    }
    func install() { OiStoreURLProtocol.handle = { [weak self] request, client in self?.receive(request, client: client) } }

    static func body(_ request: URLRequest) -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var result = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            result.append(buffer, count: count)
        }
        return result
    }

    private func receive(_ request: URLRequest, client: OiStoreURLProtocol) {
        let path = request.url?.path ?? ""
        let raw = Self.body(request)
        let body = (try? JSONSerialization.jsonObject(with: raw)) as? [String:Any] ?? [:]
        let rawOwner = request.value(forHTTPHeaderField: "Authorization") == "Bearer token-b" ? Self.other : Self.owner
        lock.lock()
        let owner = state.canonicalAccountID ?? rawOwner
        var status = 200
        var result: Any = []
        var bytes: Data?
        if path == "/auth/v1/token" {
            state.refreshRequestCount += 1
            if state.refreshSucceeds && !state.failRefreshToken {
                result = ["access_token":"token-a","refresh_token":"next-refresh","expires_in":3600,
                          "user":["id":Self.owner.uuidString]]
            } else { status = state.failRefreshToken ? 400 : 500 }
        }
        else if path == "/auth/v1/logout" {
            let scope = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
                .queryItems?.first(where: { $0.name == "scope" })?.value
            state.logoutScopes.append(scope)
            status = state.failLogout ? 503 : 204
            bytes = Data()
        }
        else if path.hasSuffix("/rpc/oi_request_card") {
            state.cardSendPayloads.append(body.compactMapValues { $0 as? String })
            status = request.httpMethod == "POST" && request.value(forHTTPHeaderField: "Authorization") != nil ? 200 : 401
            result = state.cardSendResponse
        }
        else if path.hasSuffix("/rpc/oi_resolve_card_request") || path.hasSuffix("/rpc/oi_card_requests") { status = 404 }
        else if path == "/functions/v1/account-merge", body["action"] as? String == "confirm" {
            state.mergeConfirmCount += 1
            state.canonicalAccountID = rawOwner
            result = ["account_id":rawOwner.uuidString,"already_merged":false]
        }
        else if path.contains("/object/authenticated/") {
            let key = path.replacingOccurrences(of: "/storage/v1/object/authenticated/", with: "")
            bytes = state.uploads[key]; if bytes == nil { status = 404 }
            if state.revokeOnDocumentRead { state.isOperator = false }
        } else if path == "/functions/v1/delete-account" {
            if body["account_id"] as? String == Self.owner.uuidString,
               body["proof"] as? String == "token-a", body["consent"] as? Bool == true {
                result = ["deleted": true, "apple_revocation_required": false, "deleted_member_ids": [Self.owner.uuidString]]
            } else { status = 403 }
        } else if path == "/functions/v1/analyze-evidence" {
            state.analysisBodies.append(body)
            status = state.analysisStatus
            if status == 200 { result = state.analysisResult }
            else { result = ["error": state.analysisError] }
            if state.changeEvidenceAfterAnalysis { state.evidence?["submitted_at"] = "2026-11-04T03:00:00Z" }
            if state.revokeAfterAnalysis { state.isOperator = false }
        } else if path.contains("/storage/v1/object/") {
            let key = path.replacingOccurrences(of: "/storage/v1/object/", with: "")
            if state.uploads[key] != nil { status = 409 }
            else { state.uploads[key] = raw; result = ["Key":key] }
        } else if path.hasSuffix("/rpc/oi_review_evidence") {
            let payload = body["p_payload"] as? [String: Any] ?? [:]
            let wanted = payload["status"] as? String ?? ""
            state.evidenceReviewCount += 1
            if state.evidenceRPCMissing { status = 404 }
            else if !state.isOperator { status = 403 }
            else if state.evidence?["status"] as? String != payload["expected_status"] as? String ||
                state.evidence?["object_path"] as? String != payload["expected_object_path"] as? String ||
                state.evidence?["submitted_at"] as? String != payload["expected_submitted_at"] as? String ||
                state.evidence?["reviewed_at"] as? String != payload["expected_reviewed_at"] as? String { status = 409 }
            else {
                state.evidence?["status"] = wanted
                state.evidence?["review_note"] = payload["review_note"]
                state.evidence?["reviewed_at"] = "2026-11-04T02:00:00Z"
                state.evidence?["reviewer_id"] = owner.uuidString
                if wanted == "revoked", state.story?["grant_id"] as? String == Self.grant.uuidString {
                    state.story?["status"] = "hidden"
                }
                result = state.evidence ?? [:]
                if state.failAfterReview { state.failReads = true }
                if state.loseReviewResponse { status = 503; state.loseReviewResponse = false }
            }
        } else if path.hasSuffix("/rpc/oi_mutate") {
            let payload = body["p_payload"] as? [String:Any] ?? [:]
            let action = body["p_action"] as? String ?? ""
            if action == "save_story" {
                var story = payload
                story["user_id"] = owner.uuidString
                story["status"] = "draft"
                story["revision"] = (payload["revision"] as? Int ?? 0)+1
                story["created_at"] = "2026-10-28T00:00:00Z"
                state.story = story; result = story
            } else if action == "attach_media" {
                state.paths = payload["paths"] as? [String] ?? []
                let nextRevision = (state.story?["revision"] as? Int ?? 0)+1
                state.story?["revision"] = nextRevision
                result = state.story ?? [:]
            } else if action == "submit_story" {
                state.submittedTitle = state.story?["title"] as? String
                state.story?["status"] = "pending"
                let nextRevision = (state.story?["revision"] as? Int ?? 0)+1
                state.story?["revision"] = nextRevision
                result = state.story ?? [:]
            } else if action == "review_story" {
                state.reviewCount += 1
                let wanted = payload["status"] as? String ?? ""
                if !state.isOperator { status = 403 }
                else if state.story?["revision"] as? Int != payload["revision"] as? Int { status = 409 }
                else if !["published", "hidden"].contains(wanted) { status = 400 }
                else {
                    state.story?["status"] = wanted
                    let nextRevision = (state.story?["revision"] as? Int ?? 0) + 1
                    state.story?["revision"] = nextRevision
                    result = state.story ?? [:]
                    if state.failAfterReview { state.failReads = true }
                    if state.loseReviewResponse { status = 503; state.loseReviewResponse = false }
                }
            } else if action == "start_evidence" {
                let id = payload["id"] as? String ?? ""
                state.requestIDs.insert(id)
                if state.evidence == nil {
                    state.evidence = ["id":id,"user_id":owner.uuidString,"storage_owner_id":owner.uuidString,"status":"draft"]
                }
                result = state.evidence ?? [:]
            } else if action == "submit_evidence" {
                state.evidence?["status"] = "pending"; state.evidence?["object_path"] = payload["object_path"]
                result = state.evidence ?? [:]
                if state.loseEvidenceResponse { status = 503; state.loseEvidenceResponse = false }
            } else { result = ["id":payload["id"] ?? ""] }
        } else if path.hasSuffix("/rpc/oi_operator_audit") {
            state.auditBodies.append(body); status = state.auditStatus
            if !state.isOperator { status = 403 }
            let parser = ISO8601DateFormatter()
            func date(_ value: String?) -> Date? {
                guard let value else { return nil }
                parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = parser.date(from: value) { return date }
                parser.formatOptions = [.withInternetDateTime]
                return parser.date(from: value)
            }
            let from = date(body["p_from"] as? String) ?? .distantPast
            let until = date(body["p_until"] as? String) ?? .distantFuture
            let cursorAt = date(body["p_cursor_at"] as? String)
            let cursorID = Int64(body["p_cursor_id"] as? String ?? "") ?? .max
            let category = body["p_category"] as? String ?? "all"
            let limit = body["p_limit"] as? Int ?? 50
            let matches = state.auditRecords.filter { row in
                guard let created = date(row["created_at"] as? String) else { return false }
                let id = Int64(row["id"] as? String ?? "") ?? 0
                let action = row["action"] as? String ?? ""
                let categoryMatches = category == "all" || category == "evidence" && action.hasPrefix("review_evidence:") ||
                    category == "stories" && action == "review_story" || category == "accounts" && action == "merge_accounts"
                let before = cursorAt.map { created < $0 || created == $0 && id < cursorID } ?? true
                return created >= from && created < until && categoryMatches && before
            }.sorted {
                (date($0["created_at"] as? String) ?? .distantPast, Int64($0["id"] as? String ?? "") ?? 0) >
                (date($1["created_at"] as? String) ?? .distantPast, Int64($1["id"] as? String ?? "") ?? 0)
            }
            let page = Array(matches.prefix(limit))
            var cursor: Any = NSNull()
            if matches.count > limit, let last = page.last { cursor = ["id": last["id"] ?? "", "created_at": last["created_at"] ?? ""] }
            result = ["records": page, "next_cursor": cursor]
        } else if path.hasSuffix("/rpc/oi_capabilities") {
            if state.failCapabilities { status = 503 }
            var capabilities: [String:Any] = ["operator":state.isOperator,"coins_enabled":false]
            if let enabled = state.unapprovedDraftsEnabled { capabilities["unapproved_drafts_enabled"] = enabled }
            if let canonical = state.canonicalAccountID {
                capabilities["account_id"] = canonical.uuidString
                capabilities["account_merge_enabled"] = true
                capabilities["account_member_ids"] = [Self.owner.uuidString,Self.other.uuidString]
            }
            if state.schoolProfileEnabled { capabilities["school_profile_enabled"] = true }
            if state.farmerOutfitEnabled { capabilities["farmer_outfit_enabled"] = true }
            capabilities["account_providers"] = ["apple"]
            result = capabilities
        }
        else if path.hasSuffix("/rpc/oi_farmer_outfit") || path.hasSuffix("/rpc/oi_save_farmer_outfit") {
            let writing = path.hasSuffix("/rpc/oi_save_farmer_outfit")
            if writing {
                state.farmerOutfitWrites += 1
                state.farmerOutfitPayloads.append(body)
                if state.failFarmerOutfitWrite { status = 503 }
                else if owner == Self.owner { state.farmerOutfit = body["p_outfit"] as? [String: Any] }
                else { state.otherFarmerOutfit = body["p_outfit"] as? [String: Any] }
            } else { state.farmerOutfitReads += 1 }
            let receiptOwner = state.mismatchedFarmerOutfitReceipt ? Self.other : owner
            var receipt: [String: Any] = ["account_id": receiptOwner.uuidString]
            if !state.omitsFarmerOutfitReceiptField {
                receipt["outfit"] = (owner == Self.owner ? state.farmerOutfit : state.otherFarmerOutfit) as Any? ?? NSNull()
            }
            result = receipt
        }
        else if path.hasSuffix("/rpc/oi_school_profile") || path.hasSuffix("/rpc/oi_update_school_profile") {
            let writing = path.hasSuffix("/rpc/oi_update_school_profile")
            if writing {
                state.schoolProfileWrites += 1
                if state.failSchoolProfileWrite { status = 503 }
                else {
                    state.schoolID = body["p_school_id"] as? String
                    state.schoolMetadataSchoolID = state.schoolID
                    state.schoolAdmissionYear = body["p_admission_year"] as? Int
                    state.schoolDepartment = body["p_department"] as? String
                }
            } else { state.schoolProfileReads += 1 }
            let receiptOwner = writing && state.mismatchedSchoolProfileReceipt ? Self.other : owner
            result = ["id":receiptOwner.uuidString,"nickname":state.nickname,"farmer_asset":"OiFarmer",
                "farm_name":owner == Self.owner ? state.farmName as Any? ?? NSNull() : state.otherFarmName,
                "school_id":state.schoolID as Any? ?? NSNull(),
                "public_name":state.publicName, "department":state.department, "admission_year":state.admissionYear,
                "school_admission_year":owner == Self.owner && state.schoolID == state.schoolMetadataSchoolID ? state.schoolAdmissionYear as Any? ?? NSNull() : NSNull(),
                "school_department":owner == Self.owner && state.schoolID == state.schoolMetadataSchoolID ? state.schoolDepartment as Any? ?? NSNull() : NSNull()]
        }
        else if path.hasSuffix("/rpc/oi_collection_metrics") { result = [] }
        else if path.hasSuffix("/oi_stories") {
            if state.failReads { status = 503 }
            else if let story = state.story, state.isOperator || story["user_id"] as? String == owner.uuidString {
                let query = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems ?? []
                let id = query.first { $0.name == "id" }?.value
                let filter = query.first { $0.name == "status" }?.value
                let matchesID = id == nil || id == "eq.\(story["id"] as? String ?? "")"
                let matchesState = state.ignoreStoryStatusFilter || filter == nil || filter == "eq.\(story["status"] as? String ?? "")" ||
                    (filter == "in.(pending,published,hidden)" && ["pending", "published", "hidden"].contains(story["status"] as? String ?? ""))
                if matchesID && matchesState { result = [story] }
            }
        } else if path.hasSuffix("/oi_schools") {
            result = [["id":"postech","name":"POSTECH"]] + (state.includesSecondSchool ? [["id":"other","name":"Other School"]] : [])
        }
        else if path.hasSuffix("/oi_regions") { result = [["id":"pond","school_id":"postech","name":"Pond"]] }
        else if path.hasSuffix("/oi_assets") { result = [["id":"OiCats","kind":"cucumber","name":"Cats"]] }
        else if path.hasSuffix("/oi_profiles") {
            if request.httpMethod == "PATCH" {
                state.profilePatchBodies.append(body)
                if let farm = body["farm_name"] as? String {
                    if state.failFarmWrite { status = 503 }
                    else if owner == Self.owner { state.farmName = farm }
                    else { state.otherFarmName = farm }
                }
                state.nickname = body["nickname"] as? String ?? state.nickname
                state.publicName = body["public_name"] as? String ?? state.publicName
                state.department = body["department"] as? String ?? state.department
                state.admissionYear = body["admission_year"] as? String ?? state.admissionYear
                if let school = body["school_id"] { state.schoolID = school as? String }
            }
            let receiptOwner = body["farm_name"] != nil && state.mismatchedFarmReceipt ? Self.other : owner
            result = [["id":receiptOwner.uuidString,"nickname":owner == Self.owner ? state.nickname : "Owner B",
                "farmer_asset":"OiFarmer", "school_id":state.schoolID as Any? ?? NSNull(),
                "farm_name":owner == Self.owner ? state.farmName as Any? ?? NSNull() : state.otherFarmName,
                "public_name":state.publicName, "department":state.department, "admission_year":state.admissionYear]]
        } else if path.hasSuffix("/oi_story_media") {
            result = state.paths.enumerated().map { position, path in
                ["id":UUID().uuidString,"story_id":state.story?["id"] ?? "","object_path":path,"position":position]
            }
        } else if path.hasSuffix("/oi_evidence_history") {
            if state.failHistoryReads { status = 503 }
            else {
                let query = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems ?? []
                func value(_ name: String) -> String? { query.first { $0.name == name }?.value }
                let filtered = state.history.filter { row in
                    (value("id") == nil || value("id") == "eq.\(row["id"] as? String ?? "")") &&
                    (value("request_id") == nil || value("request_id") == "eq.\(row["request_id"] as? String ?? "")")
                }.sorted { ($0["recorded_at"] as? String ?? "", $0["id"] as? String ?? "") > ($1["recorded_at"] as? String ?? "", $1["id"] as? String ?? "") }
                result = Array(filtered.dropFirst(Int(value("offset") ?? "0") ?? 0).prefix(Int(value("limit") ?? "200") ?? 200))
            }
        } else if path.hasSuffix("/oi_evidence_requests"), let evidence = state.evidence {
            if state.failReads { status = 503 }
            else {
                let query = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems ?? []
                let id = query.first { $0.name == "id" }?.value
                if id == nil || id == "eq.\(evidence["id"] as? String ?? "")" { result = [evidence] }
            }
        }
        else if path.hasSuffix("/oi_writing_grants") {
            if let url = request.url,
               let owner = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "user_id" })?.value {
                state.grantOwnerQueries.append(owner)
            }
            result = state.hasWritingGrant ? [["id":Self.grant.uuidString,"story_limit":5]] : []
            if let url = request.url,
               URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains(where: { $0.name == "evidence_id" }) == true {
                let evidenceStatus = state.evidence?["status"] as? String
                result = evidenceStatus == "approved" || evidenceStatus == "revoked"
                    ? [["id":Self.grant.uuidString,"story_limit":3,"revoked_at":evidenceStatus == "revoked" ? "2026-11-04T02:00:00Z" as Any : NSNull()]] : []
            }
        }
        let data = bytes ?? ((try? JSONSerialization.data(withJSONObject: result)) ?? Data())
        if (path.hasSuffix("/oi_stories") && owner == Self.owner && state.holdOwnerRead)
            || (path.hasSuffix("/rpc/oi_mutate") && body["p_action"] as? String == "review_story" && state.holdReviewResponse)
            || (path.hasSuffix("/rpc/oi_review_evidence") && state.holdReviewResponse)
            || (path.hasSuffix("/oi_evidence_requests") && state.holdEvidenceRead)
            || (path.hasSuffix("/oi_evidence_history") && state.holdHistoryRead)
            || (path == "/functions/v1/analyze-evidence" && state.holdAnalysis)
            || (path.hasSuffix("/rpc/oi_operator_audit") && state.holdAuditRead)
            || (path.hasSuffix("/rpc/oi_capabilities") && state.holdPostMergeRead && state.mergeConfirmCount > 0)
            || (path.hasSuffix("/rpc/oi_request_card") && state.holdCardSend)
            || (path.hasSuffix("/oi_profiles") && body["farm_name"] != nil && state.holdFarmWrite)
            || (path.hasSuffix("/rpc/oi_save_farmer_outfit") && state.holdFarmerOutfitWrite) {
            state.held = (client,data)
            let notify = state.didHold
            lock.unlock(); notify?(); return
        }
        lock.unlock()
        client.respond(status, data)
    }
}

final class OiMemorySession: OiSessionStorage {
    var value: OiSession?
    init(owner: UUID = OiTestBackend.owner, expired: Bool = false) {
        value = OiSession(accessToken: owner == OiTestBackend.owner ? "token-a" : "token-b", refreshToken: "test-refresh",
            expiresIn: 3600, expiresAt: expired ? 0 : Date().timeIntervalSince1970+3600, user: OiAccount(id: owner, email: nil))
    }
    func read() throws -> OiSession? { value }
    func write(_ session: OiSession?) throws { value = session }
}

@MainActor
final class OiControlledAuthentication: OiAuthenticating {
    private(set) var requests = 0
    private var continuation: CheckedContinuation<OiSession, Error>?
    var isPending: Bool { continuation != nil }

    func signIn(api: OiServiceAPI) async throws -> OiSession {
        requests += 1
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func complete(_ result: Result<OiSession, Error>) {
        let pending = continuation
        continuation = nil
        pending?.resume(with: result)
    }
}

@MainActor private struct OiDeletionAuthentication: OiAuthenticating {
    func signIn(api: OiServiceAPI) async throws -> OiSession {
        try XCTUnwrap(OiMemorySession().read())
    }
}

final class OiRemoteStoreTests: XCTestCase {
    @MainActor func testConfirmedDeletionPurgesOnlyDeletedAccountLocalDrafts() async throws {
        let (store, backend, vault, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        let drafts = OiDraftVault(directory: directory)
        let ours = OiLocalDraft(draft: draft(), version: 1)
        let theirs = OiLocalDraft(draft: draft(), version: 1)
        try await drafts.save(ours, owner: OiTestBackend.owner)
        try await drafts.save(theirs, owner: OiTestBackend.other)
        await store.start()
        let receipt = try await store.deleteAccount(using: OiDeletionAuthentication())
        XCTAssertTrue(receipt.deleted)
        XCTAssertNil(store.account)
        XCTAssertNil(vault.value)
        let removed = try await drafts.load(owner: OiTestBackend.owner, id: ours.id)
        let preserved = try await drafts.load(owner: OiTestBackend.other, id: theirs.id)
        XCTAssertNil(removed)
        XCTAssertNotNil(preserved)
    }

    private func auditFixture(_ id: Int) -> [String: Any] {
        ["id": String(9_007_199_254_740_990 + id), "actor_id": OiTestBackend.owner.uuidString,
         "action": id % 2 == 0 ? "review_evidence:approved" : "review_story",
         "target_id": OiTestBackend.grant.uuidString, "created_at": "2026-11-04T00:00:00Z"]
    }
    @MainActor private func auditQuery(_ category: OiAuditCategory = .all) throws -> OiAuditQuery {
        let parser = ISO8601DateFormatter()
        return try OiAuditQuery(from: XCTUnwrap(parser.date(from: "2026-11-03T00:00:00Z")),
                               until: XCTUnwrap(parser.date(from: "2026-11-05T00:00:00Z")), category: category)
    }

    @MainActor func testOperatorAuditPagesKeepCursorAndApplyCategory() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.isOperator = true; $0.auditRecords = (1...52).map(auditFixture) }
        await store.start()
        let model = OiOperatorAuditModel()
        await model.reload(try auditQuery(), using: store)
        XCTAssertEqual(model.records.count, 50); XCTAssertNotNil(model.nextCursor)
        XCTAssertEqual(model.records.first?.id, "9007199254741042")
        XCTAssertEqual(backend.snapshot().auditBodies.count, 1, "Do not automatically fetch every page")
        backend.configure { $0.auditRecords.append(auditFixture(53)) }
        await model.loadMore(using: store)
        XCTAssertEqual(model.records.count, 52); XCTAssertNil(model.nextCursor)
        XCTAssertEqual(Set(model.records.map(\.id)).count, 52)
        let body = try XCTUnwrap(backend.snapshot().auditBodies.last)
        XCTAssertEqual(body["p_limit"] as? Int, 50)
        XCTAssertNotNil(body["p_cursor_at"]); XCTAssertNotNil(body["p_cursor_id"] as? String)
        await model.reload(try auditQuery(.evidence), using: store)
        XCTAssertEqual(model.records.count, 26)
        XCTAssertTrue(model.records.allSatisfy { $0.action == "review_evidence:approved" })
        XCTAssertNil(backend.snapshot().auditBodies.last?["p_cursor_id"])
        XCTAssertNil(model.error)
    }

    @MainActor func testOperatorAuditPageFailureRetryMissingRPCAndRights() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.isOperator = true; $0.auditRecords = (1...52).map(auditFixture) }
        await store.start()
        let model = OiOperatorAuditModel()
        await model.reload(try auditQuery(), using: store)
        backend.configure { $0.auditStatus = 503 }
        await model.loadMore(using: store)
        XCTAssertEqual(model.records.count, 50); XCTAssertNotNil(model.nextCursor); XCTAssertNotNil(model.error)
        backend.configure { $0.auditStatus = 200 }
        await model.loadMore(using: store)
        XCTAssertEqual(model.records.count, 52); XCTAssertNil(model.error)
        backend.configure { $0.auditStatus = 404 }
        await model.reload(try auditQuery(), using: store)
        XCTAssertTrue(model.records.isEmpty); XCTAssertTrue(model.error?.contains("배포") == true)
        backend.configure { $0.auditStatus = 200; $0.isOperator = false }
        let count = backend.snapshot().auditBodies.count
        await model.reload(try auditQuery(), using: store)
        XCTAssertTrue(model.records.isEmpty); XCTAssertFalse(model.hasLoaded)
        XCTAssertEqual(backend.snapshot().auditBodies.count, count)
    }

    @MainActor func testOperatorAuditOldAccountResponseIsDiscarded() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.isOperator = true; $0.auditRecords = [auditFixture(1)] }
        await store.start()
        let model = OiOperatorAuditModel()
        let query = try auditQuery()
        let held = expectation(description: "audit pending")
        backend.configure { $0.holdAuditRead = true; $0.didHold = { held.fulfill() } }
        let read = Task { await model.reload(query, using: store) }
        await fulfillment(of: [held], timeout: 5)
        model.invalidate()
        await store.signOut()
        backend.releaseHeldRead()
        await read.value
        XCTAssertTrue(model.records.isEmpty); XCTAssertFalse(model.hasLoaded); XCTAssertNil(model.error)
    }

    @MainActor func testOperatorAuditDuplicatePageLoadIsBlocked() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.isOperator = true; $0.auditRecords = (1...52).map(auditFixture) }
        await store.start()
        let model = OiOperatorAuditModel()
        await model.reload(try auditQuery(), using: store)
        let held = expectation(description: "next audit page pending")
        backend.configure { $0.holdAuditRead = true; $0.didHold = { held.fulfill() } }
        let first = Task { await model.loadMore(using: store) }
        await fulfillment(of: [held], timeout: 5)
        await model.loadMore(using: store)
        XCTAssertEqual(backend.snapshot().auditBodies.count, 2)
        backend.releaseHeldRead()
        await first.value
        XCTAssertEqual(model.records.count, 52)
    }

    @MainActor func testOperatorAuditNewQueryRejectsPreviousQueryResponse() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.isOperator = true; $0.auditRecords = [auditFixture(2)] }
        await store.start()
        let model = OiOperatorAuditModel()
        let query = try auditQuery()
        let held = expectation(description: "old audit query pending")
        backend.configure { $0.holdAuditRead = true; $0.didHold = { held.fulfill() } }
        let old = Task { await model.reload(query, using: store) }
        await fulfillment(of: [held], timeout: 5)
        backend.configure { $0.holdAuditRead = false; $0.auditRecords = [auditFixture(3)] }
        await model.reload(try auditQuery(.stories), using: store)
        backend.releaseHeldRead()
        await old.value
        XCTAssertEqual(model.query?.category, .stories)
        XCTAssertEqual(model.records.map(\.action), ["review_story"])
    }

    @MainActor func testOperatorAuditRejectsInvalidRangesAndPagesWithoutInventingDecision() throws {
        let query = try auditQuery()
        XCTAssertThrowsError(try OiAuditQuery(from: query.from, until: query.from, category: .all))
        XCTAssertThrowsError(try OiAuditQuery(from: query.from, until: query.from.addingTimeInterval(32 * 86400), category: .all))
        XCTAssertNoThrow(try OiAuditQuery(from: query.from, until: query.from.addingTimeInterval(31 * 86400), category: .all))
        let record = OiAuditRecord(id: "9007199254741042", actorId: OiTestBackend.owner, action: "review_story",
                                   targetId: OiTestBackend.grant, createdAt: "2026-11-04T00:00:00Z")
        XCTAssertEqual(record.title, "이야기 공개 상태 검토")
        XCTAssertNoThrow(try OiAuditPage(records: [record], nextCursor: nil).validate(query: query, after: nil))
        XCTAssertThrowsError(try OiAuditPage(records: [record, record], nextCursor: nil).validate(query: query, after: nil))
        let cursor = OiAuditCursor(createdAt: record.createdAt, id: record.id)
        XCTAssertThrowsError(try OiAuditPage(records: [record], nextCursor: cursor).validate(query: query, after: nil))
        let unknown = OiAuditRecord(id: "1", actorId: OiTestBackend.owner, action: "future_action", targetId: OiTestBackend.grant, createdAt: record.createdAt)
        XCTAssertEqual(unknown.title, "기타 처리 (future_action)")
        XCTAssertEqual(unknown.targetLabel, "대상 ID")
    }

    @MainActor func testOperatorAuditScreenLayouts() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.isOperator = true }
        await store.start()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        for name in ["records", "empty", "error", "accessibility"] {
            backend.configure { $0.auditRecords = name == "empty" ? [] : [auditFixture(1), auditFixture(2)]; $0.auditStatus = name == "error" ? 404 : 200 }
            let window = UIWindow(windowScene: scene)
            let controller = UIHostingController(rootView: NavigationStack { OiOperatorAuditView(remote: store) }
                .environment(\.scenePhase, .active).environment(\.locale, Locale(identifier: "ko_KR"))
                .environment(\.dynamicTypeSize, name == "accessibility" ? .accessibility5 : .large)
                .preferredColorScheme(.light))
            window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
            window.rootViewController = controller; window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(400))
            controller.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
            }
            let attachment = XCTAttachment(image: image); attachment.name = "operator-audit-\(name)"; attachment.lifetime = .keepAlways; add(attachment)
            window.isHidden = true; window.rootViewController = nil
        }
    }

    private func historyFixture() -> [String: Any] {
        ["id": UUID().uuidString, "request_id": OiTestBackend.grant.uuidString,
         "status": "changes_requested", "object_path": "\(OiTestBackend.owner.uuidString.lowercased())/\(OiTestBackend.grant.uuidString.lowercased())/previous.png",
         "review_note": "가상 증빙을 보완해 주세요", "reviewer_id": OiTestBackend.other.uuidString,
         "recorded_at": "2026-11-04T00:00:00Z"]
    }

    private func analysisFixture(verdict: String = "inconclusive") -> [String: Any] {
        ["evidence_id": OiTestBackend.grant.uuidString.lowercased(), "submitted_at": "2026-11-04T01:00:00.000Z",
         "sha256": String(repeating: "a", count: 64), "analyzed_at": "2026-11-04T02:00:00Z",
         "model": "synthetic-model", "prompt_version": "evidence-visual-review-v1",
         "human_review_required": true, "authenticity_verified": false,
         "notice": "AI 참고 자료이며 원본 진위·실제 납입 확인을 보증하지 않습니다.",
         "assessment": ["verdict": verdict, "readability": verdict == "inconclusive" ? "limited" : "readable",
                        "findings": verdict == "suspicious" ? [["category": "visual_edit", "location": "가상 금액 영역", "observation": "가상 문자의 경계가 다름"]] : [],
                        "limitations": ["가상 자료만 분석한 결과입니다."], "manual_checks": ["원본과 기부 내역을 직접 확인하세요."]]]
    }

    @MainActor func testOperatorEvidenceHistoryPaginationFiltersAndFailures() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        var rows = (0..<205).map { _ in historyFixture() }
        var unrelated = historyFixture(); unrelated["request_id"] = UUID().uuidString; rows.append(unrelated)
        backend.configure { $0.isOperator = true; $0.history = rows }
        await store.start()
        let model = OiOperatorEvidenceHistoryModel()
        await model.load(OiTestBackend.grant, using: store)
        XCTAssertEqual(model.rows.count, 205); XCTAssertTrue(model.hasLoaded)
        XCTAssertTrue(model.rows.allSatisfy { $0.requestId == OiTestBackend.grant })
        XCTAssertEqual(model.rows.first?.status, "changes_requested")
        backend.configure { $0.history = [] }
        await model.load(OiTestBackend.grant, using: store)
        XCTAssertTrue(model.hasLoaded); XCTAssertTrue(model.rows.isEmpty)
        backend.configure { $0.failHistoryReads = true }
        await model.load(OiTestBackend.grant, using: store)
        XCTAssertFalse(model.hasLoaded); XCTAssertNotNil(model.error)
        backend.configure { $0.failHistoryReads = false; $0.isOperator = false }
        await model.load(OiTestBackend.grant, using: store)
        XCTAssertTrue(model.rows.isEmpty); XCTAssertNotNil(model.error)
    }

    @MainActor func testOperatorEvidenceHistoryOpensArchivedOriginalAndRechecksRights() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        let history = historyFixture()
        let path = try XCTUnwrap(history["object_path"] as? String)
        let bytes = Data([0xff, 0xd8, 0xff, 0x00])
        backend.configure {
            $0.isOperator = true; $0.evidence = evidenceFixture(); $0.history = [history]
            $0.uploads["oi-evidence/\(path)"] = bytes
        }
        await store.start()
        let entries = try await store.operatorEvidenceHistory(OiTestBackend.grant)
        let entry = try XCTUnwrap(entries.first)
        let document = try await store.operatorEvidenceHistoryDocument(entry)
        XCTAssertEqual(document.data, bytes, "Archived path, rather than current submission, must be opened")
        backend.configure { $0.history[0]["object_path"] = "changed.png" }
        do { _ = try await store.operatorEvidenceHistoryDocument(entry); XCTFail("Changed history must be rejected") }
        catch OiServiceError.conflict {}
        backend.configure { $0.history = [history]; $0.revokeOnDocumentRead = true }
        do { _ = try await store.operatorEvidenceHistoryDocument(entry); XCTFail("Rights must be rechecked before return") }
        catch OiOperatorStoryError.accessDenied {}
    }

    @MainActor func testOperatorEvidenceAnalysisUsesIDOnlyAndNeverApproves() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.isOperator = true; $0.evidence = evidenceFixture() }
        await store.start()
        let row = try await store.operatorEvidence(OiTestBackend.grant).evidence
        XCTAssertTrue(backend.snapshot().analysisBodies.isEmpty)
        let model = OiOperatorEvidenceAnalysisModel()
        for verdict in ["suspicious", "no_obvious_signs", "inconclusive"] {
            backend.configure { $0.analysisResult = analysisFixture(verdict: verdict) }
            await model.analyze(row, using: store)
            XCTAssertEqual(model.result?.assessment.verdict.rawValue, verdict)
            XCTAssertNil(model.error)
        }
        let bodies = backend.snapshot().analysisBodies
        XCTAssertEqual(bodies.count, 3)
        XCTAssertTrue(bodies.allSatisfy { Set($0.keys) == ["evidence_id"] && $0["evidence_id"] as? String == row.id.uuidString.lowercased() })
        XCTAssertEqual(backend.snapshot().evidence?["status"] as? String, "pending")
        XCTAssertEqual(backend.snapshot().evidenceReviewCount, 0)
        XCTAssertEqual(backend.snapshot().reviewCount, 0)
        backend.configure { $0.evidence?["submitted_at"] = "2026-11-04T03:00:00Z" }
        await model.revalidate(row, using: store)
        XCTAssertNil(model.result); XCTAssertNotNil(model.error)
    }

    @MainActor func testOperatorEvidenceAnalysisErrorsAreDistinctAndDoNotRetry() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.isOperator = true; $0.evidence = evidenceFixture() }
        await store.start()
        let row = try await store.operatorEvidence(OiTestBackend.grant).evidence
        let model = OiOperatorEvidenceAnalysisModel()
        for (status, code, expected) in [(404, "NOT_FOUND", "배포"), (503, "analysis_not_configured", "설정"),
                                         (429, "analysis_busy", "한도"), (504, "analysis_timeout", "초과"),
                                         (422, "analysis_refused", "자료"), (502, "invalid_analysis_response", "완료하지 못"),
                                         (409, "evidence_changed", "새로고침")] {
            backend.configure { $0.analysisStatus = status; $0.analysisError = code }
            let count = backend.snapshot().analysisBodies.count
            await model.analyze(row, using: store)
            XCTAssertNil(model.result); XCTAssertTrue(model.error?.contains(expected) == true, model.error ?? "No error")
            XCTAssertEqual(backend.snapshot().analysisBodies.count, count + 1)
        }
    }

    @MainActor func testOperatorEvidenceAnalysisRejectsStaleAndRevokedResults() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.isOperator = true; $0.evidence = evidenceFixture(); $0.analysisResult = analysisFixture() }
        await store.start()
        let row = try await store.operatorEvidence(OiTestBackend.grant).evidence
        let model = OiOperatorEvidenceAnalysisModel()
        backend.configure { $0.changeEvidenceAfterAnalysis = true }
        await model.analyze(row, using: store)
        XCTAssertNil(model.result); XCTAssertNotNil(model.error)
        backend.configure { $0.changeEvidenceAfterAnalysis = false; $0.evidence = evidenceFixture(); $0.revokeAfterAnalysis = true }
        await model.analyze(row, using: store)
        XCTAssertNil(model.result); XCTAssertFalse(store.isOperator)
        XCTAssertEqual(backend.snapshot().evidenceReviewCount, 0)
    }

    @MainActor func testOperatorEvidenceAnalysisRejectsUnsafeOrMalformedContract() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.isOperator = true; $0.evidence = evidenceFixture() }
        await store.start()
        let row = try await store.operatorEvidence(OiTestBackend.grant).evidence
        let model = OiOperatorEvidenceAnalysisModel()
        for key in ["authenticity_verified", "human_review_required", "evidence_id", "sha256", "assessment"] {
            var fixture = analysisFixture()
            switch key {
            case "authenticity_verified": fixture[key] = true
            case "human_review_required": fixture[key] = false
            case "evidence_id": fixture[key] = UUID().uuidString
            default: fixture[key] = "invalid"
            }
            backend.configure { $0.analysisResult = fixture }
            await model.analyze(row, using: store)
            XCTAssertNil(model.result); XCTAssertNotNil(model.error)
        }
    }

    @MainActor func testOperatorEvidenceAnalysisDuplicateInvalidationAndAccountChange() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.isOperator = true; $0.evidence = evidenceFixture(); $0.analysisResult = analysisFixture() }
        await store.start()
        let row = try await store.operatorEvidence(OiTestBackend.grant).evidence
        let model = OiOperatorEvidenceAnalysisModel()
        let held = expectation(description: "analysis pending")
        backend.configure { $0.holdAnalysis = true; $0.didHold = { held.fulfill() } }
        let first = Task { await model.analyze(row, using: store) }
        await fulfillment(of: [held], timeout: 5)
        await model.analyze(row, using: store)
        XCTAssertEqual(backend.snapshot().analysisBodies.count, 1)
        model.invalidate()
        await store.signOut()
        backend.releaseHeldRead()
        await first.value
        XCTAssertNil(model.result); XCTAssertNil(model.error); XCTAssertFalse(model.isLoading)
    }

    @MainActor func testOperatorEvidenceAnalysisCancellationDoesNotCreateVerdict() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.isOperator = true; $0.evidence = evidenceFixture(); $0.analysisResult = analysisFixture() }
        await store.start()
        let row = try await store.operatorEvidence(OiTestBackend.grant).evidence
        let model = OiOperatorEvidenceAnalysisModel()
        let held = expectation(description: "cancelable analysis")
        backend.configure { $0.holdAnalysis = true; $0.didHold = { held.fulfill() } }
        let request = Task { await model.analyze(row, using: store) }
        await fulfillment(of: [held], timeout: 5)
        request.cancel()
        await request.value
        backend.releaseHeldRead()
        XCTAssertNil(model.result); XCTAssertNil(model.error); XCTAssertFalse(model.isLoading)
        XCTAssertEqual(backend.snapshot().analysisBodies.count, 1)
    }

    @MainActor func testOperatorEvidenceSupplementScreenLayouts() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.isOperator = true; $0.evidence = evidenceFixture(); $0.history = [historyFixture()] }
        await store.start()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        for name in ["history", "history-empty", "history-error", "analysis-suspicious", "analysis-no_obvious_signs", "analysis-inconclusive", "analysis-accessibility"] {
            backend.configure { $0.history = name == "history-empty" ? [] : [historyFixture()]; $0.failHistoryReads = name == "history-error" }
            let view: AnyView
            if name.hasPrefix("history") { view = AnyView(NavigationStack { OiOperatorEvidenceHistoryView(remote: store, evidenceID: OiTestBackend.grant) }) }
            else {
                let verdict = name == "analysis-accessibility" ? "suspicious" : String(name.dropFirst("analysis-".count))
                let result = try decoder.decode(OiEvidenceAnalysis.self, from: JSONSerialization.data(withJSONObject: analysisFixture(verdict: verdict)))
                view = AnyView(NavigationStack { List { Section("AI 참고 분석") { OiEvidenceAnalysisResultView(result: result) } }.navigationTitle("증빙 검토 상세") })
            }
            let window = UIWindow(windowScene: scene)
            let controller = UIHostingController(rootView: view.environment(\.scenePhase, .active)
                .environment(\.locale, Locale(identifier: "ko_KR"))
                .environment(\.dynamicTypeSize, name.hasSuffix("accessibility") ? .accessibility5 : .large)
                .preferredColorScheme(.light))
            window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
            window.rootViewController = controller; window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(400))
            controller.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
            }
            let attachment = XCTAttachment(image: image); attachment.name = "operator-supplement-\(name)"; attachment.lifetime = .keepAlways; add(attachment)
            window.isHidden = true; window.rootViewController = nil
        }
        XCTAssertTrue(backend.snapshot().analysisBodies.isEmpty, "Rendering never automatically calls AI")
    }

    private func evidenceFixture(status: String = "pending") -> [String: Any] {
        ["id": OiTestBackend.grant.uuidString, "user_id": OiTestBackend.owner.uuidString,
         "storage_owner_id": OiTestBackend.owner.uuidString, "status": status,
         "object_path": "\(OiTestBackend.owner.uuidString.lowercased())/\(OiTestBackend.grant.uuidString.lowercased())/synthetic.png",
         "submitted_at": "2026-11-04T01:00:00Z"]
    }

    @MainActor func testOperatorEvidenceListDetailAndAllDecisions() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.isOperator = true; $0.evidence = evidenceFixture() }
        await store.start()
        let list = OiOperatorEvidenceListModel()
        await list.load(using: store)
        XCTAssertEqual(list.filtered.count, 1)
        let model = OiOperatorEvidenceModel()
        for decision in OiEvidenceDecision.allCases {
            backend.configure { $0.evidence = evidenceFixture(status: decision == .revoked ? "approved" : "pending") }
            await model.load(OiTestBackend.grant, using: store)
            let snapshot = try XCTUnwrap(model.detail?.evidence)
            let review = try OiEvidenceReview(snapshot: snapshot, decision: decision, note: "가상 자료 검토 의견", count: "3")
            let result = await model.review(review, using: store)
            let receipt = try XCTUnwrap(result)
            XCTAssertEqual(receipt.status, decision.rawValue)
            XCTAssertNotNil(model.notice)
            XCTAssertTrue(model.requiresReload)
            list.apply(receipt)
            XCTAssertTrue(list.filtered.isEmpty)
            list.filter = OiEvidenceFilter(rawValue: decision.rawValue) ?? .all
            XCTAssertEqual(list.filtered.first?.id, receipt.id)
            list.filter = .pending
        }
        XCTAssertEqual(backend.snapshot().evidenceReviewCount, 4)
    }

    @MainActor func testOperatorEvidenceValidationAndDocumentFormats() throws {
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let row = try decoder.decode(OiEvidence.self, from: JSONSerialization.data(withJSONObject: evidenceFixture()))
        for count in ["", "0", "-1", "1.5", "999999999999", "１２"] {
            XCTAssertThrowsError(try OiEvidenceReview(snapshot: row, decision: .approved, note: "", count: count))
        }
        XCTAssertNoThrow(try OiEvidenceReview(snapshot: row, decision: .approved, note: "", count: "2"))
        for decision in [OiEvidenceDecision.changesRequested, .rejected, .revoked] {
            XCTAssertThrowsError(try OiEvidenceReview(snapshot: row, decision: decision, note: " \n", count: ""))
        }
        XCTAssertThrowsError(try OiEvidenceReview(snapshot: row, decision: .approved, note: String(repeating: "a", count: 2001), count: "1"))
        XCTAssertThrowsError(try OiEvidenceDocument(data: Data("<html>error</html>".utf8)))
        XCTAssertThrowsError(try OiEvidenceDocument(data: Data(repeating: 0, count: OiEvidenceDocument.maximumBytes + 1)))
        XCTAssertEqual(try OiEvidenceDocument(data: Data("%PDF-synthetic".utf8)).kind, .pdf)
    }

    @MainActor func testOperatorEvidencePrivateOriginalAndStaleSnapshot() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        let fixture = evidenceFixture()
        let path = try XCTUnwrap(fixture["object_path"] as? String)
        let png = try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { context in
            UIColor.green.setFill(); context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        }.pngData())
        backend.configure { $0.isOperator = true; $0.evidence = fixture; $0.uploads["oi-evidence/\(path)"] = png }
        await store.start()
        let row = try await store.operatorEvidence(OiTestBackend.grant).evidence
        let document = try await store.operatorEvidenceDocument(row)
        XCTAssertEqual(document.data, png)
        backend.configure { $0.evidence?["submitted_at"] = "2026-11-04T01:01:00Z" }
        do { _ = try await store.operatorEvidenceDocument(row); XCTFail("Stale originals must not open") }
        catch OiServiceError.conflict {}
        let model = OiOperatorEvidenceModel()
        await model.load(row.id, using: store)
        let current = try XCTUnwrap(model.detail?.evidence)
        backend.configure { $0.evidence?["submitted_at"] = "2026-11-04T01:02:00Z" }
        let review = try OiEvidenceReview(snapshot: current, decision: .approved, note: "", count: "2")
        let receipt = await model.review(review, using: store)
        XCTAssertNil(receipt); XCTAssertTrue(model.requiresReload); XCTAssertNotNil(model.error)
        XCTAssertEqual(backend.snapshot().evidence?["status"] as? String, "pending")
    }

    @MainActor func testOperatorEvidenceResponseLossAndMissingRPCNeverReplay() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.isOperator = true; $0.evidence = evidenceFixture() }
        await store.start()
        let model = OiOperatorEvidenceModel()
        for missing in [true, false] {
            backend.configure { $0.evidence = evidenceFixture(); $0.evidenceRPCMissing = missing; $0.loseReviewResponse = !missing }
            await model.load(OiTestBackend.grant, using: store)
            let row = try XCTUnwrap(model.detail?.evidence)
            let review = try OiEvidenceReview(snapshot: row, decision: .approved, note: "", count: "2")
            let result = await model.review(review, using: store)
            XCTAssertNil(result); XCTAssertTrue(model.requiresReload)
            let count = backend.snapshot().evidenceReviewCount
            let second = await model.review(review, using: store)
            XCTAssertNil(second); XCTAssertEqual(backend.snapshot().evidenceReviewCount, count)
            if missing { XCTAssertTrue(model.error?.contains("아직 준비") == true) }
            else {
                await model.load(row.id, using: store)
                XCTAssertEqual(model.detail?.evidence.status, "approved")
            }
        }
    }

    @MainActor func testOperatorEvidenceReceiptSurvivesRefreshFailureAndRightsAreChecked() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.isOperator = true; $0.evidence = evidenceFixture(status: "approved") }
        await store.start()
        let savedResult = await store.save(draft(title: "철회 시 비공개 전환할 가상 이야기"))
        let saved = try XCTUnwrap(savedResult)
        let pendingResult = await store.submitStory(saved)
        let pending = try XCTUnwrap(pendingResult)
        _ = try await store.reviewOperatorStory(pending, publish: true)
        XCTAssertFalse(store.stories.isEmpty)
        let model = OiOperatorEvidenceModel()
        await model.load(OiTestBackend.grant, using: store)
        let row = try XCTUnwrap(model.detail?.evidence)
        let review = try OiEvidenceReview(snapshot: row, decision: .revoked, note: "가상 철회 사유", count: "")
        backend.configure { $0.failAfterReview = true }
        let result = await model.review(review, using: store)
        XCTAssertEqual(result?.status, "revoked"); XCTAssertNotNil(model.warning)
        XCTAssertEqual(store.evidence.first?.status, "revoked")
        XCTAssertTrue(store.stories.isEmpty); XCTAssertTrue(store.reviewStories.isEmpty)
        backend.configure { $0.failReads = false; $0.isOperator = false }
        do { _ = try await store.operatorEvidenceList(); XCTFail("Permission required") }
        catch OiOperatorStoryError.accessDenied {}
    }

    @MainActor func testEvidenceRevocationPreservesUnrelatedTemporaryStoryOnRefreshFailure() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure {
            $0.isOperator = true
            $0.unapprovedDraftsEnabled = true
            $0.evidence = evidenceFixture(status: "approved")
        }
        await store.start()
        var temporary = draft()
        temporary.grantId = nil
        let saveResult = await store.save(temporary)
        let saved = try XCTUnwrap(saveResult)
        let submitResult = await store.submitStory(saved)
        let pending = try XCTUnwrap(submitResult)
        _ = try await store.reviewOperatorStory(pending, publish: true)
        let evidence = try await store.operatorEvidence(OiTestBackend.grant).evidence
        let review = try OiEvidenceReview(snapshot: evidence, decision: .revoked, note: "Synthetic revocation", count: "")
        backend.configure { $0.failAfterReview = true }
        let result = try await store.reviewOperatorEvidence(review)
        XCTAssertEqual(result.evidence.status, "revoked")
        XCTAssertNotNil(result.warning)
        XCTAssertEqual(store.stories.map(\.id), [saved.id])
        XCTAssertEqual(store.ownStories.map(\.id), [saved.id])
        XCTAssertEqual(backend.snapshot().story?["status"] as? String, "published")
    }

    @MainActor func testOperatorEvidenceDuplicateAndPreviousAccountResponse() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.isOperator = true; $0.evidence = evidenceFixture() }
        await store.start()
        let model = OiOperatorEvidenceModel()
        await model.load(OiTestBackend.grant, using: store)
        let row = try XCTUnwrap(model.detail?.evidence)
        let review = try OiEvidenceReview(snapshot: row, decision: .approved, note: "", count: "2")
        let held = expectation(description: "evidence response held")
        backend.configure { $0.holdReviewResponse = true; $0.didHold = { held.fulfill() } }
        let first = Task { await model.review(review, using: store) }
        await fulfillment(of: [held], timeout: 5)
        let duplicate = await model.review(review, using: store)
        XCTAssertNil(duplicate); XCTAssertEqual(backend.snapshot().evidenceReviewCount, 1)
        await store.signOut()
        XCTAssertNotNil(store.account, "A mutation in progress blocks account changes")
        backend.releaseHeldRead()
        let result = await first.value
        XCTAssertEqual(result?.status, "approved")
        let readHeld = expectation(description: "evidence read pending")
        backend.configure { $0.holdEvidenceRead = true; $0.didHold = { readHeld.fulfill() } }
        let read = Task { try await store.operatorEvidenceList() }
        await fulfillment(of: [readHeld], timeout: 5)
        backend.configure { $0.holdEvidenceRead = false }
        await store.signOut()
        backend.releaseHeldRead()
        do { _ = try await read.value; XCTFail("Old account response must not be returned") }
        catch OiServiceError.accountChanged {}
    }

    @MainActor func testOperatorEvidenceScreenLayouts() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.isOperator = true; $0.evidence = evidenceFixture() }
        await store.start()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        for name in ["list", "detail", "detail-accessibility", "approved", "list-failed", "list-empty"] {
            backend.configure {
                $0.failReads = name == "list-failed"
                $0.evidence = evidenceFixture(status: name == "approved" ? "approved" : name == "list-empty" ? "draft" : "pending")
            }
            let detail = name.hasPrefix("detail") || name == "approved"
            let view = detail ? AnyView(NavigationStack { OiOperatorEvidenceDetailView(remote: store, evidenceID: OiTestBackend.grant) })
                : AnyView(NavigationStack { OiOperatorEvidenceListView(remote: store) })
            let window = UIWindow(windowScene: scene)
            let controller = UIHostingController(rootView: view.environment(\.scenePhase, .active)
                .environment(\.locale, Locale(identifier: "ko_KR"))
                .environment(\.dynamicTypeSize, name.hasSuffix("accessibility") ? .accessibility5 : .large)
                .preferredColorScheme(.light))
            window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
            window.rootViewController = controller; window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(500))
            controller.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
            }
            let attachment = XCTAttachment(image: image); attachment.name = "operator-evidence-\(name)"
            attachment.lifetime = .keepAlways; add(attachment)
            window.isHidden = true; window.rootViewController = nil
        }
    }

    @MainActor func testOperatorStoryReadCannotReturnPreviousAccountsData() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.isOperator = true }
        await store.start()
        let held = expectation(description: "operator list pending")
        backend.configure { $0.holdOwnerRead = true; $0.didHold = { held.fulfill() } }
        let read = Task { try await store.operatorStories() }
        await fulfillment(of: [held], timeout: 5)
        backend.configure { $0.holdOwnerRead = false }
        await store.signOut()
        backend.releaseHeldRead()
        do { _ = try await read.value; XCTFail("Old account response must not be returned") }
        catch OiServiceError.accountChanged { }
    }

    @MainActor func testOperatorStoryScreenLayouts() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.isOperator = true }
        await store.start()
        let savedResult = await store.save(draft(title: "후배에게 전하고 싶은 작은 응원"))
        let saved = try XCTUnwrap(savedResult)
        let pendingResult = await store.submitStory(saved)
        let pending = try XCTUnwrap(pendingResult)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        for name in ["list", "detail", "list-empty", "list-failed", "detail-accessibility"] {
            backend.configure {
                $0.failReads = name == "list-failed"
                $0.story?["status"] = name == "list-empty" ? "published" : "pending"
            }
            let view: AnyView
            if name.hasPrefix("detail") {
                view = AnyView(NavigationStack { OiOperatorStoryDetailView(remote: store, storyID: pending.id) })
            } else { view = AnyView(NavigationStack { OiOperatorStoriesView(remote: store) }) }
            let window = UIWindow(windowScene: scene)
            let controller = UIHostingController(rootView: view
                .environment(\.scenePhase, .active)
                .environment(\.locale, Locale(identifier: "ko_KR"))
                .environment(\.dynamicTypeSize, name.hasSuffix("accessibility") ? .accessibility5 : .large)
                .preferredColorScheme(.light))
            window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
            window.rootViewController = controller
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(500))
            controller.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "operator-story-\(name)-402x874"
            attachment.lifetime = .keepAlways
            add(attachment)
            window.isHidden = true
            window.rootViewController = nil
        }
    }

    @MainActor func testOperatorStoryReviewLoadsAndMovesBetweenFilters() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.isOperator = true }
        await store.start()
        let draftResult = await store.save(draft(title: "공개 검토할 이야기"))
        let draft = try XCTUnwrap(draftResult)
        let pendingResult = await store.submitStory(draft)
        let pending = try XCTUnwrap(pendingResult)
        let list = OiOperatorStoriesModel()
        await list.load(using: store)
        XCTAssertEqual(list.filtered.map(\.id), [pending.id])
        let detail = OiOperatorStoryModel()
        await detail.load(pending.id, using: store)
        XCTAssertEqual(detail.detail?.story.id, pending.id)
        XCTAssertTrue(detail.detail?.media.isEmpty == true)

        let publishResult = await detail.review(pending, publish: true, using: store)
        let published = try XCTUnwrap(publishResult)
        list.apply(published)
        XCTAssertTrue(list.filtered.isEmpty)
        list.filter = .published
        XCTAssertEqual(list.filtered.map(\.id), [pending.id])
        XCTAssertEqual(detail.detail?.story.status, "published")
        XCTAssertNotNil(detail.notice)
        XCTAssertTrue(store.stories.contains { $0.id == pending.id })

        let hideResult = await detail.review(published, publish: false, using: store)
        let hidden = try XCTUnwrap(hideResult)
        list.apply(hidden)
        XCTAssertTrue(list.filtered.isEmpty)
        list.filter = .hidden
        XCTAssertEqual(list.filtered.map(\.id), [pending.id])
        XCTAssertFalse(store.stories.contains { $0.id == pending.id })
        XCTAssertEqual(backend.snapshot().reviewCount, 2)
    }

    @MainActor func testOperatorStoryConflictRequiresFreshConfirmation() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.isOperator = true }
        await store.start()
        let savedResult = await store.save(draft(title: "변경 전 이야기"))
        let saved = try XCTUnwrap(savedResult)
        let pendingResult = await store.submitStory(saved)
        let pending = try XCTUnwrap(pendingResult)
        let model = OiOperatorStoryModel()
        await model.load(pending.id, using: store)
        backend.configure { $0.story?["revision"] = pending.revision + 1; $0.story?["body"] = "다른 운영자가 확인할 새 내용" }
        let conflicted = await model.review(pending, publish: true, using: store)
        XCTAssertNil(conflicted)
        XCTAssertTrue(model.requiresReload)
        XCTAssertFalse(model.canReview)
        XCTAssertNotNil(model.error)
        let blocked = await model.review(pending, publish: true, using: store)
        XCTAssertNil(blocked)
        XCTAssertEqual(backend.snapshot().reviewCount, 1)
        await model.load(pending.id, using: store)
        let latest = try XCTUnwrap(model.detail?.story)
        XCTAssertEqual(latest.body, "다른 운영자가 확인할 새 내용")
        let stale = await model.review(pending, publish: true, using: store)
        XCTAssertNil(stale, "Old confirmation must not submit a newer revision")
        XCTAssertEqual(backend.snapshot().reviewCount, 1)
        await model.load(pending.id, using: store)
        let confirmed = await model.review(latest, publish: true, using: store)
        XCTAssertNotNil(confirmed)
    }

    @MainActor func testOperatorStoryLostResponseRequiresReadBeforeAnotherDecision() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.isOperator = true }
        await store.start()
        let savedResult = await store.save(draft(title: "응답 유실 시험"))
        let saved = try XCTUnwrap(savedResult)
        let pendingResult = await store.submitStory(saved)
        let pending = try XCTUnwrap(pendingResult)
        let model = OiOperatorStoryModel()
        await model.load(pending.id, using: store)
        backend.configure { $0.loseReviewResponse = true }
        let lost = await model.review(pending, publish: true, using: store)
        XCTAssertNil(lost)
        XCTAssertNil(model.notice)
        XCTAssertTrue(model.requiresReload)
        let duplicate = await model.review(pending, publish: true, using: store)
        XCTAssertNil(duplicate)
        XCTAssertEqual(backend.snapshot().reviewCount, 1)
        await model.load(pending.id, using: store)
        XCTAssertEqual(model.detail?.story.status, "published")
        XCTAssertTrue(model.canReview)
    }

    @MainActor func testOperatorStoryConfirmedReceiptSurvivesListRefreshFailure() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.isOperator = true }
        await store.start()
        let savedResult = await store.save(draft(title: "저장 후 동기화 실패 시험"))
        let saved = try XCTUnwrap(savedResult)
        let pendingResult = await store.submitStory(saved)
        let pending = try XCTUnwrap(pendingResult)
        let model = OiOperatorStoryModel()
        await model.load(pending.id, using: store)
        backend.configure { $0.failAfterReview = true }
        let receipt = await model.review(pending, publish: true, using: store)
        XCTAssertEqual(receipt?.status, "published")
        XCTAssertEqual(model.detail?.story.status, "published")
        XCTAssertNotNil(model.notice)
        XCTAssertNotNil(model.warning)
        XCTAssertTrue(model.requiresReload)
        XCTAssertEqual(backend.snapshot().reviewCount, 1)
    }

    @MainActor func testOperatorStoryRejectsRevokedRightsAndMissingStory() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.isOperator = true }
        await store.start()
        let savedResult = await store.save(draft(title: "권한 철회 시험"))
        let saved = try XCTUnwrap(savedResult)
        let pendingResult = await store.submitStory(saved)
        let pending = try XCTUnwrap(pendingResult)
        let model = OiOperatorStoryModel()
        await model.load(UUID(), using: store)
        XCTAssertNil(model.detail)
        XCTAssertNotNil(model.error)
        await model.load(pending.id, using: store)
        backend.configure { $0.isOperator = false }
        let denied = await model.review(pending, publish: true, using: store)
        XCTAssertNil(denied)
        XCTAssertNil(model.detail)
        XCTAssertFalse(store.isOperator)
        XCTAssertEqual(backend.snapshot().reviewCount, 0)
        let list = OiOperatorStoriesModel()
        await list.load(using: store)
        XCTAssertFalse(list.hasLoaded)
        XCTAssertTrue(list.stories.isEmpty)
    }

    @MainActor func testOperatorStoryRejectsDuplicateDecisionWhileRequestPending() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.isOperator = true }
        await store.start()
        let savedResult = await store.save(draft(title: "중복 처리 시험"))
        let saved = try XCTUnwrap(savedResult)
        let pendingResult = await store.submitStory(saved)
        let pending = try XCTUnwrap(pendingResult)
        let model = OiOperatorStoryModel()
        await model.load(pending.id, using: store)
        let held = expectation(description: "decision awaiting response")
        backend.configure { $0.holdReviewResponse = true; $0.didHold = { held.fulfill() } }
        let first = Task { await model.review(pending, publish: true, using: store) }
        await fulfillment(of: [held], timeout: 5)
        XCTAssertTrue(model.isProcessing)
        let duplicate = await model.review(pending, publish: true, using: store)
        XCTAssertNil(duplicate)
        XCTAssertEqual(backend.snapshot().reviewCount, 1)
        backend.releaseHeldRead()
        let confirmed = await first.value
        XCTAssertNotNil(confirmed)
    }

    @MainActor func testOperatorHomeLayouts() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.isOperator = true }
        await store.start()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        for (name, allowed, failure, size) in [
            ("menu", true, false, DynamicTypeSize.large),
            ("menu-accessibility", true, false, DynamicTypeSize.accessibility5),
            ("denied", false, false, DynamicTypeSize.large),
            ("failed", true, true, DynamicTypeSize.large)
        ] {
            backend.configure { $0.isOperator = allowed; $0.failCapabilities = failure }
            let window = UIWindow(windowScene: scene)
            let controller = UIHostingController(rootView: OiOperatorHomeView(remote: store)
                .environment(\.scenePhase, .active)
                .environment(\.locale, Locale(identifier: "ko_KR"))
                .environment(\.dynamicTypeSize, size))
            window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
            window.rootViewController = controller
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(500))
            controller.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "operator-\(name)-402x874"
            attachment.lifetime = .keepAlways
            add(attachment)
            window.isHidden = true
            window.rootViewController = nil
        }
    }

    @MainActor func testOperatorAccessRechecksServerAndRemovesRevokedAccess() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.isOperator = true }
        await store.start()
        let access = OiOperatorAccess()
        await access.check { try await store.verifyOperatorAccess() }
        XCTAssertEqual(access.state, .allowed)
        backend.configure { $0.isOperator = false }
        await access.check { try await store.verifyOperatorAccess() }
        XCTAssertEqual(access.state, .denied)
        XCTAssertFalse(store.isOperator)
        XCTAssertTrue(store.reviewStories.isEmpty)
    }

    @MainActor func testOperatorAccessFailureClosesCachedAccessAndCanRetry() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.isOperator = true }
        await store.start()
        let access = OiOperatorAccess()
        await access.check { try await store.verifyOperatorAccess() }
        backend.configure { $0.failCapabilities = true }
        await access.check { try await store.verifyOperatorAccess() }
        XCTAssertEqual(access.state, .failed)
        backend.configure { $0.failCapabilities = false }
        await access.check { try await store.verifyOperatorAccess() }
        XCTAssertEqual(access.state, .allowed)
        await store.signOut()
        await access.check { try await store.verifyOperatorAccess() }
        XCTAssertNotEqual(access.state, .allowed)
    }

    @MainActor func testOperatorAccessDiscardsResponseAfterInvalidation() async {
        let access = OiOperatorAccess()
        await access.check {
            access.invalidate()
            return true
        }
        XCTAssertEqual(access.state, .checking)
        await access.check { throw URLError(.cancelled) }
        XCTAssertEqual(access.state, .checking)
        await access.check { false }
        XCTAssertEqual(access.state, .denied)
    }

    @MainActor func testLiveCatalogAndSchoolPersistAcrossRelaunch() async throws {
        let (store,backend,vault,session,directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        await store.start()
        XCTAssertEqual(store.schools.map(\.id), ["postech"])
        XCTAssertEqual(store.regions.first?.schoolId, "postech")
        XCTAssertEqual(store.assets.first?.kind, "cucumber")
        await store.updateProfile(nickname: "  Saved name  ", schoolID: "postech")
        XCTAssertEqual(store.profile?.nickname, "Saved name")
        XCTAssertEqual(store.profile?.schoolId, "postech")
        let restored = OiRemoteStore(api: try OiServiceAPI(key: "sb_publishable_testing", session: session), drafts: OiDraftVault(directory: directory), vault: vault)
        await restored.start()
        XCTAssertEqual(restored.profile?.schoolId, "postech")
        await restored.updateProfile(nickname: "Wrong", schoolID: "unknown")
        XCTAssertNotNil(restored.error)
        XCTAssertEqual(backend.snapshot().nickname, "Saved name")
    }

    @MainActor func testPublicAcademicInfoPersistsClearsAndPreservesLegacyProfile() async throws {
        let (store, backend, vault, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        await store.start()
        await store.updateProfile(schoolID: "postech", academicInfo: .init(name: "  테스트농부  ", department: "컴퓨터공학과", admissionYear: "2026"))
        XCTAssertNil(store.error)
        XCTAssertEqual(store.profile?.publicName, "테스트농부")
        XCTAssertEqual(store.profile?.nickname, "Owner A")
        let restored = OiRemoteStore(api: try OiServiceAPI(key: "sb_publishable_testing", session: session),
            drafts: OiDraftVault(directory: directory), vault: vault)
        await restored.start()
        XCTAssertEqual(restored.profile?.department, "컴퓨터공학과")
        XCTAssertEqual(restored.profile?.admissionYear, "2026")
        await restored.updateProfile(academicInfo: .init(name: "바뀌면 안 됨", admissionYear: "20260001"))
        XCTAssertNotNil(restored.error)
        XCTAssertEqual(backend.snapshot().publicName, "테스트농부")
        await restored.updateProfile(academicInfo: .init())
        XCTAssertNil(restored.error)
        XCTAssertEqual(restored.profile?.publicName, "")
        XCTAssertEqual(restored.profile?.department, "")
        XCTAssertEqual(restored.profile?.admissionYear, "")
        XCTAssertEqual(restored.profile?.schoolId, "postech")
        XCTAssertEqual(restored.profile?.nickname, "Owner A")
    }

    @MainActor func testPublicAndPrivateAcademicInformationRemainIndependentAcrossEdits() async throws {
        let (store, backend, vault, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure {
            $0.schoolProfileEnabled = true; $0.schoolID = "postech"
            $0.publicName = "Public donor"; $0.department = "Public department"; $0.admissionYear = "26"
            $0.schoolAdmissionYear = 2020; $0.schoolDepartment = "Private Physics"
        }
        await store.start()
        XCTAssertEqual(store.profile?.admissionYear, "26")
        XCTAssertEqual(store.profile?.department, "Public department")
        XCTAssertEqual(store.profile?.schoolAdmissionYear, 2020)
        XCTAssertEqual(store.profile?.schoolDepartment, "Private Physics")

        await store.updateSchoolProfile(schoolID: "postech", admissionYear: 2021, department: "Private Mathematics")
        XCTAssertNil(store.error)
        XCTAssertEqual(store.profile?.publicName, "Public donor")
        XCTAssertEqual(store.profile?.admissionYear, "26")
        XCTAssertEqual(store.profile?.department, "Public department")
        XCTAssertEqual(store.profile?.schoolAdmissionYear, 2021)
        XCTAssertEqual(store.profile?.schoolDepartment, "Private Mathematics")
        XCTAssertEqual(backend.snapshot().admissionYear, "26")
        XCTAssertEqual(backend.snapshot().department, "Public department")

        backend.configure { $0.failReads = true }
        await store.updateProfile(academicInfo: .init(name: "Edited public donor", department: "Public History", admissionYear: "25"))
        XCTAssertEqual(store.profile?.admissionYear, "25")
        XCTAssertEqual(store.profile?.department, "Public History")
        XCTAssertEqual(store.profile?.schoolAdmissionYear, 2021)
        XCTAssertEqual(store.profile?.schoolDepartment, "Private Mathematics")
        await store.updateFarmName("햇살")
        await store.updateProfile(nickname: "Legacy public nickname")
        XCTAssertEqual(store.profile?.publicName, "Edited public donor")
        XCTAssertEqual(store.profile?.admissionYear, "25")
        XCTAssertEqual(store.profile?.department, "Public History")
        XCTAssertEqual(store.profile?.schoolAdmissionYear, 2021)
        XCTAssertEqual(store.profile?.schoolDepartment, "Private Mathematics")
        XCTAssertEqual(backend.snapshot().profilePatchBodies.map { $0.keys.sorted() },
            [["admission_year", "department", "public_name"], ["farm_name"], ["nickname"]])

        backend.configure { $0.failReads = false }
        let restored = OiRemoteStore(api: try OiServiceAPI(key: "sb_publishable_testing", session: session),
            drafts: OiDraftVault(directory: directory), vault: vault)
        await restored.start()
        XCTAssertEqual(restored.profile?.publicName, "Edited public donor")
        XCTAssertEqual(restored.profile?.admissionYear, "25")
        XCTAssertEqual(restored.profile?.department, "Public History")
        XCTAssertEqual(restored.profile?.schoolAdmissionYear, 2021)
        XCTAssertEqual(restored.profile?.schoolDepartment, "Private Mathematics")
    }

    @MainActor func testProfileEditsDoNotOverwriteFieldsChangedOnAnotherDevice() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        await store.start()
        XCTAssertNil(store.profile?.schoolId)

        backend.configure { $0.schoolID = "postech" }
        await store.updateProfile(nickname: "Name on this device")
        XCTAssertEqual(store.profile?.nickname, "Name on this device")
        XCTAssertEqual(backend.snapshot().schoolID, "postech")

        backend.configure { $0.nickname = "Name on another device"; $0.schoolID = nil }
        await store.updateProfile(schoolID: "postech")
        XCTAssertEqual(backend.snapshot().nickname, "Name on another device")
        XCTAssertEqual(store.profile?.schoolId, "postech")
    }

    @MainActor func testSchoolProfilePersistsAndNicknameEditsPreservePrivateMetadata() async throws {
        let (store, backend, vault, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.schoolProfileEnabled = true }
        await store.start()
        XCTAssertTrue(store.isSchoolProfileAvailable)
        await store.updateSchoolProfile(schoolID: "postech", admissionYear: 2020, department: "  Computer Science  ")
        XCTAssertNil(store.error)
        XCTAssertEqual(store.profile?.schoolAdmissionYear, 2020)
        XCTAssertEqual(store.profile?.schoolDepartment, "Computer Science")
        await store.updateProfile(nickname: "Changed nickname")
        XCTAssertEqual(store.profile?.schoolAdmissionYear, 2020)
        XCTAssertEqual(store.profile?.schoolDepartment, "Computer Science")
        let restored = OiRemoteStore(api: try OiServiceAPI(key: "sb_publishable_testing", session: session),
            drafts: OiDraftVault(directory: directory), vault: vault)
        await restored.start()
        XCTAssertEqual(restored.profile?.schoolAdmissionYear, 2020)
        XCTAssertEqual(restored.profile?.schoolDepartment, "Computer Science")
        XCTAssertGreaterThanOrEqual(backend.snapshot().schoolProfileReads, 2)
    }

    @MainActor func testSkippedDepartmentClearsOnlyPrivateDepartment() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.schoolProfileEnabled = true; $0.schoolID = "postech"; $0.schoolAdmissionYear = 2020; $0.schoolDepartment = "Old department" }
        await store.start()
        await store.updateSchoolProfile(schoolID: "postech", admissionYear: 2021, department: nil)
        XCTAssertNil(store.error)
        XCTAssertNil(store.profile?.schoolDepartment)
        XCTAssertEqual(store.profile?.schoolAdmissionYear, 2021)
        XCTAssertEqual(store.profile?.nickname, "Owner A")
        XCTAssertNil(backend.snapshot().schoolDepartment)
    }

    @MainActor func testLegacyServerKeepsLoadingWithoutPrivateSchoolRPC() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        await store.start()
        XCTAssertTrue(store.hasLoadedRemote)
        XCTAssertFalse(store.isSchoolProfileAvailable)
        XCTAssertEqual(backend.snapshot().schoolProfileReads, 0)
        await store.updateSchoolProfile(schoolID: "postech", admissionYear: 2020, department: nil)
        XCTAssertNotNil(store.error)
        XCTAssertEqual(backend.snapshot().schoolProfileWrites, 0)
        XCTAssertEqual(store.profile?.nickname, "Owner A")
    }

    @MainActor func testLegacySchoolChangeDoesNotAttachPreviousDepartmentToNewSchool() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure {
            $0.schoolProfileEnabled = true; $0.includesSecondSchool = true
            $0.schoolID = "postech"; $0.schoolAdmissionYear = 2020; $0.schoolDepartment = "Original department"
        }
        await store.start()
        XCTAssertEqual(store.profile?.schoolDepartment, "Original department")
        await store.updateProfile(schoolID: "other")
        XCTAssertNil(store.error)
        XCTAssertEqual(store.profile?.schoolId, "other")
        XCTAssertNil(store.profile?.schoolAdmissionYear)
        XCTAssertNil(store.profile?.schoolDepartment)
    }

    @MainActor func testSchoolProfileWriteFailurePreservesPreviousValues() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.schoolProfileEnabled = true; $0.schoolID = "postech"; $0.schoolAdmissionYear = 2020; $0.schoolDepartment = "Original" }
        await store.start()
        backend.configure { $0.failSchoolProfileWrite = true }
        await store.updateSchoolProfile(schoolID: "postech", admissionYear: 2021, department: "Changed")
        XCTAssertNotNil(store.error)
        XCTAssertEqual(store.profile?.schoolAdmissionYear, 2020)
        XCTAssertEqual(store.profile?.schoolDepartment, "Original")
    }

    @MainActor func testSchoolProfileRejectsReceiptForAnotherAccount() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.schoolProfileEnabled = true; $0.schoolID = "postech"; $0.schoolAdmissionYear = 2020 }
        await store.start()
        backend.configure { $0.mismatchedSchoolProfileReceipt = true }
        await store.updateSchoolProfile(schoolID: "postech", admissionYear: 2021, department: "Changed")
        XCTAssertNotNil(store.error)
        XCTAssertEqual(store.profile?.schoolAdmissionYear, 2020)
        XCTAssertEqual(store.account?.id, OiTestBackend.owner)
    }

    @MainActor func testFarmNamePersistsIndependentlyAcrossRelaunchAndOtherProfileEdits() async throws {
        let (store, backend, vault, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure {
            $0.schoolProfileEnabled = true; $0.schoolID = "postech"
            $0.schoolAdmissionYear = 2020; $0.schoolDepartment = "Computer Science"
        }
        await store.start()
        XCTAssertEqual(store.profile?.farmName, "오이")
        await store.updateFarmName("  햇살  ")
        XCTAssertNil(store.error)
        XCTAssertEqual(store.profile?.farmName, "햇살")
        XCTAssertEqual(store.profile?.nickname, "Owner A")
        XCTAssertEqual(store.profile?.schoolId, "postech")
        XCTAssertEqual(store.profile?.schoolAdmissionYear, 2020)
        XCTAssertEqual(store.profile?.schoolDepartment, "Computer Science")
        XCTAssertEqual(backend.snapshot().profilePatchBodies.first?.keys.sorted(), ["farm_name"])
        let restored = OiRemoteStore(api: try OiServiceAPI(key: "sb_publishable_testing", session: session),
            drafts: OiDraftVault(directory: directory), vault: vault)
        await restored.start()
        XCTAssertEqual(restored.profile?.farmName, "햇살")
        await restored.updateProfile(nickname: "Changed public author")
        XCTAssertEqual(restored.profile?.farmName, "햇살")
        await restored.updateSchoolProfile(schoolID: "postech", admissionYear: 2021, department: "Physics")
        XCTAssertNil(restored.error)
        XCTAssertEqual(restored.profile?.farmName, "햇살")
        XCTAssertEqual(restored.profile?.nickname, "Changed public author")
    }

    @MainActor func testFarmNameRejectsEmptyAndOverlongInputAndNormalizesHangul() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        await store.start()
        for invalid in [" \n\t", "일이삼사오육칠"] {
            await store.updateFarmName(invalid)
            XCTAssertNotNil(store.error)
        }
        XCTAssertTrue(backend.snapshot().profilePatchBodies.isEmpty)
        await store.updateFarmName("오이".decomposedStringWithCanonicalMapping)
        XCTAssertNil(store.error)
        XCTAssertEqual(store.profile?.farmName, "오이")
        await store.updateFarmName("일이삼사오육")
        XCTAssertNil(store.error)
        XCTAssertEqual(store.profile?.farmName, "일이삼사오육")
        await store.updateFarmName(String(repeating: "가".decomposedStringWithCanonicalMapping, count: 6))
        XCTAssertNil(store.error)
        XCTAssertEqual(store.profile?.farmName, "가가가가가가")
        await store.updateFarmName(String(repeating: "🌱", count: 6))
        XCTAssertNil(store.error)
        XCTAssertEqual(store.profile?.farmName, String(repeating: "🌱", count: 6))
    }

    @MainActor func testLegacyServerDoesNotWriteNicknameAsFarmName() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.farmName = nil }
        await store.start()
        XCTAssertTrue(store.hasLoadedRemote)
        await store.updateFarmName("햇살")
        XCTAssertNotNil(store.error)
        XCTAssertTrue(backend.snapshot().profilePatchBodies.isEmpty)
        XCTAssertEqual(store.profile?.nickname, "Owner A")
        XCTAssertNil(store.profile?.farmName)
    }

    @MainActor func testFailedFarmWriteAndForeignReceiptPreserveConfirmedProfile() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        await store.start()
        backend.configure { $0.failFarmWrite = true }
        await store.updateFarmName("햇살")
        XCTAssertNotNil(store.error)
        XCTAssertEqual(store.profile?.farmName, "오이")
        backend.configure { $0.failFarmWrite = false; $0.mismatchedFarmReceipt = true }
        await store.updateFarmName("햇살")
        XCTAssertNotNil(store.error)
        XCTAssertEqual(store.profile?.farmName, "오이")
        XCTAssertEqual(store.account?.id, OiTestBackend.owner)
    }

    @MainActor func testLateFarmWriteCannotReplaceAnotherAccountFarm() async throws {
        let (store, backend, vault, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        await store.start()
        let held = expectation(description: "Previous account farm write is held")
        backend.configure { $0.holdFarmWrite = true; $0.didHold = { held.fulfill() } }
        let write = Task { await store.updateFarmName("햇살") }
        await fulfillment(of: [held], timeout: 5)
        vault.value = OiMemorySession(owner: OiTestBackend.other).value
        await store.start()
        backend.releaseHeldRead()
        await write.value
        XCTAssertEqual(store.account?.id, OiTestBackend.other)
        XCTAssertNil(store.profile, "A stale write must not repopulate the profile cleared during account restoration")
        // Account restoration deliberately skips a refresh while a write is busy.
        await store.refresh()
        XCTAssertEqual(store.profile?.farmName, "다른밭")
        XCTAssertEqual(store.profile?.nickname, "Owner B")
    }

    @MainActor func testFarmerOutfitPersistsAcrossRelaunchAndOtherProfileEdits() async throws {
        let (store, backend, vault, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.farmerOutfitEnabled = true; $0.schoolProfileEnabled = true }
        await store.start()
        XCTAssertTrue(store.isFarmerOutfitAvailable)
        XCTAssertNil(store.farmerOutfit)
        let outfit = OiFarmerOutfit(character: "kyu", slots: ["top": "kyu-3916-2673", "hat": "kyu-hat"])
        let saved = await store.saveFarmerOutfit(outfit)
        XCTAssertTrue(saved)
        XCTAssertEqual(store.farmerOutfit, outfit)
        XCTAssertEqual(Set(try XCTUnwrap(backend.snapshot().farmerOutfitPayloads.first).keys), ["p_outfit"])
        await store.updateFarmName("햇살")
        await store.updateProfile(nickname: "Legacy name")
        await store.updateSchoolProfile(schoolID: "postech", admissionYear: 2020, department: "Physics")
        XCTAssertEqual(store.farmerOutfit, outfit)
        let restored = OiRemoteStore(api: try OiServiceAPI(key: "sb_publishable_testing", session: session),
            drafts: OiDraftVault(directory: directory), vault: vault)
        await restored.start()
        XCTAssertEqual(restored.farmerOutfit, outfit)
        XCTAssertGreaterThanOrEqual(backend.snapshot().farmerOutfitReads, 2)
    }

    @MainActor func testLegacyServerDoesNotRequestOrPretendToSaveFarmerOutfit() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        await store.start()
        XCTAssertTrue(store.hasLoadedRemote)
        XCTAssertFalse(store.isFarmerOutfitAvailable)
        XCTAssertNil(store.farmerOutfit)
        let saved = await store.saveFarmerOutfit(OiFarmerOutfit(character: "kyu", slots: [:]))
        XCTAssertFalse(saved)
        XCTAssertNotNil(store.error)
        XCTAssertEqual(backend.snapshot().farmerOutfitReads, 0)
        XCTAssertEqual(backend.snapshot().farmerOutfitWrites, 0)
    }

    @MainActor func testFarmerOutfitRejectsInvalidSelectionBeforeNetworkWrite() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.farmerOutfitEnabled = true }
        await store.start()
        let invalid = [
            OiFarmerOutfit(version: 2, character: "kyu", slots: [:]),
            OiFarmerOutfit(character: "unknown", slots: [:]),
            OiFarmerOutfit(character: "kyu", slots: ["cape": "cape"]),
            OiFarmerOutfit(character: "kyu", slots: ["hat": "https://example.invalid/asset"]),
            OiFarmerOutfit(character: "kyu", slots: ["hat": String(repeating: "a", count: 81)])
        ]
        for outfit in invalid {
            let saved = await store.saveFarmerOutfit(outfit)
            XCTAssertFalse(saved)
            XCTAssertNotNil(store.error)
        }
        XCTAssertEqual(backend.snapshot().farmerOutfitWrites, 0)
    }

    @MainActor func testFarmerOutfitWriteFailureAndForeignReceiptPreserveLastKnownOutfit() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.farmerOutfitEnabled = true }
        await store.start()
        let original = OiFarmerOutfit(character: "cumber", slots: ["set": "legacy-classic"])
        let initialSaved = await store.saveFarmerOutfit(original)
        XCTAssertTrue(initialSaved)
        let changed = OiFarmerOutfit(character: "kyu", slots: ["hat": "kyu-hat"])
        backend.configure { $0.failFarmerOutfitWrite = true }
        let failed = await store.saveFarmerOutfit(changed)
        XCTAssertFalse(failed)
        XCTAssertEqual(store.farmerOutfit, original)
        backend.configure { $0.failFarmerOutfitWrite = false; $0.mismatchedFarmerOutfitReceipt = true }
        let mismatched = await store.saveFarmerOutfit(changed)
        XCTAssertFalse(mismatched)
        XCTAssertEqual(store.farmerOutfit, original)
        XCTAssertNotNil(store.error)
    }

    @MainActor func testFarmerOutfitMissingReceiptFieldIsNotTreatedAsAnEmptySavedOutfit() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.farmerOutfitEnabled = true; $0.omitsFarmerOutfitReceiptField = true }
        await store.start()
        XCTAssertFalse(store.hasLoadedRemote)
        XCTAssertNotNil(store.loadError)
        XCTAssertNil(store.farmerOutfit)
    }

    @MainActor func testFarmerOutfitReceiptSurvivesRefreshFailure() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.farmerOutfitEnabled = true }
        await store.start()
        backend.configure { $0.failReads = true }
        let outfit = OiFarmerOutfit(character: "kyu", slots: ["top": "kyu-top"])
        let saved = await store.saveFarmerOutfit(outfit)
        XCTAssertTrue(saved)
        XCTAssertEqual(store.farmerOutfit, outfit)
        XCTAssertNotNil(store.syncWarning)
        XCTAssertNotNil(store.loadError)
    }

    @MainActor func testLateFarmerOutfitWriteCannotReplaceAnotherAccountOutfit() async throws {
        let (store, backend, vault, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure {
            $0.farmerOutfitEnabled = true
            $0.otherFarmerOutfit = ["version": 1, "character": "cumber", "slots": ["set": "legacy-classic"]]
        }
        await store.start()
        let held = expectation(description: "Previous account outfit write is held")
        backend.configure { $0.holdFarmerOutfitWrite = true; $0.didHold = { held.fulfill() } }
        let write = Task { await store.saveFarmerOutfit(OiFarmerOutfit(character: "kyu", slots: ["top": "kyu-top"])) }
        await fulfillment(of: [held], timeout: 5)
        vault.value = OiMemorySession(owner: OiTestBackend.other).value
        await store.start()
        backend.releaseHeldRead()
        let saved = await write.value
        XCTAssertFalse(saved)
        XCTAssertEqual(store.account?.id, OiTestBackend.other)
        XCTAssertNil(store.farmerOutfit)
        await store.refresh()
        XCTAssertEqual(store.farmerOutfit, OiFarmerOutfit(character: "cumber", slots: ["set": "legacy-classic"]))
    }

    @MainActor func testSignOutOnlyRevokesCurrentSessionAndClearsDeviceCredentials() async throws {
        let (store, backend, vault, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        await store.start()
        XCTAssertNotNil(store.account)

        await store.signOut()

        XCTAssertEqual(backend.snapshot().logoutScopes, ["local"])
        XCTAssertNil(try vault.read())
        XCTAssertNil(store.account)
        XCTAssertNil(store.syncWarning)
    }

    @MainActor func testFailedServerSignOutWarningSurvivesSuccessfulPublicRefresh() async throws {
        let (store, backend, vault, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        await store.start()
        backend.configure { $0.failLogout = true }

        await store.signOut()

        let warning = try XCTUnwrap(store.syncWarning)
        XCTAssertNil(try vault.read())
        XCTAssertNil(store.account)
        XCTAssertTrue(store.hasLoadedRemote)
        XCTAssertNil(store.loadError)
        await store.refresh()
        XCTAssertEqual(store.syncWarning, warning)
    }

    @MainActor func testCardResolutionNotFoundIsConflictWithoutChangingOtherNotFoundErrors() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        await store.start()

        do {
            try await store.resolveCardRequest(UUID(), accept: true)
            XCTFail("A withdrawn request cannot be resolved")
        } catch OiServiceError.conflict { }

        do {
            _ = try await store.cardRequests()
            XCTFail("A missing list endpoint cannot be read")
        } catch OiServiceError.unavailable { }
    }

    @MainActor func testCardSendAcceptsAnExistingRequestForTheSameStory() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        await store.start()
        let storyID = UUID(), requestID = UUID(), existingID = UUID()
        backend.configure {
            $0.cardSendResponse = ["id": existingID.uuidString, "story_id": storyID.uuidString, "status": "pending"]
        }
        let pending = try await store.sendCardRequest(storyID: storyID, requestID: requestID)
        XCTAssertEqual(pending, .pending)
        let retried = try await store.sendCardRequest(storyID: storyID, requestID: requestID)
        XCTAssertEqual(retried, .pending)

        backend.configure { $0.cardSendResponse["status"] = "accepted" }
        let resolved = try await store.sendCardRequest(storyID: storyID, requestID: existingID)
        XCTAssertEqual(resolved, .accepted)
        let payload = ["p_story_id": storyID.uuidString, "p_request_id": requestID.uuidString]
        let original = ["p_story_id": storyID.uuidString, "p_request_id": existingID.uuidString]
        XCTAssertEqual(backend.snapshot().cardSendPayloads, [payload, payload, original])
        XCTAssertTrue(store.collections.isEmpty)
    }

    @MainActor func testCardSendRejectsAReceiptForAnotherStory() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        await store.start()
        let storyID = UUID(), requestID = UUID()
        backend.configure {
            $0.cardSendResponse = ["id": requestID.uuidString, "story_id": UUID().uuidString, "status": "pending"]
        }
        do {
            _ = try await store.sendCardRequest(storyID: storyID, requestID: requestID)
            XCTFail("A different story cannot acknowledge this request")
        } catch OiServiceError.unavailable { }
    }

    @MainActor func testCardSendDiscardsReceiptAfterSignOutAndRequiresAuthentication() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        await store.start()
        let storyID = UUID(), requestID = UUID()
        let held = expectation(description: "Card request is in flight")
        backend.configure {
            $0.cardSendResponse = ["id": requestID.uuidString, "story_id": storyID.uuidString, "status": "pending"]
            $0.holdCardSend = true
            $0.didHold = { held.fulfill() }
        }
        let send = Task { try await store.sendCardRequest(storyID: storyID, requestID: requestID) }
        await fulfillment(of: [held], timeout: 5)
        await store.signOut()
        backend.releaseHeldRead()

        do {
            _ = try await send.value
            XCTFail("The previous session's result must not be reported")
        } catch OiServiceError.accountChanged { }
        do {
            _ = try await store.sendCardRequest(storyID: storyID, requestID: requestID)
            XCTFail("Signed-out clients cannot submit requests")
        } catch OiServiceError.signInRequired { }
        XCTAssertEqual(backend.snapshot().cardSendPayloads.count, 1)
    }

    @MainActor func testPublicRepositoryLoadsActualStoryAndRejectsHidden() async throws {
        let (store,backend,_,session,directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        await store.start()
        guard let saved = await store.save(draft(title: "Public body test")) else { XCTFail("Save failed"); return }
        backend.configure { $0.story?["status"] = "published" }
        let repository = RealStoryRepository(key: "sb_publishable_testing", session: session)
        let story = try await repository.fetchPublicStory(storyID: saved.id.uuidString)
        XCTAssertEqual(story?.id, saved.id.uuidString)
        XCTAssertEqual(story?.content, saved.body)
        let card = try await repository.fetchPublicStoryCard(storyID: saved.id.uuidString)
        XCTAssertEqual(card?.storyID, story?.id)
        XCTAssertNil(card?.imageURL, "No fabricated card image URL")
        // Simulate a malformed server response despite the public status filter.
        backend.configure { $0.story?["status"] = "hidden"; $0.ignoreStoryStatusFilter = true }
        do { _ = try await repository.fetchPublicStory(storyID: saved.id.uuidString); XCTFail("Hidden story rendered") }
        catch {}
    }

    @MainActor func testAccountAndEditorLayoutsAtSupportedWidths() async throws {
        let (store,backend,_,session,directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        await store.start()
        let local = OiLocalDraft(draft: draft(title: "내가 캠퍼스에 남기고 싶은 이야기"), version: 1)
        try await store.saveLocalDraft(local, owner: OiTestBackend.owner)
        let folder = URL.documentsDirectory.appending(path: "oi-flow-layout-checks")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for width in [375,402,440] {
            for editor in [false,true] {
                let name = "oi-\(editor ? "editor" : "account")-\(width)"
                let root = AnyView(NavigationStack {
                    if editor { OiStoryEditor(remote: store, localID: local.id) }
                    else { MYSettingsView(remote: store) }
                }.preferredColorScheme(.light))
                let controller = UIHostingController(rootView: root)
                let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
                let window = UIWindow(windowScene: scene)
                window.frame = CGRect(x: 0, y: 0, width: width, height: 874)
                window.rootViewController = controller
                window.isHidden = false
                defer { window.isHidden = true; window.rootViewController = nil }
                controller.view.frame = window.bounds
                controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(150))
                let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                XCTAssertEqual(image.size.width, CGFloat(width))
                let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways
                add(attachment)
                try XCTUnwrap(image.pngData()).write(to: folder.appending(path: name+".png"))
            }
        }
    }

    /// Opt-in sheet/save regression, with only synthetic local photos (no library interaction).
    @MainActor func testInteractiveWardrobePhotoSheet() async throws {
        guard ProcessInfo.processInfo.environment["OI_WARDROBE_SHEET_CHECK"] == "1" else {
            throw XCTSkip("Opt in: photo sheet → duplicate front photo → Done → card")
        }
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        await store.start()
        let image = try XCTUnwrap(UIImage(named: "DonationCampus"))
        let asset = try OiPhotoRenderer.asset(XCTUnwrap(image.jpegData(compressionQuality: 0.8)))
        var wardrobe = OiWardrobeLook(); wardrobe.top = .tshirt
        try wardrobe.artwork.set(OiPhotoDesign(layers: [OiPhotoLayer(source: asset.id, side: .back),
                                    OiPhotoLayer(source: asset.id, side: .back), OiPhotoLayer(source: asset.id)]),
                                 sources: [asset.id: asset.data], for: "top-tshirt")
        var customization = OiDraftCustomization(); customization.wardrobe = wardrobe
        let local = OiLocalDraft(draft: draft(title: "사진 시트 검증"), version: 1,
                                creationStep: OiCreationStep.cucumber.rawValue, customization: customization)
        try await store.saveLocalDraft(local, owner: OiTestBackend.owner)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKey = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: Color.white.fullScreenCover(isPresented: .constant(true)) {
            NavigationStack { OiStoryEditor(remote: store, localID: local.id).environment(\.scenePhase, .active) }
        })
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; window.windowScene = nil; previousKey?.makeKey() }
        for _ in 0..<240 {
            try await Task.sleep(for: .seconds(1))
            let saved = try await store.localDraft(id: local.id, owner: OiTestBackend.owner)
            XCTAssertNil(backend.snapshot().story, "Clothing edits must not submit a story")
            if saved?.creationStep == OiCreationStep.card.rawValue {
                let design = try XCTUnwrap(saved?.customization?.wardrobe?.artwork.designs["top-tshirt"])
                XCTAssertEqual(design.layers.filter { $0.side == .front }.count, 2)
                XCTAssertEqual(design.layers.filter { $0.side == .back }.count, 2)
                XCTAssertTrue(saved?.customization?.wardrobe?.artwork.isValid == true)
                return
            }
        }
        XCTFail("Wardrobe sheet interaction route did not finish")
    }

    /// Exercises the production editor with local photos and no network writes.
    @MainActor func testInteractivePhotoCancelAndLocation() async throws {
        guard ProcessInfo.processInfo.environment["OI_PHOTO_INTERACTION_CHECK"] == "1" else {
            throw XCTSkip("Opt in: edit/delete → Cancel → edit/delete → Done → location → Cancel")
        }
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        await store.start()
        let first = UUID(), second = UUID()
        let image = try XCTUnwrap(UIImage(named: "DonationCampus")?.jpegData(compressionQuality: 0.9))
        for id in [first, second] { try await store.saveLocalPhoto(image, id: id, owner: OiTestBackend.owner) }
        let local = OiLocalDraft(draft: draft(title: "사진·위치 화면 검증"), photos: [first, second], version: 1,
                                creationStep: OiCreationStep.photos.rawValue)
        try await store.saveLocalDraft(local, owner: OiTestBackend.owner)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKey = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: NavigationStack {
            OiStoryEditor(remote: store, localID: local.id).environment(\.scenePhase, .active)
        })
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; window.windowScene = nil; previousKey?.makeKey() }
        var sawEdit = false, sawCancel = false, sawDone = false, sawLocation = false
        for _ in 0..<240 {
            try await Task.sleep(for: .seconds(1))
            let candidate = try await store.localDraft(id: local.id, owner: OiTestBackend.owner)
            let saved = try XCTUnwrap(candidate)
            XCTAssertNil(backend.snapshot().story, "Photo and location edits never submit to server")
            if saved.photos != local.photos { sawEdit = true }
            if sawEdit && saved.creationStep == OiCreationStep.story.rawValue && !sawCancel {
                XCTAssertEqual(saved.photos, local.photos, "Cancel restores all original attachments")
                let bytes = try await store.localPhoto(id: first, owner: OiTestBackend.owner)
                XCTAssertEqual(bytes, image, "Edits keep the original photo copy intact")
                sawCancel = true
            }
            if sawCancel && saved.creationStep == OiCreationStep.story.rawValue && saved.photos.count == 1 { sawDone = true }
            if sawDone && saved.creationStep == OiCreationStep.location.rawValue { sawLocation = true }
            if sawLocation && saved.creationStep == OiCreationStep.story.rawValue {
                XCTAssertEqual(saved.draft.latitude, local.draft.latitude)
                XCTAssertEqual(saved.draft.longitude, local.draft.longitude)
                XCTAssertEqual(saved.photos.count, 1)
                return
            }
        }
        XCTFail("Photo/location UI route did not finish")
    }

    /// Opt-in live UI check with a fake API and an isolated draft vault. Never uses a real account.
    @MainActor func testInteractiveCreationNavigation() async throws {
        let mode = ProcessInfo.processInfo.environment["OI_CREATION_INTERACTION_CHECK"]
        let freelyExplore = mode == "all-screens"
        guard mode == "1" || freelyExplore else {
            throw XCTSkip("Opt in to drive Done → Next → Previous → Previous with simulator UI automation")
        }
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        await store.start()
        var look = OiDraftCustomization()
        look.wardrobe = OiWardrobeLook()
        var input = draft(title: "화면 이동 검증용 이야기")
        if freelyExplore { input.body = ""; input.latitude = nil; input.longitude = nil; input.cucumberName = "" }
        let local = OiLocalDraft(draft: input, version: 1,
            creationStep: (freelyExplore ? OiCreationStep.consent : .cucumber).rawValue, customization: look)
        try await store.saveLocalDraft(local, owner: OiTestBackend.owner)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKey = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        let controller = UIHostingController(rootView: NavigationStack {
            OiStoryEditor(remote: store, localID: local.id).environment(\.scenePhase, .active)
        }.preferredColorScheme(.light))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true; window.rootViewController = nil; window.windowScene = nil
            previousKey?.makeKey()
        }
        var reachedCard = false
        var visited = Set<String>()
        for _ in 0..<300 {
            try await Task.sleep(for: .seconds(1))
            let saved = try await store.localDraft(id: local.id, owner: OiTestBackend.owner)
            if freelyExplore {
                if let step = saved?.creationStep { visited.insert(step) }
                XCTAssertFalse(OiStoryConsentState(savedIDs: saved?.agreedConsentClauseIDs ?? []).allRequiredClausesAreAgreed,
                               "Visiting screens never accepts terms")
                XCTAssertNil(backend.snapshot().story, "Previewing screens never creates a server story")
                if visited.count == OiCreationStep.allCases.count && saved?.creationStep == OiCreationStep.consent.rawValue {
                    XCTAssertEqual(saved?.draft, input)
                    XCTAssertEqual(saved?.customization?.wardrobe, look.wardrobe)
                    return
                }
                continue
            }
            if saved?.creationStep == OiCreationStep.card.rawValue { reachedCard = true }
            if reachedCard && saved?.creationStep == OiCreationStep.story.rawValue {
                XCTAssertEqual(saved?.draft.title, local.draft.title)
                XCTAssertEqual(saved?.customization?.wardrobe, look.wardrobe)
                XCTAssertNil(backend.snapshot().story, "Navigation and Done must not submit a story")
                return
            }
        }
        XCTFail("The simulator UI check did not complete its requested navigation route")
    }

    @MainActor private func context(expired: Bool = false, authentication: (any OiAuthenticating)? = nil) throws -> (OiRemoteStore, OiTestBackend, OiMemorySession, URLSession, URL) {
        let backend = OiTestBackend(); backend.install()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OiStoreURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let api = try OiServiceAPI(key: "sb_publishable_testing", session: session)
        let vault = OiMemorySession(expired: expired)
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        return (OiRemoteStore(api: api, drafts: OiDraftVault(directory: directory), vault: vault, authentication: authentication),backend,vault,session,directory)
    }

    private func clean(_ session: URLSession, directory: URL) {
        session.invalidateAndCancel(); OiStoreURLProtocol.handle = nil
        if FileManager.default.fileExists(atPath: directory.path) { XCTAssertNoThrow(try FileManager.default.removeItem(at: directory)) }
    }

    private func draft(title: String = "Current edited title") -> OiStoryDraft {
        var value = OiStoryDraft(); value.grantId = OiTestBackend.grant
        value.title = title; value.body = "Current body"; value.theme = "감사"; value.emotion = "기쁨"
        value.cucumberName = "테스트오이"; value.latitude = 36.01261057021347; value.longitude = 129.3197268697784
        return value
    }

    @MainActor func testTemporaryWritingFlagPreservesStoryAndPhotoWhenDisabled() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { clean(session, directory: directory) }
        backend.configure { $0.hasWritingGrant = false }
        await store.start()
        XCTAssertFalse(store.canStartStory, "Old servers with no flag must require approval")
        backend.configure { $0.unapprovedDraftsEnabled = true }
        await store.refresh()
        XCTAssertTrue(store.canStartStory)
        var temporary = draft(); temporary.grantId = nil
        guard let saved = await store.save(temporary),
              let withPhoto = await store.uploadStoryImage(Data([1, 2, 3]), photoID: UUID(), story: saved) else {
            XCTFail("Temporary draft/photo save failed"); return
        }
        XCTAssertNil(withPhoto.grantId)
        XCTAssertEqual(withPhoto.status, "draft")
        XCTAssertTrue(store.stories.isEmpty, "Saving must not publish")
        let paths = store.mediaPaths(storyID: saved.id)
        XCTAssertEqual(paths.count, 1)
        backend.configure { $0.unapprovedDraftsEnabled = false }
        await store.refresh()
        XCTAssertFalse(store.canStartStory)
        XCTAssertFalse(store.canWriteStory(grantID: nil))
        XCTAssertEqual(store.ownStories.first?.body, temporary.body)
        XCTAssertEqual(store.mediaPaths(storyID: saved.id), paths)
        let denied = await store.save(OiStoryDraft(story: withPhoto))
        XCTAssertNil(denied)
        XCTAssertEqual(backend.snapshot().uploads.count, 1)
        backend.configure { $0.hasWritingGrant = true }
        await store.refresh()
        var resumed = OiStoryDraft(story: withPhoto); resumed.grantId = OiTestBackend.grant
        let approved = await store.save(resumed)
        XCTAssertEqual(approved?.id, saved.id)
        XCTAssertEqual(approved?.grantId, OiTestBackend.grant)
        XCTAssertEqual(store.mediaPaths(storyID: saved.id), paths)
        backend.configure { $0.unapprovedDraftsEnabled = true }
        await store.refresh()
        XCTAssertTrue(store.unapprovedDraftsEnabled)
        await store.signOut()
        XCTAssertFalse(store.unapprovedDraftsEnabled)
        XCTAssertFalse(store.canStartStory)
    }

    @MainActor func testWriteReceiptSurvivesRefreshFailure() async throws {
        let (store,backend,_,session,directory) = try context()
        defer { clean(session, directory: directory) }
        await store.start(); XCTAssertTrue(store.hasLoadedRemote)
        backend.configure { $0.failReads = true }
        let saved = await store.save(draft())
        XCTAssertEqual(saved?.revision, 1)
        XCTAssertEqual(store.ownStories.first?.id, saved?.id)
        XCTAssertNil(store.error); XCTAssertNotNil(store.syncWarning); XCTAssertNotNil(store.loadError)
    }

    @MainActor func testSecondPhotoPreservesFirstWhenRefreshFails() async throws {
        let (store,backend,_,session,directory) = try context()
        defer { clean(session, directory: directory) }
        await store.start()
        guard let saved = await store.save(draft()) else { XCTFail("Save failed"); return }
        backend.configure { $0.failReads = true }
        guard let first = await store.uploadStoryImage(Data([1,2,3]), photoID: UUID(), story: saved) else { XCTFail("First image failed"); return }
        let second = await store.uploadStoryImage(Data([4,5,6]), photoID: UUID(), story: first)
        XCTAssertNotNil(second)
        XCTAssertEqual(backend.snapshot().paths.count, 2)
        XCTAssertEqual(store.mediaPaths(storyID: saved.id).count, 2)
        XCTAssertNotNil(store.syncWarning)
    }

    @MainActor func testRemovedPhotoStaysRemovedAfterRefreshFailureAndReviewSubmission() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { clean(session, directory: directory) }
        await store.start()
        guard let saved = await store.save(draft()),
              let first = await store.uploadStoryImage(Data([1,2,3]), photoID: UUID(), story: saved),
              let second = await store.uploadStoryImage(Data([4,5,6]), photoID: UUID(), story: first) else {
            XCTFail("Photo setup failed"); return
        }
        let retained = Array(store.mediaPaths(storyID: saved.id).suffix(1))
        backend.configure { $0.failReads = true }
        guard let edited = await store.setStoryMedia(retained, story: second) else { XCTFail("Remove failed"); return }
        XCTAssertEqual(store.mediaPaths(storyID: saved.id), retained)
        XCTAssertEqual(backend.snapshot().paths, retained)
        let receipt = await store.submitStory(edited)
        XCTAssertEqual(receipt?.status, "pending")
        XCTAssertFalse(OiCreationAccess.canEdit(status: receipt?.status, submitted: false))
        XCTAssertTrue(store.stories.isEmpty, "Review request must not publish the story")
    }

    @MainActor func testMediaRemovalKeepsAttachmentsMissingFromLocalCache() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        await store.start()
        let receipt = await store.save(draft())
        let story = try XCTUnwrap(receipt)
        let removedID = UUID()
        let directoryPath = "\(story.userId.uuidString)/\(story.id.uuidString)"
        let removedByID = "\(directoryPath)/\(removedID.uuidString).jpg"
        let removedByPath = "\(directoryPath)/another-photo.jpg"
        let retained = ["\(directoryPath)/newer-device-photo.jpg", "\(directoryPath)/\(removedID.uuidString)-copy.jpg"]
        backend.configure { state in
            state.paths = [removedByID, retained[0], removedByPath, retained[1]]
            state.failReads = true
        }
        XCTAssertTrue(store.mediaPaths(storyID: story.id).isEmpty)

        let updated = await store.removeStoryMedia(paths: [removedByPath], photoIDs: [removedID], story: story)

        XCTAssertNotNil(updated)
        XCTAssertEqual(backend.snapshot().paths, retained)
        XCTAssertEqual(store.mediaPaths(storyID: story.id), retained)
    }

    @MainActor func testInvalidRefreshRequiresReauthenticationNotEmptySuccess() async throws {
        let (store,backend,_,session,directory) = try context(expired: true)
        defer { clean(session, directory: directory) }
        backend.configure { $0.failRefreshToken = true }
        await store.start()
        XCTAssertTrue(store.needsReauthentication)
        XCTAssertFalse(store.hasLoadedRemote)
        XCTAssertNotNil(store.loadError)
        XCTAssertEqual(store.account?.id, OiTestBackend.owner)
    }

    @MainActor func testFirstLoadFailureIsNotTrueEmpty() async throws {
        let (store,backend,_,session,directory) = try context()
        defer { clean(session, directory: directory) }
        backend.configure { $0.failReads = true }
        await store.start()
        XCTAssertFalse(store.hasLoadedRemote); XCTAssertNotNil(store.loadError)
        backend.configure { $0.failReads = false }
        await store.refresh()
        XCTAssertTrue(store.hasLoadedRemote); XCTAssertTrue(store.stories.isEmpty); XCTAssertNil(store.loadError)
    }

    @MainActor func testAccountSwitchClearsCachesAndSeparatesDrafts() async throws {
        let (store,backend,vault,session,directory) = try context()
        defer { clean(session, directory: directory) }
        await store.start()
        let record = OiLocalDraft(draft: draft(), version: 1)
        try await store.saveLocalDraft(record, owner: OiTestBackend.owner)
        _ = await store.save(record.draft)
        vault.value = OiMemorySession(owner: OiTestBackend.other).value
        backend.configure { $0.failReads = true }
        await store.start()
        XCTAssertEqual(store.account?.id, OiTestBackend.other)
        XCTAssertTrue(store.ownStories.isEmpty && store.collections.isEmpty && store.favorites.isEmpty)
        XCTAssertFalse(store.hasLoadedRemote)
        let values = try await store.localDrafts(); XCTAssertTrue(values.isEmpty)
        do { _ = try await store.localDraft(id: record.id, owner: OiTestBackend.owner); XCTFail("Cross-account draft read") }
        catch OiServiceError.accountChanged {}
    }

    @MainActor func testLatePreviousAccountReadCannotReplaceNewAccount() async throws {
        let (store,backend,vault,session,directory) = try context()
        defer { clean(session, directory: directory) }
        await store.start()
        let held = expectation(description: "Old account request is held")
        backend.configure { $0.holdOwnerRead = true; $0.didHold = { held.fulfill() } }
        let oldRead = Task { await store.refresh() }
        await fulfillment(of: [held], timeout: 5)
        vault.value = OiMemorySession(owner: OiTestBackend.other).value
        await store.start()
        backend.releaseHeldRead()
        await oldRead.value
        XCTAssertEqual(store.account?.id, OiTestBackend.other)
        XCTAssertEqual(store.profile?.nickname, "Owner B")
    }

    @MainActor func testEvidenceLostResponseResumesSameApplicationAndFile() async throws {
        let (store,backend,vault,session,directory) = try context()
        defer { clean(session, directory: directory) }
        await store.start()
        backend.configure { $0.loseEvidenceResponse = true }
        await store.submitEvidence(data: Data([1,2,3]), contentType: "image/png", fileExtension: "png")
        let operation = store.evidenceOperation
        XCTAssertEqual(operation?.phase, "failed")
        let api = try OiServiceAPI(key: "sb_publishable_testing", session: session)
        let restored = OiRemoteStore(api: api, drafts: OiDraftVault(directory: directory), vault: vault)
        await restored.start(); await restored.retryEvidence()
        XCTAssertEqual(restored.evidenceOperation?.requestID, operation?.requestID)
        XCTAssertEqual(restored.evidenceOperation?.uploadID, operation?.uploadID)
        XCTAssertEqual(restored.evidenceOperation?.phase, "pending")
        XCTAssertEqual(backend.snapshot().requestIDs.count, 1)
        XCTAssertEqual(backend.snapshot().uploads.count, 1)
    }

    @MainActor func testPublicationUsesLatestSavedContentAndRevision() async throws {
        let (store,backend,_,session,directory) = try context()
        defer { clean(session, directory: directory) }
        await store.start()
        var current = draft(title: "Old title")
        guard let first = await store.save(current) else { XCTFail("First save failed"); return }
        current = OiStoryDraft(story: first); current.title = "Latest corrected title"
        guard let updated = await store.save(current) else { XCTFail("Second save failed"); return }
        let receipt = await store.submitStory(updated)
        XCTAssertEqual(receipt?.status, "pending")
        XCTAssertEqual(backend.snapshot().submittedTitle, "Latest corrected title")
        XCTAssertEqual(receipt?.revision, 3)
    }
}

@MainActor
final class OiPhotoImportTests: XCTestCase {
    func testPhotoImportBoundsAndInvalidInput() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let source = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 1500), format: format).image { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 3000, height: 1500))
        }
        let processed = try OiPhotoProcessor.prepare(XCTUnwrap(source.pngData()))
        let image = try XCTUnwrap(UIImage(data: processed)?.cgImage)
        XCTAssertEqual(image.width, 2048); XCTAssertEqual(image.height, 1024)
        XCTAssertThrowsError(try OiPhotoProcessor.prepare(Data("not an image".utf8)))
        XCTAssertThrowsError(try OiPhotoProcessor.prepare(Data(repeating: 0, count: 40_000_001)))
    }
}

@MainActor
final class OiPhotoCropTests: XCTestCase {
    func testFreeAspectGridMatchesSavedPixelsWithoutMovingPhoto() throws {
        let source = quadrantImage()
        let view = OiPhotoCropViewport(image: source)
        view.frame = CGRect(x: 0, y: 0, width: 448, height: 400)
        view.layoutIfNeeded()
        let fixedImageRect = view.imageRect
        XCTAssertEqual(fixedImageRect, CGRect(x: 24, y: 100, width: 400, height: 200))
        view.adjustSelection(handle: .topLeft, translation: CGPoint(x: 250, y: 100))
        view.adjustSelection(handle: .right, translation: CGPoint(x: -50, y: 0))
        view.adjustSelection(handle: .bottom, translation: CGPoint(x: 0, y: -40))
        let rect = try XCTUnwrap(view.normalizedCropRect)
        XCTAssertEqual(view.imageRect, fixedImageRect, "Resizing the grid never changes the photo's size or position")
        XCTAssertEqual(rect.minX, 0.625, accuracy: 0.0001)
        XCTAssertEqual(rect.minY, 0.5, accuracy: 0.0001)
        XCTAssertEqual(rect.width, 0.25, accuracy: 0.0001)
        XCTAssertEqual(rect.height, 0.3, accuracy: 0.0001)
        let data = try OiPhotoProcessor.edit(XCTUnwrap(source.pngData()), operation: .crop(rect))
        let result = try XCTUnwrap(UIImage(data: data)?.cgImage)
        XCTAssertEqual(result.width, 200); XCTAssertEqual(result.height, 120)
        let color = try centerPixel(result)
        XCTAssertGreaterThan(color[0], 220); XCTAssertGreaterThan(color[1], 220); XCTAssertLessThan(color[2], 30)
        XCTAssertEqual(source.cgImage?.width, 800)
    }

    func testPortraitMoveResizeAndResetKeepSelectionInsideFixedImage() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 800), format: format).image { _ in }
        let view = OiPhotoCropViewport(image: image)
        view.frame = CGRect(x: 0, y: 0, width: 248, height: 448); view.layoutIfNeeded()
        XCTAssertEqual(view.normalizedCropRect, CGRect(x: 0, y: 0, width: 1, height: 1))
        view.adjustSelection(handle: .topLeft, translation: CGPoint(x: 50, y: 100))
        view.adjustSelection(handle: .bottom, translation: CGPoint(x: 0, y: -100))
        view.adjustSelection(handle: .move, translation: CGPoint(x: 1000, y: 1000))
        let beforeResize = try XCTUnwrap(view.normalizedCropRect)
        XCTAssertEqual(beforeResize.minX, 0.25, accuracy: 0.0001)
        XCTAssertEqual(beforeResize.minY, 0.5, accuracy: 0.0001)
        XCTAssertEqual(beforeResize.width, 0.75, accuracy: 0.0001)
        XCTAssertEqual(beforeResize.height, 0.5, accuracy: 0.0001)
        view.frame.size = CGSize(width: 448, height: 848); view.layoutIfNeeded()
        XCTAssertEqual(view.normalizedCropRect, beforeResize)
        // A layout change can make the chosen region smaller than a touch target.
        view.frame.size = CGSize(width: 80, height: 80); view.layoutIfNeeded()
        view.adjustSelection(handle: .left, translation: CGPoint(x: 1000, y: 0))
        let smallRect = try XCTUnwrap(view.normalizedCropRect)
        XCTAssertGreaterThanOrEqual(smallRect.minX, 0); XCTAssertLessThanOrEqual(smallRect.maxX, 1)
        view.resetCrop()
        XCTAssertEqual(view.normalizedCropRect, CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    func testEveryEdgeAndCornerResizesIndependentlyAndCannotCross() {
        let bounds = CGRect(x: 20, y: 30, width: 300, height: 220)
        let original = CGRect(x: 50, y: 80, width: 120, height: 100)
        let cases: [(OiPhotoCropGeometry.Handle, CGRect)] = [
            (.topLeft, CGRect(x: 60, y: 95, width: 110, height: 85)),
            (.top, CGRect(x: 50, y: 95, width: 120, height: 85)),
            (.topRight, CGRect(x: 50, y: 95, width: 130, height: 85)),
            (.right, CGRect(x: 50, y: 80, width: 130, height: 100)),
            (.bottomRight, CGRect(x: 50, y: 80, width: 130, height: 115)),
            (.bottom, CGRect(x: 50, y: 80, width: 120, height: 115)),
            (.bottomLeft, CGRect(x: 60, y: 80, width: 110, height: 115)),
            (.left, CGRect(x: 60, y: 80, width: 110, height: 100))
        ]
        for (handle, expected) in cases {
            XCTAssertEqual(OiPhotoCropGeometry.adjusted(original, handle: handle, translation: CGPoint(x: 10, y: 15), inside: bounds), expected)
            for translation in [CGPoint(x: -1000, y: -1000), CGPoint(x: 1000, y: 1000)] {
                let rect = OiPhotoCropGeometry.adjusted(original, handle: handle, translation: translation, inside: bounds)
                XCTAssertGreaterThanOrEqual(rect.width, 44); XCTAssertGreaterThanOrEqual(rect.height, 44)
                XCTAssertTrue(bounds.contains(rect))
            }
        }
        let moved = OiPhotoCropGeometry.adjusted(original, handle: .move, translation: CGPoint(x: -1000, y: -1000), inside: bounds)
        XCTAssertEqual(moved, CGRect(x: 20, y: 30, width: 120, height: 100))
    }

    func testInvalidCropFailsAndRotatedPhotoCanBeCropped() throws {
        let original = try XCTUnwrap(quadrantImage().pngData())
        for rect in [CGRect.zero, CGRect(x: -0.1, y: 0, width: 0.5, height: 0.5),
                     CGRect(x: 0.8, y: 0, width: 0.5, height: 0.5),
                     CGRect(x: CGFloat.nan, y: 0, width: 0.5, height: 0.5)] {
            XCTAssertThrowsError(try OiPhotoProcessor.edit(original, operation: .crop(rect)))
        }
        let rotated = try OiPhotoProcessor.edit(original, operation: .rotateLeft)
        let cropped = try OiPhotoProcessor.edit(rotated, operation: .crop(CGRect(x: 0, y: 0, width: 0.5, height: 0.25)))
        let result = try XCTUnwrap(UIImage(data: cropped)?.cgImage)
        XCTAssertEqual(result.width, 200); XCTAssertEqual(result.height, 200)
        let color = try centerPixel(result)
        XCTAssertLessThan(color[0], 30); XCTAssertGreaterThan(color[1], 220); XCTAssertLessThan(color[2], 30)
    }

    func testFreeRotationPreviewAndSavedPhotoHaveSameClockwiseComposition() throws {
        let source = quadrantImage()
        let view = OiPhotoRotationViewport(image: source)
        view.frame = CGRect(x: 0, y: 0, width: 400, height: 200); view.layoutIfNeeded()
        view.setPreviewRotation(.pi / 6)
        let right = CGPoint(x: 100, y: 0).applying(view.imageView.transform)
        XCTAssertGreaterThan(right.y, 0, "Positive rotation moves the right side down (clockwise)")
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let preview = UIGraphicsImageRenderer(size: view.bounds.size, format: format).image { context in
            view.layer.render(in: context.cgContext)
        }
        let bytes = try OiPhotoProcessor.edit(XCTUnwrap(source.pngData()), operation: .rotate(.pi / 6))
        let saved = try XCTUnwrap(UIImage(data: bytes)?.cgImage)
        XCTAssertEqual(saved.width, 800); XCTAssertEqual(saved.height, 400)
        let previewCG = try XCTUnwrap(preview.cgImage)
        for point in [CGPoint(x: 0.2, y: 0.2), CGPoint(x: 0.8, y: 0.2),
                      CGPoint(x: 0.2, y: 0.8), CGPoint(x: 0.8, y: 0.8)] {
            func sample(_ image: CGImage) throws -> [UInt8] {
                let rect = CGRect(x: point.x * CGFloat(image.width) - 4, y: point.y * CGFloat(image.height) - 4, width: 8, height: 8)
                return try centerPixel(XCTUnwrap(image.cropping(to: rect)))
            }
            let a = try sample(previewCG), b = try sample(saved)
            for channel in 0..<3 { XCTAssertEqual(Int(a[channel]), Int(b[channel]), accuracy: 15) }
        }
        view.setPreviewRotation(-.pi / 6)
        XCTAssertLessThan(CGPoint(x: 100, y: 0).applying(view.imageView.transform).y, 0)
    }

    func testArbitraryRotationCoversCornersAndRejectsInvalidAngles() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        for size in [CGSize(width: 800, height: 400), CGSize(width: 400, height: 800)] {
            let original = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
                UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            }
            for degrees: CGFloat in [-170, -45, 15, 60, 120] {
                let data = try OiPhotoProcessor.edit(XCTUnwrap(original.pngData()), operation: .rotate(degrees * .pi / 180))
                let image = try XCTUnwrap(UIImage(data: data)?.cgImage)
                for x in [2, image.width - 6] {
                    for y in [2, image.height - 6] {
                        let corner = try XCTUnwrap(image.cropping(to: CGRect(x: x, y: y, width: 4, height: 4)))
                        XCTAssertGreaterThan(try centerPixel(corner)[0], 235, "Rotation must not save black corners")
                    }
                }
            }
        }
        for invalid in [CGFloat.nan, .infinity, -.infinity] {
            XCTAssertThrowsError(try OiPhotoProcessor.edit(XCTUnwrap(quadrantImage().pngData()), operation: .rotate(invalid)))
        }
    }

    private func quadrantImage() -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 800, height: 400), format: format).image { ctx in
            UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 200))
            UIColor.green.setFill(); ctx.fill(CGRect(x: 400, y: 0, width: 400, height: 200))
            UIColor.blue.setFill(); ctx.fill(CGRect(x: 0, y: 200, width: 400, height: 200))
            UIColor.yellow.setFill(); ctx.fill(CGRect(x: 400, y: 200, width: 400, height: 200))
        }
    }

    private func centerPixel(_ image: CGImage) throws -> [UInt8] {
        var rgba = [UInt8](repeating: 0, count: 4)
        try rgba.withUnsafeMutableBytes { bytes in
            let ctx = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.draw(image, in: CGRect(x: -image.width / 2, y: -image.height / 2, width: image.width, height: image.height))
        }
        return rgba
    }
}

extension OiRemoteStoreTests {
    @MainActor func testCanceledAdditionalProofPreservesCanonicalLoginAndVault() async throws {
        let (store,backend,vault,session,directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.canonicalAccountID = OiTestBackend.other }
        await store.start()
        let before = try XCTUnwrap(vault.value)
        let authentication = OiControlledAuthentication()
        let additional = Task { try await store.authenticateAdditional(using: authentication) }
        while !authentication.isPending { await Task.yield() }
        authentication.complete(.failure(CancellationError()))
        do {
            _ = try await additional.value
            XCTFail("Canceled additional proof unexpectedly succeeded")
        } catch is CancellationError { }
        XCTAssertEqual(store.account?.id, OiTestBackend.other)
        XCTAssertEqual(vault.value?.user, before.user)
        XCTAssertEqual(vault.value?.accessToken, before.accessToken)
        XCTAssertEqual(vault.value?.refreshToken, before.refreshToken)
        XCTAssertEqual(vault.value?.appAccount, before.appAccount)
        XCTAssertNil(store.error)
        XCTAssertFalse(store.isBusy)
    }

    @MainActor func testAdditionalAuthenticationDoesNotReplaceTheActiveAccount() async throws {
        let (store,backend,vault,session,directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        await store.start()
        let before = try XCTUnwrap(vault.value)
        let authentication = OiControlledAuthentication()
        let additional = Task { try await store.authenticateAdditional(using: authentication) }
        while !authentication.isPending { await Task.yield() }
        authentication.complete(.success(try XCTUnwrap(OiMemorySession(owner: OiTestBackend.other).value)))
        let proof = try await additional.value
        XCTAssertEqual(proof.user.id, OiTestBackend.other)
        XCTAssertEqual(store.account?.id, before.user.id)
        XCTAssertEqual(vault.value?.user, before.user)
        XCTAssertEqual(vault.value?.accessToken, before.accessToken)
        XCTAssertEqual(vault.value?.appAccount, before.appAccount)
        XCTAssertNil(store.error)
        XCTAssertFalse(store.isBusy)
    }

    @MainActor func testCanonicalCatalogUsesTargetOwnerWhileRefreshUsesRawAuthIdentity() async throws {
        let (store,backend,vault,session,directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.canonicalAccountID = OiTestBackend.other; $0.refreshSucceeds = true }
        await store.start()
        XCTAssertEqual(store.account?.id, OiTestBackend.other)
        XCTAssertEqual(vault.value?.appAccount?.id, OiTestBackend.other)
        vault.value?.expiresAt = 0
        await store.start()
        XCTAssertTrue(store.hasLoadedRemote)
        XCTAssertFalse(store.needsReauthentication)
        XCTAssertEqual(backend.snapshot().refreshRequestCount, 1)
        XCTAssertEqual(vault.value?.user.id, OiTestBackend.owner)
        XCTAssertEqual(vault.value?.appAccount?.id, OiTestBackend.other)
        XCTAssertEqual(store.profile?.id, OiTestBackend.other)
        XCTAssertFalse(store.grants.isEmpty)
        XCTAssertEqual(backend.snapshot().grantOwnerQueries.last, "eq.\(OiTestBackend.other.uuidString)")
        guard let saved = await store.save(draft()) else { XCTFail("Canonical story save failed"); return }
        XCTAssertEqual(saved.userId, OiTestBackend.other)
        XCTAssertEqual(store.ownStories.first?.id, saved.id)
        XCTAssertTrue(store.isAccountMergeAvailable)
    }

    @MainActor func testMergedStoryPhotoUploadRetainsOriginalStoragePrefix() async throws {
        let (store,backend,_,session,directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.canonicalAccountID = OiTestBackend.other }
        await store.start()
        guard let saved = await store.save(draft()) else { XCTFail("Canonical story save failed"); return }
        backend.configure { $0.story?["storage_owner_id"] = OiTestBackend.owner.uuidString }
        await store.refresh()
        let merged = try XCTUnwrap(store.ownStories.first(where: { $0.id == saved.id }))
        XCTAssertEqual(merged.userId, OiTestBackend.other)
        XCTAssertEqual(merged.storageOwnerId, OiTestBackend.owner)
        let photoID = UUID()
        let updated = await store.uploadStoryImage(Data([1,2,3]), photoID: photoID, story: merged)
        XCTAssertNotNil(updated)
        let expected = "\(OiTestBackend.owner.uuidString.lowercased())/\(saved.id.uuidString.lowercased())/\(photoID.uuidString.lowercased()).jpg"
        XCTAssertEqual(backend.snapshot().paths, [expected])
        XCTAssertNotNil(backend.snapshot().uploads["oi-story-media/" + expected])
    }

    @MainActor func testConfirmedMergeReceiptSurvivesCanceledPostCommitRefresh() async throws {
        let (store,backend,vault,session,directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.canonicalAccountID = OiTestBackend.owner }
        await store.start()
        XCTAssertTrue(store.isAccountMergeAvailable)
        let source = try XCTUnwrap(vault.value)
        let target = try XCTUnwrap(OiMemorySession(owner: OiTestBackend.other).value)
        let preview = OiMergePreview(challengeId: UUID(), targetAccountId: OiTestBackend.other,
            sourceAccountId: OiTestBackend.owner, sourceIsNew: false,
            expiresAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(300)),
            counts: OiMergeCounts(stories: 0, collections: 0, favorites: 0, evidence: 0, grants: 0))
        let held = expectation(description: "Merge receipt installed before post-commit capabilities read")
        backend.configure { $0.holdPostMergeRead = true; $0.didHold = { held.fulfill() } }
        let confirmation = Task {
            try await store.confirmMerge(target: target, source: source, preview: preview, operationID: UUID())
        }
        await fulfillment(of: [held], timeout: 5)
        XCTAssertEqual(vault.value?.user.id, target.user.id)
        XCTAssertEqual(vault.value?.appAccount?.id, preview.targetAccountId)
        confirmation.cancel()
        backend.releaseHeldRead()
        let receipt = try await confirmation.value
        XCTAssertEqual(receipt.accountId, preview.targetAccountId)
        XCTAssertFalse(receipt.alreadyMerged)
        XCTAssertEqual(backend.snapshot().mergeConfirmCount, 1)
        XCTAssertEqual(store.account?.id, preview.targetAccountId)
        XCTAssertEqual(vault.value?.accessToken, target.accessToken)
        XCTAssertEqual(vault.value?.refreshToken, target.refreshToken)
        XCTAssertFalse(store.isBusy)
        XCTAssertFalse(store.isAccountMergeAvailable)
        XCTAssertFalse(store.hasLoadedRemote)
        XCTAssertFalse(store.needsReauthentication)
        XCTAssertNil(store.error)
        XCTAssertNil(store.loadError)
    }

    @MainActor func testAdoptedUncreatedEvidenceUsesNewServerStorageOwner() async throws {
        let (store,backend,_,session,directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        let local = OiDraftVault(directory: directory)
        let data = Data([4,5,6])
        let original = OiEvidenceOperation(requestID: UUID(), uploadID: UUID(), contentType: "image/png",
            fileExtension: "png", phase: "failed", failure: "Offline before server application creation")
        try await local.saveAttachment(data, owner: OiTestBackend.owner, id: original.uploadID)
        try await local.saveEvidence(original, owner: OiTestBackend.owner)
        backend.configure { $0.canonicalAccountID = OiTestBackend.other }
        await store.start()
        XCTAssertTrue(backend.snapshot().requestIDs.isEmpty)
        XCTAssertNil(backend.snapshot().evidence)
        XCTAssertEqual(store.evidenceOperation?.storageOwnerID, OiTestBackend.owner)
        await store.retryEvidence()
        let expected = "\(OiTestBackend.other.uuidString.lowercased())/\(original.requestID.uuidString.lowercased())/\(original.uploadID.uuidString.lowercased()).png"
        let state = backend.snapshot()
        XCTAssertEqual(state.requestIDs, Set([original.requestID.uuidString]))
        XCTAssertEqual(state.evidence?["storage_owner_id"] as? String, OiTestBackend.other.uuidString)
        XCTAssertEqual(state.evidence?["object_path"] as? String, expected)
        XCTAssertEqual(state.uploads["oi-evidence/" + expected], data)
        XCTAssertEqual(state.uploads.count, 1)
        XCTAssertEqual(store.evidenceOperation?.storageOwnerID, OiTestBackend.other)
        XCTAssertEqual(store.evidenceOperation?.phase, "pending")
        XCTAssertNil(store.error)
        let preservedOperation = try await local.evidence(owner: OiTestBackend.owner)
        let preservedAttachment = try await local.attachment(owner: OiTestBackend.owner, id: original.uploadID)
        let adoptedOperation = try await local.evidence(owner: OiTestBackend.other)
        XCTAssertEqual(preservedOperation, original)
        XCTAssertEqual(preservedAttachment, data)
        XCTAssertEqual(adoptedOperation?.storageOwnerID, OiTestBackend.other)
    }

    @MainActor func testRepeatedLoginDoesNotBecomeConfigurationError() async throws {
        let authentication = OiControlledAuthentication()
        let (store,backend,_,session,directory) = try context(authentication: authentication)
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        await store.start()
        let first = Task { await store.signIn() }
        while !authentication.isPending { await Task.yield() }
        await store.signIn()
        XCTAssertTrue(store.isBusy)
        XCTAssertNil(store.error)
        XCTAssertEqual(authentication.requests, 1)
        authentication.complete(.failure(CancellationError()))
        await first.value
        XCTAssertFalse(store.isBusy)
        XCTAssertNil(store.error)
    }

    @MainActor func testCanceledLoginPreservesPreviousAccountWithoutGlobalError() async throws {
        let authentication = OiControlledAuthentication()
        let (store,backend,vault,session,directory) = try context(authentication: authentication)
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        await store.start()
        let previous = store.account
        for cancellation in [CancellationError() as Error, URLError(.cancelled)] {
            let login = Task { await store.signIn() }
            while !authentication.isPending { await Task.yield() }
            authentication.complete(.failure(cancellation))
            await login.value
            XCTAssertNil(store.error)
            XCTAssertEqual(store.account, previous)
            XCTAssertEqual(vault.value?.user, previous)
            XCTAssertFalse(store.isBusy)
        }
    }

    @MainActor func testCanceledLoginTaskCannotCommitLateSuccess() async throws {
        let authentication = OiControlledAuthentication()
        let (store,backend,vault,session,directory) = try context(authentication: authentication)
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        await store.start()
        let previous = store.account
        let login = Task { await store.signIn() }
        while !authentication.isPending { await Task.yield() }
        login.cancel()
        let replacement = try XCTUnwrap(OiMemorySession(owner: OiTestBackend.other).value)
        authentication.complete(.success(replacement))
        await login.value
        XCTAssertEqual(store.account, previous)
        XCTAssertEqual(vault.value?.user, previous)
        XCTAssertNil(store.error)
        XCTAssertFalse(store.isBusy)
    }

    @MainActor func testSuccessfulRetryClearsPreviousOperationError() async throws {
        let (store,backend,_,session,directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        await store.start()
        _ = await store.save(OiStoryDraft())
        XCTAssertNotNil(store.error)
        await store.refresh()
        XCTAssertNil(store.error)
        XCTAssertNil(store.loadError)
    }

    @MainActor func testRefreshCannotEraseAnErrorFromANewerOperation() async throws {
        let (store,backend,_,session,directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        await store.start()
        let held = expectation(description: "Refresh is in flight")
        backend.configure { $0.holdOwnerRead = true; $0.didHold = { held.fulfill() } }
        let refresh = Task { await store.refresh() }
        await fulfillment(of: [held], timeout: 5)
        _ = await store.save(OiStoryDraft())
        let newestError = try XCTUnwrap(store.error)
        backend.releaseHeldRead()
        await refresh.value
        XCTAssertEqual(store.error, newestError)
    }

    @MainActor func testTransportCancellationIsNotAConnectivityWarning() async throws {
        let (store,backend,_,session,directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        await store.start()
        OiStoreURLProtocol.handle = { _, client in
            client.client?.urlProtocol(client, didFailWithError: URLError(.cancelled))
        }
        await store.refresh()
        XCTAssertNil(store.loadError)
        XCTAssertNil(store.error)
        XCTAssertFalse(store.isRefreshing)
    }

    @MainActor func testRealConnectivityFailureStillProducesAWarning() async throws {
        let (store,backend,_,session,directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        await store.start()
        OiStoreURLProtocol.handle = { _, client in
            client.client?.urlProtocol(client, didFailWithError: URLError(.notConnectedToInternet))
        }
        await store.refresh()
        XCTAssertNotNil(store.loadError)
        XCTAssertFalse(store.isRefreshing)
    }
    @MainActor func testAccountConnectionScreensRenderWithoutRetainedWindows() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.canonicalAccountID = OiTestBackend.owner }
        await store.start()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        defer { previousKeyWindow?.makeKey() }
        for width in [375.0, 402.0, 440.0] {
            let screens: [(String, AnyView)] = [
                ("account", AnyView(NavigationStack { MYSettingsView(remote: store) })),
                ("add-method", AnyView(NavigationStack { OiAccountMergeView(remote: store, mode: .addLoginMethod) })),
                ("merge-existing", AnyView(NavigationStack { OiAccountMergeView(remote: store) })),
            ]
            for (name, view) in screens {
                let window = UIWindow(windowScene: scene)
                defer { window.isHidden = true; window.rootViewController = nil }
                let controller = UIHostingController(rootView: view.environment(\.locale, Locale(identifier: "ko_KR")))
                window.frame = CGRect(x: 0, y: 0, width: width, height: 874)
                window.rootViewController = controller
                window.makeKeyAndVisible()
                try await Task.sleep(for: .milliseconds(250))
                controller.view.layoutIfNeeded()
                var rendered = false
                let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                    rendered = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                XCTAssertTrue(rendered)
                let attachment = XCTAttachment(image: image)
                attachment.name = "account-connection-\(name)-\(Int(width))"
                attachment.lifetime = .keepAlways
                add(attachment)
                window.isHidden = true
                window.rootViewController = nil
                XCTAssertTrue(window.isHidden)
                XCTAssertNil(window.rootViewController)
            }
        }
    }

}

extension OiRemoteStoreTests {
    @MainActor func testDonationAIResultRejectsOtherSubmissionAndApprovalClaims() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OiStoreURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let previous = OiStoreURLProtocol.handle
        defer { session.invalidateAndCancel(); OiStoreURLProtocol.handle = previous }
        let api = try OiServiceAPI(key: "sb_publishable_testing", session: session)
        let request = OiEvidence(id: UUID(), userId: OiTestBackend.owner, status: "pending",
            objectPath: "private.png", reviewNote: nil, submittedAt: "2026-11-05T00:00:00Z")
        let base: [String: Any] = [
            "review_type": "donation_evidence", "evidence_id": request.id.uuidString,
            "submitted_at": request.submittedAt ?? "", "analyzed_at": "2026-11-05T00:01:00Z",
            "human_review_required": true, "authenticity_verified": false, "notice": "운영자 검토 필요",
            "assessment": ["verdict": "no_obvious_signs", "readability": "readable", "findings": [],
                "limitations": ["진위 및 납입 미확인"], "manual_checks": ["원본 확인"]]
        ]
        for field in ["valid", "evidence_id", "submitted_at", "human_review_required", "authenticity_verified"] {
            var response = base
            if field == "evidence_id" { response[field] = UUID().uuidString }
            if field == "submitted_at" { response[field] = "2026-11-05T00:02:00Z" }
            if field == "human_review_required" { response[field] = false }
            if field == "authenticity_verified" { response[field] = true }
            let bytes = try JSONSerialization.data(withJSONObject: response)
            OiStoreURLProtocol.handle = { input, client in
                XCTAssertEqual(input.url?.path, "/functions/v1/analyze-donation-evidence")
                XCTAssertEqual(input.httpMethod, "POST")
                XCTAssertEqual(input.timeoutInterval, 70)
                let payload = try? JSONSerialization.jsonObject(with: OiTestBackend.body(input)) as? [String: String]
                XCTAssertEqual(payload, ["evidence_id": request.id.uuidString])
                client.respond(200, bytes)
            }
            do {
                let review = try await api.reviewDonationEvidence(request, token: "synthetic-session")
                XCTAssertEqual(field, "valid")
                XCTAssertEqual(review.assessment.verdict, .noObviousSigns)
                XCTAssertNil(review.summary, "A legacy visual-only response must remain compatible without implying evidence sufficiency")
            } catch { XCTAssertNotEqual(field, "valid", "The matching non-authoritative result must be accepted") }
        }
    }

    @MainActor func testDonationEvidenceDatesAndUnknownStatesAreNotFabricated() throws {
        XCTAssertEqual(OiDonationEvidenceContent.dateLabel("2026-11-05T00:00:00.000Z"), "2026년 11월 5일 목요일 09:00")
        XCTAssertEqual(OiDonationEvidenceContent.dateLabel(nil), "접수일 확인 중")
        XCTAssertEqual(OiDonationEvidenceContent.statusTitle("new_server_status"), "상태 확인 필요")
        XCTAssertEqual(OiDonationEvidenceContent.statusTitle("approved"), "작성 승인")
    }

    @MainActor func testDonationSemanticSummaryAcceptsSMSAndSeparatesOtherOutcomes() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OiStoreURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let previous = OiStoreURLProtocol.handle
        defer { session.invalidateAndCancel(); OiStoreURLProtocol.handle = previous }
        let api = try OiServiceAPI(key: "sb_publishable_testing", session: session)
        let evidence = OiEvidence(id: UUID(), userId: OiTestBackend.owner, status: "pending",
            objectPath: "synthetic-private.png", reviewNote: nil, submittedAt: "2026-11-05T00:00:00Z")
        for outcome in OiDonationEvidenceSummary.Outcome.allCases {
            let sufficient = outcome == .sufficientEvidence
            let summary: [String: Any] = [
                "outcome": outcome.rawValue, "sufficient_evidence": sufficient,
                "title": sufficient ? "문자에서 기부 완료 근거를 확인했어요" : "자료에 추가 확인이 필요해요",
                "reasons": ["실제 발신번호와 입금 완료 내용을 함께 대조했어요."],
                "checks": [["kind": "sender", "status": "matched", "detail": "공식 기부 문의 번호와 일치해요."]],
                "source_references": [["id": "postech-giving", "url": "https://vision.postech.ac.kr/web/?sub=contract&top=participation",
                    "title": "POSTECH 발전기금", "kind": "official", "verified_at": "2026-11-05"]]
            ]
            let response: [String: Any] = [
                "review_type": "donation_evidence", "evidence_id": evidence.id.uuidString,
                "submitted_at": evidence.submittedAt ?? "", "analyzed_at": "2026-11-05T00:01:00Z",
                "human_review_required": true, "authenticity_verified": false, "notice": "글 작성은 운영자 최종 승인 후 가능해요.",
                "summary": summary,
                "assessment": ["verdict": "no_obvious_signs", "readability": "readable", "findings": [],
                    "limitations": ["원본 진위와 실제 납입은 별도 확인이 필요해요."], "manual_checks": ["제출자 본인 자료인지 확인해 주세요."]]
            ]
            let bytes = try JSONSerialization.data(withJSONObject: response)
            OiStoreURLProtocol.handle = { _, client in client.respond(200, bytes) }
            let review = try await api.reviewDonationEvidence(evidence, token: "synthetic-session")
            XCTAssertEqual(review.summary?.outcome, outcome)
            XCTAssertEqual(review.summary?.sufficientEvidence, sufficient)
            XCTAssertEqual(review.humanReviewRequired, true)
            XCTAssertEqual(review.authenticityVerified, false)
            XCTAssertNotNil(review.summary?.sourceReferences.first?.safeURL)
        }
    }

    @MainActor func testDonationSemanticSummaryRejectsConflictingPassClaims() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OiStoreURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let previous = OiStoreURLProtocol.handle
        defer { session.invalidateAndCancel(); OiStoreURLProtocol.handle = previous }
        let api = try OiServiceAPI(key: "sb_publishable_testing", session: session)
        let evidence = OiEvidence(id: UUID(), userId: OiTestBackend.owner, status: "pending",
            objectPath: "synthetic-private.png", reviewNote: nil, submittedAt: "2026-11-05T00:00:00Z")
        for scenario in ["mismatchedFlag", "missingPassFlag", "suspiciousPass", "unreadablePass", "emptyReasons", "unknownOutcome"] {
            var summary: [String: Any] = ["outcome": "sufficient_evidence", "sufficient_evidence": true,
                "title": "문자 증빙 충족", "reasons": ["입금 완료 근거 확인"], "checks": [], "source_references": []]
            var assessment: [String: Any] = ["verdict": "no_obvious_signs", "readability": "readable", "findings": [],
                "limitations": ["원본 진위 미확인"], "manual_checks": ["운영자 확인"]]
            if scenario == "mismatchedFlag" { summary["outcome"] = "needs_more_evidence" }
            if scenario == "missingPassFlag" { summary["sufficient_evidence"] = false }
            if scenario == "suspiciousPass" { assessment["verdict"] = "suspicious" }
            if scenario == "unreadablePass" { assessment["readability"] = "unreadable" }
            if scenario == "emptyReasons" { summary["reasons"] = [] as [String] }
            if scenario == "unknownOutcome" { summary["outcome"] = "automatically_approved" }
            let response: [String: Any] = ["review_type": "donation_evidence", "evidence_id": evidence.id.uuidString,
                "submitted_at": evidence.submittedAt ?? "", "analyzed_at": "2026-11-05T00:01:00Z",
                "human_review_required": true, "authenticity_verified": false, "notice": "운영자 확인 필요",
                "summary": summary, "assessment": assessment]
            let bytes = try JSONSerialization.data(withJSONObject: response)
            OiStoreURLProtocol.handle = { _, client in client.respond(200, bytes) }
            do {
                _ = try await api.reviewDonationEvidence(evidence, token: "synthetic-session")
                XCTFail("Conflicting evidence pass must be rejected: \(scenario)")
            } catch {}
        }
    }

    @MainActor func testDonationSourceLinksOnlyOpenTrustedHTTPSHosts() {
        for value in ["https://vision.postech.ac.kr/web/", "https://www.postech.ac.kr/"] {
            let source = OiDonationEvidenceSummary.SourceReference(id: "official", url: value,
                title: "기부 안내", kind: "official", verifiedAt: "2026-11-05")
            XCTAssertNotNil(source.safeURL)
        }
        for value in ["http://vision.postech.ac.kr/", "javascript:alert(1)", "https://postech.ac.kr.example.com/",
                      "https://postech.ac.kr@evil.example/", "https://user@vision.postech.ac.kr/",
                      "https://vision.postech.ac.kr:8080/", "https://unreviewed-donor.example/"] {
            let source = OiDonationEvidenceSummary.SourceReference(id: "untrusted", url: value,
                title: "기부 후기", kind: "report", verifiedAt: "2026-11-05")
            XCTAssertNil(source.safeURL)
        }
    }
}

@MainActor
final class OiCostumePhotoTests: XCTestCase {
    private func canvas(_ draw: (CGContext) -> Void) -> CGImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: 1024, height: 512), format: format).image { draw($0.cgContext) }.cgImage!
    }
    private func rgba(_ image: CGImage, size: Int) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: size * size * 4)
        let context = CGContext(data: &data, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        return data
    }
    private var looks: [OiWardrobeLook] {
        OiWardrobeLook.Costume.allCases.map { costume in var l = OiWardrobeLook(); l.costume = costume; return l }
        + OiWardrobeLook.Bottom.allCases.map { bottom in var l = OiWardrobeLook(); l.top = .postech; l.bottom = bottom; return l }
    }
    // Metal's normalized linear sampler interpolates the native texel centers.
    // CGContext's default image resizing uses a different reconstruction filter.
    private func linearPixel(_ bytes: [UInt8], sourceSize: Int, pixel: Int, outputSize: Int) -> [Int] {
        let x = (Double(pixel % outputSize) + 0.5) * Double(sourceSize) / Double(outputSize) - 0.5
        let y = (Double(pixel / outputSize) + 0.5) * Double(sourceSize) / Double(outputSize) - 0.5
        let x0 = Int(floor(x)), y0 = Int(floor(y)), dx = x - floor(x), dy = y - floor(y)
        func sample(_ x: Int, _ y: Int, _ channel: Int) -> Double {
            Double(bytes[(min(sourceSize - 1, max(0, y)) * sourceSize + min(sourceSize - 1, max(0, x))) * 4 + channel])
        }
        return (0..<4).map { channel in
            Int(((sample(x0, y0, channel) * (1-dx) + sample(x0+1, y0, channel) * dx) * (1-dy)
                + (sample(x0, y0+1, channel) * (1-dx) + sample(x0+1, y0+1, channel) * dx) * dy).rounded())
        }
    }
    func testEveryCostumeBakesOriginalUVsAndPreservesUnpaintedPixels() async throws {
        let empty = canvas { _ in }
        let ink = canvas { cg in
            cg.setFillColor(UIColor.red.cgColor); cg.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
            cg.setFillColor(UIColor.blue.cgColor); cg.fill(CGRect(x: 512, y: 0, width: 512, height: 512))
        }
        for look in looks {
            let resource = OiPhotoSlot.top.resource(in: look)
            let restored = try await OiCostumePhotoBaker.shared.bake(empty, resource: resource)
            let printed = try await OiCostumePhotoBaker.shared.bake(ink, resource: resource)
            XCTAssertEqual(restored.count, printed.count)
            var front = 0, back = 0
            for (original, edited) in zip(restored, printed) {
                let originalImage = try XCTUnwrap(UIImage(contentsOfFile: OiCostumePhotoBaker.resource(original.binding.baseImage).path)?.cgImage)
                let size = original.binding.size
                XCTAssertEqual(originalImage.width, originalImage.height)
                let source = rgba(originalImage, size: originalImage.width)
                let plain = rgba(original.image, size: size), color = rgba(edited.image, size: size)
                let compressed = try Data(contentsOf: OiCostumePhotoBaker.resource(original.binding.map))
                let data = try (compressed as NSData).decompressed(using: .zlib) as Data
                let map = data.withUnsafeBytes { Array($0.bindMemory(to: UInt16.self)) }
                var unchanged = 0
                for pixel in stride(from: 0, to: size * size, by: 67) {
                    let i = pixel * 4
                    let expected = linearPixel(source, sourceSize: originalImage.width, pixel: pixel, outputSize: size)
                    for c in 0..<3 { XCTAssertLessThanOrEqual(abs(Int(plain[i+c])-expected[c]), 3, look.modelName) }
                    if map[pixel*2] == 65535 {
                        XCTAssertEqual(Array(plain[i..<i+4]), Array(color[i..<i+4]), look.modelName); unchanged += 1
                    } else if map[pixel*2] < 32760 {
                        XCTAssertGreaterThan(color[i], 250, look.modelName); XCTAssertLessThan(color[i+2], 5, look.modelName); front += 1
                    } else if map[pixel*2] > 32775 {
                        XCTAssertGreaterThan(color[i+2], 250, look.modelName); XCTAssertLessThan(color[i], 5, look.modelName); back += 1
                    }
                }
                XCTAssertGreaterThan(unchanged, 1000)
            }
            XCTAssertGreaterThan(front, 50); XCTAssertGreaterThan(back, 50)
            print("OI_PHOTO_BAKE_PASS \(look.modelName)")
        }
    }
    func testPhotoVerticalOrientationAlphaAndUnpaintedBack() async throws {
        let ink = canvas { cg in
            cg.setFillColor(UIColor.red.cgColor); cg.fill(CGRect(x: 0, y: 0, width: 512, height: 256))
            cg.setFillColor(UIColor.green.withAlphaComponent(0.5).cgColor)
            cg.fill(CGRect(x: 0, y: 256, width: 512, height: 256))
        }
        let resource = "photo-wardrobe-costume-dinosaur-top"
        let originals = try await OiCostumePhotoBaker.shared.bake(canvas { _ in }, resource: resource)
        let edits = try await OiCostumePhotoBaker.shared.bake(ink, resource: resource)
        let original = try XCTUnwrap(originals.first), edited = try XCTUnwrap(edits.first)
        let size = original.binding.size
        let plain = rgba(original.image, size: size), color = rgba(edited.image, size: size)
        let compressed = try Data(contentsOf: OiCostumePhotoBaker.resource(original.binding.map))
        let data = try (compressed as NSData).decompressed(using: .zlib) as Data
        let map = data.withUnsafeBytes { Array($0.bindMemory(to: UInt16.self)) }
        var top = 0, bottom = 0, back = 0
        for pixel in stride(from: 0, to: size * size, by: 67) where map[pixel*2] != 65535 {
            let i = pixel * 4, u = Float(map[pixel*2])/65534, v = Float(map[pixel*2+1])/65534
            if u > 0.51 {
                XCTAssertEqual(Array(plain[i..<i+4]), Array(color[i..<i+4])); back += 1
            } else if u < 0.49 && v < 0.45 {
                XCTAssertGreaterThan(color[i], 250); XCTAssertLessThan(color[i+1], 5); top += 1
            } else if u < 0.49 && v > 0.55 {
                XCTAssertEqual(Int(color[i]), Int(plain[i])/2, accuracy: 2)
                XCTAssertEqual(Int(color[i+1]), 128 + Int(plain[i+1])/2, accuracy: 2)
                XCTAssertEqual(Int(color[i+2]), Int(plain[i+2])/2, accuracy: 2); bottom += 1
            }
        }
        XCTAssertGreaterThan(top, 100); XCTAssertGreaterThan(bottom, 100); XCTAssertGreaterThan(back, 100)
    }
    func testEveryCostumeBindsWithoutExtraMeshAndRestoresMaterial() async throws {
        let ink = canvas { cg in cg.setFillColor(UIColor.magenta.cgColor); cg.fill(CGRect(x: 0, y: 0, width: 1024, height: 512)) }
        func nodes(_ node: Entity) -> [Entity] { (node.components[ModelComponent.self] == nil ? [] : [node]) + node.children.flatMap(nodes) }
        for look in looks {
            let root = try await Entity(contentsOf: OiWardrobeAsset.url(look.modelName, folder: "Wardrobe"))
            let before = nodes(root)
            let bounds = root.visualBounds(relativeTo: root)
            let textures = before.map { ($0.components[ModelComponent.self]?.materials.first as? PhysicallyBasedMaterial)?.baseColor.texture?.resource }
            let prepared = try await OiCostumePhotoMaterial.prepare(ink, resource: OiPhotoSlot.top.resource(in: look))
            try OiCostumePhotoMaterial.apply(prepared, to: root)
            XCTAssertEqual(nodes(root).count, before.count)
            XCTAssertEqual(root.visualBounds(relativeTo: root).extents, bounds.extents)
            OiCostumePhotoMaterial.restore(root)
            for (node, original) in zip(before, textures) {
                let restored = (node.components[ModelComponent.self]?.materials.first as? PhysicallyBasedMaterial)?.baseColor.texture?.resource
                XCTAssertEqual(restored, original, look.modelName)
            }
            print("OI_PHOTO_BIND_PASS \(look.modelName)")
        }
    }
    func testSavedPhotoRemovalAndPlainGarmentStillWork() async throws {
        var look = OiWardrobeLook(); look.costume = .dinosaur
        let asset = try OiPhotoRenderer.asset(UIImage(cgImage: canvas { cg in
            cg.setFillColor(UIColor.orange.cgColor); cg.fill(CGRect(x: 0, y: 0, width: 1024, height: 512))
        }))
        let design = OiPhotoDesign(layers: [OiPhotoLayer(source: asset.id)])
        try look.artwork.set(design, sources: [asset.id: asset.data], for: OiPhotoSlot.top.itemID(in: look))
        let roundTrip = try JSONDecoder().decode(OiWardrobeLook.self, from: JSONEncoder().encode(look))
        XCTAssertEqual(roundTrip, look)
        let (printed, overlays) = try await OiWardrobeAsset.prepare(roundTrip)
        XCTAssertTrue(overlays.isEmpty)
        try look.artwork.set(nil, for: OiPhotoSlot.top.itemID(in: look))
        let (restored, remaining) = try await OiWardrobeAsset.prepare(look, existing: printed)
        XCTAssertTrue(remaining.isEmpty); XCTAssertFalse(restored === printed)
        XCTAssertEqual(restored.visualBounds(relativeTo: restored).extents, printed.visualBounds(relativeTo: printed).extents)
        look.costume = nil
        try look.artwork.set(design, sources: [asset.id: asset.data], for: "top-tshirt")
        let (_, plainOverlays) = try await OiWardrobeAsset.prepare(look)
        XCTAssertNotNil(plainOverlays[.top])
    }
    func testRoundedFramesClipMovedRotatedPhotosOnEveryGarment() throws {
        let resources = looks.map { OiPhotoSlot.top.resource(in: $0) } + OiWardrobeLook.Top.allCases.flatMap { top in
            OiWardrobeLook.Bottom.allCases.flatMap { bottom -> [String] in
                var look = OiWardrobeLook(); look.top = top; look.bottom = bottom
                return OiPhotoSlot.allCases.map { $0.resource(in: look) }
            }
        }
        let solid = try OiPhotoRenderer.asset(UIImage(cgImage: canvas { cg in
            cg.setFillColor(UIColor.magenta.cgColor); cg.fill(CGRect(x: 0, y: 0, width: 1024, height: 512))
        }))
        for resource in Set(resources) {
            let layout = try OiPhotoPrintLayout.load(resource: resource)
            // Extreme scale/rotation/translation must never escape the fixed print area.
            let layers = OiPhotoSide.allCases.map { OiPhotoLayer(source: solid.id, side: $0,
                placement: OiPhotoPlacement(x: 0.52, y: 0.45, width: 1.5, rotation: 32)) }
            let image = try XCTUnwrap(OiPhotoRenderer.atlas(layers: layers, assets: [solid.id: solid], panelSize: 256,
                color: 0xFFFFFF, transparent: true, layout: layout).cgImage)
            var bytes = [UInt8](repeating: 0, count: 512*256*4)
            let context = CGContext(data: &bytes, width: 512, height: 256, bitsPerComponent: 8, bytesPerRow: 512*4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: 512, height: 256))
            for (index, side) in OiPhotoSide.allCases.enumerated() {
                let frame = layout[side], r = frame.rect(edge: 256)
                func alpha(_ x: CGFloat, _ y: CGFloat) -> Int { Int(bytes[(Int(y)*512 + index*256 + Int(x))*4+3]) }
                XCTAssertEqual(alpha(r.midX, r.midY), 255, resource)
                XCTAssertEqual(alpha(floor(r.minX), floor(r.minY)), 0, resource) // Rounded corner, not a square crop.
                XCTAssertEqual(alpha(ceil(r.maxX)-1, ceil(r.maxY)-1), 0, resource)
                for y in stride(from: 0, to: 256, by: 7) { for x in stride(from: 0, to: 256, by: 7) {
                    if !r.insetBy(dx: -2, dy: -2).contains(CGPoint(x: x, y: y)) {
                        XCTAssertEqual(alpha(CGFloat(x), CGFloat(y)), 0, resource)
                    }
                }}
            }
        }
    }

    func testDeletingOnePhotoKeepsOtherSideAndSharedSourceUntilSave() throws {
        let asset = try OiPhotoRenderer.asset(UIImage(cgImage: canvas { cg in
            cg.setFillColor(UIColor.orange.cgColor); cg.fill(CGRect(x: 0, y: 0, width: 1024, height: 512))
        }))
        let a = OiPhotoLayer(source: asset.id), b = OiPhotoLayer(source: asset.id), back = OiPhotoLayer(source: asset.id, side: .back)
        var artwork = OiWardrobeArtwork()
        try artwork.set(OiPhotoDesign(layers: [a, b, back]), sources: [asset.id: asset.data], for: "costume-dinosaur")
        let original = artwork
        var draft = try OiPhotoRenderer.load(artwork.designs["costume-dinosaur"]!, sources: artwork.sources)
        XCTAssertEqual(draft.remove(b.id, on: .front), a.id)
        XCTAssertEqual(draft.layers, [a, back]); XCTAssertNotNil(draft.assets[asset.id])
        XCTAssertEqual(artwork, original, "Cancel must still restore the saved design")
        XCTAssertNil(draft.remove(a.id, on: .front)); XCTAssertEqual(draft.layers, [back])
        XCTAssertNotNil(draft.assets[asset.id])
        XCTAssertNil(draft.remove(back.id, on: .back)); XCTAssertTrue(draft.assets.isEmpty)
        try artwork.set(OiPhotoDesign(layers: draft.layers), sources: draft.assets.mapValues(\.data), for: "costume-dinosaur")
        let restored = try JSONDecoder().decode(OiWardrobeArtwork.self, from: JSONEncoder().encode(artwork))
        XCTAssertTrue(restored.designs.isEmpty); XCTAssertTrue(restored.sources.isEmpty)
    }

    func testMovingEditorPhotoKeepsFrameFixedAndMatchesPrintedPixels() async throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let source = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 300), format: format).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 200, height: 300))
            UIColor.blue.setFill(); context.fill(CGRect(x: 100, y: 0, width: 100, height: 150))
        }
        let accent = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 50), format: format).image { context in
            UIColor.green.setFill(); context.fill(CGRect(x: 0, y: 0, width: 100, height: 50))
        }
        let asset = try OiPhotoRenderer.asset(source), second = try OiPhotoRenderer.asset(accent)
        let assets = [asset.id: asset, second.id: second]
        let layout = try OiPhotoPrintLayout.load(resource: "photo-wardrobe-costume-astronaut-top")
        let window = UIWindow(windowScene: try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene))
        let edge: CGFloat = 256
        let layerID = UUID().uuidString, secondID = UUID().uuidString
        func content(_ layers: [OiPhotoLayer], side: OiPhotoSide) -> some View {
            OiPhotoLayerCanvas(layers: layers, assets: assets, side: side,
                selectedID: nil, frame: layout[side], width: edge).background(.white)
        }
        let controller = UIHostingController(rootView: content([], side: .front))
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        for side in OiPhotoSide.allCases {
            let initial = layout[side].placement(for: asset.image)
            let viewport = OiPhotoPrintViewport(frame: layout[side], width: edge)
            let size = viewport.rect.size
            for count in 1...2 {
                var firstPixels: [UInt8]?
                for (step, delta) in [(0, CGPoint.zero), (1, CGPoint(x: -0.06, y: 0.10)),
                                      (2, CGPoint(x: 0.12, y: -0.08)), (3, CGPoint.zero)] {
                    var placement = initial; placement.x += delta.x; placement.y += delta.y
                    if step == 2 { placement.rotation = 28; placement.width *= 0.75 }
                    var layers = [OiPhotoLayer(id: layerID, source: asset.id, side: side, placement: placement)]
                    if count == 2 {
                        layers.append(OiPhotoLayer(id: secondID, source: second.id, side: side,
                            placement: OiPhotoPlacement(x: initial.x + 0.18, y: initial.y, width: 0.18, rotation: -18)))
                    }
                    // A design on the other side must not bleed into this preview.
                    layers.append(OiPhotoLayer(source: second.id, side: side == .front ? .back : .front))
                    controller.rootView = content(layers, side: side)
                    controller.view.layoutIfNeeded()
                    try await Task.sleep(for: .milliseconds(100))
                    // Capture the live hosting view, retaining photo IDs across successive updates.
                    let bounds = controller.view.bounds, insets = controller.view.safeAreaInsets
                    let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
                        context.cgContext.translateBy(x: -(bounds.width-size.width+insets.left-insets.right)/2,
                            y: -(bounds.height-size.height+insets.top-insets.bottom)/2)
                        controller.view.drawHierarchy(in: bounds, afterScreenUpdates: true)
                    }
                    let atlas = OiPhotoRenderer.atlas(layers: layers, assets: assets, panelSize: 512,
                        color: 0xFFFFFF, layout: layout)
                    // Enlarge only the authored print region from the actual 3D atlas.
                    // This catches display zoom that changes saved placements or the crop.
                    let expectedImage = UIGraphicsImageRenderer(size: size, format: format).image { context in
                        context.cgContext.translateBy(x: -viewport.rect.minX, y: -viewport.rect.minY)
                        context.cgContext.scaleBy(x: viewport.panelEdge/512, y: viewport.panelEdge/512)
                        atlas.draw(at: CGPoint(x: side == .front ? 0 : -512, y: 0))
                    }
                    let actual = rgba(try XCTUnwrap(image.cgImage), size: 256), expected = rgba(try XCTUnwrap(expectedImage.cgImage), size: 256)
                    var mismatches = 0
                    // Permit small antialiasing differences between SwiftUI and the print renderer.
                    for y in stride(from: 4, to: 252, by: 4) { for x in stride(from: 4, to: 252, by: 4) {
                        let i = (y*256+x)*4
                        if (0..<3).contains(where: { abs(Int(actual[i+$0])-Int(expected[i+$0])) > 30 }) { mismatches += 1 }
                    }}
                    XCTAssertLessThan(mismatches, 45, "\(side), \(count) photos, step \(step): editor must match printed crop")
                    if step == 0 { firstPixels = actual }
                    if step == 3 { XCTAssertEqual(actual, firstPixels, "Returning to the original position must restore every cropped edge") }
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "fixed-frame-\(side)-\(count)-\(step)"; attachment.lifetime = .keepAlways; add(attachment)
                }
            }
        }
    }

    func testRoundedFrameEditorSnapshot() async throws {
        var look = OiWardrobeLook(); look.costume = .raincoat
        let asset = try OiPhotoRenderer.asset(UIImage(cgImage: canvas { cg in
            cg.setFillColor(UIColor.systemTeal.cgColor); cg.fill(CGRect(x: 0, y: 0, width: 1024, height: 512))
            ("OI PHOTO" as NSString).draw(at: CGPoint(x: 180, y: 180), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 90)])
        }))
        let frame = try OiPhotoPrintLayout.load(resource: OiPhotoSlot.top.resource(in: look)).front
        try look.artwork.set(OiPhotoDesign(layers: [OiPhotoLayer(source: asset.id, placement: frame.placement(for: asset.image))]),
            sources: [asset.id: asset.data], for: "costume-raincoat")
        let empty = ProcessInfo.processInfo.environment["OI_PHOTO_EMPTY_SNAPSHOT"] == "1"
        if empty { look.artwork = OiWardrobeArtwork() }
        let scene = OiWardrobeScene(editingSlot: .top)
        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: windowScene)
        let interactive = ProcessInfo.processInfo.environment["OI_PHOTO_DELETE_CHECK"] == "1"
        var saved: OiWardrobeArtwork?
        let editor = OiWardrobePhotoEditor(slot: .top, look: look, scene: scene) { saved = $0 }
        let controller = UIHostingController(rootView: VStack(spacing: 0) {
            OiWardrobePreview(look: look, controls: false, scene: scene).frame(height: 245)
            editor.frame(height: 462).background(Color(red: 0.92, green: 0.94, blue: 0.89))
        }.environment(\.scenePhase, .active))
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { scene.release(); window.isHidden = true }
        try await Task.sleep(for: .seconds(3))
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = "rounded-photo-editor-\(empty ? "empty" : "photo")"; attachment.lifetime = .keepAlways; add(attachment)
        if interactive {
            print("OI_PHOTO_DELETE_INTERACTION_READY")
            for _ in 0..<300 where saved == nil { try await Task.sleep(for: .seconds(1)) }
            XCTAssertNotNil(saved); XCTAssertTrue(saved?.designs.isEmpty == true); XCTAssertTrue(saved?.sources.isEmpty == true)
        }
    }

    func testLegacyPhotosFollowRaisedFrameOnceAndKeepSources() throws {
        let photo = try OiPhotoRenderer.asset(UIImage(cgImage: canvas { cg in
            cg.setFillColor(UIColor.orange.cgColor); cg.fill(CGRect(x: 0, y: 0, width: 1024, height: 512))
        }))
        let migrationLooks = looks + OiWardrobeLook.Top.allCases.map { top in
            var look = OiWardrobeLook(); look.top = top; return look
        }
        for look in migrationLooks {
            let layout = try OiPhotoPrintLayout.load(resource: OiPhotoSlot.top.resource(in: look))
            let layers = try OiPhotoSide.allCases.map { side in
                let old = try XCTUnwrap(side == .front ? layout.legacyFront : layout.legacyBack)
                var placement = old.placement(for: photo.image); placement.rotation = 23
                return OiPhotoLayer(source: photo.id, side: side, placement: placement)
            }
            let encoded = try JSONEncoder().encode(OiPhotoDesign(frameRevision: nil, layers: layers))
            let oldDesign = try JSONDecoder().decode(OiPhotoDesign.self, from: encoded)
            XCTAssertNil(oldDesign.frameRevision); XCTAssertTrue(oldDesign.isValid)
            let draft = try OiPhotoRenderer.load(oldDesign, sources: [photo.id: photo.data], layout: layout)
            for layer in draft.layers {
                let frame = layout[layer.side]
                XCTAssertEqual(layer.placement.x, frame.x+frame.width/2, accuracy: 0.00001)
                XCTAssertEqual(layer.placement.y, frame.y+frame.height/2, accuracy: 0.00001)
                XCTAssertEqual(layer.placement.rotation, 23)
                XCTAssertTrue(layer.isValid)
            }
            XCTAssertEqual(oldDesign.layers, layers, "Opening/cancelling must not modify the saved draft")
            let saved = OiPhotoDesign(layers: draft.layers)
            let reopened = try OiPhotoRenderer.load(JSONDecoder().decode(OiPhotoDesign.self, from: JSONEncoder().encode(saved)),
                sources: [photo.id: photo.data], layout: layout)
            XCTAssertEqual(reopened.layers, draft.layers, "Apply the frame move only once")
            XCTAssertEqual(reopened.assets[photo.id]?.data, photo.data)
        }
    }

    func testCostumePhotoVisualProof() async throws {
        let ink = canvas { cg in
            for y in 0..<8 { for x in 0..<16 {
                let color: UIColor = (x+y)%2 == 0 ? .systemCyan : .systemOrange
                cg.setFillColor(color.cgColor); cg.fill(CGRect(x: x*64, y: y*64, width: 64, height: 64))
            }}
            ("FRONT →" as NSString).draw(at: CGPoint(x: 90, y: 220), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 48), .foregroundColor: UIColor.black])
            ("BACK →" as NSString).draw(at: CGPoint(x: 610, y: 220), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 48), .foregroundColor: UIColor.black])
        }
        let scene = OiWardrobeScene(editingSlot: .top)
        let view = scene.install(); view.frame = CGRect(x: 0, y: 0, width: 500, height: 650)
        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: windowScene); let controller = UIViewController()
        controller.view = view; window.rootViewController = controller; window.makeKeyAndVisible()
        defer { scene.release(); window.isHidden = true }
        let requested = ProcessInfo.processInfo.environment["OI_PHOTO_PROOF_SET"].flatMap(OiWardrobeLook.Costume.init(rawValue:))
        var proofLooks = (requested.map({ [$0] }) ?? OiWardrobeLook.Costume.allCases).map { costume in
            var look = OiWardrobeLook(); look.costume = costume; return (costume.rawValue, look)
        }
        if requested == nil {
            proofLooks += OiWardrobeLook.Top.allCases.map { top in
                var look = OiWardrobeLook(); look.top = top; return ("plain-" + top.rawValue, look)
            }
        }
        for (name, look) in proofLooks {
            let detailed = ["dinosaur", "farmer", "cat-bear"].contains(name)
            scene.editPhotos(in: nil, look: look)
            for _ in 0..<300 where scene.loading { try await Task.sleep(for: .milliseconds(50)) }
            XCTAssertNil(scene.error); XCTAssertFalse(scene.loading)
            if detailed {
                scene.angle(0); try await Task.sleep(for: .milliseconds(700))
                let baseline: UIImage? = await withCheckedContinuation { c in view.snapshot(saveToHDR: false) { c.resume(returning: $0) } }
                let original = XCTAttachment(image: try XCTUnwrap(baseline))
                original.name = "original-\(name)-front"; original.lifetime = .keepAlways; add(original)
            }
            scene.editPhotos(in: .top, look: look)
            for _ in 0..<300 where scene.loading { try await Task.sleep(for: .milliseconds(50)) }
            XCTAssertNil(scene.error); XCTAssertFalse(scene.loading)
            let photo = try OiPhotoRenderer.asset(UIImage(cgImage: ink))
            let layout = try OiPhotoPrintLayout.load(resource: OiPhotoSlot.top.resource(in: look))
            let layers = OiPhotoSide.allCases.map { OiPhotoLayer(source: photo.id, side: $0, placement: layout[$0].placement(for: photo.image)) }
            let framed = OiPhotoRenderer.atlas(layers: layers, assets: [photo.id: photo], panelSize: 512,
                color: 0xFFFFFF, transparent: OiPhotoSlot.top.preservesOriginalMaterial(in: look), layout: layout)
            await scene.setPhotoPreview(try XCTUnwrap(framed.cgImage)); XCTAssertNil(scene.photoPreviewError)
            for (direction, angle) in [("front", Float(0)), ("side", .pi/3), ("back", .pi)] {
                if direction == "side" && !detailed { continue }
                scene.angle(angle); try await Task.sleep(for: .milliseconds(700))
                let image: UIImage? = await withCheckedContinuation { c in view.snapshot(saveToHDR: false) { c.resume(returning: $0) } }
                let screenshot = try XCTUnwrap(image)
                let attachment = XCTAttachment(image: screenshot); attachment.name = "photo-\(name)-\(direction)"; attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }
}
