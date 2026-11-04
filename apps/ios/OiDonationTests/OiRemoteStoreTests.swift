// Created by 이돈혁

import XCTest
import SwiftUI
import UIKit
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
        var nickname = "Owner A"
        var schoolID: String?
        var failReads = false
        var isOperator = false
        var failCapabilities = false
        var reviewCount = 0
        var failAfterReview = false
        var loseReviewResponse = false
        var holdReviewResponse = false
        var ignoreStoryStatusFilter = false
        var failRefreshToken = false
        var failLogout = false
        var logoutScopes: [String?] = []
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
        configure { $0.held = nil; $0.holdOwnerRead = false; $0.holdPostMergeRead = false; $0.holdReviewResponse = false }
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
        else if path.hasSuffix("/rpc/oi_resolve_card_request") || path.hasSuffix("/rpc/oi_card_requests") { status = 404 }
        else if path == "/functions/v1/account-merge", body["action"] as? String == "confirm" {
            state.mergeConfirmCount += 1
            state.canonicalAccountID = rawOwner
            result = ["account_id":rawOwner.uuidString,"already_merged":false]
        }
        else if path.contains("/object/authenticated/") {
            let key = path.replacingOccurrences(of: "/storage/v1/object/authenticated/", with: "")
            bytes = state.uploads[key]; if bytes == nil { status = 404 }
        } else if path.contains("/storage/v1/object/") {
            let key = path.replacingOccurrences(of: "/storage/v1/object/", with: "")
            if state.uploads[key] != nil { status = 409 }
            else { state.uploads[key] = raw; result = ["Key":key] }
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
        } else if path.hasSuffix("/rpc/oi_capabilities") {
            if state.failCapabilities { status = 503 }
            var capabilities: [String:Any] = ["operator":state.isOperator,"coins_enabled":false]
            if let canonical = state.canonicalAccountID {
                capabilities["account_id"] = canonical.uuidString
                capabilities["account_merge_enabled"] = true
                capabilities["account_member_ids"] = [Self.owner.uuidString,Self.other.uuidString]
            }
            result = capabilities
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
        } else if path.hasSuffix("/oi_schools") { result = [["id":"postech","name":"POSTECH"]] }
        else if path.hasSuffix("/oi_regions") { result = [["id":"pond","school_id":"postech","name":"Pond"]] }
        else if path.hasSuffix("/oi_assets") { result = [["id":"OiCats","kind":"cucumber","name":"Cats"]] }
        else if path.hasSuffix("/oi_profiles") {
            if request.httpMethod == "PATCH" {
                state.nickname = body["nickname"] as? String ?? state.nickname
                if let school = body["school_id"] { state.schoolID = school as? String }
            }
            result = [["id":owner.uuidString,"nickname":owner == Self.owner ? state.nickname : "Owner B","farmer_asset":"OiFarmer", "school_id":state.schoolID as Any? ?? NSNull()]]
        } else if path.hasSuffix("/oi_story_media") {
            result = state.paths.enumerated().map { position, path in
                ["id":UUID().uuidString,"story_id":state.story?["id"] ?? "","object_path":path,"position":position]
            }
        } else if path.hasSuffix("/oi_evidence_requests"), let evidence = state.evidence { result = [evidence] }
        else if path.hasSuffix("/oi_writing_grants") {
            if let url = request.url,
               let owner = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "user_id" })?.value {
                state.grantOwnerQueries.append(owner)
            }
            result = [["id":Self.grant.uuidString,"story_limit":5]]
        }
        let data = bytes ?? ((try? JSONSerialization.data(withJSONObject: result)) ?? Data())
        if (path.hasSuffix("/oi_stories") && owner == Self.owner && state.holdOwnerRead)
            || (path.hasSuffix("/rpc/oi_mutate") && body["p_action"] as? String == "review_story" && state.holdReviewResponse)
            || (path.hasSuffix("/rpc/oi_capabilities") && state.holdPostMergeRead && state.mergeConfirmCount > 0) {
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

final class OiRemoteStoreTests: XCTestCase {
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
