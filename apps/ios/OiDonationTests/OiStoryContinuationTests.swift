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
        let view = CampusNotificationInboxView(requests: [], isLoading: false, loadError: nil,
            onReload: {}, onOpenRequest: { _ in }, continuations: notices, onOpenContinuation: { _ in })
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

    private func capture<V: View>(_ view: V, name: String) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: view.environment(\.colorScheme, .light))
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 750)
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
