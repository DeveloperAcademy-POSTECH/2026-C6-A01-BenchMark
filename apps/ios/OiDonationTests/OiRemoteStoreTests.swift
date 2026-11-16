//
//  OiRemoteStoreTests.swift
//  OiDonationTests
//
//  Created by 이돈혁 on 10/28/26.
//

import XCTest
import CryptoKit
import ARKit
import CoreLocation
import RealityKit
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
    func timeOut() { client?.urlProtocol(self, didFailWithError: URLError(.timedOut)) }
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
        var unapprovedDraftsEnabled: Bool? = true
        var independentStoryCreation: Bool? = true
        var publicCucumberAppearance = false
        var publicStoryCard = false
        var duplexStoryCard = false
        var storyCardCover = false
        var storyCardCoverJpeg = false
        var autoStoryModeration = false
        var rejectModeration = false
        var moderationCount = 0
        var storyReview: [String: Any]?
        var corruptSubmittedCoverType = false
        var corruptReviewedCoverType = false
        var reviewPayloads: [[String: Any]] = []
        var uploadContentTypes: [String: String] = [:]
        var failCardCoverUpload = false
        var failCardCoverRead = false
        var failCardBackUpload = false
        var failCardBackRead = false
        var failCucumberTextureUpload = false
        var timeOutCardUploadAfterCommit = false
        var timeOutSubmitAfterCommit = false
        var timeOutSubmitBeforeCommit = false
        var submitCount = 0
        var deleteCount = 0
        var failDelete = false
        var failReadsAfterDelete = false
        var artworkUploadAttempts = 0
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
        var holdModerationResponse = false
        var holdStorySubmissionResponse = false
        var ignoreStoryStatusFilter = false
        var auditRecords: [[String: Any]] = []
        var auditBodies: [[String: Any]] = []
        var auditStatus = 200
        var nfcTags: [[String: Any]] = []
        var nfcBodies: [[String: Any]] = []
        var nfcStatus = 200
        var nfcMismatchedReceipt = false
        var holdAuditRead = false
        var failRefreshToken = false
        var failLogout = false
        var logoutScopes: [String?] = []
        var cardSendResponse: [String: String] = [:]
        var cardSendPayloads: [[String: String]] = []
        var holdCardSend = false
        var holdOwnerRead = false
        var holdPostMergeRead = false
        var mergeConfirmCount = 0
        var didHold: (() -> Void)?
        var held: (OiStoreURLProtocol, Data)?
        var story: [String:Any]?
        var paths: [String] = []
        var uploads: [String:Data] = [:]
        var submittedTitle: String?
        var canonicalAccountID: UUID?
        var refreshSucceeds = false
        var refreshRequestCount = 0
        var grantOwnerQueries: [String] = []
        var retiredEvidenceRequests: [String] = []
        var catalogReads = 0
        var boundedMetricsStatus = 200
        var boundedMetricsIDs: [[String]] = []
        var legacyMetricsReads = 0
    }
    private var state = State()

    func configure(_ update: (inout State) -> Void) { lock.lock(); defer { lock.unlock() }; update(&state) }
    func snapshot() -> State { lock.lock(); defer { lock.unlock() }; return state }
    func releaseHeldRead() {
        let value = snapshot().held
        configure {
            $0.held = nil; $0.holdOwnerRead = false; $0.holdPostMergeRead = false
            $0.holdReviewResponse = false; $0.holdModerationResponse = false; $0.holdStorySubmissionResponse = false
            $0.holdAuditRead = false; $0.holdCardSend = false; $0.holdFarmWrite = false; $0.holdFarmerOutfitWrite = false
        }
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
        if path.hasSuffix("/oi_evidence_requests") || path.hasSuffix("/oi_review_evidence")
            || path.contains("/object/oi-evidence/") || path.hasSuffix("/analyze-evidence")
            || path.hasSuffix("/analyze-donation-evidence") {
            state.retiredEvidenceRequests.append(path)
            status = 410
        } else if path == "/auth/v1/token" {
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
        } else if path == "/functions/v1/delete-account" {
            if body["account_id"] as? String == Self.owner.uuidString,
               body["proof"] as? String == "token-a", body["consent"] as? Bool == true {
                result = ["deleted": true, "apple_revocation_required": false, "deleted_member_ids": [Self.owner.uuidString]]
            } else { status = 403 }
        } else if path.hasPrefix("/storage/v1/object/sign/") && (path.contains("/appearance/") || path.contains("/card/")) {
            let key = String(path.dropFirst("/storage/v1/object/sign/".count))
            if state.failCardCoverRead && (key.hasSuffix("/cover.png") || key.hasSuffix("/cover.jpg")) { status = 503 }
            else if state.failCardBackRead && (key.hasSuffix("/back-preview.png") || key.hasSuffix("/back.png")) { status = 503 }
            else if let image = state.uploads[key] {
                if request.httpMethod == "POST" { result = ["signedURL": String(path.dropFirst("/storage/v1".count)) + "?token=fixture"] }
                else { bytes = image }
            } else { status = 404 }
        } else if path.contains("/storage/v1/object/") {
            let key = path.replacingOccurrences(of: "/storage/v1/object/", with: "")
            if key.contains("/card/") || key.contains("/appearance/") { state.artworkUploadAttempts += 1 }
            if state.failCardCoverUpload && (key.hasSuffix("/cover.png") || key.hasSuffix("/cover.jpg")) { status = 503 }
            else if state.failCardBackUpload && key.hasSuffix("/back.png") { status = 503 }
            else if state.failCucumberTextureUpload && key.hasSuffix("/top.png") { status = 503 }
            else if state.uploads[key] != nil { status = 409 }
            else {
                state.uploads[key] = raw
                state.uploadContentTypes[key] = request.value(forHTTPHeaderField: "Content-Type")
                result = ["Key":key]
            }
            if status == 200, key.contains("/card/"), state.timeOutCardUploadAfterCommit {
                state.timeOutCardUploadAfterCommit = false
                lock.unlock(); client.timeOut(); return
            }
        } else if path.hasSuffix("/rpc/oi_my_story_reviews") {
            result = state.storyReview.map { [$0] } ?? []
        } else if path.hasSuffix("/rpc/oi_plant_story") {
            if let review = state.storyReview, review["status"] as? String == "approved",
               let revision = state.story?["revision"] as? Int,
               body["p_revision"] as? Int == revision, body["p_story"] as? String == state.story?["id"] as? String {
                state.story?["status"] = "published"
                state.story?["revision"] = revision + 1
                state.storyReview = nil
                result = state.story ?? [:]
            } else { status = 409 }
        } else if path.hasSuffix("/rpc/oi_mutate") || path.hasSuffix("/functions/v1/moderate-story") {
            let automated = path.hasSuffix("/functions/v1/moderate-story")
            let payload = automated ? body : (body["p_payload"] as? [String:Any] ?? [:])
            let action = automated ? "submit_story" : (body["p_action"] as? String ?? "")
            if action == "save_story" {
                var story = payload
                story["grant_id"] = state.story?["id"] as? String == payload["id"] as? String
                    ? state.story?["grant_id"] ?? NSNull() : NSNull()
                story["user_id"] = owner.uuidString
                story["status"] = "draft"
                story["revision"] = (payload["revision"] as? Int ?? 0)+1
                story["created_at"] = "2026-10-28T00:00:00Z"
                if state.story?["id"] as? String == payload["id"] as? String {
                    story["card_snapshot_id"] = state.story?["card_snapshot_id"]
                    story["card_snapshot_format"] = state.story?["card_snapshot_format"]
                    story["card_cover_type"] = state.story?["card_cover_type"]
                    story["cucumber_appearance"] = state.story?["cucumber_appearance"]
                }
                state.story = story; result = story
            } else if action == "attach_media" {
                state.paths = payload["paths"] as? [String] ?? []
                let nextRevision = (state.story?["revision"] as? Int ?? 0)+1
                state.story?["revision"] = nextRevision
                result = state.story ?? [:]
            } else if automated && state.rejectModeration {
                state.moderationCount += 1
                let review: [String: Any] = ["status": "rejected", "reason": "privacy", "source": "card",
                    "story_id": payload["id"] ?? "", "revision": payload["revision"] ?? 0]
                state.storyReview = review
                result = review
            } else if action == "submit_story" {
                if automated { state.moderationCount += 1 }
                state.submitCount += 1
                if state.timeOutSubmitBeforeCommit {
                    state.timeOutSubmitBeforeCommit = false
                    lock.unlock(); client.timeOut(); return
                }
                state.submittedTitle = state.story?["title"] as? String
                if let appearance = payload["cucumber_appearance"] { state.story?["cucumber_appearance"] = appearance }
                if let card = payload["card_snapshot_id"] { state.story?["card_snapshot_id"] = card }
                if let format = payload["card_snapshot_format"] {
                    state.story?["card_snapshot_format"] = format
                    state.story?["card_cover_type"] = (format as? Int) == 3 ? (payload["card_cover_type"] ?? "png") : nil
                }
                if state.corruptSubmittedCoverType { state.story?["card_cover_type"] = "png" }
                state.story?["status"] = automated ? "draft" : "pending"
                let nextRevision = (state.story?["revision"] as? Int ?? 0)+1
                state.story?["revision"] = nextRevision
                let story = state.story ?? [:]
                if automated {
                    let review: [String: Any] = ["status": "approved", "story_id": payload["id"] ?? "", "revision": nextRevision]
                    state.storyReview = review
                    result = review.merging(["story": story]) { existing, _ in existing }
                } else {
                    result = story
                }
                if state.timeOutSubmitAfterCommit {
                    state.timeOutSubmitAfterCommit = false
                    lock.unlock(); client.timeOut(); return
                }
            } else if action == "delete_story" {
                state.deleteCount += 1
                if state.failDelete { status = 503 }
                else if state.story?["id"] as? String != payload["id"] as? String ||
                            state.story?["revision"] as? Int != payload["revision"] as? Int { status = 409 }
                else {
                    let nextRevision = (state.story?["revision"] as? Int ?? 0) + 1
                    state.story?["status"] = "deleted"
                    state.story?["revision"] = nextRevision
                    result = state.story ?? [:]
                    if state.failReadsAfterDelete { state.failReads = true }
                }
            } else if action == "reopen_story" {
                state.story?["status"] = "draft"
                let nextRevision = (state.story?["revision"] as? Int ?? 0) + 1
                state.story?["revision"] = nextRevision
                result = state.story ?? [:]
            } else if action == "review_story" {
                state.reviewCount += 1
                state.reviewPayloads.append(payload)
                let wanted = payload["status"] as? String ?? ""
                if !state.isOperator { status = 403 }
                else if state.story?["revision"] as? Int != payload["revision"] as? Int { status = 409 }
                else if !["published", "hidden"].contains(wanted) { status = 400 }
                else if wanted == "published", let appearance = state.story?["cucumber_appearance"] as? [String: Any],
                        appearance["id"] as? String != payload["appearance_id"] as? String { status = 409 }
                else if wanted == "published", let card = state.story?["card_snapshot_id"] as? String,
                        card != payload["card_snapshot_id"] as? String { status = 409 }
                else if wanted == "published", state.story?["card_cover_type"] as? String == "jpeg",
                        payload["card_cover_type"] as? String != "jpeg" { status = 409 }
                else {
                    state.story?["status"] = wanted
                    let nextRevision = (state.story?["revision"] as? Int ?? 0) + 1
                    state.story?["revision"] = nextRevision
                    var reviewed = state.story ?? [:]
                    if state.corruptReviewedCoverType { reviewed["card_cover_type"] = "png" }
                    result = reviewed
                    if state.failAfterReview { state.failReads = true }
                    if state.loseReviewResponse { status = 503; state.loseReviewResponse = false }
                }
            } else { result = ["id":payload["id"] ?? ""] }
        } else if path.hasSuffix("/rpc/oi_operator_nfc_tags") {
            status = state.isOperator ? state.nfcStatus : 403
            result = state.nfcTags
        } else if path.hasSuffix("/rpc/oi_operator_set_nfc_tag") {
            state.nfcBodies.append(body)
            status = state.isOperator ? state.nfcStatus : 403
            let story = body["p_story"] as? String
            var row: [String: Any] = ["tag_id": body["p_tag"] ?? "", "story_id": story.map { $0 as Any } ?? NSNull(),
                                      "active": state.nfcMismatchedReceipt ? !(body["p_active"] as? Bool ?? true) : body["p_active"] ?? true,
                                      "note": body["p_note"] ?? "", "updated_at": "2026-11-13T09:00:00Z"]
            if status == 200 {
                state.nfcTags.removeAll { $0["tag_id"] as? String == body["p_tag"] as? String }
                row["story_title"] = story == nil ? NSNull() : "Fixture story"
                row["story_status"] = story == nil ? NSNull() : "published"
                state.nfcTags.append(row)
            }
            result = row
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
            if let independent = state.independentStoryCreation { capabilities["independent_story_creation"] = independent }
            if state.publicCucumberAppearance { capabilities["public_cucumber_appearance"] = true }
            if state.publicStoryCard { capabilities["public_story_card"] = true }
            if state.duplexStoryCard { capabilities["duplex_story_card"] = true }
            if state.storyCardCover { capabilities["story_card_cover"] = true }
            if state.storyCardCoverJpeg { capabilities["story_card_cover_jpeg"] = true }
            if state.autoStoryModeration { capabilities["auto_story_moderation"] = true }
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
        else if path.hasSuffix("/rpc/oi_collection_metrics_for_stories") {
            let ids = body["p_story_ids"] as? [String] ?? []
            state.boundedMetricsIDs.append(ids)
            status = state.boundedMetricsStatus
            result = ids.map { ["story_id": $0, "collection_count": 3] }
        }
        else if path.hasSuffix("/rpc/oi_collection_metrics") {
            state.legacyMetricsReads += 1
            if let id = state.story?["id"] as? String, state.story?["status"] as? String == "published" {
                result = [["story_id": id, "collection_count": 3]]
            }
        }
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
            state.catalogReads += 1
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
        } else if path.hasSuffix("/oi_writing_grants") {
            if let url = request.url,
               let owner = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "user_id" })?.value {
                state.grantOwnerQueries.append(owner)
            }
            result = state.hasWritingGrant ? [["id":Self.grant.uuidString,"story_limit":5]] : []
        }
        let data = bytes ?? ((try? JSONSerialization.data(withJSONObject: result)) ?? Data())
        if (path.hasSuffix("/oi_stories") && owner == Self.owner && state.holdOwnerRead)
            || (path.hasSuffix("/rpc/oi_mutate") && body["p_action"] as? String == "review_story" && state.holdReviewResponse)
            || (path.hasSuffix("/functions/v1/moderate-story") && state.holdModerationResponse)
            || (path.hasSuffix("/rpc/oi_mutate") && body["p_action"] as? String == "submit_story" && state.holdStorySubmissionResponse)
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
    @MainActor func testEducationBridgeUsesExistingAccountAndOnlyEducationRPC() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        await store.start()
        let response = try await store.educationRequest("identity", values: [:])
        let identity = try XCTUnwrap(response as? [String: Any])
        XCTAssertEqual(identity["id"] as? String, OiTestBackend.owner.uuidString.lowercased())
        XCTAssertEqual(identity["canWrite"] as? Bool, true)
        OiStoreURLProtocol.handle = { request, client in
            XCTAssertEqual(request.url?.path, "/rest/v1/rpc/oi_education_stories")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-a")
            client.respond(200, Data("[]".utf8))
        }
        let rows = try await store.educationRequest("rpc", values: ["name": "oi_education_stories", "payload": ["p_mine": true]])
        XCTAssertEqual((rows as? [Any])?.count, 0)
        for values: [String: Any] in [
            ["name": "oi_mutate", "payload": [:]],
            ["name": "oi_operator_set_nfc_tag", "payload": [:]]
        ] {
            do { _ = try await store.educationRequest("rpc", values: values); XCTFail("Other channels must stay outside the bridge") }
            catch { XCTAssertTrue(error is OiServiceError) }
        }
        do { _ = try await store.educationRequest("media", values: ["path": "owner/story/card.png"]); XCTFail("Campus paths must be rejected") }
        catch { XCTAssertTrue(error is OiServiceError) }
    }

    @MainActor func testEducationBridgeAllowsAnonymousReadingButRequiresSignInToWrite() async throws {
        let (store, backend, vault, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        try vault.write(nil)
        OiStoreURLProtocol.handle = { request, client in
            XCTAssertEqual(request.url?.path, "/rest/v1/rpc/oi_education_stories")
            XCTAssertNotEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-a")
            client.respond(200, Data("[]".utf8))
        }
        _ = try await store.educationRequest("rpc", values: ["name": "oi_education_stories", "payload": [:]])
        do { _ = try await store.educationRequest("rpc", values: ["name": "oi_education_mutate", "payload": [:]]); XCTFail("Anonymous writes must fail") }
        catch { XCTAssertTrue(error is OiServiceError) }
    }

    @MainActor func testEducationBridgeDiscardsPrivateResponseAfterSignOut() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        await store.start()
        let original = OiStoreURLProtocol.handle
        let requested = expectation(description: "Private education request held")
        var held: OiStoreURLProtocol?
        OiStoreURLProtocol.handle = { request, client in
            if request.url?.path == "/rest/v1/rpc/oi_education_story" { held = client; requested.fulfill() }
            else { original?(request, client) }
        }
        let pending = Task { try await store.educationRequest("rpc", values: ["name": "oi_education_story", "payload": ["p_id": UUID().uuidString]]) }
        await fulfillment(of: [requested], timeout: 2)
        await store.signOut()
        held?.respond(200, Data("{\"body\":\"synthetic private story\"}".utf8))
        do { _ = try await pending.value; XCTFail("An old account's private response must not reach JavaScript") }
        catch { guard case OiServiceError.accountChanged = error else { return XCTFail(String(describing: error)) } }
    }

    @MainActor func testExistingAccountStartsAndRefreshesWithoutDonationEvidence() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        await store.start()
        await store.refresh()
        XCTAssertTrue(store.hasLoadedRemote)
        XCTAssertTrue(store.canStartStory)
        XCTAssertTrue(backend.snapshot().retiredEvidenceRequests.isEmpty)
    }

    @MainActor func testPollingReusesCatalogWithoutRepublishingUnchangedData() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        await store.start()
        let firstRevision = store.revision
        let firstCatalogReads = backend.snapshot().catalogReads

        await store.refresh(reuseCatalog: true)
        XCTAssertEqual(backend.snapshot().catalogReads, firstCatalogReads)
        XCTAssertEqual(store.revision, firstRevision)

        backend.configure { $0.includesSecondSchool = true }
        await store.refresh()
        XCTAssertEqual(backend.snapshot().catalogReads, firstCatalogReads + 1)
        XCTAssertTrue(store.schools.contains { $0.id == "other" })
        XCTAssertGreaterThan(store.revision, firstRevision)
    }

    @MainActor func testBoundedMetricsOnlyFallbackForMissingRPCAndStopReadingHiddenStories() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        await store.start()
        let saved = await store.save(draft())
        let id = try XCTUnwrap(saved?.id)
        XCTAssertTrue(backend.snapshot().boundedMetricsIDs.isEmpty)

        backend.configure { $0.story?["status"] = "published"; $0.boundedMetricsStatus = 503 }
        await store.refresh()
        XCTAssertNil(store.loadError)
        XCTAssertNotNil(store.syncWarning)
        XCTAssertEqual(store.stories.map(\.id), [id])
        XCTAssertEqual(backend.snapshot().legacyMetricsReads, 0)

        backend.configure { $0.boundedMetricsStatus = 200 }
        await store.refresh()
        XCTAssertNil(store.loadError)
        XCTAssertNil(store.syncWarning)
        XCTAssertEqual(store.collectionCounts[id], 3)
        XCTAssertEqual(backend.snapshot().boundedMetricsIDs.last, [id.uuidString])

        backend.configure { $0.boundedMetricsStatus = 404 }
        await store.refresh()
        XCTAssertNil(store.loadError)
        XCTAssertEqual(store.collectionCounts[id], 3)
        XCTAssertEqual(backend.snapshot().legacyMetricsReads, 1)

        backend.configure { $0.story?["status"] = "hidden" }
        await store.refresh(reuseCatalog: true)
        XCTAssertTrue(store.stories.isEmpty)
        XCTAssertTrue(store.collectionCounts.isEmpty)
        XCTAssertEqual(backend.snapshot().legacyMetricsReads, 1)
    }

    @MainActor func testBoundedMetricsPagesAtMostTwoHundredIDs() async throws {
        let (_, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        let api = try OiServiceAPI(key: "sb_publishable_testing", session: session)
        let ids = (1...201).map { _ in UUID() }
        let metrics = try await api.collectionMetrics(for: ids, token: nil)
        XCTAssertEqual(metrics.map(\.storyId), ids)
        XCTAssertEqual(backend.snapshot().boundedMetricsIDs.map(\.count), [200, 1])
    }

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

    @MainActor func testOperatorNFCTagsListAndSaveSendExactValues() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        let story = UUID(uuidString: "b1000000-0000-4000-8000-0000000000aa")!
        backend.configure {
            $0.isOperator = true
            $0.nfcTags = [["tag_id": "pond-01", "story_id": story.uuidString.lowercased(), "active": true, "note": "연못 벤치",
                           "updated_at": "2026-11-13T08:00:00Z", "story_title": "연못 이야기", "story_status": "published"],
                          ["tag_id": "lib-02", "story_id": NSNull(), "active": false, "note": "",
                           "updated_at": NSNull(), "story_title": NSNull(), "story_status": NSNull()]]
        }
        await store.start()
        let tags = try await store.operatorNFCTags()
        XCTAssertEqual(tags.map(\.tagId), ["pond-01", "lib-02"])
        XCTAssertTrue(tags[0].opensPostcard); XCTAssertEqual(tags[0].storyId, story)
        XCTAssertFalse(tags[1].opensPostcard); XCTAssertEqual(tags[1].statusText, "중지됨")
        XCTAssertEqual(tags[0].url.absoluteString, "https://appclip.apple.com/id?p=com.Spero.OiDonation.Clip&postcard=pond-01")

        let receipt = try await store.setNFCTag("lib-02", story: story, active: true, note: "  도서관 입구  ")
        XCTAssertEqual(receipt.storyId, story); XCTAssertTrue(receipt.active)
        let body = try XCTUnwrap(backend.snapshot().nfcBodies.last)
        XCTAssertEqual(body["p_tag"] as? String, "lib-02")
        XCTAssertEqual(body["p_story"] as? String, story.uuidString.lowercased())
        XCTAssertEqual(body["p_active"] as? Bool, true)
        XCTAssertEqual(body["p_note"] as? String, "도서관 입구")

        _ = try await store.setNFCTag("pond-01", story: nil, active: false, note: "")
        XCTAssertTrue(backend.snapshot().nfcBodies.last?["p_story"] is NSNull, "Unlinking sends an explicit null story")
    }

    func testOperatorNFCTagSuggestionIsValidUnambiguousAndUnused() {
        let taken: Set<String> = ["oi-aaaaaa"]
        for _ in 0..<200 {
            let id = OiNFCTagID.suggestion(avoiding: taken)
            XCTAssertTrue(AppClipLink.isValidPostcardTag(id), id)
            XCTAssertTrue(id.hasPrefix("oi-")); XCTAssertEqual(id.count, 9)
            XCTAssertFalse(taken.contains(id))
            XCTAssertTrue(id.dropFirst(3).allSatisfy { !"0o1li".contains($0) }, id)
        }
    }

    @MainActor func testOperatorNFCTagsRejectInvalidInputMissingRPCAndMismatchedReceipt() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.isOperator = true }
        await store.start()
        do { _ = try await store.setNFCTag("Pond 01", story: nil, active: true, note: ""); XCTFail("Invalid tag must not be sent") }
        catch { XCTAssertEqual(error as? OiNFCTagError, .invalidTag) }
        XCTAssertTrue(backend.snapshot().nfcBodies.isEmpty)

        backend.configure { $0.nfcStatus = 404 }
        do { _ = try await store.operatorNFCTags(); XCTFail("Missing RPC must be reported") }
        catch { XCTAssertEqual(error as? OiNFCTagError, .notDeployed) }

        backend.configure { $0.nfcStatus = 200; $0.nfcMismatchedReceipt = true }
        do { _ = try await store.setNFCTag("pond-01", story: nil, active: true, note: ""); XCTFail("Receipt must match the request") }
        catch { XCTAssertEqual(error as? OiNFCTagError, .mismatchedReceipt) }

        backend.configure { $0.nfcMismatchedReceipt = false; $0.isOperator = false }
        do { _ = try await store.operatorNFCTags(); XCTFail("Non-operators must not read tags") }
        catch { XCTAssertNotEqual(error as? OiNFCTagError, .notDeployed) }
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
        let readsBeforeWrite = backend.snapshot().schoolProfileReads
        await store.updateSchoolProfile(schoolID: "postech", admissionYear: 2020, department: "  Computer Science  ")
        XCTAssertNil(store.error)
        XCTAssertEqual(backend.snapshot().schoolProfileReads, readsBeforeWrite, "A valid write receipt must not wait for a full refresh")
        XCTAssertEqual(store.profiles.first { $0.id == OiTestBackend.owner }?.schoolId, "postech")
        XCTAssertNil(store.profiles.first { $0.id == OiTestBackend.owner }?.schoolAdmissionYear)
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

    @MainActor func testLegacyOpaqueCardPortraitRegeneratesWithoutChangingTheDraft() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        await store.start()
        let owner = OiTestBackend.owner
        let original = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 60)).image { context in
            UIColor.black.setFill(); context.fill(CGRect(x: 0, y: 0, width: 40, height: 60))
        }
        let photoID = UUID()
        let photo = try XCTUnwrap(original.pngData())
        try await store.saveLocalPhoto(photo, id: photoID, owner: owner)
        var customization = OiDraftCustomization()
        let look = OiWardrobeLook()
        customization.wardrobe = look
        var card = OiCardDesign()
        card.portraitPNG = photo
        card.portraitKey = "portrait-v4-bright4-skin-old-opaque-cache"
        card.characterOrientation = OiCardOrientation(yaw: 0.2, pitch: 0.1)
        card.characterPlacement = OiCardPlacement(x: 0.4, y: 0.6, scale: 0.8)
        card.characterBackdropEnabled = false
        card.characterBackdropColor = 0x845F77
        card.postcardLayoutVersion = 2
        card.postcardBackground = OiPostcardBackgroundStyle(color: 0xEECFDF)
        card.postcardDate = Date(timeIntervalSince1970: 1_794_700_000)
        customization.card = card
        let local = OiLocalDraft(draft: draft(title: "불투명 캐시 복원 확인"), photos: [photoID], version: 1,
            creationStep: OiCreationStep.card.rawValue, customization: customization)
        try await store.saveLocalDraft(local, owner: owner)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKey = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: NavigationStack {
            OiStoryEditor(remote: store, localID: local.id).environment(\.scenePhase, .active)
        })
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; window.windowScene = nil; previousKey?.makeKey() }
        var regenerated: OiLocalDraft?
        for _ in 0..<200 {
            try await Task.sleep(for: .milliseconds(100))
            let current = try await store.localDraft(id: local.id, owner: owner)
            if current?.customization?.card?.portraitKey?.hasPrefix("transparent-matte-v1-") == true {
                regenerated = current; break
            }
        }
        let saved = try XCTUnwrap(regenerated, "Opening an old card draft must regenerate its derived portrait")
        let savedCard = try XCTUnwrap(saved.customization?.card)
        let png = try XCTUnwrap(savedCard.portraitPNG)
        XCTAssertTrue(OiPortraitMatte.hasTransparentBackground(try XCTUnwrap(UIImage(data: png))))
        XCTAssertNotEqual(png, photo)
        XCTAssertEqual(saved.draft, local.draft)
        XCTAssertEqual(saved.photos, local.photos)
        XCTAssertEqual(saved.customization?.wardrobe, look)
        var expected = card
        expected.portraitPNG = savedCard.portraitPNG
        expected.portraitKey = savedCard.portraitKey
        XCTAssertEqual(savedCard, expected, "Regeneration must preserve card settings and orientation")
        let restoredPhoto = try await store.localPhoto(id: photoID, owner: owner)
        XCTAssertEqual(restoredPhoto, photo)
        XCTAssertNil(backend.snapshot().story, "A local portrait repair must not submit or change a server story")
    }

    /// Figma `5400:7726`: STEP 2 keeps its buttons at the end of the scroll; Next with missing input
    /// stays on the step and lists what is missing under the buttons (#373).
    @MainActor func testStoryNextShowsMissingItemsUnderInlineButtons() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        await store.start()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        func scrollViews(_ view: UIView) -> [UIScrollView] {
            (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
        }
        let local = OiLocalDraft(draft: draft(title: "스크롤 버튼 확인"), version: 1,
            creationStep: OiCreationStep.story.rawValue)
        try await store.saveLocalDraft(local, owner: OiTestBackend.owner)
        var panelVisible = false
        var actions: OiStoryEditor.NavigationTestActions?
        let controller = UIHostingController(rootView: NavigationStack {
            OiStoryEditor(remote: store, localID: local.id)
                .observeNavigationForTest({ panelVisible = $0 }, actions: { actions = $0 })
        })
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = controller; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil; window.windowScene = nil }
        try await Task.sleep(for: .seconds(2))
        XCTAssertFalse(panelVisible, "STEP 2 must not float a navigation panel")
        XCTAssertEqual(try XCTUnwrap(actions).shownMissingItems(), [], "Missing items stay hidden before Next")
        try XCTUnwrap(actions).next()
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(try XCTUnwrap(actions).currentStep(), .story, "Next with missing input must stay on STEP 2")
        XCTAssertTrue(try XCTUnwrap(actions).shownMissingItems().contains("사진은 1장 이상 추가해주세요 (대표이미지)"))
        let scroll = try XCTUnwrap(scrollViews(controller.view).filter { $0.bounds.height > 100 }
            .max { $0.bounds.height < $1.bounds.height })
        let end = max(-scroll.adjustedContentInset.top,
            scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height)
        // The buttons and messages end above the 24pt content padding.
        XCTAssertGreaterThan(scroll.contentOffset.y, end - 40, "Next must scroll the missing items into view")
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image); attachment.name = "story-missing-items-under-buttons"
        attachment.lifetime = .keepAlways; add(attachment)
    }

    /// STEP 1 ↔ STEP 2 switch both ways without a slide; pauses leave room for a screen recording (#373).
    @MainActor func testConsentStoryTransitionGoesBothWays() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        await store.start()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let local = OiLocalDraft(draft: draft(title: "전환 확인"), version: 1, creationStep: OiCreationStep.consent.rawValue,
            agreedConsentClauseIDs: Set(OiStoryConsentClause.ID.allCases.map(\.rawValue)))
        try await store.saveLocalDraft(local, owner: OiTestBackend.owner)
        var actions: OiStoryEditor.NavigationTestActions?
        let controller = UIHostingController(rootView: NavigationStack {
            OiStoryEditor(remote: store, localID: local.id).observeNavigationForTest({ _ in }, actions: { actions = $0 })
        })
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; window.windowScene = nil }
        try await Task.sleep(for: .seconds(5)) // past the launch splash
        // Pauses let a screen recording show forward, backward and the next step separately.
        try XCTUnwrap(actions).next()
        try await Task.sleep(for: .seconds(1.5))
        XCTAssertEqual(try XCTUnwrap(actions).currentStep(), .story)
        try XCTUnwrap(actions).editFromReview(.consent)
        try await Task.sleep(for: .seconds(1.5))
        XCTAssertEqual(try XCTUnwrap(actions).currentStep(), .consent)
        try XCTUnwrap(actions).next()
        try await Task.sleep(for: .seconds(1.5))
        XCTAssertEqual(try XCTUnwrap(actions).currentStep(), .story)
    }

    /// Opening the photo editor while typing must not leave the story keyboard over it (#373).
    @MainActor func testOpeningPhotoEditorEndsStoryTyping() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        await store.start()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        func textViews(_ view: UIView) -> [UITextView] {
            (view as? UITextView).map { [$0] } ?? view.subviews.flatMap(textViews)
        }
        let local = OiLocalDraft(draft: draft(title: "키보드 확인"), version: 1, creationStep: OiCreationStep.story.rawValue)
        try await store.saveLocalDraft(local, owner: OiTestBackend.owner)
        var photoActions: OiStoryEditor.PhotoEditingTestActions?
        let controller = UIHostingController(rootView: NavigationStack {
            OiStoryEditor(remote: store, localID: local.id).observePhotoEditingForTest { photoActions = $0 }
        })
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; window.windowScene = nil }
        try await Task.sleep(for: .seconds(2))
        let body = try XCTUnwrap(textViews(controller.view).first { $0.accessibilityIdentifier == "oi.draft.body" })
        XCTAssertTrue(body.becomeFirstResponder())
        try await Task.sleep(for: .milliseconds(400))
        try XCTUnwrap(photoActions).open()
        try await Task.sleep(for: .seconds(1))
        XCTAssertFalse(body.isFirstResponder, "The story keyboard must close when the photo editor opens")
        try XCTUnwrap(photoActions).cancel()
        try await Task.sleep(for: .seconds(1))
        XCTAssertFalse(body.isFirstResponder, "Closing the photo editor must not bring the keyboard back")
    }

    @MainActor func testCustomizationNavigationRequiresDoneAndCardNextOpensPlacement() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        await store.start()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        for step in [OiCreationStep.cucumber, .card] {
            let local = OiLocalDraft(draft: draft(title: "완료 후 이동 확인"), version: 1, creationStep: step.rawValue)
            try await store.saveLocalDraft(local, owner: OiTestBackend.owner)
            var visible = false
            var actions: OiStoryEditor.NavigationTestActions?
            let controller = UIHostingController(rootView: NavigationStack {
                OiStoryEditor(remote: store, localID: local.id)
                    .observeNavigationForTest({ visible = $0 }, actions: { actions = $0 })
            })
            let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            window.rootViewController = controller; window.isHidden = false
            defer { window.isHidden = true; window.rootViewController = nil; window.windowScene = nil }
            try await Task.sleep(for: .seconds(2))
            XCTAssertFalse(visible, "Editing must not reveal navigation")
            func verticalScrolls(_ view: UIView) -> [UIScrollView] {
                let own = (view as? UIScrollView).map { [$0] } ?? []
                return own + view.subviews.flatMap(verticalScrolls)
            }
            let settings = try XCTUnwrap(verticalScrolls(controller.view).filter {
                $0.bounds.height > 80 && $0.contentSize.height > $0.bounds.height + 20
            }.max { $0.bounds.height < $1.bounds.height })
            let frame = settings.convert(settings.bounds, to: window)
            XCTAssertGreaterThan(frame.minY, 200, "Settings must sit below the fixed preview and tabs")
            XCTAssertEqual(frame.maxY, window.bounds.maxY, accuracy: 1,
                "Editing settings must scroll all the way to the screen bottom")
            for scrolled in [false, true] {
                settings.setContentOffset(CGPoint(x: 0, y: scrolled
                    ? max(0, settings.contentSize.height - settings.bounds.height + settings.adjustedContentInset.bottom)
                    : -settings.adjustedContentInset.top), animated: false)
                try await Task.sleep(for: .milliseconds(300))
                XCTAssertFalse(visible, "Scrolling settings must not bypass Done")
                XCTAssertEqual(settings.convert(settings.bounds, to: window).minY, frame.minY, accuracy: 1)
                let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                let proof = XCTAttachment(image: screenshot)
                proof.name = "customization-panel-\(step)-\(scrolled ? "scrolled" : "top")"
                proof.lifetime = .keepAlways; add(proof)
            }

            if step == .card {
                // Figma `5887:10243`: STEP 4 Done saves locally and opens the completion summary (#377).
                try XCTUnwrap(actions).finish()
                try await Task.sleep(for: .seconds(1))
                XCTAssertTrue(try XCTUnwrap(actions).isCompletion(), "Card Done must open the completion view")
                XCTAssertFalse(try XCTUnwrap(actions).isPlacementPreview())
                XCTAssertNil(backend.snapshot().story, "Card Done must not submit a story")
                let saved = try await store.localDraft(id: local.id, owner: OiTestBackend.owner)
                XCTAssertNotNil(saved, "Card Done must keep the draft on this device")
                let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                let attachment = XCTAttachment(image: image); attachment.name = "story-completion-view"
                attachment.lifetime = .keepAlways; add(attachment)
                continue
            }
            try XCTUnwrap(actions).finish()
            try await Task.sleep(for: .seconds(1))
            XCTAssertTrue(visible, "Done must reveal navigation without scrolling")
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image); attachment.name = "step-navigation-\(step)-after-done"
            attachment.lifetime = .keepAlways; add(attachment)
            try XCTUnwrap(actions).finish()
            try await Task.sleep(for: .milliseconds(400))
            XCTAssertFalse(visible, "Editing again must hide navigation")
            try XCTUnwrap(actions).finish()
            try await Task.sleep(for: .milliseconds(200))
            try XCTUnwrap(actions).next()
            try await Task.sleep(for: .milliseconds(400))
            XCTAssertFalse(visible, "Next must leave the finished customization panel")
            if step == .card {
                XCTAssertTrue(try XCTUnwrap(actions).isPlacementPreview())
                try XCTUnwrap(actions).editFromReview(.card)
                try await Task.sleep(for: .milliseconds(400))
                XCTAssertFalse(try XCTUnwrap(actions).isPlacementPreview(),
                    "Editing the current card from review must reopen its controls")
                XCTAssertFalse(visible)
                try XCTUnwrap(actions).finish()
                try await Task.sleep(for: .milliseconds(400))
                XCTAssertTrue(visible, "The corrected card must keep its Done navigation flow")
                XCTAssertNil(backend.snapshot().story, "Editing from review must not submit a story")
            }
        }
    }

    /// Figma `5887:10243`: STEP 4 Done saves locally, shows the completion view, and its Done returns to the list (#377).
    @MainActor func testCardDoneShowsCompletionAndReturnsToList() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        await store.start()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        var local = OiLocalDraft(draft: draft(title: "접수 완료 뷰"), version: 1, creationStep: OiCreationStep.card.rawValue)
        local.draft.cucumberName = "기계이일구오이"
        try await store.saveLocalDraft(local, owner: OiTestBackend.owner)
        var actions: OiStoryEditor.NavigationTestActions?
        var finished = false
        let controller = UIHostingController(rootView: NavigationStack {
            OiStoryEditor(remote: store, localID: local.id, onFinish: { finished = true })
                .observeNavigationForTest({ _ in }, actions: { actions = $0 })
        })
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = controller; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil; window.windowScene = nil }
        try await Task.sleep(for: .seconds(2))
        XCTAssertFalse(try XCTUnwrap(actions).isCompletion())
        try XCTUnwrap(actions).finish()
        try await Task.sleep(for: .seconds(1))
        XCTAssertTrue(try XCTUnwrap(actions).isCompletion(), "Card Done must open the completion view")
        XCTAssertNil(backend.snapshot().story, "Card Done must not submit a story")
        let saved = try await store.localDraft(id: local.id, owner: OiTestBackend.owner)
        XCTAssertEqual(saved?.draft.cucumberName, "기계이일구오이", "Card Done must keep the draft on this device")
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image); attachment.name = "story-completion-view"
        attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertFalse(finished)
        try XCTUnwrap(actions).completionDone()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(finished, "Completion Done must return to the story list")
    }

    @MainActor func testStepOneExitSavesDraftAndKeepsItOnSaveFailure() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        await store.start()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        for fails in [false, true] {
            let local = OiLocalDraft(draft: draft(title: "약관 화면 나가기"), version: 1,
                creationStep: OiCreationStep.consent.rawValue,
                agreedConsentClauseIDs: OiStoryConsentState().savedIDs,
                personalPlacement: .init(regionID: "test", name: "내 오이", latitude: 36, longitude: 129,
                    heightMeters: 1.5, headingDegrees: 0))
            try await store.saveLocalDraft(local, owner: OiTestBackend.owner)
            var actions: OiStoryEditor.NavigationTestActions?
            let controller = UIHostingController(rootView: NavigationStack {
                OiStoryEditor(remote: store, localID: local.id)
                    .observeNavigationForTest({ _ in }, actions: { actions = $0 })
            })
            let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            window.rootViewController = controller; window.isHidden = false
            defer { window.isHidden = true; window.rootViewController = nil; window.windowScene = nil }
            try await Task.sleep(for: .seconds(1))
            let backup = directory.appendingPathExtension("backup")
            if fails {
                try FileManager.default.moveItem(at: directory, to: backup)
                try Data("blocked storage".utf8).write(to: directory)
            }
            let saved = await (try XCTUnwrap(actions)).exit()
            XCTAssertEqual(saved, !fails)
            if fails {
                XCTAssertNotNil(controller.view.window, "A failed save must keep the editor mounted")
                try FileManager.default.removeItem(at: directory)
                try FileManager.default.moveItem(at: backup, to: directory)
            }
            let loaded = try await store.localDraft(id: local.id, owner: OiTestBackend.owner)
            let restored = try XCTUnwrap(loaded)
            XCTAssertEqual(restored.draft, local.draft)
            XCTAssertEqual(restored.personalPlacement, local.personalPlacement, "Exit must not delete a map placement")
            XCTAssertEqual(restored.creationStep, OiCreationStep.consent.rawValue)
            XCTAssertNil(backend.snapshot().story, "Exit saves locally and must not submit a story")
        }
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
            let isEditingPhotos = window.rootViewController?.presentedViewController != nil
            XCTAssertNil(backend.snapshot().story, "Photo and location edits never submit to server")
            if isEditingPhotos && saved.photos != local.photos { sawEdit = true }
            if sawEdit && !isEditingPhotos && saved.creationStep == OiCreationStep.story.rawValue && !sawCancel {
                XCTAssertEqual(saved.photos, local.photos, "Cancel restores all original attachments")
                let bytes = try await store.localPhoto(id: first, owner: OiTestBackend.owner)
                XCTAssertEqual(bytes, image, "Edits keep the original photo copy intact")
                sawCancel = true
            }
            if sawCancel && !isEditingPhotos && saved.creationStep == OiCreationStep.story.rawValue && saved.photos.count == 1 { sawDone = true }
            if sawDone && saved.creationStep == OiCreationStep.location.rawValue { sawLocation = true }
            if sawLocation && saved.creationStep == OiCreationStep.story.rawValue {
                XCTAssertEqual(saved.draft.latitude, local.draft.latitude)
                XCTAssertEqual(saved.draft.longitude, local.draft.longitude)
                XCTAssertEqual(saved.photos.count, 1)
                return
            }
        }
        XCTFail("Photo/location UI route did not finish (edited: \(sawEdit), cancelled: \(sawCancel), saved: \(sawDone), picked location: \(sawLocation))")
    }

    #if DEBUG
    /// Restores the real photo cover and drives its editor handlers with server and device photos.
    @MainActor func testPhotoReorderCancelDoneAndReopenWithMixedPhotos() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        await store.start()
        let image = try XCTUnwrap(UIImage(named: "DonationCampus")?.jpegData(compressionQuality: 0.9))
        let serverID = UUID(), localA = UUID(), localB = UUID()
        let savedReceipt = await store.save(draft(title: "사진 순서 검증"))
        let saved = try XCTUnwrap(savedReceipt)
        let attachedReceipt = await store.uploadStoryImage(image, photoID: serverID, story: saved)
        let attached = try XCTUnwrap(attachedReceipt)
        for id in [localA, localB] { try await store.saveLocalPhoto(image, id: id, owner: OiTestBackend.owner) }
        let serverPaths = store.mediaPaths(storyID: saved.id)
        XCTAssertEqual(serverPaths.count, 1)
        let local = OiLocalDraft(draft: OiStoryDraft(story: attached), photos: [localA, localB], version: 1,
                                creationStep: OiCreationStep.photos.rawValue)
        try await store.saveLocalDraft(local, owner: OiTestBackend.owner)

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previousKey = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        var actions: OiStoryEditor.PhotoEditingTestActions?
        defer {
            actions = nil
            window.isHidden = true
            window.rootViewController = nil
            window.windowScene = nil
            previousKey?.makeKey()
        }

        func mountEditor() {
            actions = nil
            window.rootViewController = UIHostingController(rootView: NavigationStack {
                OiStoryEditor(remote: store, localID: local.id)
                    .observePhotoEditingForTest { actions = $0 }
                    .environment(\.scenePhase, .active)
            })
            window.makeKeyAndVisible()
        }
        func savedDraft() async throws -> OiLocalDraft {
            let value = try await store.localDraft(id: local.id, owner: OiTestBackend.owner)
            return try XCTUnwrap(value)
        }
        func photoEditorIsPresented() -> Bool { window.rootViewController?.presentedViewController != nil }
        func waitFor(_ label: String, _ condition: () async throws -> Bool) async throws {
            for _ in 0..<100 {
                if try await condition() { return }
                try await Task.sleep(for: .milliseconds(100))
            }
            XCTFail("Timed out: \(label)")
            throw CancellationError()
        }
        func reopen(expectedOrder: [String]) async throws -> OiStoryEditor.PhotoEditingTestActions {
            try await waitFor("photo editor closed") { !photoEditorIsPresented() }
            try await waitFor("story editor mounted") { actions != nil }
            let current = try XCTUnwrap(actions)
            try await waitFor("saved photo order restored") { current.items().map(\.orderKey) == expectedOrder }
            current.open()
            try await waitFor("photo editor reopened") { photoEditorIsPresented() }
            XCTAssertEqual(current.items().map(\.orderKey), expectedOrder)
            return current
        }

        let server = serverID.uuidString, a = localA.uuidString, b = localB.uuidString
        let originalOrder = [server, a, b], reordered = [a, server, b]

        // A legacy draft saved in the photo step opens the cover over the story form.
        mountEditor()
        try await waitFor("photo editor restored") { photoEditorIsPresented() && actions != nil }
        var controls = try XCTUnwrap(actions)
        XCTAssertEqual(controls.items().map(\.orderKey), originalOrder)
        controls.move(try XCTUnwrap(controls.items().first), 1)
        try await waitFor("reorder saved") { try await savedDraft().photoOrder == reordered }
        controls.cancel()
        try await waitFor("cancel restores order") {
            let draft = try await savedDraft()
            return draft.photoOrder == nil && draft.photos == [localA, localB] && !photoEditorIsPresented()
        }

        controls = try await reopen(expectedOrder: originalOrder)
        controls.move(try XCTUnwrap(controls.items().first), 1)
        controls.done()
        try await waitFor("done keeps order") { try await savedDraft().photoOrder == reordered && !photoEditorIsPresented() }

        // Mount a fresh editor so the order has to be read from the saved draft.
        mountEditor()
        controls = try await reopen(expectedOrder: reordered)
        controls.move(.local(localB), -1)
        try await waitFor("restored order moved") { try await savedDraft().photoOrder == [a, b, server] }
        controls.cancel()
        try await waitFor("cancel returns to saved order") {
            try await savedDraft().photoOrder == reordered && !photoEditorIsPresented()
        }

        // Rotate the representative device photo in place, then delete it.
        controls = try await reopen(expectedOrder: reordered)
        let didRotate = await controls.edit(localA, .rotateLeft)
        XCTAssertTrue(didRotate)
        var rotated: UUID?
        try await waitFor("rotation keeps position") {
            let draft = try await savedDraft()
            guard let id = draft.photos.first, id != localA, draft.photos == [id, localB] else { return false }
            rotated = id
            return draft.photoOrder == [id.uuidString, server, b]
        }
        let rotatedID = try XCTUnwrap(rotated)
        controls.remove(.local(rotatedID))
        try await waitFor("delete updates order") {
            let draft = try await savedDraft()
            return draft.photos == [localB] && draft.photoOrder == [server, b]
        }
        controls.done()
        try await waitFor("delete saved") { !photoEditorIsPresented() }
        let final = try await savedDraft()
        XCTAssertEqual(final.photos, [localB])
        XCTAssertEqual(final.photoOrder, [server, b])
        XCTAssertEqual(store.mediaPaths(storyID: saved.id), serverPaths, "Device-only reordering never writes the server")
    }
    #endif

    /// Opt-in live UI check with a fake API and an isolated draft vault. Never uses a real account.
    @MainActor func testInteractiveCreationNavigation() async throws {
        let mode = ProcessInfo.processInfo.environment["OI_CREATION_INTERACTION_CHECK"]
        let freelyExplore = mode == "all-screens"
        let checkMovement = mode == "placement-gestures"
        let checkReview = mode == "review"
        let checkPersonal = mode == "personal-placement"
        let checkPlacement = mode == "placement" || checkMovement || checkReview || checkPersonal
        guard mode == "1" || freelyExplore || checkPlacement else {
            throw XCTSkip("Opt in to drive the editor with simulator UI automation")
        }
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        if checkPersonal { backend.configure { $0.hasWritingGrant = false; $0.unapprovedDraftsEnabled = false } }
        if checkReview { backend.configure { $0.publicCucumberAppearance = true; $0.publicStoryCard = true } }
        await store.start()
        var look = OiDraftCustomization()
        look.wardrobe = OiWardrobeLook()
        var input = draft(title: "화면 이동 검증용 이야기")
        var expectedGround: SIMD3<Float>?
        var photos: [UUID] = []
        if freelyExplore { input.body = ""; input.latitude = nil; input.longitude = nil; input.cucumberName = "" }
        if checkPlacement {
            let map = try CampusMapData.load()
            let point = try XCTUnwrap(map.graph.sorted { $0.key < $1.key }.map { map.world($0.value.p) }
                .first { map.placementError(at: $0) == nil })
            let coordinate = map.coordinate(point)
            expectedGround = point
            input.latitude = coordinate.latitude; input.longitude = coordinate.longitude
            look.wardrobe?.topColor = 0x6A4194
        }
        if checkPlacement && !checkPersonal {
            let photo = UUID()
            let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).jpegData(withCompressionQuality: 0.8) { context in
                UIColor.green.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
            }
            try await store.saveLocalPhoto(image, id: photo, owner: OiTestBackend.owner)
            photos = [photo]
        }
        if checkReview {
            input.title = "연못 옆에서 보낸 첫 학기"
            input.body = "수업이 끝나면 친구와 연못을 걸었어요.\n그 산책이 오래 기억에 남아요."
            input.cucumberName = "산책오이"
            input.heightMeters = 1.35
            photos = []
            let images = try ["DonationCampus", "CampusSchoolMap"].map { name in
                try OiPhotoProcessor.prepare(XCTUnwrap(UIImage(named: name)?.jpegData(compressionQuality: 0.84)))
            }
            for image in images {
                let id = UUID()
                try await store.saveLocalPhoto(image, id: id, owner: OiTestBackend.owner)
                photos.append(id)
            }
            var wardrobe = OiWardrobeLook()
            wardrobe.topColor = 0x748D43
            let front = try OiPhotoRenderer.asset(images[0])
            let back = try OiPhotoRenderer.asset(images[1])
            let layers = [OiPhotoLayer(source: front.id, side: .front), OiPhotoLayer(source: back.id, side: .back)]
            try wardrobe.artwork.set(OiPhotoDesign(layers: layers), sources: [front.id: front.data, back.id: back.data],
                                     for: OiPhotoSlot.top.itemID(in: wardrobe))
            look.wardrobe = wardrobe
        }
        if checkPersonal {
            input.grantId = nil; input.title = ""; input.body = ""; input.theme = ""; input.emotion = ""
        }
        let initialStep: OiCreationStep = checkPersonal || freelyExplore ? .consent : checkPlacement ? .card : .cucumber
        let local = OiLocalDraft(draft: input, photos: photos, version: 1,
            creationStep: initialStep.rawValue, customization: look,
            agreedConsentClauseIDs: checkPlacement && !checkPersonal ? Set(OiStoryConsentClause.writingClauses.map(\.id.rawValue)) : nil)
        try await store.saveLocalDraft(local, owner: OiTestBackend.owner)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKey = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        let controller = UIHostingController(rootView: Group {
            if checkPersonal { RootTabView(container: .preview, remote: store) }
            else { NavigationStack { OiStoryEditor(remote: store, localID: local.id) } }
        }.environment(\.scenePhase, .active).preferredColorScheme(.light))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        if checkPlacement { previousKey?.isHidden = true }
        defer {
            window.isHidden = true; window.rootViewController = nil; window.windowScene = nil
            if checkPlacement { previousKey?.isHidden = false }
            previousKey?.makeKey()
        }
        if let expectedGround {
            func placedOi(in view: UIView) -> (RealityKit.ARView, Entity)? {
                if let canvas = view as? CampusMapCanvas {
                    guard let map = canvas.map,
                          let model = map.scene.findEntity(named: "placement:" + local.id.uuidString) else { return nil }
                    return (map, model)
                }
                return view.subviews.lazy.compactMap { placedOi(in: $0) }.first
            }
            var sawPlacement = false
            var sawMovement = false
            var sawPersonalMap = false
            func modelOnHomeMap(in view: UIView) -> Entity? {
                guard !view.isHidden else { return nil }
                if let canvas = view as? CampusMapCanvas {
                    let visibleMarker = canvas.subviews.contains { !$0.isHidden && $0.accessibilityIdentifier == "campus.authored." + local.id.uuidString }
                    return visibleMarker ? canvas.map?.scene.findEntity(named: "authored:" + local.id.uuidString) : nil
                }
                return view.subviews.lazy.compactMap { modelOnHomeMap(in: $0) }.first
            }
            for _ in 0..<180 {
                try await Task.sleep(for: .seconds(1))
                let backendState = backend.snapshot()
                if checkReview {
                    if let submitted = backendState.story, submitted["status"] as? String == "pending" {
                        XCTAssertTrue(sawPlacement)
                        XCTAssertEqual(backendState.submittedTitle, input.title)
                        XCTAssertEqual(backendState.paths.count, photos.count)
                        XCTAssertNotNil(submitted["card_snapshot_id"], "Submit the reviewed card image with the story")
                        XCTAssertNil(submitted["customization"], "Original photos and editing settings stay on the device")
                        return
                    }
                } else {
                    XCTAssertNil(backendState.story, "Done and opening review never submit the draft")
                }
                if !sawPlacement, let (_, model) = placedOi(in: window) {
                    XCTAssertLessThan(simd_distance(model.position(relativeTo: nil), expectedGround), 0.001)
                    XCTAssertGreaterThan(model.visualBounds(relativeTo: nil).extents.y, 1)
                    sawPlacement = true
                }
                if checkMovement, sawPlacement, !sawMovement, let (map, model) = placedOi(in: window),
                   let saved = try await store.localDraft(id: local.id, owner: OiTestBackend.owner),
                   let latitude = saved.draft.latitude, let longitude = saved.draft.longitude,
                   latitude != local.draft.latitude || longitude != local.draft.longitude {
                    let moved = try CampusMapData.load().world(latitude: latitude, longitude: longitude)
                    XCTAssertGreaterThan(simd_distance(moved, expectedGround), 0.02)
                    XCTAssertLessThan(simd_distance(model.position(relativeTo: nil), moved), 0.001)
                    let image: UIImage? = await withCheckedContinuation { continuation in
                        map.snapshot(saveToHDR: false) { continuation.resume(returning: $0) }
                    }
                    let attachment = XCTAttachment(image: try XCTUnwrap(image))
                    attachment.name = "draft-oi-after-drag"; attachment.lifetime = .keepAlways; add(attachment)
                    sawMovement = true
                }
                if checkPersonal, sawPlacement, !sawPersonalMap, let model = modelOnHomeMap(in: window) {
                    let saved = try await store.localDraft(id: local.id, owner: OiTestBackend.owner)
                    XCTAssertLessThan(simd_distance(model.position(relativeTo: nil), expectedGround), 0.001)
                    XCTAssertEqual(saved?.customization?.wardrobe, look.wardrobe)
                    XCTAssertEqual(saved?.photos, [])
                    XCTAssertNotNil(saved?.personalPlacement)
                    XCTAssertTrue(saved?.agreedConsentClauseIDs?.isEmpty == true)
                    XCTAssertTrue(backendState.uploads.isEmpty)
                    sawPersonalMap = true
                }
                if checkPersonal, sawPersonalMap, controller.presentedViewController != nil { return }
                if !checkReview, !checkPersonal, sawPlacement, (!checkMovement || sawMovement), controller.presentedViewController != nil {
                    let saved = try await store.localDraft(id: local.id, owner: OiTestBackend.owner)
                    XCTAssertEqual(saved?.customization?.wardrobe, look.wardrobe)
                    XCTAssertEqual(saved?.photos, photos)
                    return
                }
            }
            return XCTFail("Done → placement preview → review did not complete")
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

    @MainActor func testInteractiveStoryListSwipeDeletion() async throws {
        guard ProcessInfo.processInfo.environment["OI_STORY_LIST_INTERACTION_CHECK"] == "1" else {
            throw XCTSkip("Opt in: swipe left → Delete → Cancel → swipe left → Delete → confirm")
        }
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        await store.start()
        let photoID = UUID()
        let bytes = Data([1, 2, 3])
        var record = OiLocalDraft(draft: draft(title: "스와이프 삭제 검증"), photos: [photoID], version: 1)
        record.personalPlacement = OiPersonalPlacement(regionID: "pond", name: "삭제 검증 오이", latitude: 36.0126,
            longitude: 129.3197, heightMeters: 1.35, headingDegrees: 0)
        try await store.savePersonalPlacement(record, owner: OiTestBackend.owner)
        try await store.saveLocalPhoto(bytes, id: photoID, owner: OiTestBackend.owner)
        let revision = store.localPlacementRevision
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKey = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: NavigationStack { OiStoryListScreen(remote: store) })
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; window.windowScene = nil; previousKey?.makeKey() }
        for _ in 0..<240 {
            try await Task.sleep(for: .seconds(1))
            if try await store.localDraft(id: record.id, owner: OiTestBackend.owner) == nil {
                XCTAssertGreaterThan(store.localPlacementRevision, revision)
                do {
                    _ = try await store.localPhoto(id: photoID, owner: OiTestBackend.owner)
                    XCTFail("Deleted draft attachments must be removed")
                } catch { }
                XCTAssertNil(backend.snapshot().story, "Local deletion must not create or mutate a server story")
                return
            }
        }
        XCTFail("The swipe and confirmation route did not finish")
    }

    @MainActor func testStoryListUsesNativeScrollingAtStandardAndAccessibilitySizes() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKey = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        defer { window.isHidden = true; window.rootViewController = nil; window.windowScene = nil; previousKey?.makeKey() }
        func scrollViews(in view: UIView) -> [UIScrollView] {
            (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
        }
        for size in [DynamicTypeSize.large, .accessibility3] {
            window.rootViewController = UIHostingController(rootView: NavigationStack {
                OiStoryListView(state: .preview,
                    onSelectStory: { _ in }, onCreateStory: {}, onDeleteStory: { _ in })
                    .environment(\.dynamicTypeSize, size)
            })
            window.makeKeyAndVisible()
            try await Task.sleep(for: .seconds(1))
            window.layoutIfNeeded()
            let list = try XCTUnwrap(scrollViews(in: window).first { $0 is UICollectionView || $0 is UITableView })
            XCTAssertGreaterThan(list.bounds.height, 100)
            XCTAssertGreaterThan(list.contentSize.height, 400)
            list.setContentOffset(CGPoint(x: 0, y: max(-list.adjustedContentInset.top, list.contentSize.height - list.bounds.height + list.adjustedContentInset.bottom)), animated: false)
            try await Task.sleep(for: .milliseconds(300))
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "story-list-\(size)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor func testStoryListDeletionPreservesFailuresAndRemovesConfirmedReceipt() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { clean(session, directory: directory) }
        await store.start()
        let savedResult = await store.save(draft(title: "삭제 검증"))
        let saved = try XCTUnwrap(savedResult)
        backend.configure { $0.failDelete = true }
        let rejected = await store.deleteStory(saved)
        XCTAssertFalse(rejected)
        XCTAssertEqual(store.ownStories.first?.id, saved.id)
        XCTAssertNotNil(store.error)

        backend.configure { $0.failDelete = false; $0.failReadsAfterDelete = true }
        let deleted = await store.deleteStory(saved)
        XCTAssertTrue(deleted, "A confirmed deletion succeeds even if the following refresh fails")
        XCTAssertFalse(store.ownStories.contains { $0.id == saved.id })
        XCTAssertFalse(store.stories.contains { $0.id == saved.id })
        XCTAssertEqual(backend.snapshot().story?["status"] as? String, "deleted")
        XCTAssertNotNil(store.syncWarning)
        XCTAssertNil(store.error)
    }

    @MainActor func testStoryListDeletionRejectsStaleRevisionAndSignedOutAccount() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { clean(session, directory: directory) }
        await store.start()
        let firstResult = await store.save(draft())
        let first = try XCTUnwrap(firstResult)
        var edited = draft(title: "새 버전")
        edited.id = first.id
        edited.revision = first.revision
        let latestResult = await store.save(edited)
        let latest = try XCTUnwrap(latestResult)
        let staleDelete = await store.deleteStory(first)
        XCTAssertFalse(staleDelete)
        XCTAssertEqual(store.ownStories.first?.revision, latest.revision)
        let count = backend.snapshot().deleteCount
        await store.signOut()
        let signedOutDelete = await store.deleteStory(latest)
        XCTAssertFalse(signedOutDelete)
        XCTAssertEqual(backend.snapshot().deleteCount, count)
    }

    @MainActor func testPersonalPlacementStaysInTheAccountVaultWhenPublicationIsPaused() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { clean(session, directory: directory) }
        backend.configure { $0.hasWritingGrant = false; $0.unapprovedDraftsEnabled = false }
        await store.start()
        XCTAssertTrue(store.canPlaceOi)
        XCTAssertFalse(store.canStartStory)

        let owner = OiTestBackend.owner
        var record = OiLocalDraft(draft: OiStoryDraft(), version: 2, creationStep: OiCreationStep.card.rawValue)
        record.personalPlacement = OiPersonalPlacement(regionID: "pond", name: "내 오이", latitude: 36.0126,
            longitude: 129.3197, heightMeters: 1.35, headingDegrees: 230)
        try await store.savePersonalPlacement(record, owner: owner)
        var stale = record
        stale.personalPlacement = nil
        stale.version -= 1
        try await store.saveLocalDraft(stale, owner: owner)

        let reopenedVault = OiDraftVault(directory: directory)
        let reopened = try await reopenedVault.load(owner: owner, id: record.id)
        let otherAccountCopy = try await reopenedVault.load(owner: UUID(), id: record.id)
        XCTAssertEqual(reopened, record)
        XCTAssertNil(otherAccountCopy)
        XCTAssertNil(backend.snapshot().story)
        XCTAssertTrue(backend.snapshot().uploads.isEmpty)
        XCTAssertTrue(store.stories.isEmpty)
        XCTAssertTrue(store.ownStories.isEmpty)

        let placementRevision = store.localPlacementRevision
        try await store.discardLocalDraft(id: record.id, owner: owner)
        let discarded = try await reopenedVault.load(owner: owner, id: record.id)
        XCTAssertNil(discarded)
        XCTAssertGreaterThan(store.localPlacementRevision, placementRevision)
        await store.signOut()
        XCTAssertFalse(store.canPlaceOi)
    }

    @MainActor func testWritingPausePreservesStoryAndPhotoWithoutRequiringEvidence() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { clean(session, directory: directory) }
        backend.configure { $0.hasWritingGrant = false; $0.independentStoryCreation = nil }
        await store.start()
        XCTAssertFalse(store.canStartStory, "The old writing flag alone does not prove the new policy is active")
        backend.configure { $0.independentStoryCreation = true }
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
        backend.configure { $0.unapprovedDraftsEnabled = false; $0.hasWritingGrant = true }
        await store.refresh()
        XCTAssertFalse(store.canStartStory)
        XCTAssertEqual(store.ownStories.first?.body, temporary.body)
        XCTAssertEqual(store.mediaPaths(storyID: saved.id), paths)
        let denied = await store.save(OiStoryDraft(story: withPhoto))
        XCTAssertNil(denied)
        XCTAssertEqual(backend.snapshot().uploads.count, 1)
        backend.configure { $0.unapprovedDraftsEnabled = true }
        await store.refresh()
        var resumed = OiStoryDraft(story: withPhoto); resumed.grantId = OiTestBackend.grant
        let reopened = await store.save(resumed)
        XCTAssertEqual(reopened?.id, saved.id)
        XCTAssertNil(reopened?.grantId)
        XCTAssertEqual(store.mediaPaths(storyID: saved.id), paths)
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

    @MainActor func testMediaReorderKeepsAttachmentsMissingFromLocalCache() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        await store.start()
        let receipt = await store.save(draft())
        let story = try XCTUnwrap(receipt)
        let firstID = UUID(), secondID = UUID()
        let prefix = "\(story.userId.uuidString)/\(story.id.uuidString)"
        let first = "\(prefix)/\(firstID.uuidString.lowercased()).jpg"
        let second = "\(prefix)/\(secondID.uuidString.lowercased()).jpg"
        let unknown = "\(prefix)/another-device.jpg"
        backend.configure {
            $0.paths = [first, unknown, second]
            $0.failReads = true
        }
        let preferred = [secondID.uuidString, firstID.uuidString]
        let reordered = await store.reorderStoryMedia(preferred, story: story)
        let updated = try XCTUnwrap(reordered)
        XCTAssertEqual(updated.revision, story.revision + 1)
        XCTAssertEqual(backend.snapshot().paths, [second, first, unknown])
        XCTAssertEqual(store.mediaPaths(storyID: story.id), [second, first, unknown])
        let repeated = await store.reorderStoryMedia(preferred, story: updated)
        XCTAssertEqual(repeated?.revision, updated.revision)
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

    @MainActor func testAutomaticReviewKeepsDraftPrivateUntilExplicitPlanting() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { clean(session, directory: directory) }
        backend.configure { $0.autoStoryModeration = true; $0.rejectModeration = true }
        await store.start()
        XCTAssertTrue(store.autoStoryModeration)
        let savedReceipt = await store.save(draft())
        let saved = try XCTUnwrap(savedReceipt)

        let withoutConsent = await store.submitStory(saved)
        XCTAssertNil(withoutConsent)
        XCTAssertEqual(backend.snapshot().moderationCount, 0)

        let rejected = await store.submitStory(saved, agreesToAIReview: true)
        XCTAssertNil(rejected)
        XCTAssertEqual(store.error, "카드 이미지에 공개하면 안 되는 개인정보가 포함돼 있어요.")
        XCTAssertEqual(store.ownStories.first?.status, "draft")
        XCTAssertTrue(store.stories.isEmpty)

        backend.configure { $0.rejectModeration = false; $0.timeOutSubmitAfterCommit = true }
        let reviewed = await store.submitStory(saved, agreesToAIReview: true)
        let approved = try XCTUnwrap(reviewed)
        XCTAssertEqual(approved.status, "draft")
        XCTAssertEqual(approved.revision, saved.revision + 1)
        XCTAssertEqual(store.moderationResult(for: approved)?.status, .approved)
        XCTAssertTrue(store.stories.isEmpty)
        XCTAssertEqual(backend.snapshot().moderationCount, 2)
        XCTAssertEqual(backend.snapshot().submitCount, 1)
        XCTAssertEqual(backend.snapshot().reviewCount, 0)

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: NavigationStack { OiStoryListScreen(remote: store) })
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil; window.windowScene = nil }
        try await Task.sleep(for: .seconds(1))
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "review-approved-story-list"
        attachment.lifetime = .keepAlways
        add(attachment)

        let planted = await store.plantStory(approved)
        XCTAssertTrue(planted)
        XCTAssertEqual(store.stories.first?.id, saved.id)
        XCTAssertNil(store.moderationResult(for: approved))
    }

    @MainActor func testStoryListRequestsReviewAndShowsResultInPlace() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure {
            $0.autoStoryModeration = true; $0.rejectModeration = true
            $0.publicStoryCard = true; $0.duplexStoryCard = true
        }
        await store.start()
        let owner = OiTestBackend.owner
        let photo = UUID()
        let record = OiLocalDraft(draft: draft(), photos: [photo], version: 1,
            agreedConsentClauseIDs: Set(OiStoryConsentClause.writingClauses.map { $0.id.rawValue }))
        let photoBytes = try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 80, height: 80)).image { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 80))
        }.jpegData(compressionQuality: 0.9))
        try await store.saveLocalDraft(record, owner: owner)
        try await store.saveLocalPhoto(photoBytes, id: photo, owner: owner)

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKey = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        var actions: OiStoryListScreen.ReviewTestActions?
        var appearances = 0
        let controller = UIHostingController(rootView: NavigationStack {
            OiStoryListScreen(remote: store, onReviewActionsForTest: { actions = $0; appearances += 1 })
        })
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; window.windowScene = nil; previousKey?.makeKey() }
        try await Task.sleep(for: .seconds(1))
        let buttons = try XCTUnwrap(actions)
        XCTAssertEqual(buttons.status(record.id).title, "검토 전")
        buttons.request(record.id)
        for _ in 0..<60 where !buttons.needsConsent(record.id) { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertTrue(buttons.needsConsent(record.id))
        XCTAssertEqual(backend.snapshot().moderationCount, 0)

        let held = expectation(description: "Review remains in progress until the server responds")
        backend.configure { $0.holdModerationResponse = true; $0.didHold = { held.fulfill() } }
        buttons.grantConsent(record.id)
        await fulfillment(of: [held], timeout: 15)
        XCTAssertEqual(buttons.status(record.id).title, "검토중")
        buttons.request(record.id)
        XCTAssertEqual(backend.snapshot().moderationCount, 1)
        backend.releaseHeldRead()
        for _ in 0..<120 where buttons.status(record.id) != .rejected { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertEqual(buttons.status(record.id).title, "수정 필요")
        XCTAssertEqual(buttons.message(record.id), "카드 이미지에 공개하면 안 되는 개인정보가 포함돼 있어요.")
        XCTAssertNil(controller.presentedViewController)
        XCTAssertEqual(appearances, 1)
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = "story-review-rejection-in-list"
        attachment.lifetime = .keepAlways
        add(attachment)

        backend.configure { $0.rejectModeration = false }
        buttons.request(record.id)
        for _ in 0..<160 where buttons.status(record.id) != .approved { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertEqual(buttons.status(record.id).title, "게시 가능")
        XCTAssertNil(buttons.message(record.id))
        XCTAssertEqual(backend.snapshot().moderationCount, 2)
        XCTAssertEqual(store.ownStories.first?.status, "draft")
        XCTAssertTrue(store.stories.isEmpty)
        let saved = try await store.localDraft(id: record.id, owner: owner)
        XCTAssertTrue(saved?.matchesReviewedContent == true)
        XCTAssertTrue(saved?.agreedConsentClauseIDs?.contains("aiReviewV1") == true)
    }

    @MainActor func testStoryListShowsUpdatedLayoutWithLegacyReview() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        await store.start()
        let saved = await store.save(draft())
        XCTAssertNotNil(saved)
        XCTAssertFalse(store.autoStoryModeration)

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKey = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: NavigationStack { OiStoryListScreen(remote: store) })
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; window.windowScene = nil; previousKey?.makeKey() }
        try await Task.sleep(for: .seconds(1))
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "story-list-legacy-review"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor func testStoryListKeepsPendingStoryInItsSlotWhileScrollingAndRefreshing() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.publicStoryCard = true; $0.duplexStoryCard = true }
        await store.start()
        XCTAssertFalse(store.autoStoryModeration)
        let owner = try XCTUnwrap(store.account?.id)
        var reviewDraft = draft(title: "검토 중에도 보여야 하는 이야기")
        reviewDraft.id = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let photo = UUID()
        let record = OiLocalDraft(draft: reviewDraft, photos: [photo], version: 1,
            agreedConsentClauseIDs: Set(OiStoryConsentClause.writingClauses.map { $0.id.rawValue }))
        let otherDrafts = (1...3).map { OiLocalDraft(draft: draft(title: "다른 이야기 \($0)")) }
        let expectedIDs = ([record.id] + otherDrafts.map(\.id)).sorted { $0.uuidString < $1.uuidString }
        for item in [record] + otherDrafts { try await store.saveLocalDraft(item, owner: owner) }
        let photoBytes = try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 80, height: 80)).image { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 80))
        }.jpegData(compressionQuality: 0.9))
        try await store.saveLocalPhoto(photoBytes, id: photo, owner: owner)

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKey = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        var actions: OiStoryListScreen.ReviewTestActions?
        let controller = UIHostingController(rootView: NavigationStack {
            OiStoryListScreen(remote: store, onReviewActionsForTest: { actions = $0 })
                .environment(\.dynamicTypeSize, .accessibility3)
        })
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; window.windowScene = nil; previousKey?.makeKey() }
        try await Task.sleep(for: .seconds(1))
        let buttons = try XCTUnwrap(actions)
        XCTAssertEqual(buttons.visibleIDs(), expectedIDs)

        let held = expectation(description: "Operator review submission is in flight")
        backend.configure { $0.holdStorySubmissionResponse = true; $0.didHold = { held.fulfill() } }
        buttons.request(record.id)
        await fulfillment(of: [held], timeout: 15)
        func scrollViews(in view: UIView) -> [UIScrollView] {
            (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
        }
        let list = try XCTUnwrap(scrollViews(in: controller.view).first { $0.contentSize.height > $0.bounds.height })
        let top = -list.adjustedContentInset.top
        let bottom = list.contentSize.height - list.bounds.height + list.adjustedContentInset.bottom
        XCTAssertGreaterThan(bottom, top)
        list.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
        XCTAssertEqual(buttons.status(record.id), .reviewing)
        XCTAssertEqual(buttons.visibleIDs(), expectedIDs)
        backend.releaseHeldRead()
        for _ in 0..<120 where store.isBusy || store.ownStories.first?.status != "pending" {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(store.ownStories.first?.status, "pending")
        for _ in 0..<120 {
            if try await store.localDraft(id: record.id, owner: owner)?.submitted == true { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let saved = try await store.localDraft(id: record.id, owner: owner)
        XCTAssertTrue(saved?.submitted == true)
        await store.refresh()
        list.setContentOffset(CGPoint(x: 0, y: top), animated: false)
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(buttons.visibleIDs(), expectedIDs)
        XCTAssertEqual(buttons.status(record.id).title, "검토중")
        buttons.request(record.id)
        XCTAssertEqual(backend.snapshot().submitCount, 1)
        XCTAssertTrue(store.stories.isEmpty)

        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "story-list-pending-after-scroll"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor func testStoryProductionRulesUsesAnchoredPopoverOnIPhone() async throws {
        struct PopoverSample: View {
            @State private var showingRules = false

            var body: some View {
                VStack {
                    Spacer()
                    OiStoryProductionRulesButton(isPresented: $showingRules)
                    Text("농장에 오이 심기")
                        .font(.custom("Paperlogy-6SemiBold", size: 18))
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .padding(.horizontal, 20)
                .task {
                    try? await Task.sleep(for: .milliseconds(200))
                    showingRules = true
                }
            }
        }

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let controller = UIHostingController(rootView: PopoverSample())
        let window = UIWindow(windowScene: scene)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; window.windowScene = nil }
        try await Task.sleep(for: .seconds(1))
        let popup = try XCTUnwrap(controller.presentedViewController)
        XCTAssertNotNil(popup.popoverPresentationController, "The rules remain a popover in a compact size class")
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "story-production-rules-popover"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor func testPublicationUsesLatestSavedContentAndRevision() async throws {
        let (store,backend,_,session,directory) = try context()
        defer { clean(session, directory: directory) }
        await store.start()
        var current = draft(title: "Old title")
        guard let first = await store.save(current) else { XCTFail("First save failed"); return }
        current = OiStoryDraft(story: first); current.title = "Latest corrected title"
        current.heightMeters = 1.35; current.headingDegrees = 263.5
        guard let updated = await store.save(current) else { XCTFail("Second save failed"); return }
        let receipt = await store.submitStory(updated)
        XCTAssertEqual(receipt?.status, "pending")
        XCTAssertEqual(backend.snapshot().submittedTitle, "Latest corrected title")
        XCTAssertEqual(receipt?.revision, 3)
        XCTAssertEqual(receipt?.heightMeters, 1.35)
        XCTAssertEqual(receipt?.headingDegrees, 263.5)
        XCTAssertEqual(store.ownStories.first(where: { $0.id == current.id })?.isRegisteredOnCampus, true)
        XCTAssertTrue(store.stories.isEmpty, "A pending placement must stay out of the public map and search")
        backend.configure { $0.story?["status"] = "published" }
        let published = try await store.publishedStory(current.id)
        XCTAssertEqual(published.campusPlacement?.heightCentimeters, 135)
        XCTAssertEqual(published.campusPlacement?.headingDegrees, 263.5)
        let campusStory = store.campusStory(published)
        XCTAssertEqual(campusStory.heightMeters, 1.35, accuracy: 0.001)
        XCTAssertEqual(campusStory.headingDegrees, 263.5, accuracy: 0.001)
    }

    @MainActor func testGeographicCameraPairsAnOlderFixWithItsHistoricalPose() throws {
        let now = Date()
        // A target about 9m east. GPS was measured before an 8m walk.
        let target = CampusPlacement(storyID: "walk-test", latitude: 36.012, longitude: 129.3231)
        let fix = ARCameraGeoPlacement.Fix(latitude: 36.012, longitude: 129.323, accuracy: 1,
                                          timestamp: now.addingTimeInterval(-8))
        var poses = ARCameraPoseHistory()
        poses.record(position: [0, 1.5, 0], timestamp: 100)
        poses.record(position: [0.2, 1.5, 0], timestamp: 100.2)
        poses.record(position: [8, 1.5, 0], timestamp: 108)
        XCTAssertNil(poses.position(at: 99), "A fix measured before this AR world must wait")
        XCTAssertNil(poses.position(at: 109), "Never extrapolate a future pose")
        XCTAssertNil(poses.position(at: 104), "Never bridge a gap in AR tracking")
        let interpolated = try XCTUnwrap(poses.position(at: 100.1))
        XCTAssertEqual(interpolated.x, 0.1, accuracy: 0.001)
        var resolution = ARCameraGeoPlacement(target: target)
        XCTAssertEqual(resolution.update(fix: fix, trackingNormal: true, cameraAtFix: nil, now: now,
                                         groundHeight: { _ in 0 }), .waitingForSynchronizedLocation)
        let offset = target.offsetMeters(fromLatitude: fix.latitude, longitude: fix.longitude)
        let status = resolution.update(fix: fix, trackingNormal: true, cameraAtFix: poses.position(at: 100), now: now,
                                       groundHeight: { _ in 0 })
        XCTAssertEqual(status, .ready([offset.x, 0, offset.z]), "The later 8m walk must not be added to the target")
        poses.reset()
        XCTAssertNil(poses.position(at: 100), "Restarting tracking must discard old world poses")
        poses.record(position: .zero, timestamp: 200)
        poses.record(position: [1, 0, 0], timestamp: 213)
        XCTAssertNil(poses.position(at: 200), "Pose history must remain bounded")
    }

    @MainActor func testGeographicCameraWaitsForLocationPermissionBeforeHeadingTracking() {
        final class Location: ARCameraLocationProviding {
            var location: CLLocation?
            var hasUsableFix = false
            var hasPreciseLocationPermission = false
            var message: String?
            var stops = 0
            func start() { }
            func stop() { stops += 1 }
        }
        let target = CampusPlacement(storyID: "permission-test", latitude: 36.012, longitude: 129.323)
        let subject = ARCameraSubject(id: target.id, title: "위치 권한 검사", heightMeters: 1.5, placement: target) { Entity() }
        let location = Location()
        let camera = ARSessionController(subject: subject, locationProvider: location)
        XCTAssertEqual(camera.makeSessionConfiguration().worldAlignment, .gravity)
        location.hasPreciseLocationPermission = true
        let authorized = camera.makeSessionConfiguration()
        XCTAssertEqual(authorized.worldAlignment, .gravityAndHeading)
        XCTAssertEqual(authorized.planeDetection, [.horizontal])
        XCTAssertTrue(authorized.isLightEstimationEnabled)
        XCTAssertFalse(camera.canCapture, "Location authorization alone never allows capture before a valid placement")
        location.hasPreciseLocationPermission = false
        XCTAssertEqual(camera.makeSessionConfiguration().worldAlignment, .gravity)
        camera.pause()
        XCTAssertEqual(location.stops, 1)
        XCTAssertFalse(camera.geographicReady)
        XCTAssertEqual(ARSessionController().makeSessionConfiguration().worldAlignment, .gravity)
    }

    @MainActor func testGeographicCameraGatesLocationAndFreezesWorldPosition() throws {
        let now = Date()
        let target = CampusPlacement(storyID: "geographic-test", latitude: 36.012, longitude: 129.323,
            heightMeters: 1.5, headingDegrees: 90)
        var resolution = ARCameraGeoPlacement(target: target)
        var groundQueries = 0
        func fix(latitude: Double = 36.012, longitude: Double = 129.323,
                 accuracy: Double = 5, age: Double = 0) -> ARCameraGeoPlacement.Fix {
            .init(latitude: latitude, longitude: longitude, accuracy: accuracy, timestamp: now.addingTimeInterval(-age))
        }
        func update(_ sample: ARCameraGeoPlacement.Fix?, tracking: Bool = true,
                    camera: SIMD3<Float> = [4, 1.7, 2], ground: Float? = 0.3) -> ARCameraGeoPlacement.Status {
            resolution.update(fix: sample, trackingNormal: tracking, cameraAtFix: camera, now: now) { _ in
                groundQueries += 1
                return ground
            }
        }
        XCTAssertEqual(update(nil), .waitingForLocation)
        XCTAssertEqual(update(fix(accuracy: 16)), .waitingForLocation)
        XCTAssertEqual(update(fix(accuracy: -1)), .waitingForLocation)
        XCTAssertEqual(update(fix(age: 11)), .waitingForLocation)
        XCTAssertEqual(update(fix(latitude: .nan)), .waitingForLocation)
        if case .outsideRange(let distance) = update(fix(latitude: 36.013)) {
            XCTAssertGreaterThan(distance, 25)
        } else { XCTFail("A remote saved point must stay hidden") }
        XCTAssertEqual(update(fix(), tracking: false), .waitingForTracking)
        XCTAssertEqual(groundQueries, 0, "Invalid location/tracking must not place an anchor")
        XCTAssertEqual(update(fix(), ground: nil), .waitingForGround)
        XCTAssertEqual(update(fix(), ground: .nan), .waitingForGround)
        XCTAssertNil(resolution.position)
        let fixed = SIMD3<Float>(4, 0.3, 2)
        XCTAssertEqual(update(fix()), .ready(fixed))
        let queriesAfterPlacement = groundQueries
        XCTAssertEqual(update(fix(latitude: 36.01201, longitude: 129.32301), camera: [8, 3, 6]), .ready(fixed),
                       "GPS noise and walking must not move a placed character")
        XCTAssertEqual(groundQueries, queriesAfterPlacement)
        XCTAssertEqual(update(fix(accuracy: 30)), .waitingForLocation)
        XCTAssertEqual(update(fix(), tracking: false), .waitingForTracking)
        XCTAssertEqual(update(fix()), .ready(fixed), "A good fix resumes the same world anchor")
        resolution.reset()
        XCTAssertNil(resolution.position)
        XCTAssertEqual(update(fix(), camera: [8, 3, 6], ground: 1), .ready([8, 1, 6]))
    }

    @MainActor func testGeographicCameraUsesMetresAndSavedHeadingWithoutManualFallback() throws {
        let now = Date()
        let target = CampusPlacement(storyID: "direction-test", latitude: 36.0121, longitude: 129.3231,
                                     heightMeters: 1.5, headingDegrees: 90)
        var resolution = ARCameraGeoPlacement(target: target)
        let offset = target.offsetMeters(fromLatitude: 36.012, longitude: 129.323)
        XCTAssertGreaterThan(offset.x, 8)
        XCTAssertLessThan(offset.x, 10)
        XCTAssertLessThan(offset.z, -10)
        XCTAssertGreaterThan(offset.z, -12)
        let status = resolution.update(fix: .init(latitude: 36.012, longitude: 129.323, accuracy: 5, timestamp: now),
            trackingNormal: true, cameraAtFix: [3, 2, 4], now: now) { candidate in
                XCTAssertEqual(candidate.x, 3 + offset.x, accuracy: 0.001)
                XCTAssertEqual(candidate.z, 4 + offset.z, accuracy: 0.001)
                return -0.7
            }
        XCTAssertEqual(status, .ready([3 + offset.x, -0.7, 4 + offset.z]))
        let subject = ARCameraSubject(id: target.id, title: "위치 오이", heightMeters: 1.5, placement: target) { Entity() }
        let controller = ARSessionController(subject: subject)
        XCTAssertTrue(controller.usesGeographicPlacement)
        XCTAssertFalse(controller.geographicReady)
        XCTAssertFalse(controller.canCapture)
        XCTAssertEqual(controller.settings.rotation, 90)
        controller.settings.rotation = 0
        controller.resetSettings()
        XCTAssertEqual(controller.settings.rotation, 90)
        XCTAssertEqual(controller.settings.height, 1.5)
        controller.applyGeographicStatus(.outsideRange(40), locationMessage: nil)
        XCTAssertTrue(controller.locationNotice.contains("40m"))
        XCTAssertFalse(controller.canCapture)
        controller.applyGeographicStatus(.waitingForLocation, locationMessage: "위치 접근을 허용해 주세요.")
        XCTAssertEqual(controller.locationNotice, "위치 접근을 허용해 주세요.")
        controller.pause()
        XCTAssertFalse(controller.geographicReady)
        XCTAssertFalse(ARSessionController().usesGeographicPlacement)
    }

    @MainActor func testARCameraCreatesOneSessionAcrossPresenterRefreshes() async throws {
        var created = 0
        func screen() -> ARCameraScreen {
            ARCameraScreen(makeModel: {
                created += 1
                return ARCameraViewModel()
            })
        }
        let initial = screen()
        XCTAssertEqual(created, 0, "Constructing a view value must not allocate an ARView")
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previousKey = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: initial)
        defer {
            window.isHidden = true; window.rootViewController = nil; window.windowScene = nil
            previousKey?.makeKey()
        }
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        for _ in 0..<20 where created == 0 { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertEqual(created, 1)
        for _ in 0..<5 {
            host.rootView = screen()
            host.view.setNeedsLayout(); host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(60))
        }
        XCTAssertEqual(created, 1, "Presenter refreshes must keep the same camera without allocating discarded ARViews")
    }

    @MainActor func testSelectedCucumberCameraNormalizesAndResetsItsFixedSubject() async throws {
        let id = UUID()
        let subject = ARCameraSubject(id: id, title: "선택한 오이", heightMeters: 1.5) {
            ModelEntity(mesh: .generateBox(size: SIMD3<Float>(1, 3, 1)))
        }
        let camera = ARSessionController(subject: subject)
        XCTAssertEqual(camera.subject?.id, id)
        XCTAssertEqual(camera.settings.height, 1.5)
        XCTAssertEqual(camera.settings.cucumberStoryID, id)
        XCTAssertEqual(camera.settings.cucumberName, subject.title)
        camera.settings.height = 0.8
        camera.resetSettings()
        XCTAssertEqual(camera.settings.height, 1.5, "Reset must preserve the selected cucumber and its initial height")
        XCTAssertEqual(camera.settings.cucumberStoryID, id)
        let loaded = try await ARCharacterController().load(subject)
        let bounds = loaded.root.visualBounds(relativeTo: nil)
        XCTAssertEqual(bounds.extents.y, 1, accuracy: 0.001)
        XCTAssertEqual(bounds.min.y, 0, accuracy: 0.001)
        loaded.root.scale = SIMD3(repeating: camera.settings.height)
        XCTAssertEqual(loaded.root.visualBounds(relativeTo: nil).extents.y, 1.5, accuracy: 0.001)
        let legacy = ARSessionController()
        XCTAssertNil(legacy.subject)
        XCTAssertEqual(legacy.settings.character, .neopjuk)
        XCTAssertNil(legacy.settings.cucumberStoryID)
        XCTAssertEqual(legacy.settings.height, 1.2)
        let bytes = try JSONEncoder().encode(camera.settings)
        XCTAssertEqual(try JSONDecoder().decode(ARCaptureSettings.self, from: bytes).cucumberStoryID, id)
        let oldBytes = try JSONEncoder().encode(legacy.settings)
        XCTAssertNil(try JSONDecoder().decode(ARCaptureSettings.self, from: oldBytes).cucumberStoryID)
    }

    @MainActor func testPublishedOutfitSurvivesApprovalAndLoadsOnAnotherClient() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.publicCucumberAppearance = true; $0.isOperator = true; $0.failCucumberTextureUpload = true }
        await store.start()
        let saved = await store.save(draft())
        let story = try XCTUnwrap(saved)
        func sample(_ color: UIColor) -> UIImage {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            return UIGraphicsImageRenderer(size: CGSize(width: 96, height: 96), format: format).image { context in
                color.setFill(); context.fill(CGRect(x: 0, y: 0, width: 96, height: 96))
            }
        }
        var look = OiWardrobeLook()
        look.top = .hoodie; look.bottom = .shorts; look.topColor = 0x2345CD; look.shoeColor = 0x11B122
        let active = try OiPhotoRenderer.asset(sample(.red))
        let unused = try OiPhotoRenderer.asset(sample(.green))
        try look.artwork.set(OiPhotoDesign(layers: [.init(source: active.id)]), sources: [active.id: active.data], for: "top-hoodie")
        try look.artwork.set(OiPhotoDesign(layers: [.init(source: unused.id)]), sources: [unused.id: unused.data], for: "top-tshirt")
        let portrait = try XCTUnwrap(sample(.orange).pngData())
        let submission = try OiCucumberPublication(look: look, portrait: portrait)
        let failed = await store.submitStory(story, cucumber: submission)
        XCTAssertNil(failed)
        XCTAssertEqual(backend.snapshot().story?["status"] as? String, "draft", "A failed outfit upload must not send the story for approval")

        backend.configure { $0.failCucumberTextureUpload = false }
        let submitted = await store.submitStory(story, cucumber: submission)
        let pending = try XCTUnwrap(submitted)
        let artwork = try XCTUnwrap(pending.cucumberArtwork)
        XCTAssertEqual(pending.status, "pending")
        XCTAssertTrue(store.stories.isEmpty)
        XCTAssertEqual(Set(backend.snapshot().uploads.keys), Set([.portrait, .top].map { "oi-story-media/" + artwork.path($0) }))
        XCTAssertFalse(backend.snapshot().uploads.values.contains(active.data))
        XCTAssertFalse(backend.snapshot().uploads.values.contains(unused.data))

        let result = try await store.reviewOperatorStory(pending, publish: true)
        XCTAssertEqual(result.story.cucumberArtwork, artwork)
        let api = try OiServiceAPI(key: "sb_publishable_testing", session: session)
        let reader = OiRemoteStore(api: api, drafts: OiDraftVault(directory: directory))
        let published = try await reader.publishedStory(pending.id)
        XCTAssertEqual(published.cucumberAppearance?.top, "hoodie")
        XCTAssertEqual(published.cucumberAppearance?.shoeColor, 0x11B122)
        XCTAssertEqual(reader.campusStory(published).cucumberPortraitPath, artwork.path(.portrait))
        let model = try await reader.cucumberModel(artwork)
        XCTAssertNotNil(model.findEntity(named: "OiPhotoOverlay"), "The public 3D model has the outfit's applied photo texture")
        XCTAssertEqual(model.visualBounds(relativeTo: nil).extents.y, 1.5, accuracy: 0.001)

        let repository = RealStoryRepository(key: "sb_publishable_testing", session: session)
        let clipStory = try await repository.fetchPublicStory(storyID: pending.id.uuidString)
        XCTAssertEqual(clipStory?.hasCustomCucumberImage, true)
        XCTAssertEqual(clipStory?.cucumberImageURL?.path, "/storage/v1/object/sign/oi-story-media/" + artwork.path(.portrait))
        let projected = reader.campusStory(published)
        let subject = try XCTUnwrap(CampusCucumberCameraSubject.make(story: projected, remote: reader))
        XCTAssertEqual(subject.id, published.id)
        XCTAssertEqual(subject.defaultSettings.height, Float(projected.heightMeters))
        XCTAssertEqual(subject.placement, published.campusPlacement)
        XCTAssertNotNil(subject.placement)
        let normalized = try await ARCharacterController().load(subject)
        XCTAssertNotNil(normalized.model.findEntity(named: "OiPhotoOverlay"), "The photo camera must use the selected approved outfit and its texture")
        XCTAssertEqual(normalized.root.visualBounds(relativeTo: nil).extents.y, 1, accuracy: 0.001)
        XCTAssertNil(CampusCucumberCameraSubject.make(story: CampusStoryExamples.stories[0], remote: reader))
        let originalLatitude = published.latitude
        backend.configure { $0.story?["latitude"] = originalLatitude + 0.001 }
        do { _ = try await subject.loadModel(); XCTFail("A changed saved location must not use the stale camera target") }
        catch { }
        backend.configure { $0.story?["latitude"] = originalLatitude }
        backend.configure { $0.story?["status"] = "hidden"; $0.ignoreStoryStatusFilter = true }
        do { _ = try await subject.loadModel(); XCTFail("A withdrawn story must not remain available to the photo camera") }
        catch { }
        backend.configure {
            $0.story?["status"] = "published"
            $0.uploads.removeValue(forKey: "oi-story-media/" + artwork.path(.top))
        }
        do { _ = try await subject.loadModel(); XCTFail("Missing approved artwork must not fall back to a different cucumber") }
        catch { }
    }

    @MainActor func testAuthoredCardIsReviewedAndReusedWhenStoryIsResubmitted() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure {
            $0.isOperator = true; $0.publicStoryCard = true; $0.publicCucumberAppearance = true; $0.duplexStoryCard = true
            $0.timeOutCardUploadAfterCommit = true
        }
        await store.start()
        let input = draft()
        var customization = OiDraftCustomization()
        customization.firstColor = 0x3F7DA4
        var design = OiCardDesign(); design.caption = "검토용 카드 문구"; design.anonymous = true
        customization.card = design
        let preview = OiDraftCardPreview(draft: input, customization: customization, donorName: "Fixture")
        let card = try preview.publication(colorScheme: .light)
        XCTAssertEqual(try preview.publication(colorScheme: .light).id, card.id)
        let image = try OiPublishedCucumberImage.decode(card.png, part: .portrait)
        XCTAssertEqual(image.width, 1086)
        XCTAssertEqual(image.height, 1506)
        let cucumber = try OiCucumberPublication(look: OiWardrobeLook(), portrait: card.png)

        let draftReceipt = await store.save(input)
        let saved = try XCTUnwrap(draftReceipt)
        let pendingReceipt = await store.submitStory(saved, cucumber: cucumber, card: card)
        let pending = try XCTUnwrap(pendingReceipt, "A committed image must survive a lost upload response")
        let cardPath = try XCTUnwrap(pending.cardArtworkPath)
        XCTAssertEqual(backend.snapshot().uploads["oi-story-media/" + cardPath], card.png)
        let repository = RealStoryRepository(key: "sb_publishable_testing", session: session)
        let privateCard = try await repository.fetchPublicStoryCard(storyID: saved.id.uuidString)
        XCTAssertNil(privateCard)

        let approved = try await store.reviewOperatorStory(pending, publish: true).story
        let publicCard = try await repository.fetchPublicStoryCard(storyID: saved.id.uuidString)
        XCTAssertEqual(publicCard?.imageURL?.path, "/storage/v1/object/sign/oi-story-media/" + cardPath)
        XCTAssertEqual(pending.cardSnapshotFormat, 2)
        XCTAssertNotNil(publicCard?.backImageURL)
        XCTAssertNotNil(publicCard?.frontPreviewURL)
        XCTAssertNotNil(publicCard?.backPreviewURL)
        let details = try await repository.fetchPublicPostcardDetails(storyID: saved.id.uuidString)
        XCTAssertEqual(details?.frontURL, publicCard?.frontPreviewURL, "NFC uses the same reviewed preview as the general Clip")
        XCTAssertEqual(details?.backURL, publicCard?.backImageURL, "The scratch postcard shows the full-resolution back")
        backend.configure { $0.failCardBackRead = true }
        do {
            _ = try await repository.fetchPublicPostcardDetails(storyID: saved.id.uuidString)
            XCTFail("A missing format-2 back must not silently fall back to generated text")
        } catch {}
        backend.configure { $0.failCardBackRead = false }
        for path in pending.cardArtworkPaths { XCTAssertNotNil(backend.snapshot().uploads["oi-story-media/" + path]) }
        XCTAssertEqual(store.campusStory(approved).cardArtworkPath, cardPath)
        let uploadCount = backend.snapshot().artworkUploadAttempts

        await store.perform("reopen_story", payload: ["id": approved.id.uuidString, "revision": approved.revision])
        var edited = OiStoryDraft(story: try XCTUnwrap(store.ownStories.first { $0.id == approved.id }))
        edited.body = "Edited after approval"
        let editReceipt = await store.save(edited)
        let resubmitting = try XCTUnwrap(editReceipt)
        backend.configure { $0.timeOutSubmitBeforeCommit = true }
        let unconfirmed = await store.submitStory(resubmitting, cucumber: cucumber, card: card)
        XCTAssertNil(unconfirmed, "An uncommitted request must remain a draft")
        XCTAssertEqual(store.ownStories.first?.status, "draft")
        backend.configure { $0.timeOutSubmitAfterCommit = true }
        let confirmed = await store.submitStory(resubmitting, cucumber: cucumber, card: card)
        XCTAssertEqual(confirmed?.status, "pending", "Verify the committed revision without submitting twice")
        XCTAssertEqual(confirmed?.body, edited.body)
        XCTAssertEqual(confirmed?.cardArtworkPath, cardPath)
        XCTAssertEqual(backend.snapshot().submitCount, 3)
        XCTAssertEqual(backend.snapshot().artworkUploadAttempts, uploadCount)
        let pendingCard = try await repository.fetchPublicStoryCard(storyID: saved.id.uuidString)
        XCTAssertNil(pendingCard)
    }

    @MainActor func testCoverCapabilityUploadsReviewsAndReadsFiveParts() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.isOperator = true; $0.publicStoryCard = true; $0.duplexStoryCard = true; $0.storyCardCover = true }
        await store.start()
        XCTAssertTrue(store.canPublishStoryCardCover)
        let input = draft()
        let card = try OiDraftCardPreview(draft: input, customization: OiDraftCustomization()).publication(colorScheme: .light, includeCover: true)
        let savedReceipt = await store.save(input)
        let saved = try XCTUnwrap(savedReceipt)
        backend.configure { $0.failCardCoverUpload = true }
        let partial = await store.submitStory(saved, card: card)
        XCTAssertNil(partial)
        XCTAssertEqual(backend.snapshot().submitCount, 0)
        XCTAssertEqual(store.ownStories.first?.status, "draft")
        backend.configure { $0.failCardCoverUpload = false }
        let receipt = await store.submitStory(saved, card: card)
        let pending = try XCTUnwrap(receipt)
        XCTAssertEqual(pending.cardSnapshotFormat, 3)
        XCTAssertEqual(pending.cardArtworkPaths.count, 5)
        XCTAssertTrue(pending.cardArtworkPaths.last?.hasSuffix("/cover.png") == true)
        XCTAssertNotNil(pending.cardBackArtworkPath)
        for path in pending.cardArtworkPaths { XCTAssertNotNil(backend.snapshot().uploads["oi-story-media/" + path]) }
        let repository = RealStoryRepository(key: "sb_publishable_testing", session: session)
        let privateDetails = try await repository.fetchPublicPostcardDetails(storyID: saved.id.uuidString)
        XCTAssertNil(privateDetails)
        let approved = try await store.reviewOperatorStory(pending, publish: true).story
        XCTAssertEqual(approved.cardSnapshotFormat, 3)
        let details = try await repository.fetchPublicPostcardDetails(storyID: saved.id.uuidString)
        XCTAssertTrue(details?.coverURL?.path.hasSuffix("/cover.png") == true)
        XCTAssertTrue(details?.frontURL?.path.hasSuffix("/front-preview.png") == true)
        XCTAssertTrue(details?.backURL?.path.hasSuffix("/back.png") == true)
        backend.configure { $0.failCardCoverRead = true }
        let fallback = try await repository.fetchPublicPostcardDetails(storyID: saved.id.uuidString)
        XCTAssertNil(fallback?.coverURL)
        XCTAssertNotNil(fallback?.frontURL, "A missing optional cover preserves the approved front fallback")
    }

    @MainActor private func jpegCard() throws -> OiStoryCardPublication {
        try OiDraftCardPreview(draft: draft(), customization: OiDraftCustomization())
            .publication(colorScheme: .light, includeCover: true, coverType: .jpeg)
    }

    @MainActor func testJPEGCoverUploadsReviewsAndReadsWithExactType() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.isOperator = true; $0.publicStoryCard = true; $0.duplexStoryCard = true; $0.storyCardCover = true; $0.storyCardCoverJpeg = true }
        await store.start()
        XCTAssertTrue(store.canPublishStoryCardCoverJPEG)
        let card = try jpegCard()
        let saved = await store.save(draft())
        backend.configure { $0.failCardCoverUpload = true }
        let failed = await store.submitStory(try XCTUnwrap(saved), card: card)
        XCTAssertNil(failed)
        XCTAssertEqual(backend.snapshot().submitCount, 0, "A partial bundle cannot enter review")
        backend.configure { $0.failCardCoverUpload = false; $0.timeOutSubmitAfterCommit = true }
        let submitted = await store.submitStory(try XCTUnwrap(saved), card: card)
        let pending = try XCTUnwrap(submitted)
        XCTAssertEqual(pending.cardSnapshotFormat, 3)
        XCTAssertEqual(pending.cardCoverType, "jpeg")
        XCTAssertEqual(pending.cardSnapshotId, card.id)
        XCTAssertEqual(pending.cardArtworkPaths.count, 5)
        let coverPath = try XCTUnwrap(pending.cardArtworkPaths.last)
        XCTAssertTrue(coverPath.hasSuffix("/cover.jpg"))
        for path in pending.cardArtworkPaths {
            XCTAssertEqual(backend.snapshot().uploadContentTypes["oi-story-media/" + path], path == coverPath ? "image/jpeg" : "image/png")
        }
        let bytes = try await store.storyCoverData(coverPath, type: .jpeg)
        XCTAssertEqual(bytes, card.parts[.cover])
        let reused = try OiCardImageExport.publication(front: XCTUnwrap(UIImage(data: card.png)),
            message: "뒷면 수정", author: "가상 작성자", cover: bytes, coverType: .jpeg)
        XCTAssertEqual(reused.parts[.cover], bytes, "Saved JPEG must not be compressed again")
        XCTAssertNotEqual(reused.id, card.id)
        let approved = try await store.reviewOperatorStory(pending, publish: true).story
        XCTAssertEqual(approved.cardCoverType, "jpeg")
        XCTAssertEqual(backend.snapshot().reviewPayloads.last?["card_cover_type"] as? String, "jpeg")
        let repository = RealStoryRepository(key: "sb_publishable_testing", session: session)
        let details = try await repository.fetchPublicPostcardDetails(storyID: pending.id.uuidString)
        XCTAssertEqual(details?.coverType, .jpeg)
        XCTAssertTrue(details?.coverURL?.path.hasSuffix("/cover.jpg") == true)
        XCTAssertTrue(details?.backURL?.path.hasSuffix("/back.png") == true)
        backend.configure { $0.failCardCoverRead = true }
        let fallback = try await repository.fetchPublicPostcardDetails(storyID: pending.id.uuidString)
        XCTAssertNil(fallback?.coverURL)
        XCTAssertNotNil(fallback?.frontURL)
        await store.signOut()
        XCTAssertFalse(store.canPublishStoryCardCoverJPEG)
    }

    @MainActor func testJPEGCoverFallsBackToRealPNGOnPNGOnlyServer() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.isOperator = true; $0.publicStoryCard = true; $0.duplexStoryCard = true; $0.storyCardCover = true }
        await store.start()
        XCTAssertFalse(store.canPublishStoryCardCoverJPEG)
        let jpeg = try jpegCard(), png = try jpeg.withPNGCover()
        XCTAssertNotEqual(jpeg.id, png.id)
        let saved = await store.save(draft())
        let submitted = await store.submitStory(try XCTUnwrap(saved), card: jpeg)
        var pending = try XCTUnwrap(submitted)
        XCTAssertEqual(pending.cardSnapshotId, png.id)
        XCTAssertEqual(pending.cardSnapshotFormat, 3)
        let path = try XCTUnwrap(pending.cardArtworkPaths.last)
        XCTAssertTrue(path.hasSuffix("/cover.png"))
        let data = try XCTUnwrap(backend.snapshot().uploads["oi-story-media/" + path])
        _ = try OiPublishedStoryCover.decode(data, type: .png)
        XCTAssertEqual(backend.snapshot().uploadContentTypes["oi-story-media/" + path], "image/png")
        XCTAssertFalse(backend.snapshot().uploads.keys.contains { $0.hasSuffix("/cover.jpg") })
        // A pre-JPEG server omits the metadata column entirely.
        backend.configure { $0.story?.removeValue(forKey: "card_cover_type") }
        pending.cardCoverType = nil
        _ = try await store.reviewOperatorStory(pending, publish: true)
        let details = try await RealStoryRepository(key: "sb_publishable_testing", session: session)
            .fetchPublicPostcardDetails(storyID: pending.id.uuidString)
        XCTAssertEqual(details?.coverType, .png)
        XCTAssertTrue(details?.coverURL?.path.hasSuffix("/cover.png") == true)
    }

    @MainActor func testJPEGCoverRejectsWrongSubmissionTypeIncludingTimeout() async throws {
        for timeout in [false, true] {
            let (store, backend, _, session, directory) = try context()
            defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
            backend.configure { $0.publicStoryCard = true; $0.duplexStoryCard = true; $0.storyCardCover = true; $0.storyCardCoverJpeg = true; $0.corruptSubmittedCoverType = true; $0.timeOutSubmitAfterCommit = timeout }
            await store.start()
            let saved = await store.save(draft())
            let result = await store.submitStory(try XCTUnwrap(saved), card: try jpegCard())
            XCTAssertNil(result, "Matching snapshot IDs with a different codec are not a confirmed submission")
            XCTAssertNotNil(store.error)
        }
    }

    @MainActor func testJPEGCoverRejectsWrongApprovalReceiptAndUnknownType() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.isOperator = true; $0.publicStoryCard = true; $0.duplexStoryCard = true; $0.storyCardCover = true; $0.storyCardCoverJpeg = true }
        await store.start()
        let saved = await store.save(draft())
        let submitted = await store.submitStory(try XCTUnwrap(saved), card: try jpegCard())
        var pending = try XCTUnwrap(submitted)
        pending.cardCoverType = "future-codec"
        XCTAssertFalse(pending.hasSupportedCardArtwork)
        do { _ = try await store.reviewOperatorStory(pending, publish: true); XCTFail("Unknown cover types cannot be approved") } catch {}
        XCTAssertEqual(backend.snapshot().reviewCount, 0)
        pending.cardCoverType = "jpeg"
        backend.configure { $0.corruptReviewedCoverType = true }
        do { _ = try await store.reviewOperatorStory(pending, publish: true); XCTFail("Wrong type receipt must be rejected") }
        catch { XCTAssertTrue(error is OiOperatorStoryError) }
    }

    @MainActor func testCoverFallsBackToSameDuplexVersionOnOlderServer() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.publicStoryCard = true; $0.duplexStoryCard = true }
        await store.start()
        XCTAssertFalse(store.canPublishStoryCardCover)
        let input = draft()
        let preview = OiDraftCardPreview(draft: input, customization: OiDraftCustomization())
        let card = try preview.publication(colorScheme: .light, includeCover: true)
        let legacy = try card.withoutCover()
        XCTAssertEqual(legacy.id, try preview.publication(colorScheme: .light).id)
        let savedReceipt = await store.save(input)
        let receipt = await store.submitStory(try XCTUnwrap(savedReceipt), card: card)
        XCTAssertEqual(receipt?.cardSnapshotFormat, 2)
        XCTAssertEqual(receipt?.cardSnapshotId, legacy.id)
        XCTAssertEqual(backend.snapshot().uploads.keys.filter { $0.contains("/card/") }.count, 4)
        XCTAssertFalse(backend.snapshot().uploads.keys.contains { $0.hasSuffix("/cover.png") })
    }

    @MainActor func testDuplexCardPartialUploadAndOldServerPreserveDraft() async throws {
        let (store, backend, _, session, directory) = try context()
        defer { withExtendedLifetime(backend) {}; clean(session, directory: directory) }
        backend.configure { $0.publicStoryCard = true }
        await store.start()
        let input = draft()
        let card = try OiDraftCardPreview(draft: input, customization: OiDraftCustomization()).publication(colorScheme: .light)
        let savedReceipt = await store.save(input)
        let saved = try XCTUnwrap(savedReceipt)
        let oldServer = await store.submitStory(saved, card: card)
        XCTAssertNil(oldServer)
        XCTAssertEqual(backend.snapshot().artworkUploadAttempts, 0, "Never silently downgrade a two-sided card")
        backend.configure { $0.duplexStoryCard = true; $0.failCardBackUpload = true }
        await store.refresh()
        let partial = await store.submitStory(saved, card: card)
        XCTAssertNil(partial)
        XCTAssertEqual(backend.snapshot().submitCount, 0)
        XCTAssertEqual(store.ownStories.first?.status, "draft")
        backend.configure { $0.failCardBackUpload = false }
        let retried = await store.submitStory(saved, card: card)
        XCTAssertEqual(retried?.status, "pending")
        XCTAssertEqual(retried?.cardSnapshotFormat, 2)
        XCTAssertEqual(backend.snapshot().uploads.keys.filter { $0.contains("/card/") }.count, 4)
        XCTAssertEqual(backend.snapshot().submitCount, 1)
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
        XCTAssertTrue(backend.snapshot().grantOwnerQueries.isEmpty, "Writing does not load donation grants")
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

    @MainActor func testFeatureUsagePersistsWithoutChangingOtherFeatures() throws {
        let suite = "OiFeatureUsage-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let usage = OiFeatureUsage(defaults: defaults)
        XCTAssertTrue(OiAppFeature.allCases.allSatisfy(usage.isEnabled))
        usage.setEnabled(false, for: .photos)
        let restored = OiFeatureUsage(defaults: defaults)
        XCTAssertFalse(restored.isEnabled(.photos))
        XCTAssertTrue(restored.isEnabled(.camera))
        XCTAssertTrue(restored.isEnabled(.location))
        XCTAssertThrowsError(try restored.require(.photos)) {
            XCTAssertEqual($0 as? OiFeatureUsageError, .disabled(.photos))
        }
        restored.setEnabled(true, for: .photos)
        XCTAssertNoThrow(try restored.require(.photos))
        XCTAssertTrue(OiFeatureUsage(defaults: defaults).isEnabled(.photos))
    }

    @MainActor func testDisabledFeaturesBlockLocationCameraAndPhotoStorage() async throws {
        let usage = OiFeatureUsage.shared
        let previous = Dictionary(uniqueKeysWithValues: OiAppFeature.allCases.map { ($0, usage.isEnabled($0)) })
        defer { for (feature, enabled) in previous { usage.setEnabled(enabled, for: feature) } }
        usage.setEnabled(false, for: .location)
        usage.setEnabled(false, for: .camera)
        usage.setEnabled(false, for: .photos)
        let bench = BenchLocationService()
        bench.locate()
        XCTAssertFalse(bench.isLocating)
        XCTAssertFalse(bench.isAuthorized)
        XCTAssertEqual(bench.notice?.message, OiFeatureUsageError.disabled(.location).localizedDescription)
        let location = CampusGeoLocation()
        location.start()
        XCTAssertNil(location.location)
        XCTAssertFalse(location.hasPreciseLocationPermission)
        XCTAssertEqual(location.message, OiFeatureUsageError.disabled(.location).localizedDescription)
        do {
            _ = try await CampusCardLocation().classify()
            XCTFail("Disabled location must not start a system permission or location request")
        } catch { XCTAssertEqual(error as? OiFeatureUsageError, .disabled(.location)) }
        let nearby = CampusNearbyARController()
        await nearby.start(location: location)
        XCTAssertFalse(nearby.ready)
        XCTAssertEqual(nearby.message, OiFeatureUsageError.disabled(.camera).localizedDescription)
        do {
            try await ARPhotoLibraryService().save(UIImage())
            XCTFail("Disabled photo storage must not prompt or save")
        } catch { XCTAssertEqual(error as? OiFeatureUsageError, .disabled(.photos)) }
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
    func testOversizedPNGImportsAndPreservesTransparencyInSavedArtwork() throws {
        let edge = 768
        var state: UInt32 = 0x9130abc
        var pixels = Data(count: edge * edge * 4)
        pixels.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) in
            for y in 0..<edge {
                // Leave the left edge transparent and use incompressible color on the rest.
                for x in 96..<edge {
                    state = 1664525 &* state &+ 1013904223
                    let i = (y * edge + x) * 4
                    buffer[i] = UInt8(truncatingIfNeeded: state >> 24)
                    buffer[i + 1] = UInt8(truncatingIfNeeded: state >> 16)
                    buffer[i + 2] = UInt8(truncatingIfNeeded: state >> 8)
                    buffer[i + 3] = 255
                }
            }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: pixels as CFData))
        let bitmap = CGBitmapInfo.byteOrder32Big.union(.init(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(CGImage(width: edge, height: edge, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: edge * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmap,
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let png = try XCTUnwrap(UIImage(cgImage: image).pngData())
        XCTAssertGreaterThan(png.count, OiWardrobeArtwork.maximumSourceBytes)

        let imported = try OiPhotoRenderer.asset(png)
        XCTAssertLessThanOrEqual(imported.data.count, OiWardrobeArtwork.maximumSourceBytes)
        let layer = OiPhotoLayer(source: imported.id, side: .front)
        var look = OiWardrobeLook()
        look.costume = .dinosaur
        let slot = OiPhotoSlot.top
        let layout = try OiPhotoPrintLayout.load(for: slot, in: look)
        let design = OiPhotoDesign(layers: [layer])
        try look.artwork.set(design, sources: [imported.id: imported.data], for: slot.itemID(in: look))
        let saved = try OiPhotoRenderer.load(design, sources: look.artwork.sources, layout: layout)
        let restoredImage = try XCTUnwrap(saved.assets[imported.id]?.image.cgImage)
        let importedImage = try XCTUnwrap(imported.image.cgImage)
        XCTAssertEqual(restoredImage.width, importedImage.width)
        XCTAssertEqual(restoredImage.height, importedImage.height)
        let preview = rgba(restoredImage, size: 8)
        XCTAssertEqual(preview[(4 * 8) * 4 + 3], 0, "The transparent edge survives saving")
        XCTAssertEqual(preview[(4 * 8 + 4) * 4 + 3], 255, "The center still contains the photo")
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
    func testWardrobePreviewRestoresAppliedAndEditingPhotosAfterReopening() async throws {
        var look = OiWardrobeLook()
        look.top = .hoodie
        let slot = OiPhotoSlot.top
        let layout = try OiPhotoPrintLayout.load(for: slot, in: look)
        let size = CGSize(width: 64, height: 64)
        func photo(_ color: UIColor) throws -> OiPhotoImageAsset {
            try OiPhotoRenderer.asset(UIGraphicsImageRenderer(size: size).image { context in
                color.setFill()
                context.fill(CGRect(origin: .zero, size: size))
            })
        }
        let saved = try photo(.magenta)
        try look.artwork.set(OiPhotoDesign(layers: [OiPhotoLayer(source: saved.id)]),
                             sources: [saved.id: saved.data], for: slot.itemID(in: look))

        let scene = OiWardrobeScene()
        let surface = OiWardrobeSurface(scene: scene, look: look)
        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKey = windowScene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: windowScene)
        let host = UIViewController()
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previousKey?.makeKey() }

        func open() -> RealityKit.ARView {
            let view = scene.install()
            view.frame = host.view.bounds
            host.view.addSubview(view)
            scene.update(look)
            return view
        }

        func close(_ view: RealityKit.ARView) {
            OiWardrobeSurface.dismantleUIView(view, coordinator: surface.makeCoordinator())
            view.removeFromSuperview()
        }

        func photoPixels(in view: RealityKit.ARView, matching color: (Int, Int, Int) -> Bool) async throws -> Int {
            for _ in 0..<200 where scene.loading { try await Task.sleep(for: .milliseconds(50)) }
            XCTAssertFalse(scene.loading)
            XCTAssertNil(scene.error)
            try await Task.sleep(for: .milliseconds(300))
            let image: UIImage? = await withCheckedContinuation { continuation in
                view.snapshot(saveToHDR: false) { continuation.resume(returning: $0) }
            }
            let pixels = rgba(try XCTUnwrap(image?.cgImage), size: 128)
            return stride(from: 0, to: pixels.count, by: 4).reduce(into: 0) { count, index in
                if color(Int(pixels[index]), Int(pixels[index + 1]), Int(pixels[index + 2])) { count += 1 }
            }
        }

        let magenta: (Int, Int, Int) -> Bool = { red, green, blue in min(red, blue) > green + 45 }
        let firstView = open()
        let firstCount = try await photoPixels(in: firstView, matching: magenta)
        XCTAssertGreaterThan(firstCount, 20)
        close(firstView)

        let reopenedView = open()
        let reopenedCount = try await photoPixels(in: reopenedView, matching: magenta)
        XCTAssertGreaterThan(reopenedCount, 20, "Reopening should render the selected hoodie and its saved photo")

        // The editor can produce a new photo while the SwiftUI surface is being replaced.
        scene.editPhotos(in: slot, look: look)
        close(reopenedView)
        let editing = try photo(.blue)
        let atlas = OiPhotoRenderer.atlas(layers: [OiPhotoLayer(source: editing.id)], assets: [editing.id: editing],
                                         panelSize: 256, color: look.topColor, layout: layout)
        await scene.setPhotoPreview(try XCTUnwrap(atlas.cgImage))
        let editingView = open()
        let replacementView = open()
        close(editingView)
        defer { close(replacementView) }
        let editingCount = try await photoPixels(in: replacementView) { red, green, blue in
            blue > max(red, green) + 45
        }
        XCTAssertGreaterThan(editingCount, 20, "A late teardown should not hide the reopened live photo preview")
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
    func testRoundedFramesClipMovedRotatedPhotosOnEveryCostume() throws {
        let solid = try OiPhotoRenderer.asset(UIImage(cgImage: canvas { cg in
            cg.setFillColor(UIColor.magenta.cgColor); cg.fill(CGRect(x: 0, y: 0, width: 1024, height: 512))
        }))
        for look in looks where look.costume != nil {
            let resource = OiPhotoSlot.top.resource(in: look)
            let layout = try OiPhotoPrintLayout.load(for: .top, in: look)
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

    func testIndividualGarmentsKeepFullUVAndSavedPlacements() throws {
        let square = try XCTUnwrap(canvas { cg in
            cg.setFillColor(UIColor.red.cgColor); cg.fill(CGRect(x: 0, y: 0, width: 1024, height: 512))
        }.cropping(to: CGRect(x: 0, y: 0, width: 512, height: 512)))
        let photo = try OiPhotoRenderer.asset(UIImage(cgImage: square))
        for top in OiWardrobeLook.Top.allCases {
            for bottom in OiWardrobeLook.Bottom.allCases {
                var look = OiWardrobeLook(); look.top = top; look.bottom = bottom
                for slot in OiPhotoSlot.allCases {
                    let layout = try OiPhotoPrintLayout.load(for: slot, in: look)
                    let layers = OiPhotoSide.allCases.map { OiPhotoLayer(source: photo.id, side: $0,
                        placement: OiPhotoPlacement(x: 0.42, y: 0.56, width: 0.72, rotation: 27)) }
                    for revision in [nil, 1, 2] as [Int?] {
                        let design = OiPhotoDesign(frameRevision: revision, layers: layers)
                        let restored = try OiPhotoRenderer.load(design, sources: [photo.id: photo.data], layout: layout)
                        XCTAssertEqual(restored.layers, layers, "Individual garments must not relocate saved photos")
                        XCTAssertEqual(restored.assets[photo.id]?.data, photo.data)
                    }
                    // A photo spanning the UV panel must paint beyond the small
                    // costume frame, including all four corners on both sides.
                    let fill = OiPhotoSide.allCases.map { OiPhotoLayer(source: photo.id, side: $0,
                        placement: OiPhotoPlacement(width: 1.5)) }
                    let atlas = try XCTUnwrap(OiPhotoRenderer.atlas(layers: fill, assets: [photo.id: photo],
                        panelSize: 64, color: 0xFFFFFF, transparent: true, layout: layout).cgImage)
                    for (index, side) in OiPhotoSide.allCases.enumerated() {
                        let panel = try XCTUnwrap(atlas.cropping(to: CGRect(x: index*64, y: 0, width: 64, height: 64)))
                        let pixels = rgba(panel, size: 64)
                        for y in [0, 32, 63] { for x in [0, 32, 63] {
                            let offset = (y*64+x)*4
                            XCTAssertGreaterThan(pixels[offset], 250)
                            XCTAssertLessThan(pixels[offset+1], 5)
                            XCTAssertEqual(pixels[offset+3], 255)
                        }}
                        let name = slot.resource(in: look) + "-" + side.rawValue
                        let guide = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "WardrobePhotoUV")
                            ?? Bundle.main.url(forResource: name, withExtension: "json"))
                        let edges = try JSONDecoder().decode([[[Double]]].self, from: Data(contentsOf: guide))
                        XCTAssertFalse(edges.isEmpty, "Both UV outlines must remain available")
                    }
                }
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
        if let top = ProcessInfo.processInfo.environment["OI_PHOTO_PLAIN_SNAPSHOT"].flatMap(OiWardrobeLook.Top.init(rawValue:)) {
            look.costume = nil; look.top = top
        }
        let asset = try OiPhotoRenderer.asset(UIImage(cgImage: canvas { cg in
            cg.setFillColor(UIColor.systemTeal.cgColor); cg.fill(CGRect(x: 0, y: 0, width: 1024, height: 512))
            ("OI PHOTO" as NSString).draw(at: CGPoint(x: 180, y: 180), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 90)])
        }))
        let frame = try OiPhotoPrintLayout.load(for: .top, in: look).front
        let placement = look.costume == nil ? OiPhotoPlacement() : frame.placement(for: asset.image)
        try look.artwork.set(OiPhotoDesign(layers: [OiPhotoLayer(source: asset.id, placement: placement)]),
            sources: [asset.id: asset.data], for: OiPhotoSlot.top.itemID(in: look))
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
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .seconds(3))
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = "photo-editor-\(look.costume == nil ? "uv" : "rounded")-\(empty ? "empty" : "photo")"; attachment.lifetime = .keepAlways; add(attachment)
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
        for look in looks where look.costume != nil {
            let layout = try OiPhotoPrintLayout.load(for: .top, in: look)
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
        defer { scene.uninstall(view); window.isHidden = true }
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
            let layout = try OiPhotoPrintLayout.load(for: .top, in: look)
            let layers = OiPhotoSide.allCases.map { OiPhotoLayer(source: photo.id, side: $0,
                placement: look.costume == nil ? OiPhotoPlacement() : layout[$0].placement(for: photo.image)) }
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

/// Load the shipped USDZs with the same RealityKit path as customization/cards.
/// A valid ZIP alone cannot catch unsupported materials or missing bundled textures.
@MainActor
final class OiWardrobeAssetTests: XCTestCase {
    func testFittedCardiganShortsKeepShapeWhenPhotosAreAppliedAndRemoved() async throws {
        var plain = OiWardrobeLook(); plain.top = .cardigan; plain.bottom = .shorts
        plain.topColor = 0xD7CBB8; plain.bottomColor = 0xD7CBB8
        let (base, _) = try await OiWardrobeAsset.prepare(plain)
        let bottom = try XCTUnwrap(base.findEntity(named: "Bottom"))
        // The original protruding shorts reached +0.192m; the approved fit ends at +0.157m.
        XCTAssertEqual(bottom.visualBounds(relativeTo: base).max.z, 0.156525, accuracy: 0.001)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { context in
            UIColor.magenta.setFill(); context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }
        let asset = try OiPhotoRenderer.asset(image)
        var printed = plain
        for slot in OiPhotoSlot.allCases {
            let design = OiPhotoDesign(layers: [OiPhotoLayer(source: asset.id), OiPhotoLayer(source: asset.id, side: .back)])
            try printed.artwork.set(design, sources: [asset.id: asset.data], for: slot.itemID(in: printed))
        }
        let restored = try JSONDecoder().decode(OiWardrobeLook.self, from: JSONEncoder().encode(printed))
        XCTAssertEqual(restored, printed)
        let (root, overlays) = try await OiWardrobeAsset.prepare(restored)
        XCTAssertEqual(overlays.count, OiPhotoSlot.allCases.count)
        for slot in OiPhotoSlot.allCases {
            let garment = try XCTUnwrap(root.findEntity(named: slot.role))
            let overlay = try XCTUnwrap(overlays[slot])
            let expected = garment.visualBounds(relativeTo: root)
            let actual = overlay.visualBounds(relativeTo: nil)
            for axis in 0..<3 {
                XCTAssertEqual(actual.min[axis], expected.min[axis], accuracy: 0.00001, slot.role)
                XCTAssertEqual(actual.max[axis], expected.max[axis], accuracy: 0.00001, slot.role)
            }
        }
        OiWardrobeAsset.assemble(restored, root: root, overlays: overlays)
        for slot in OiPhotoSlot.allCases {
            XCTAssertFalse(try XCTUnwrap(root.findEntity(named: slot.role)).isEnabled)
            XCTAssertTrue(overlays[slot]?.parent === root)
        }
        let (removed, remaining) = try await OiWardrobeAsset.prepare(plain, existing: root)
        OiWardrobeAsset.assemble(plain, root: removed, overlays: remaining)
        XCTAssertTrue(remaining.isEmpty)
        for slot in OiPhotoSlot.allCases {
            XCTAssertTrue(try XCTUnwrap(removed.findEntity(named: slot.role)).isEnabled)
        }
        XCTAssertEqual(removed.visualBounds(relativeTo: nil).extents.y, 1.5, accuracy: 0.005)

        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: windowScene)
        let controller = UIViewController()
        window.frame = CGRect(x: 0, y: 0, width: 480, height: 600)
        window.rootViewController = controller; window.isHidden = false
        let scene = OiWardrobeScene()
        let view = scene.install(); view.frame = window.bounds
        controller.view.addSubview(view)
        defer {
            scene.uninstall(view); view.removeFromSuperview()
            window.isHidden = true; window.rootViewController = nil; window.windowScene = nil
        }
        for (name, look) in [("plain", plain), ("photos", restored), ("removed", plain)] {
            scene.update(look)
            for _ in 0..<200 where scene.loading { try await Task.sleep(for: .milliseconds(100)) }
            XCTAssertFalse(scene.loading); XCTAssertNil(scene.error)
            for (angleName, angle) in [("side", -Float.pi / 2), ("angle", -Float.pi / 3)] {
                scene.angle(angle)
                try await Task.sleep(for: .milliseconds(650))
                let image: UIImage? = await withCheckedContinuation { c in
                    view.snapshot(saveToHDR: false) { c.resume(returning: $0) }
                }
                let attachment = XCTAttachment(image: try XCTUnwrap(image))
                attachment.name = "cardigan-fit-\(name)-\(angleName)"
                attachment.lifetime = .keepAlways; add(attachment)
            }
        }
    }

    func testModularOutfitsKeepApprovedSkinAndRenderInWardrobe() async throws {
        func checkSkin(_ entity: Entity, role: String = "") -> Int {
            let current = entity.name.hasPrefix("Skin_") ? entity.name : role
            var count = 0
            if current.hasPrefix("Skin_"), let model = entity.components[ModelComponent.self] {
                for material in model.materials {
                    guard let skin = material as? PhysicallyBasedMaterial else {
                        XCTFail("Skin must load as PBR: \(entity.name)"); continue
                    }
                    XCTAssertNotNil(skin.baseColor.texture, entity.name)
                    XCTAssertNotNil(skin.normal.texture, entity.name)
                    XCTAssertEqual(skin.roughness.scale, 155 / 255, accuracy: 0.0001, entity.name)
                    XCTAssertNil(skin.roughness.texture, entity.name)
                    XCTAssertEqual(skin.metallic.scale, 0, entity.name)
                    count += 1
                }
            }
            return count + entity.children.reduce(0) { $0 + checkSkin($1, role: current) }
        }
        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: windowScene)
        let controller = UIViewController()
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 500)
        window.rootViewController = controller; window.isHidden = false
        let scene = OiWardrobeScene()
        let view = scene.install(); view.frame = window.bounds
        controller.view.addSubview(view)
        defer {
            scene.uninstall(view); view.removeFromSuperview()
            window.isHidden = true; window.rootViewController = nil; window.windowScene = nil
        }
        for top in OiWardrobeLook.Top.allCases {
            for bottom in OiWardrobeLook.Bottom.allCases {
                var look = OiWardrobeLook(); look.top = top; look.bottom = bottom
                let (model, overlays) = try await OiWardrobeAsset.prepare(look)
                let expected = bottom == .shorts ? 5 : 3
                XCTAssertEqual(checkSkin(model), expected, look.modelName)
                OiWardrobeAsset.assemble(look, root: model, overlays: overlays)
                XCTAssertEqual(checkSkin(model), expected, "Clothing tint must preserve the skin material")
                XCTAssertEqual(model.visualBounds(relativeTo: nil).extents.y, 1.5, accuracy: 0.005)
                scene.update(look)
                for _ in 0..<200 {
                    if !scene.loading { break }
                    try await Task.sleep(for: .milliseconds(100))
                }
                XCTAssertFalse(scene.loading, look.modelName); XCTAssertNil(scene.error, look.modelName)
                try await Task.sleep(for: .seconds(1))
                let image: UIImage? = await withCheckedContinuation { c in
                    view.snapshot(saveToHDR: false) { c.resume(returning: $0) }
                }
                let attachment = XCTAttachment(image: try XCTUnwrap(image, look.modelName))
                attachment.name = "wardrobe-skin-" + look.modelName
                attachment.lifetime = .keepAlways; add(attachment)
            }
        }
    }

    @MainActor func testCardRotationSymbolExists() {
        XCTAssertNotNil(UIImage(systemName: "rotate.3d"))
    }

    func testCompleteCostumesLoadWithThumbnailsAndGroundedBounds() async throws {
        for costume in OiWardrobeLook.Costume.allCases {
            var look = OiWardrobeLook()
            look.costume = costume
            let url = try OiWardrobeAsset.url(look.modelName, folder: "Wardrobe")
            let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            XCTAssertGreaterThan(bytes, 0, costume.rawValue)
            XCTAssertLessThan(bytes, 12 * 1_024 * 1_024, "Costume exceeds the mobile asset budget: \(costume.rawValue)")
            let thumbnail = try XCTUnwrap(Bundle.main.url(forResource: costume.thumbnailName, withExtension: "png"), costume.rawValue)
            XCTAssertNotNil(UIImage(contentsOfFile: thumbnail.path), "Missing/invalid thumbnail: \(costume.rawValue)")

            let (model, overlays) = try await OiWardrobeAsset.prepare(look)
            OiWardrobeAsset.assemble(look, root: model, overlays: overlays)
            XCTAssertTrue(overlays.isEmpty, "Complete costumes must retain their authored materials")
            let bounds = model.visualBounds(relativeTo: nil)
            XCTAssertEqual(bounds.extents.y, 1.5, accuracy: 0.005, costume.rawValue)
            XCTAssertEqual(bounds.min.y, 0, accuracy: 0.005, costume.rawValue)
            XCTAssertGreaterThan(bounds.extents.x, 0.1, costume.rawValue)
            XCTAssertGreaterThan(bounds.extents.z, 0.1, costume.rawValue)
            XCTAssertGreaterThan(materialCount(in: model), 0, "No renderable materials: \(costume.rawValue)")
        }
    }

    func testNewCostumesRenderInWardrobePreview() async throws {
        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: windowScene)
        let controller = UIViewController()
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 500)
        window.rootViewController = controller
        window.isHidden = false
        defer {
            window.isHidden = true
            window.rootViewController = nil
            window.windowScene = nil
        }
        let scene = OiWardrobeScene()
        let view = scene.install()
        view.frame = window.bounds
        controller.view.addSubview(view)
        defer { scene.uninstall(view); view.removeFromSuperview() }
        for costume in OiWardrobeLook.Costume.allCases {
            var look = OiWardrobeLook(); look.costume = costume
            scene.update(look)
            for _ in 0..<200 {
                if !scene.loading { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            XCTAssertFalse(scene.loading, costume.rawValue)
            XCTAssertNil(scene.error, costume.rawValue)
            try await Task.sleep(for: .seconds(1))
            // UIKit drawHierarchy omits Metal contents; capture the actual RealityKit render.
            let image: UIImage? = await withCheckedContinuation { continuation in
                view.snapshot(saveToHDR: false) { continuation.resume(returning: $0) }
            }
            let rendered = try XCTUnwrap(image, costume.rawValue)
            let attachment = XCTAttachment(image: rendered)
            attachment.name = "wardrobe-render-" + costume.rawValue
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testCostumePhotosKeepBaseAndRoundTripPerOutfit() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }
        let asset = try OiPhotoRenderer.asset(image)
        var looks = OiWardrobeLook.Costume.allCases.map { costume in
            var look = OiWardrobeLook(); look.costume = costume; return look
        }
        for bottom in [OiWardrobeLook.Bottom.long, .shorts] {
            var look = OiWardrobeLook(); look.top = .postech; look.bottom = bottom; looks.append(look)
        }
        for var look in looks {
            let slot = OiPhotoSlot.top
            let layers = [OiPhotoLayer(source: asset.id), OiPhotoLayer(source: asset.id, side: .back)]
            try look.artwork.set(OiPhotoDesign(layers: layers), sources: [asset.id: asset.data], for: slot.itemID(in: look))
            let restored = try JSONDecoder().decode(OiWardrobeLook.self, from: JSONEncoder().encode(look))
            XCTAssertEqual(restored, look)
            let (root, prints) = try await OiWardrobeAsset.prepare(restored)
            let before = materialCount(in: root)
            XCTAssertNil(prints[.top], "Complete costumes bake photos into the existing materials")
            OiWardrobeAsset.assemble(restored, root: root, overlays: prints)
            XCTAssertEqual(materialCount(in: root), before)
            if look.costume == nil {
                XCTAssertTrue(root.findEntity(named: "Top")?.isEnabled ?? false, "The varsity jacket must remain visible under the photo")
            }
            XCTAssertEqual(root.visualBounds(relativeTo: nil).extents.y, 1.5, accuracy: 0.005)
        }
    }

    func testCostumePhotoAtlasKeepsUnprintedPixelsTransparent() throws {
        let red = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { c in
            UIColor.red.setFill(); c.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
        let asset = try OiPhotoRenderer.asset(red)
        let layout = try OiPhotoPrintLayout.load(resource: "photo-wardrobe-costume-astronaut-top")
        let center = layout.front.rect(edge: 64)
        let layer = OiPhotoLayer(source: asset.id, placement: layout.front.placement(for: red))
        let atlas = OiPhotoRenderer.atlas(layers: [layer], assets: [asset.id: asset],
                                          panelSize: 64, color: 0xFFFFFF, transparent: true, layout: layout)
        let cg = try XCTUnwrap(atlas.cgImage)
        var rgba = [UInt8](repeating: 0, count: 128 * 64 * 4)
        let context = try XCTUnwrap(CGContext(data: &rgba, width: 128, height: 64, bitsPerComponent: 8,
            bytesPerRow: 128 * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cg, in: CGRect(x: 0, y: 0, width: 128, height: 64))
        XCTAssertEqual(rgba[(Int(center.midY) * 128 + Int(center.midX)) * 4 + 3], 255, "Front photo is opaque")
        XCTAssertEqual(rgba[(1 * 128 + 1) * 4 + 3], 0, "Original cloth remains visible outside the photo")
        XCTAssertEqual(rgba[(32 * 128 + 96) * 4 + 3], 0, "An empty back must not acquire a white coating")
    }

    private func materialCount(in entity: Entity) -> Int {
        (entity.components[ModelComponent.self]?.materials.count ?? 0)
            + entity.children.reduce(0) { $0 + materialCount(in: $1) }
    }
}

extension OiRemoteStoreTests {
    @MainActor func testWardrobeModelCacheSharesLoadingAndKeepsClonesIndependent() async throws {
        var loads = 0
        let cache = OiWardrobeModelCache(observePressure: false) { _ in
            loads += 1
            try await Task.sleep(for: .milliseconds(40))
            let root = Entity(); let child = Entity(); child.name = "Original"
            root.addChild(child)
            return root
        }
        let url = URL(fileURLWithPath: "/selected.usdz")
        let cancelled = Task { try await cache.clone(from: url) }
        let surviving = Task { try await cache.clone(from: url) }
        try await Task.sleep(for: .milliseconds(10)); cancelled.cancel()
        do { _ = try await cancelled.value; XCTFail("Cancelled callers must not publish a model") }
        catch is CancellationError { }
        let first = try await surviving.value
        first.children.first?.name = "Edited"
        let second = try await cache.clone(from: url)
        XCTAssertEqual(loads, 1)
        XCTAssertFalse(first === second)
        XCTAssertEqual(second.children.first?.name, "Original", "One renderer must not modify another renderer's source")
        cache.clear()
        _ = try await cache.clone(from: url)
        XCTAssertEqual(loads, 2, "Memory-pressure eviction must discard the retained source")
    }

    @MainActor func testWardrobeModelCacheBoundsLoadingAndRetainsOnlyLastSelection() async throws {
        var active = 0, maximumActive = 0, loads = 0
        let cache = OiWardrobeModelCache(observePressure: false) { _ in
            active += 1; maximumActive = max(maximumActive, active); loads += 1
            defer { active -= 1 }
            try await Task.sleep(for: .milliseconds(30))
            return Entity()
        }
        let a = URL(fileURLWithPath: "/a.usdz"), b = URL(fileURLWithPath: "/b.usdz")
        let first = Task { try await cache.clone(from: a) }
        try await Task.sleep(for: .milliseconds(5))
        let second = Task { try await cache.clone(from: b) }
        _ = try await first.value; _ = try await second.value
        XCTAssertEqual(maximumActive, 1)
        _ = try await cache.clone(from: b)
        XCTAssertEqual(loads, 2)
        _ = try await cache.clone(from: a)
        XCTAssertEqual(loads, 3, "Previous selections must not accumulate in memory")
    }

    @MainActor func testPortraitImageWorkerPreservesResolutionAlphaAndReusesValidatedImage() async throws {
        let worker = OiPortraitImages()
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        let original = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 100), format: format).image { context in
            UIColor.green.setFill(); context.fill(CGRect(x: 20, y: 20, width: 40, height: 60))
            UIColor.black.setFill(); context.fill(CGRect(x: 30, y: 30, width: 5, height: 5))
        }
        let encoded = await worker.encode(original, key: "look-angle-a")
        let data = try XCTUnwrap(encoded)
        let firstValue = await worker.restore(data, key: "look-angle-a")
        let first = try XCTUnwrap(firstValue)
        let secondValue = await worker.restore(data, key: "look-angle-a")
        let second = try XCTUnwrap(secondValue)
        XCTAssertTrue(first === second)
        XCTAssertEqual(first.cgImage?.width, 80); XCTAssertEqual(first.cgImage?.height, 100)
        XCTAssertEqual(data, original.pngData(), "PNG bytes must not be recompressed at a lower quality")
        XCTAssertTrue(OiPortraitMatte.hasTransparentBackground(first))
        let opaque = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 100)).image { context in
            UIColor.black.setFill(); context.fill(CGRect(x: 0, y: 0, width: 80, height: 100))
        }
        let rejected = await worker.restore(try XCTUnwrap(opaque.pngData()), key: "look-angle-a")
        XCTAssertNil(rejected, "A matching key must never bypass alpha validation for different bytes")
        let otherAngle = await worker.cached(key: "different-angle")
        XCTAssertNil(otherAngle)
        await worker.clear()
        let evicted = await worker.cached(key: "look-angle-a")
        XCTAssertNil(evicted)
        let restoredValue = await worker.restore(data, key: "look-angle-a")
        let restored = try XCTUnwrap(restoredValue)
        XCTAssertTrue(OiPortraitMatte.hasTransparentBackground(restored))
        XCTAssertEqual(restored.cgImage?.width, 80)
    }
}


extension OiRemoteStoreTests {
    @MainActor func testPortraitMatteMatchesOriginalPixelOutputIncludingBlackFeatures() throws {
        func linear(_ n: UInt8) -> Double {
            let value = Double(n) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        func encoded(_ n: Double) -> UInt8 {
            UInt8(((n <= 0.0031308 ? n * 12.92 : 1.055 * pow(n, 1 / 2.4) - 0.055) * 255).rounded())
        }
        var black = [UInt8](), white = [UInt8]()
        for y in 0..<32 {
            for x in 0..<32 {
                let alpha = [0.0, 1, 0.25, 0.5, 0.75, 1][x % 6]
                let color = y % 4 == 0 ? [0, 0, 0] : [x * 7 % 256, y * 9 % 256, (x + y) * 5 % 256]
                black += color.map { encoded(alpha * linear(UInt8($0))) } + [255]
                white += color.map { encoded(alpha * linear(UInt8($0)) + 1 - alpha) } + [255]
            }
        }
        func image(_ bytes: [UInt8]) throws -> UIImage {
            let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
            let cg = try XCTUnwrap(CGImage(width: 32, height: 32, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: 128, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent))
            return UIImage(cgImage: cg)
        }
        let result = try XCTUnwrap(OiPortraitMatte.image(black: image(black), white: image(white)))
        let pixels = try XCTUnwrap(result.cgImage?.dataProvider?.data) as Data
        // Golden hash from the original transparent-matte-v1 formula, before optimization.
        XCTAssertEqual(SHA256.hash(data: pixels).map { String(format: "%02x", $0) }.joined(),
            "a27fce77483f2c23c0578e810b61027dd0afeb19869c91632d74ecd21c55f39c")
        XCTAssertTrue(OiPortraitMatte.hasTransparentBackground(result))
    }
}

extension OiRemoteStoreTests {
    @MainActor func testWardrobeModelCacheRecoversAfterFailureAndEvictionDuringLoading() async throws {
        var loads = 0
        let cache = OiWardrobeModelCache(observePressure: false) { _ in
            loads += 1
            try await Task.sleep(for: .milliseconds(30))
            if loads == 1 { throw CocoaError(.fileReadCorruptFile) }
            return Entity()
        }
        let url = URL(fileURLWithPath: "/retry.usdz")
        do { _ = try await cache.clone(from: url); XCTFail("Broken sources cannot be cached") } catch { }
        let request = Task { try await cache.clone(from: url) }
        try await Task.sleep(for: .milliseconds(10)); cache.clear()
        _ = try await request.value
        _ = try await cache.clone(from: url)
        XCTAssertEqual(loads, 3, "A load already in flight must not repopulate an evicted cache")
    }
}

@MainActor private final class OiPortraitRotationProbe: ObservableObject {
    @Published var orientation = OiCardOrientation()
}
@MainActor private struct OiPortraitRotationCheck: View {
    @ObservedObject var probe: OiPortraitRotationProbe
    let captured: (Data, String) -> Void
    var body: some View {
        OiCardPortraitCapture(look: OiWardrobeLook(), cacheKey: probe.orientation.cacheIdentity,
            orientation: probe.orientation, interactivePreview: true, onCapture: captured)
            .frame(width: 220, height: 308)
    }
}
extension OiRemoteStoreTests {
    @MainActor func testInteractivePortraitRecreatesCaptureSurfaceAfterRotation() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let probe = OiPortraitRotationProbe()
        let initial = probe.orientation.cacheIdentity
        let rotated = OiCardOrientation(yaw: 0.7, pitch: 0.1)
        let finished = expectation(description: "Both settled orientations captured")
        finished.expectedFulfillmentCount = 2
        var keys: [String] = [], images: [UIImage] = []
        window.rootViewController = UIHostingController(rootView: OiPortraitRotationCheck(probe: probe) { data, key in
            keys.append(key)
            if let image = UIImage(data: data) { images.append(image) }
            finished.fulfill()
            if key == initial {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(250))
                    probe.orientation = rotated
                }
            }
        })
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; window.windowScene = nil; previous?.makeKey() }
        await fulfillment(of: [finished], timeout: 30)
        XCTAssertEqual(keys, [initial, rotated.cacheIdentity])
        XCTAssertEqual(images.count, 2)
        for image in images { XCTAssertTrue(OiPortraitMatte.hasTransparentBackground(image)) }
        XCTAssertEqual(images.first?.cgImage?.width, images.last?.cgImage?.width)
        XCTAssertEqual(images.first?.cgImage?.height, images.last?.cgImage?.height)
    }
}
