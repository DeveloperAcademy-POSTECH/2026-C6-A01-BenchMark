//
//  CampusBuildingNotesTests.swift
//  OiDonationTests
//
//  Created by Codex on 11/16/26.
//

import XCTest
import SwiftUI
import RealityKit
@testable import OiDonation

@MainActor private final class BuildingNoteServiceFixture: CampusBuildingNoteServing {
    var buildingNoteAccountID: UUID? = UUID()
    var canWriteBuildingNote = true
    var page: [CampusBuildingNote] = []
    var attempts: [UUID] = []
    var failFirstSend = false
    var holdLoad = false
    var holdSend = false
    var loadContinuation: CheckedContinuation<[CampusBuildingNote], Error>?
    var sendContinuation: CheckedContinuation<CampusBuildingNote, Error>?
    private var sendStarted: CheckedContinuation<Void, Never>?
    var sendReceipt: CampusBuildingNote?
    var before: CampusBuildingNote?
    func buildingNotes(building: String, before: CampusBuildingNote?) async throws -> [CampusBuildingNote] {
        self.before = before
        if holdLoad { return try await withCheckedThrowingContinuation { loadContinuation = $0 } }
        return page
    }
    func postBuildingNote(id: UUID, building: String, body: String) async throws -> CampusBuildingNote {
        attempts.append(id)
        let receipt = note(id: id, building: building, body: body)
        sendReceipt = receipt
        if holdSend {
            return try await withCheckedThrowingContinuation {
                sendContinuation = $0; sendStarted?.resume(); sendStarted = nil
            }
        }
        if failFirstSend && attempts.count == 1 { throw URLError(.timedOut) }
        return receipt
    }
    func deleteBuildingNote(id: UUID) async throws { page.removeAll { $0.id == id } }
    func waitForHeldSend() async {
        if sendContinuation == nil { await withCheckedContinuation { sendStarted = $0 } }
    }
    func note(id: UUID = UUID(), building: String = "136182168", body: String = "함께 공부해요") -> CampusBuildingNote {
        CampusBuildingNote(id: id, buildingId: building, authorId: buildingNoteAccountID!, body: body,
            createdAt: "2026-11-16T09:00:00+00:00", nickname: "농부", admissionYear: "2024", department: "기계공학과")
    }
}

@MainActor final class CampusBuildingNotesTests: XCTestCase {
    func testUncertainSendRetriesSameIDAndPreservesDraft() async {
        let service = BuildingNoteServiceFixture(); service.failFirstSend = true
        let model = CampusBuildingNotesModel(buildingID: "136182168", service: service)
        model.text = "  함께 공부해요  "
        await model.send()
        XCTAssertTrue(model.notes.isEmpty); XCTAssertFalse(model.text.isEmpty); XCTAssertNotNil(model.error)
        await model.send()
        XCTAssertEqual(service.attempts.count, 2); XCTAssertEqual(service.attempts.first, service.attempts.last)
        XCTAssertEqual(model.notes.map(\.body), ["함께 공부해요"]); XCTAssertTrue(model.text.isEmpty)
    }

    func testNewDraftIsNotClearedByPreviousSendAndAccountSwitchDropsReceipt() async throws {
        let service = BuildingNoteServiceFixture(); service.holdSend = true
        let model = CampusBuildingNotesModel(buildingID: "136182168", service: service)
        model.text = "첫 글"
        let first = Task { await model.send() }
        await Task.yield()
        model.text = "다음 글"
        try XCTUnwrap(service.sendContinuation).resume(returning: try XCTUnwrap(service.sendReceipt))
        await first.value
        XCTAssertEqual(model.text, "다음 글")
        let second = Task { await model.send() }
        await Task.yield()
        let pending = try XCTUnwrap(service.sendContinuation), receipt = try XCTUnwrap(service.sendReceipt)
        service.buildingNoteAccountID = UUID(); model.resetForAccount()
        pending.resume(returning: receipt); await second.value
        XCTAssertTrue(model.notes.isEmpty); XCTAssertTrue(model.text.isEmpty); XCTAssertFalse(model.sending)
    }

    func testDeletingRetriedNoteIgnoresLateResultAndPreservesChangedDraft() async throws {
        for succeeds in [true, false] {
            let service = BuildingNoteServiceFixture(); service.failFirstSend = true
            let model = CampusBuildingNotesModel(buildingID: "136182168", service: service)
            model.text = "삭제할 글"; await model.send()
            let posted = try XCTUnwrap(service.sendReceipt)
            service.page = [posted]; await model.load()
            XCTAssertEqual(model.notes, [posted])

            service.holdSend = true
            let retry = Task { await model.send() }
            await service.waitForHeldSend()
            let continuation = try XCTUnwrap(service.sendContinuation)
            XCTAssertEqual(service.attempts.last, posted.id)
            model.text = "다음 글"
            await model.delete(posted)
            if succeeds { continuation.resume(returning: posted) }
            else { continuation.resume(throwing: URLError(.timedOut)) }
            await retry.value

            XCTAssertTrue(model.notes.isEmpty, "A late retry receipt must not restore a deleted note")
            XCTAssertEqual(model.text, "다음 글"); XCTAssertNil(model.sentID)
            XCTAssertFalse(model.sending); XCTAssertNil(model.error)
            service.holdSend = false
            model.text = "삭제할 글"; await model.send()
            XCTAssertNotEqual(service.attempts.last, posted.id, "Confirmed deletion retires the pending submission ID")
            XCTAssertEqual(model.notes.map(\.body), ["삭제할 글"])
        }
    }

    func testDeletingDifferentNotePreservesPendingSend() async throws {
        let service = BuildingNoteServiceFixture()
        let previous = service.note(body: "이전 글"); service.page = [previous]
        let model = CampusBuildingNotesModel(buildingID: "136182168", service: service)
        await model.load()
        service.holdSend = true; model.text = "새 글"
        let send = Task { await model.send() }
        await service.waitForHeldSend()
        let continuation = try XCTUnwrap(service.sendContinuation), receipt = try XCTUnwrap(service.sendReceipt)
        await model.delete(previous)
        continuation.resume(returning: receipt); await send.value

        XCTAssertEqual(model.notes, [receipt]); XCTAssertEqual(model.sentID, receipt.id)
        XCTAssertTrue(model.text.isEmpty); XCTAssertFalse(model.sending); XCTAssertNil(model.error)
    }

    func testStaleFeedDoesNotEraseNewlyPostedNote() async throws {
        let service = BuildingNoteServiceFixture(); service.holdLoad = true
        let model = CampusBuildingNotesModel(buildingID: "136182168", service: service)
        let load = Task { await model.load() }; await Task.yield()
        model.text = "방금 등록"; await model.send()
        try XCTUnwrap(service.loadContinuation).resume(returning: [])
        await load.value
        XCTAssertEqual(model.notes.map(\.body), ["방금 등록"])
        XCTAssertFalse(model.loading)
    }

    func testPaginationDeduplicatesAndKeepsServerCursor() async {
        let service = BuildingNoteServiceFixture()
        service.page = (0..<50).map { service.note(body: "글 \($0)") }
        let cursor = service.page.last
        let model = CampusBuildingNotesModel(buildingID: "136182168", service: service)
        await model.load(); XCTAssertTrue(model.hasMore)
        service.page = [service.page[0], service.note(), service.note(building: "different")]
        await model.load(older: true)
        XCTAssertEqual(service.before, cursor); XCTAssertEqual(model.notes.count, 51)
        XCTAssertFalse(model.hasMore); XCTAssertTrue(model.hasLoadedOlderNotes)
        service.page = []; await model.load()
        XCTAssertTrue(model.notes.isEmpty, "A refreshed server deletion must disappear")
        XCTAssertFalse(model.hasLoadedOlderNotes)
    }

    func testTextAndSignInValidation() {
        let service = BuildingNoteServiceFixture()
        let model = CampusBuildingNotesModel(buildingID: "136182168", service: service)
        model.text = " \n "; XCTAssertFalse(model.canSend)
        model.text = String(repeating: "가", count: 140); XCTAssertTrue(model.canSend)
        model.text += "나"; XCTAssertFalse(model.canSend)
        model.text = "글"; service.canWriteBuildingNote = false; XCTAssertFalse(model.canSend)
        XCTAssertEqual(service.note().authorLabel, "24학번 기계공학과")
    }

    func testRPCTransportAndMutationReceipts() async throws {
        let id = UUID(), owner = UUID(), report = UUID()
        let note: [String: Any] = ["id": id.uuidString, "building_id": "136182168", "author_id": owner.uuidString,
            "body": "서버 글", "created_at": "2026-11-16T09:00:00+00:00", "nickname": "농부"]
        var requests: [URLRequest] = [], mismatchedReceipt = false
        OiStoreURLProtocol.handle = { request, client in
            requests.append(request)
            let path = request.url!.lastPathComponent
            let response: Any
            switch path {
            case "oi_building_notes": response = [note]
            case "oi_post_building_note": response = note
            case "oi_report_building_note": response = ["id": report.uuidString, "status": "pending"]
            case "oi_review_building_note": response = ["id": report.uuidString, "status": "deleted"]
            default: response = ["id": (mismatchedReceipt ? UUID() : id).uuidString, "status": "deleted"]
            }
            client.respond(200, try! JSONSerialization.data(withJSONObject: response))
        }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [OiStoreURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); OiStoreURLProtocol.handle = nil }
        let api = try OiServiceAPI(key: "sb_publishable_testing", session: session)
        let notes = try await api.buildingNotes(building: "136182168", before: nil)
        XCTAssertEqual(notes.first?.body, "서버 글")
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Authorization"), "Public notes never use a member's privileged token")
        _ = try await api.buildingNotes(building: "136182168", before: notes.first)
        let cursor = try XCTUnwrap(JSONSerialization.jsonObject(with: OiTestBackend.body(requests[1])) as? [String: Any])
        XCTAssertEqual(cursor["p_before_id"] as? String, id.uuidString)
        _ = try await api.postBuildingNote(id: id, building: "136182168", body: "서버 글", token: "test-token")
        XCTAssertEqual(requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: OiTestBackend.body(requests.last!)) as? [String: Any])
        XCTAssertEqual(Set(payload.keys), ["p_id", "p_building", "p_body"], "The server derives author and publication state")
        let queued = try await api.reportBuildingNote(id: id, reason: "abuse", detail: "테스트 신고", token: "test-token")
        XCTAssertEqual(queued.id, report)
        XCTAssertEqual(queued.status, "pending", "Reports wait for manual operator review")
        XCTAssertEqual(requests.last?.url?.lastPathComponent, "oi_report_building_note")
        XCTAssertFalse(requests.contains { $0.url?.lastPathComponent == "moderate-building-note" },
                       "Manual review must not submit public notes to AI")
        try await api.reviewBuildingNote(report: report, action: "deleted", note: "테스트 검토", token: "operator-token")
        try await api.deleteBuildingNote(id: id, token: "test-token")
        mismatchedReceipt = true
        do { try await api.deleteBuildingNote(id: id, token: "test-token"); XCTFail("An unrelated receipt must not confirm deletion") }
        catch { XCTAssertTrue(error is OiServiceError) }
    }

    func testBuildingPickUsesConcaveSurfaceAndNearestDepth() {
        let building = CampusBuildingTarget(id: "A", name: "A",
            footprint: [[0,0],[4,0],[4,1],[1,1],[1,4],[0,4]], floor: 0, roof: 3)
        XCTAssertNil(building.distance(origin: [3,10,3], direction: [0,-1,0]), "Do not select the empty courtyard")
        XCTAssertEqual(building.distance(origin: [0.5,10,3], direction: [0,-1,0]), 7)
        XCTAssertEqual(building.distance(origin: [-5,1,0.5], direction: [1,0,0]), 5)
        let rear = CampusBuildingTarget(id: "B", name: "B", footprint: building.footprint.map { $0 + [10,0] }, floor: 0, roof: 3)
        XCTAssertEqual(CampusBuildingTarget.hit(in: [rear,building], origin: [-5,1,0.5], direction: [1,0,0])?.id, "A")
    }

    func testCatalogExcludesDemolishedSiteAndCameraFitsEveryCorner() throws {
        let buildings = CampusBuildingTarget.catalog(try CampusMapData.load())
        XCTAssertEqual(buildings.count, 89)
        XCTAssertFalse(buildings.contains { $0.id == CampusEducationSite.retiredBuildingID })
        let library = try XCTUnwrap(buildings.first { $0.id == "136182168" })
        for size in [CGSize(width: 402, height: 399), CGSize(width: 375, height: 210)] {
            let yaw: Float = 0.4, pitch: Float = 0.78
            let radius = library.cameraRadius(viewport: size, yaw: yaw, pitch: pitch)
            let eye = library.center + SIMD3<Float>(sin(yaw)*cos(pitch), sin(pitch), cos(yaw)*cos(pitch))*radius
            let projection = CampusMapProjection(eye: eye, yaw: yaw, pitch: pitch, verticalFOV: 42, viewport: CGRect(origin: .zero, size: size))
            for point in library.footprint {
                for height in [library.floor, library.roof] {
                    let screen = try XCTUnwrap(projection.point([point.x,height,point.y]))
                    XCTAssertTrue(CGRect(origin: .zero, size: size).insetBy(dx: 10, dy: 10).contains(screen))
                }
            }
        }
    }

    /// Production HomeView, real map and local network fixtures. No live notes are posted.
    func testFigmaBuildingPanelCapture() async throws {
        let backend = OiTestBackend(); backend.install()
        let fallback = OiStoreURLProtocol.handle
        let fixtures: [[String: Any]] = [
            ["id": UUID().uuidString, "building_id": "136182168", "author_id": OiTestBackend.other.uuidString,
             "body": "청암 커미 커피가 제일 맛있는 듯", "created_at": "2026-11-16T09:01:00+00:00", "nickname": "농부", "admission_year": "2024", "department": "반도체공학과"],
            ["id": UUID().uuidString, "building_id": "136182168", "author_id": OiTestBackend.other.uuidString,
             "body": "도서관 6층 옥상 밤에 뷰 좋던데", "created_at": "2026-11-16T09:02:00+00:00", "nickname": "농부", "admission_year": "2022", "department": "기계공학과"],
            ["id": UUID().uuidString, "building_id": "136182168", "author_id": OiTestBackend.owner.uuidString,
             "body": "청암에 커플들 엄청 많드라 부럽....", "created_at": "2026-11-16T09:03:00+00:00", "nickname": "나", "admission_year": "2019", "department": "기계공학과"],
            ["id": UUID().uuidString, "building_id": "136182168", "author_id": OiTestBackend.other.uuidString,
             "body": "청암 시험기간에 자리 너무 없음...", "created_at": "2026-11-16T09:04:00+00:00", "nickname": "농부", "admission_year": "2018", "department": "컴퓨터공학과"],
            ["id": UUID().uuidString, "building_id": "136182168", "author_id": OiTestBackend.other.uuidString,
             "body": "5층에 VR 생겼던데요?!", "created_at": "2026-11-16T09:05:00+00:00", "nickname": "농부", "admission_year": "2026", "department": "기계공학과"]
        ]
        let bytes = try JSONSerialization.data(withJSONObject: fixtures.reversed().map { $0 })
        OiStoreURLProtocol.handle = { request, client in
            if request.url?.path.hasSuffix("/oi_building_notes") == true { client.respond(200, bytes) }
            else { fallback?(request, client) }
        }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [OiStoreURLProtocol.self]
        let session = URLSession(configuration: config)
        let api = try OiServiceAPI(key: "sb_publishable_testing", session: session)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let remote = OiRemoteStore(api: api, drafts: OiDraftVault(directory: directory), vault: OiMemorySession())
        defer { session.invalidateAndCancel(); OiStoreURLProtocol.handle = nil; try? FileManager.default.removeItem(at: directory); withExtendedLifetime(backend) {} }
        await remote.start(); XCTAssertTrue(remote.canWriteBuildingNote)
        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let defaultsName = "building-notes-tests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let host = UIHostingController(rootView: NavigationStack {
            HomeView(container: .pilot, store: CampusStoryStore(defaults: defaults), myDemo: MYLibraryStore(),
                isCameraCoverActive: false, onOpenProfile: {}, onOpenStory: { _ in }, remote: remote)
                .environment(\.scenePhase, .active)
        })
        let window = UIWindow(windowScene: windowScene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = host; window.isHidden = false
        defer {
            descendants(host.view).compactMap { $0 as? CampusMapCanvas }.forEach { $0.removeRenderer() }
            window.isHidden = true; window.rootViewController = nil; window.windowScene = nil
        }
        for _ in 0..<150 {
            if descendants(host.view).contains(where: { ($0 as? CampusMapCanvas)?.map?.scene.findEntity(named: "POSTECH v09 apricot cream copy") != nil }) { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let canvas = try XCTUnwrap(descendants(host.view).compactMap { $0 as? CampusMapCanvas }.first)
        let map = try XCTUnwrap(canvas.map)
        let camera = try XCTUnwrap(map.scene.anchors.flatMap { Array($0.children) }.compactMap { $0 as? PerspectiveCamera }.first)
        let before = camera.position(relativeTo: nil)
        let label = try XCTUnwrap(descendants(canvas).first { $0.accessibilityIdentifier == "campus.label.building.136182168" })
        XCTAssertTrue(label.accessibilityActivate())
        try await Task.sleep(for: .seconds(2))
        XCTAssertGreaterThan(simd_distance(camera.position(relativeTo: nil), before), 10)
        let markers = descendants(canvas).filter { ($0.accessibilityIdentifier ?? "").hasPrefix("campus.region.") || ($0.accessibilityIdentifier ?? "").hasPrefix("campus.cluster.") }
        XCTAssertFalse(markers.isEmpty); XCTAssertTrue(markers.allSatisfy(\.isHidden))
        let mapFrame = canvas.convert(canvas.bounds, to: window)
        XCTAssertGreaterThanOrEqual(mapFrame.maxY, 359, "The map must continue underneath the panel's rounded edge")
        let image = await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            map.snapshot(saveToHDR: false) { continuation.resume(returning: $0) }
        }
        let mapSnapshot = UIImageView(image: try XCTUnwrap(image)); mapSnapshot.frame = map.bounds; map.addSubview(mapSnapshot)
        defer { mapSnapshot.removeFromSuperview() }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let png = UIGraphicsImageRenderer(bounds: window.bounds, format: format).pngData { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png"); attachment.name = "figma-building-notes"; attachment.lifetime = .keepAlways; add(attachment)
        if let output = ProcessInfo.processInfo.environment["OI_BUILDING_CAPTURE_DIR"] {
            try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
            try png.write(to: URL(fileURLWithPath: output).appendingPathComponent("building-notes.png"))
        }
        XCTAssertTrue(remote.error == nil)
    }

    func testBuildingExitRestoresCameraAndNumberedMarkers() async throws {
        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let scene = CampusExploreScene(), controller = UIViewController(), window = UIWindow(windowScene: windowScene)
        window.rootViewController = controller
        let canvas = scene.makeView(); canvas.frame = controller.view.bounds; controller.view.addSubview(canvas)
        window.isHidden = false
        defer { scene.suspendRendering(); window.isHidden = true; window.rootViewController = nil; window.windowScene = nil }
        var selected: String?
        scene.onBuilding = { selected = $0.id }
        await scene.load(); canvas.layoutIfNeeded()
        let camera = try XCTUnwrap(canvas.map?.scene.anchors.flatMap { Array($0.children) }.compactMap { $0 as? PerspectiveCamera }.first)
        let position = camera.position(relativeTo: nil), orientation = camera.orientation(relativeTo: nil)
        let markerViews = descendants(canvas).filter { ($0.accessibilityIdentifier ?? "").hasPrefix("campus.region.") || ($0.accessibilityIdentifier ?? "").hasPrefix("campus.cluster.") }
        let visibleBefore = Set(markerViews.filter { !$0.isHidden }.compactMap(\.accessibilityIdentifier))
        XCTAssertFalse(visibleBefore.isEmpty)
        let library = try XCTUnwrap(CampusBuildingTarget.catalog(try XCTUnwrap(scene.data)).first { $0.id == "136182168" })
        scene.selectBuilding(library)
        let initialSize = canvas.bounds.size
        canvas.frame.size.height = 399; canvas.layoutIfNeeded()
        try await Task.sleep(for: .seconds(1))
        XCTAssertEqual(selected, library.id); XCTAssertTrue(markerViews.allSatisfy(\.isHidden))
        XCTAssertGreaterThan(simd_distance(camera.position(relativeTo: nil), position), 10)
        scene.finishBuilding(); canvas.frame.size = initialSize; canvas.layoutIfNeeded()
        try await Task.sleep(for: .seconds(1))
        XCTAssertNil(scene.selectedBuilding)
        XCTAssertLessThan(simd_distance(camera.position(relativeTo: nil), position), 0.01)
        XCTAssertLessThan(simd_length(camera.orientation(relativeTo: nil).vector - orientation.vector), 0.001)
        XCTAssertEqual(Set(markerViews.filter { !$0.isHidden }.compactMap(\.accessibilityIdentifier)), visibleBefore)
    }

    private func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
}
