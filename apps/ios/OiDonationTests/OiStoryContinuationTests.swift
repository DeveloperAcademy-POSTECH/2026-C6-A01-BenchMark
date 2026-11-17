//
//  OiStoryContinuationTests.swift
//  OiDonationTests
//
//  Created by Codex on 2026/11/17.
//

import XCTest
import SwiftUI
@testable import OiDonation

@MainActor
final class OiStoryContinuationTests: XCTestCase {
    private let parent = UUID(uuidString: "c4180000-0000-4000-8000-000000000004")!
    private let child = UUID(uuidString: "c4180000-0000-4000-8000-000000000011")!

    private func draft() -> OiStoryDraft {
        var value = OiStoryDraft()
        value.id = child; value.title = "함께 이어가는 이야기"; value.body = "가상의 공개 이야기입니다."
        value.theme = "감사"; value.emotion = "기쁨"; value.cucumberName = "이어진오이"
        value.latitude = 36.01261057; value.longitude = 129.31972687
        return value
    }

    private func row() throws -> [String: Any] {
        var story = try draft().payload()
        story["user_id"] = OiTestBackend.other.uuidString
        story["revision"] = 1; story["status"] = "published"; story["created_at"] = "2026-11-17T00:00:00Z"
        return ["child_story_id": child.uuidString, "parent_story_id": parent.uuidString,
                "published_at": "2026-11-17T00:00:00+00:00", "read_at": NSNull(), "story": story]
    }

    func testPayloadDistinguishesPreserveSetAndClearAndOldDraftDecodes() throws {
        var value = draft(); value.continuedFromStoryID = parent
        XCTAssertNil(try value.payload()["continued_from_story_id"], "Omitted means preserve, not clear")
        value.updatesContinuation = true
        XCTAssertEqual(try value.payload()["continued_from_story_id"] as? String, parent.uuidString)
        value.continuedFromStoryID = nil
        XCTAssertTrue(try value.payload()["continued_from_story_id"] is NSNull)
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        old.removeValue(forKey: "continuedFromStoryID"); old.removeValue(forKey: "updatesContinuation")
        let decoded = try JSONDecoder().decode(OiStoryDraft.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertNil(decoded.continuedFromStoryID); XCTAssertNil(decoded.updatesContinuation)
        let caps = try JSONDecoder().decode(OiCapabilities.self, from: Data(#"{"operator":false,"coinsEnabled":false}"#.utf8))
        XCTAssertNil(caps.storyContinuations); XCTAssertNil(caps.storyContinuationNotifications)
    }

    func testExplicitClearMustReachServerWhenHiddenParentIsRedacted() throws {
        var json = try XCTUnwrap(try row()["story"] as? [String: Any]); json["status"] = "draft"
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let server = try decoder.decode(OiLiveStory.self, from: JSONSerialization.data(withJSONObject: json))
        var draft = OiStoryDraft(story: server)
        XCTAssertNil(server.continuedFromStoryId)
        XCTAssertTrue(OiCreationAccess.canRebase(draft, to: server))
        draft.updatesContinuation = true
        XCTAssertFalse(OiCreationAccess.canRebase(draft, to: server), "Explicit null must not be mistaken for no change")
        draft.continuedFromStoryID = parent
        XCTAssertFalse(OiCreationAccess.canRebase(draft, to: server))
        draft.updatesContinuation = nil
        XCTAssertTrue(OiCreationAccess.canRebase(draft, to: server), "Older drafts preserve the existing server relationship")
    }

    func testRPCUsesPublicReadAuthenticatedInboxBlockedFilterAndStableCursor() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [OiStoreURLProtocol.self]
        let session = URLSession(configuration: config), previous = OiStoreURLProtocol.handle
        defer { session.invalidateAndCancel(); OiStoreURLProtocol.handle = previous }
        let api = try OiServiceAPI(key: "sb_publishable_testing", session: session)
        let item = try row(), parent = parent, child = child
        let page = try JSONSerialization.data(withJSONObject: ["items": [item], "total": 21,
            "next_cursor": ["published_at": "2026-11-17T00:00:00+00:00", "child_story_id": child.uuidString]])
        OiStoreURLProtocol.handle = { request, client in
            let payload = (try? JSONSerialization.jsonObject(with: OiTestBackend.body(request))) as? [String: Any]
            XCTAssertEqual(payload?["p_blocked"] as? [String], [OiTestBackend.other.uuidString])
            if request.url?.path.hasSuffix("oi_read_story_continuation") == true {
                XCTAssertEqual(payload?["p_child"] as? String, child.uuidString)
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-token")
                client.respond(200, try! JSONSerialization.data(withJSONObject: item))
            } else if request.url?.path.hasSuffix("oi_story_continuation_counts") == true {
                XCTAssertEqual(payload?["p_stories"] as? [String], [parent.uuidString])
                client.respond(200, try! JSONSerialization.data(withJSONObject: [["story_id": parent.uuidString, "count": 21]]))
            } else {
                XCTAssertEqual(payload?["p_mine"] as? Bool, request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-token")
                if let before = payload?["p_before"] as? String {
                    XCTAssertEqual(before, "2026-11-17T00:00:00+00:00")
                    XCTAssertEqual(payload?["p_before_id"] as? String, child.uuidString)
                }
                client.respond(200, page)
            }
        }
        let first = try await api.continuations(parent: parent, blocked: [OiTestBackend.other])
        XCTAssertEqual(first.items.first?.story.id, child); XCTAssertEqual(first.total, 21)
        _ = try await api.continuations(mine: true, cursor: first.nextCursor, blocked: [OiTestBackend.other], token: "synthetic-token")
        let counts = try await api.continuationCounts([parent], blocked: [OiTestBackend.other])
        XCTAssertEqual(counts.first?.count, 21)
        let read = try await api.readContinuation(child, blocked: [OiTestBackend.other], token: "synthetic-token")
        XCTAssertEqual(read.parentStoryId, parent)
        OiStoreURLProtocol.handle = { _, client in client.respond(404, Data("{}".utf8)) }
        do { _ = try await api.continuations(parent: parent, blocked: []); XCTFail("Missing capability RPC must not look like an empty relation") }
        catch { XCTAssertTrue(error is OiContinuationError) }
    }

    func testCapabilityGatesSubmissionAndSupportedServerHydratesOwnerTarget() async throws {
        for supported in [false, true] {
            let backend = OiTestBackend(); backend.install()
            let fallback = OiStoreURLProtocol.handle, target = parent
            let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [OiStoreURLProtocol.self]
            let session = URLSession(configuration: config)
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer {
                session.invalidateAndCancel(); OiStoreURLProtocol.handle = nil
                try? FileManager.default.removeItem(at: directory); withExtendedLifetime(backend) {}
            }
            OiStoreURLProtocol.handle = { request, client in
                if request.url?.path.hasSuffix("oi_capabilities") == true {
                    client.respond(200, try! JSONSerialization.data(withJSONObject: ["operator": false, "coins_enabled": false,
                        "unapproved_drafts_enabled": true, "independent_story_creation": true,
                        "story_continuations": supported, "story_continuation_notifications": supported]))
                } else if request.url?.path.hasSuffix("oi_my_story_continuation_targets") == true {
                    let id = backend.snapshot().story?["id"] as? String ?? ""
                    client.respond(200, try! JSONSerialization.data(withJSONObject: id.isEmpty ? [] : [["story_id": id, "continued_from_story_id": target.uuidString]]))
                } else { fallback?(request, client) }
            }
            let api = try OiServiceAPI(key: "sb_publishable_testing", session: session)
            let remote = OiRemoteStore(api: api, drafts: OiDraftVault(directory: directory), vault: OiMemorySession())
            await remote.start()
            XCTAssertNil(remote.loadError); XCTAssertEqual(remote.supportsStoryContinuations, supported)
            var value = draft(); value.updatesContinuation = true; value.continuedFromStoryID = parent
            let saved = await remote.save(value)
            XCTAssertNotNil(saved)
            XCTAssertEqual(backend.snapshot().story?["continued_from_story_id"] as? String, supported ? parent.uuidString : nil)
            if supported {
                await remote.refresh()
                XCTAssertNil(remote.loadError)
                XCTAssertEqual(remote.ownStories.first?.continuedFromStoryId, parent)
            }
        }
    }

    func testNotificationRetentionAndCaptureDoesNotClaimPayment() async throws {
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let item = try decoder.decode(OiStoryContinuation.self, from: JSONSerialization.data(withJSONObject: row()))
        let remote = OiRemoteStore(api: nil)
        let now = ISO8601DateFormatter().date(from: "2026-11-17T01:00:00Z")!
        let notices = CampusNotificationSheet.notices([item], remote: remote, now: now)
        XCTAssertEqual(notices.count, 1); XCTAssertTrue(notices[0].isUnread)
        XCTAssertTrue(CampusNotificationSheet.notices([item], remote: remote, now: now.addingTimeInterval(31 * 86400)).isEmpty)
        let view = CampusNotificationInboxView(requests: [], isLoading: false,
            onOpenRequest: { _ in }, continuations: notices, onOpenContinuation: { _ in })
            .frame(width: 402, height: 650).background(CampusStyle.mapSheet)
        try await capture(view, name: "continuation-notification")
    }

    func testPublicListMYAndReadReceiptRejectLateAccountResponse() async throws {
        let backend = OiTestBackend(); backend.install()
        backend.configure { $0.storyContinuations = true; $0.storyContinuationNotifications = true }
        let fallback = OiStoreURLProtocol.handle
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [OiStoreURLProtocol.self]
        let session = URLSession(configuration: config)
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let defaultsName = "OiContinuationCapture.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer {
            session.invalidateAndCancel(); OiStoreURLProtocol.handle = nil
            try? FileManager.default.removeItem(at: directory); defaults.removePersistentDomain(forName: defaultsName)
            withExtendedLifetime(backend) {}
        }
        let item = try row(), parent = parent
        let page = try JSONSerialization.data(withJSONObject: ["items": [item], "total": 1, "next_cursor": NSNull()])
        let itemData = try JSONSerialization.data(withJSONObject: item)
        let held = expectation(description: "Read receipt is in flight")
        OiStoreURLProtocol.handle = { request, client in
            switch request.url?.lastPathComponent {
            case "oi_my_story_continuation_targets": client.respond(200, Data("[]".utf8))
            case "oi_story_continuations": client.respond(200, page)
            case "oi_story_continuation_counts":
                client.respond(200, try! JSONSerialization.data(withJSONObject: [["story_id": parent.uuidString,"count": 1]]))
            case "oi_read_story_continuation":
                backend.configure { $0.held = (client, itemData) }; held.fulfill()
            default: fallback?(request, client)
            }
        }
        let remote = OiRemoteStore(api: try OiServiceAPI(key: "sb_publishable_testing", session: session),
            drafts: OiDraftVault(directory: directory), vault: OiMemorySession())
        await remote.start(); XCTAssertNil(remote.loadError)
        let store = CampusStoryStore(defaults: defaults)
        try await capture(NavigationStack { OiContinuationList(parent: parent, store: store).environment(remote) },
            name: "parent-story-continuations")
        XCTAssertEqual(remote.continuationCounts[parent], 1)
        XCTAssertNotNil(store.story(child.uuidString))
        try await capture(NavigationStack {
            MYWorkshopView(demo: MYLibraryStore(), remote: remote, initialTab: .connected)
                .environment(remote).environment(store)
        }, name: "my-incoming-continuations")
        XCTAssertEqual(remote.incomingContinuationCount, 1)
        backend.configure { $0.storyContinuations = false; $0.storyContinuationNotifications = false }
        await remote.refresh()
        XCTAssertNil(remote.incomingContinuationCount, "Disabling the capability must invalidate previous counts")
        XCTAssertTrue(remote.continuationCounts.isEmpty)
        backend.configure { $0.storyContinuations = true; $0.storyContinuationNotifications = true }
        await remote.refresh()
        XCTAssertNil(remote.incomingContinuationCount, "Re-enabling must reload, not resurrect an old count")
        let request = Task { try await remote.readStoryContinuation(child) }
        await fulfillment(of: [held], timeout: 5)
        await remote.signOut(); backend.releaseHeldRead()
        do { _ = try await request.value; XCTFail("A late notification must not open after sign out") }
        catch OiServiceError.accountChanged { }
        XCTAssertNil(remote.incomingContinuationCount)
        XCTAssertTrue(remote.continuationCounts.isEmpty)
    }

    func testContinuationIntentResolvesOnlyForEligibleNewDraftOwner() throws {
        let owner = OiTestBackend.owner
        let author = OiTestBackend.other
        let story = CampusStory(id: parent.uuidString, regionID: "pond", title: "이어갈오이",
            image: "", tags: [], donor: "테스트", location: "", date: "", order: 0, popularity: 0, palette: 0,
            authorID: author)
        let store = CampusStoryStore()
        store.synchronize(stories: [story], collected: [])
        let signedIn = try XCTUnwrap(OiStoryContinuationIntent(story: story, requestedBy: owner))
        XCTAssertEqual(signedIn.availableParent(in: store, for: owner), parent.uuidString)
        XCTAssertNil(signedIn.availableParent(in: store, for: UUID()))
        XCTAssertNil(OiStoryContinuationIntent(story: story, requestedBy: author))
        let guest = try XCTUnwrap(OiStoryContinuationIntent(story: story, requestedBy: nil))
        XCTAssertEqual(guest.availableParent(in: store, for: owner), parent.uuidString)
        XCTAssertNil(guest.availableParent(in: store, for: author))
        store.synchronize(stories: [], collected: [])
        XCTAssertNil(guest.availableParent(in: store, for: owner))
    }

    func testNewCreationSavesSelectedParentAndExistingDraftKeepsItsSelection() async throws {
        let backend = OiTestBackend()
        backend.install()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OiStoreURLProtocol.self]
        let session = URLSession(configuration: config)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            session.invalidateAndCancel()
            OiStoreURLProtocol.handle = nil
            try? FileManager.default.removeItem(at: directory)
            withExtendedLifetime(backend) {}
        }
        let owner = OiTestBackend.owner
        let remote = OiRemoteStore(api: try OiServiceAPI(key: "sb_publishable_testing", session: session),
            drafts: OiDraftVault(directory: directory), vault: OiMemorySession(owner: owner))
        await remote.start()
        XCTAssertEqual(remote.account?.id, owner)
        let story = CampusStory(id: parent.uuidString, regionID: "pond", title: "이어갈오이",
            image: "", tags: [], donor: "테스트", location: "", date: "", order: 0, popularity: 0, palette: 0,
            authorID: OiTestBackend.other)
        let store = CampusStoryStore()
        store.synchronize(stories: [story], collected: [])
        let intent = try XCTUnwrap(OiStoryContinuationIntent(story: story, requestedBy: owner))

        try await capture(NavigationStack {
            OiStoryCreationConsentFlow(remote: remote, continuation: intent).environment(store)
        }, name: "continue-creation-consent")
        var records = try await remote.localDrafts()
        let created = try XCTUnwrap(records.first)
        XCTAssertEqual(created.customization?.connectedStoryID, parent.uuidString)
        XCTAssertEqual(created.customization?.connectedStorySelectionEdited, true)

        let existingParent = UUID()
        var existing = OiLocalDraft(draft: OiStoryDraft())
        existing.creationStep = OiCreationStep.consent.rawValue
        var customization = OiDraftCustomization()
        customization.connectedStoryID = existingParent.uuidString
        customization.connectedStorySelectionEdited = true
        existing.customization = customization
        try await remote.saveLocalDraft(existing, owner: owner)
        try await capture(NavigationStack {
            OiStoryEditor(remote: remote, localID: existing.id, continuation: intent).environment(store)
        }, name: "continue-existing-draft")
        records = try await remote.localDrafts()
        XCTAssertEqual(records.first(where: { $0.id == existing.id })?.customization?.connectedStoryID,
                       existingParent.uuidString)
    }

    func testPublicMYUsesAnonymousAuthorQueriesAndRejectsPrivateOrForeignStories() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OiStoreURLProtocol.self]
        let session = URLSession(configuration: config)
        let previous = OiStoreURLProtocol.handle
        defer { session.invalidateAndCancel(); OiStoreURLProtocol.handle = previous }

        let author = OiTestBackend.other
        let remote = OiRemoteStore(api: try OiServiceAPI(key: "sb_publishable_testing", session: session),
                                  vault: OiMemorySession())
        let profile = try JSONSerialization.data(withJSONObject: [[
            "id": author.uuidString, "nickname": "공개 닉네임", "farmer_asset": "OiFarmer",
            "public_name": "테스트농부", "department": "기계공학과", "admission_year": "19"
        ]])
        let published = try XCTUnwrap(try row()["story"] as? [String: Any])
        var privateStory = published
        privateStory["id"] = UUID().uuidString
        privateStory["status"] = "draft"
        var foreignStory = published
        foreignStory["id"] = UUID().uuidString
        foreignStory["user_id"] = UUID().uuidString
        let stories = try JSONSerialization.data(withJSONObject: [published, privateStory, foreignStory])

        OiStoreURLProtocol.handle = { request, client in
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            switch request.url?.lastPathComponent {
            case "oi_profiles":
                XCTAssertTrue(query.contains(.init(name: "id", value: "eq.\(author.uuidString)")))
                XCTAssertTrue(query.contains(.init(name: "select",
                    value: "id,nickname,school_id,farmer_asset,public_name,department,admission_year")))
                client.respond(200, profile)
            case "oi_stories":
                XCTAssertTrue(query.contains(.init(name: "user_id", value: "eq.\(author.uuidString)")))
                XCTAssertTrue(query.contains(.init(name: "status", value: "eq.published")))
                client.respond(200, stories)
            default:
                XCTFail("Public MY used an unexpected endpoint")
                client.respond(404, Data("{}".utf8))
            }
        }
        let result = try await remote.publicAuthor(author)
        XCTAssertEqual(result.profile.id, author)
        XCTAssertEqual(result.profile.farmerAsset, "OiFarmer")
        XCTAssertNotNil(UIImage(named: result.profile.farmerAsset))
        XCTAssertNil(result.profile.schoolDepartment)
        XCTAssertEqual(result.stories.map(\.id), [child])

        let store = CampusStoryStore()
        for (name, size, dynamicType) in [
            ("402x874", CGSize(width: 402, height: 874), DynamicTypeSize.large),
            ("375x667", CGSize(width: 375, height: 667), .large),
            ("440x956", CGSize(width: 440, height: 956), .large),
            ("accessibility", CGSize(width: 402, height: 874), .accessibility3)
        ] {
            try await capture(NavigationStack(path: .constant([author])) {
                Color.clear.navigationDestination(for: UUID.self) { id in
                    MYPublicWorkshopView(authorID: id, remote: remote, store: store)
                        .environment(\.scenePhase, .active)
                        .environment(\.dynamicTypeSize, dynamicType)
                }
            }, name: "public-my-\(name)", size: size)
        }
        XCTAssertEqual(store.stories.map(\.id), [child.uuidString])
        XCTAssertEqual(store.stories.first?.donor, result.profile.publicDonorLine)
        XCTAssertEqual(store.stories.first?.donorFarmerAsset, "OiFarmer")

        OiStoreURLProtocol.handle = { _, client in client.respond(200, Data("[]".utf8)) }
        do {
            _ = try await remote.publicAuthor(author)
            XCTFail("An author who no longer has a public profile must not be shown")
        } catch OiServiceError.unavailable {}
    }

    private func capture<V: View>(_ view: V, name: String, size: CGSize = CGSize(width: 402, height: 750)) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: view.environment(\.colorScheme, .light))
        window.frame = CGRect(origin: .zero, size: size)
        window.rootViewController = host; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil; window.windowScene = nil }
        window.layoutIfNeeded(); host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(350))
        host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let shot = XCTAttachment(image: image); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        XCTAssertGreaterThan(try XCTUnwrap(image.pngData()).count, 15000, "The capture must include rendered text, not a blank host")
    }
}
