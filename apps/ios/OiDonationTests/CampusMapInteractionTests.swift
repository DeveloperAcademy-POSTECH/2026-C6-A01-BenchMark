//
//  CampusMapInteractionTests.swift
//  OiDonationTests
//
//  Created by 이돈혁 on 11/4/26.
//

import RealityKit
import UIKit
import XCTest
@testable import OiDonation

@MainActor
final class CampusMapInteractionTests: XCTestCase {
    func testAuthoredOiShowsBeforeAndDuringReviewAndKeepsPublicMarkerSeparate() async throws {
        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: windowScene)
        let controller = UIViewController()
        window.rootViewController = controller
        let scene = CampusExploreScene()
        let canvas = scene.makeView()
        canvas.frame = controller.view.bounds
        canvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controller.view.addSubview(canvas)
        window.isHidden = false
        defer {
            scene.suspendForARCamera()
            window.isHidden = true
            window.rootViewController = nil
            window.windowScene = nil
        }
        await scene.load()
        window.layoutIfNeeded()
        canvas.layoutIfNeeded()

        let data = try XCTUnwrap(scene.data)
        let region = try XCTUnwrap(CampusRegion.campus.first { $0.id == "pond" })
        let location = try XCTUnwrap(data.graph.sorted { $0.key < $1.key }.map { data.world($0.value.p) }
            .first { data.placementError(at: $0) == nil })
        let coordinate = data.coordinate(location)
        let owner = UUID()
        let storyID = UUID()
        func story(_ status: String, revision: Int) -> OiLiveStory {
            OiLiveStory(id: storyID, userId: owner, grantId: nil, regionId: region.id,
                title: "검증용 이야기", body: "검증용 본문", theme: "우정", emotion: "즐거움",
                cucumberName: "보라색 오이", cucumberAsset: "OiCats", cardAsset: "MYBasicCard",
                latitude: coordinate.latitude, longitude: coordinate.longitude,
                status: status, revision: revision, createdAt: "2026-11-08T00:00:00Z")
        }
        let pending = story("pending", revision: 3)
        var look = OiWardrobeLook()
        look.topColor = 0x6A4194
        look.bottomColor = 0xA3BAD9
        var customization = OiDraftCustomization()
        customization.wardrobe = look
        var local = OiLocalDraft(draft: OiStoryDraft(story: pending), customization: customization)
        local.personalPlacement = OiPersonalPlacement(regionID: region.id, name: pending.cucumberName,
            latitude: coordinate.latitude, longitude: coordinate.longitude, heightMeters: 1.2, headingDegrees: 135)
        let personal = try XCTUnwrap(CampusAuthoredPlacement(personal: local, story: nil))
        let markerID = "campus.authored." + storyID.uuidString
        let modelName = "authored:" + storyID.uuidString
        scene.setAuthoredPlacements([personal])
        await scene.loadAuthoredModels()
        XCTAssertEqual(personal.visibility, .personal)
        XCTAssertEqual(personal.placement.headingDegrees, 135)
        XCTAssertEqual(personal.wardrobe, look)
        XCTAssertNotNil(canvas.map?.scene.findEntity(named: modelName), "The outfit loads on the campus overview")

        let legacy = try XCTUnwrap(CampusAuthoredPlacement(story: pending, owner: owner, localDraft: local))
        XCTAssertNil(CampusAuthoredPlacement(story: pending, owner: UUID(), localDraft: local))
        XCTAssertNil(CampusAuthoredPlacement(story: story("hidden", revision: 4), owner: owner, localDraft: local))
        XCTAssertNil(CampusAuthoredPlacement(story: story("draft", revision: 4), owner: owner, localDraft: local))
        XCTAssertNil(CampusAuthoredPlacement(story: story("published", revision: 4), owner: owner, localDraft: nil))
        // Server receipts can normalize fields without changing the identity of the private outfit.
        local.draft.latitude = coordinate.latitude + 0.001
        XCTAssertEqual(CampusAuthoredPlacement(story: pending, owner: owner, localDraft: local)?.wardrobe, look)
        XCTAssertEqual(legacy.wardrobe, look)
        let authored = try XCTUnwrap(CampusAuthoredPlacement(personal: local, story: pending))
        XCTAssertEqual(authored.placement, personal.placement, "Unconfirmed draft edits leave the saved position intact")

        scene.setAuthoredPlacements([authored])
        scene.focus(region, stories: [], placement: authored.placement)
        await scene.loadAuthoredModels()
        let marker = try XCTUnwrap(canvas.subviews.first { $0.accessibilityIdentifier == markerID } as? UIButton)
        XCTAssertTrue(marker.accessibilityLabel?.contains("검토 중 · 나만 보기") == true)
        var opened: UUID?
        scene.onAuthoredPlacement = { opened = $0 }
        marker.sendActions(for: .touchUpInside)
        XCTAssertEqual(opened, storyID)
        let model = try XCTUnwrap(canvas.map?.scene.findEntity(named: modelName))
        XCTAssertLessThan(simd_distance(model.position(relativeTo: nil), location), 0.001)
        XCTAssertGreaterThan(model.visualBounds(relativeTo: nil).extents.y, 1)
        try await capture("authored-oi-at-selected-location", in: canvas)

        let published = try XCTUnwrap(CampusAuthoredPlacement(story: story("published", revision: 4), owner: owner, localDraft: local))
        scene.setAuthoredPlacements([published])
        let publicStory = CampusStory(id: storyID.uuidString, regionID: region.id, title: pending.cucumberName,
            image: pending.cucumberAsset, tags: [], donor: "테스트 작성자", location: region.title, date: "",
            order: 0, popularity: 0, palette: 0, latitude: coordinate.latitude, longitude: coordinate.longitude)
        scene.focus(region, stories: [publicStory], placement: published.placement)
        let publicPinID = "campus.pin." + storyID.uuidString
        XCTAssertFalse(canvas.subviews.contains { $0.accessibilityIdentifier == publicPinID })
        XCTAssertEqual(canvas.subviews.filter { $0.accessibilityIdentifier == markerID }.count, 1)
        scene.suspendForARCamera()
        scene.setVisible(true)
        XCTAssertNotNil(canvas.map?.scene.findEntity(named: modelName))

        scene.setAuthoredPlacements([])
        XCTAssertNil(canvas.map?.scene.findEntity(named: modelName))
        XCTAssertFalse(canvas.subviews.contains { $0.accessibilityIdentifier == markerID })
        XCTAssertTrue(canvas.subviews.contains { $0.accessibilityIdentifier == publicPinID })
    }

    func testCenterLocationTracksMapAndRejectsBuildings() async throws {
        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: windowScene)
        let controller = UIViewController()
        window.rootViewController = controller
        let scene = CampusExploreScene()
        let canvas = scene.makeView()
        canvas.frame = controller.view.bounds
        canvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controller.view.addSubview(canvas)
        window.isHidden = false
        defer {
            scene.endPlacement()
            scene.suspendForARCamera()
            canvas.removeFromSuperview()
            window.isHidden = true
            window.rootViewController = nil
            window.windowScene = nil
        }
        await scene.load()
        window.layoutIfNeeded()
        canvas.layoutIfNeeded()
        let data = try XCTUnwrap(scene.data)
        let library = try XCTUnwrap(CampusRegion.campus.first { $0.id == "library" })
        let libraryPOI = try XCTUnwrap(data.pois.first { $0.id == library.placeID })
        let libraryCenter = data.world(libraryPOI.p)
        let outdoors = data.graph.values.map { data.world($0.p) }.filter { p in
            [-1, 0, 1].allSatisfy { x in
                [-1, 0, 1].allSatisfy { z in
                    data.placementError(at: p + SIMD3(Float(x), 0, Float(z))) == nil
                }
            }
        }
        let point = try XCTUnwrap(outdoors.min {
            simd_distance_squared($0, libraryCenter) < simd_distance_squared($1, libraryCenter)
        })
        let original = data.coordinate(point)
        scene.beginCenterLocation(latitude: original.latitude, longitude: original.longitude)
        XCTAssertFalse(scene.placementReady, "Location picking must not require loading a character")
        XCTAssertTrue(scene.selectingCenterLocation)
        let first = try XCTUnwrap(scene.draftPoint)
        XCTAssertLessThan(simd_distance(first, point), 0.001)
        scene.setMapLabelPresentation(enabled: true, topInset: 70, bottomInset: 190)

        let pan = TestTilt()
        pan.touches = 1
        pan.state = .began
        scene.perform(NSSelectorFromString("pan:"), with: pan)
        pan.state = .changed
        pan.delta = CGPoint(x: 2, y: -2)
        scene.perform(NSSelectorFromString("pan:"), with: pan)
        let moved = try XCTUnwrap(scene.draftPoint)
        XCTAssertGreaterThan(simd_distance(first, moved), 0.001)
        pan.state = .ended
        scene.perform(NSSelectorFromString("pan:"), with: pan)

        let pinch = TestPinch()
        pinch.state = .began
        scene.perform(NSSelectorFromString("pinch:"), with: pinch)
        pinch.state = .changed; pinch.scale = 1.2
        scene.perform(NSSelectorFromString("pinch:"), with: pinch)
        pinch.state = .ended
        scene.perform(NSSelectorFromString("pinch:"), with: pinch)
        pan.touches = 2; pan.state = .began
        scene.perform(NSSelectorFromString("pan:"), with: pan)
        pan.state = .changed; pan.delta = CGPoint(x: 20, y: 12)
        scene.perform(NSSelectorFromString("pan:"), with: pan)
        pan.state = .ended
        scene.perform(NSSelectorFromString("pan:"), with: pan)

        let confirmed = try XCTUnwrap(scene.confirmCenterLocation())
        let selected = data.world(latitude: confirmed.latitude, longitude: confirmed.longitude)
        let map = try XCTUnwrap(canvas.map)
        let camera = try XCTUnwrap(map.scene.anchors.flatMap { Array($0.children) }
            .compactMap { $0 as? PerspectiveCamera }.first)
        let matrix = camera.transform.matrix
        let forward = -SIMD3(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z)
        let ray = simd_normalize(selected - camera.position(relativeTo: nil))
        XCTAssertGreaterThan(simd_dot(ray, forward), 0.99999, "Saved location must lie below the fixed optical-center pin")

        // A building selection cannot silently keep the preceding valid location.
        let building = try XCTUnwrap(data.pois.first { data.placementError(at: data.world($0.p)) != nil })
        scene.focusPlaceForPlacement(building.id)
        XCTAssertNil(scene.draftPoint)
        XCTAssertNotNil(scene.centerLocationError)
        XCTAssertNil(scene.confirmCenterLocation())
        scene.endPlacement()
        XCTAssertFalse(scene.selectingCenterLocation)
        XCTAssertNil(scene.draftPoint)
        scene.beginCenterLocation(latitude: original.latitude, longitude: original.longitude)
        let reopened = try XCTUnwrap(scene.confirmCenterLocation())
        XCTAssertEqual(reopened.latitude, original.latitude, accuracy: 0.000001)
        XCTAssertEqual(reopened.longitude, original.longitude, accuracy: 0.000001)
        XCTAssertEqual(reopened.region?.id, library.id, "Save the confirmed pin's region instead of the default region")
    }

    func testPlacementPreviewGesturesChangeOiWithoutMovingCamera() async throws {
        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: windowScene)
        let controller = UIViewController()
        window.rootViewController = controller
        let scene = CampusExploreScene()
        scene.setSharedMap(true)
        let canvas = scene.makeView()
        canvas.frame = controller.view.bounds
        canvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controller.view.addSubview(canvas)
        window.isHidden = false
        defer {
            scene.suspendForARCamera()
            window.isHidden = true
            window.rootViewController = nil
            window.windowScene = nil
        }
        await scene.load()
        window.layoutIfNeeded()
        canvas.layoutIfNeeded()

        let data = try XCTUnwrap(scene.data)
        let start = try XCTUnwrap(data.graph.sorted { $0.key < $1.key }.map { data.world($0.value.p) }.first { point in
            [0, 0.5, 1].allSatisfy { data.placementError(at: point + SIMD3($0, 0, 0)) == nil }
        })
        let coordinate = data.coordinate(start)
        let placement = CampusPlacement(storyID: "gesture-check", latitude: coordinate.latitude,
            longitude: coordinate.longitude, heightMeters: 1.2, headingDegrees: 10)
        scene.beginPlacementPreview(placement)
        await scene.preparePlacements(wardrobe: OiWardrobeLook())
        let modelName = "placement:" + placement.id.uuidString
        let map = try XCTUnwrap(canvas.map)
        let model = try XCTUnwrap(map.scene.findEntity(named: modelName))
        let camera = try XCTUnwrap(map.scene.anchors.flatMap { Array($0.children) }.compactMap { $0 as? PerspectiveCamera }.first)
        let cameraStart = camera.position(relativeTo: nil)
        let initialHeight = model.visualBounds(relativeTo: nil).extents.y
        var committed: CampusPlacement?
        scene.onPreviewChange = { value, _ in committed = value }

        let a = CGPoint(x: 80, y: 100)
        scene.updatePlacementPreviewTouches([0: a])
        scene.updatePlacementPreviewTouches([0: CGPoint(x: 82, y: 100)])
        XCTAssertEqual(scene.placementPreview, placement, "A small motion while setting down a finger does not drag")
        scene.updatePlacementPreviewTouches([0: CGPoint(x: 92, y: 100)])
        let moved = try XCTUnwrap(scene.placementPreview)
        XCTAssertGreaterThan(moved.longitude, placement.longitude)
        let ground = data.world(latitude: moved.latitude, longitude: moved.longitude)
        XCTAssertLessThan(simd_distance(model.position(relativeTo: nil), ground), 0.001)
        scene.updatePlacementPreviewTouches([0: CGPoint(x: canvas.bounds.width * 2, y: 100)])
        XCTAssertNotNil(scene.previewMovementError)
        XCTAssertEqual(scene.placementPreview, moved)

        scene.updatePlacementPreviewTouches([0: a, 1: CGPoint(x: 120, y: 100)])
        XCTAssertEqual(scene.placementPreview, moved, "Touch centroid changes do not move or rotate the model")
        let centerX = 100 + canvas.bounds.width / 2
        scene.updatePlacementPreviewTouches([0: CGPoint(x: centerX - 20, y: 100), 1: CGPoint(x: centerX + 20, y: 100)])
        XCTAssertEqual(scene.placementPreview?.headingDegrees, 190)
        scene.updatePlacementPreviewTouches([0: CGPoint(x: centerX, y: 80), 1: CGPoint(x: centerX, y: 120)])
        XCTAssertEqual(try XCTUnwrap(scene.placementPreview?.headingDegrees), 100, accuracy: 0.001)

        scene.updatePlacementPreviewTouches([0: CGPoint(x: centerX, y: 75), 1: CGPoint(x: centerX, y: 125)])
        XCTAssertEqual(scene.placementPreview?.heightCentimeters, 150)
        XCTAssertEqual(model.visualBounds(relativeTo: nil).extents.y, initialHeight * 1.25, accuracy: 0.001)
        scene.updatePlacementPreviewTouches([0: CGPoint(x: centerX, y: 0), 1: CGPoint(x: centerX, y: 200)])
        XCTAssertEqual(scene.placementPreview?.heightCentimeters, 200)
        scene.updatePlacementPreviewTouches([0: CGPoint(x: centerX, y: 98), 1: CGPoint(x: centerX, y: 102)])
        XCTAssertEqual(scene.placementPreview?.heightCentimeters, 40)
        let adjusted = try XCTUnwrap(scene.placementPreview)
        scene.updatePlacementPreviewTouches([0: CGPoint(x: centerX, y: 98)])
        scene.updatePlacementPreviewTouches([0: CGPoint(x: centerX + 28, y: 98)])
        scene.updatePlacementPreviewTouches([0: CGPoint(x: centerX + 50, y: 98)])
        XCTAssertEqual(scene.placementPreview, adjusted, "Lifting one finger must not turn rotation into a move")
        XCTAssertNil(committed, "The sequence ends only after all fingers lift")
        scene.updatePlacementPreviewTouches([:])
        XCTAssertEqual(committed, scene.placementPreview)
        XCTAssertEqual(committed?.latitude, moved.latitude)
        XCTAssertEqual(committed?.longitude, moved.longitude)

        scene.updatePlacementPreviewTouches([2: a])
        scene.updatePlacementPreviewTouches([2: CGPoint(x: 92, y: 100)])
        let movedAgain = try XCTUnwrap(scene.placementPreview)
        XCTAssertGreaterThan(movedAgain.longitude, moved.longitude, "A fresh one-finger drag can move the model")
        scene.updatePlacementPreviewTouches([:])
        XCTAssertEqual(committed, movedAgain)
        XCTAssertEqual(camera.position(relativeTo: nil), cameraStart)
        scene.suspendForARCamera(); scene.setVisible(true)
        let restored = try XCTUnwrap(canvas.map?.scene.findEntity(named: modelName))
        let restoredGround = data.world(latitude: movedAgain.latitude, longitude: movedAgain.longitude)
        XCTAssertLessThan(simd_distance(restored.position(relativeTo: nil), restoredGround), 0.001)
        XCTAssertEqual(restored.scale, model.scale)
    }

    func testOverviewPinchReversalAndTilt() async throws {
        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: windowScene)
        let windowID = ObjectIdentifier(window)
        let controller = UIViewController()
        window.rootViewController = controller
        let scene = CampusExploreScene()
        let canvas = scene.makeView()
        canvas.frame = controller.view.bounds
        canvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controller.view.addSubview(canvas)
        window.isHidden = false
        defer {
            scene.suspendForARCamera()
            canvas.removeFromSuperview()
            window.isHidden = true
            window.rootViewController = nil
            window.windowScene = nil
            XCTAssertFalse(windowScene.windows.contains { ObjectIdentifier($0) == windowID })
        }

        scene.setRegionCounts(["pond": 2, "dorm": 3])
        await scene.load()
        XCTAssertTrue(scene.ready, scene.error ?? "Expected the bundled map")
        window.layoutIfNeeded()
        canvas.layoutIfNeeded()

        let initial = badges(in: canvas)
        XCTAssertTrue(initial.values.contains { $0.label.contains("오이 5개") })
        XCTAssertLessThan(initial.count, CampusRegion.campus.count)
        try await capture("map-overview", in: canvas)

        // Feed one recognizer through multiple changes, reversing its scale
        // twice without ending the gesture.
        let pinch = TestPinch()
        let pinchAction = NSSelectorFromString("pinch:")
        pinch.state = .began
        scene.perform(pinchAction, with: pinch)
        pinch.state = .changed
        pinch.scale = 1.6
        scene.perform(pinchAction, with: pinch)
        let midway = badges(in: canvas)
        pinch.scale = 2
        scene.perform(pinchAction, with: pinch)
        let separated = badges(in: canvas)
        XCTAssertNotNil(separated["campus.region.pond"], "Expected split badges; got \(separated.keys.sorted())")
        XCTAssertNotNil(separated["campus.region.dorm"])
        XCTAssertTrue(separated["campus.region.pond"]?.label.contains("오이 2개") == true)
        XCTAssertTrue(separated["campus.region.dorm"]?.label.contains("오이 3개") == true)

        pinch.scale = 0.5
        scene.perform(pinchAction, with: pinch)
        assertSame(badges(in: canvas), as: midway)
        pinch.scale = 2
        scene.perform(pinchAction, with: pinch)
        assertSame(badges(in: canvas), as: separated)

        pinch.state = .ended
        scene.perform(pinchAction, with: pinch)

        let pan = TestTilt()
        let panAction = NSSelectorFromString("pan:")
        pan.state = .began
        scene.perform(panAction, with: pan)
        pan.state = .changed
        pan.delta = CGPoint(x: 15, y: -60)
        scene.perform(panAction, with: pan)
        try await assertPondAnchor(scene: scene, canvas: canvas, panelOpacity: 1)
        try await capture("map-tilted", in: canvas)

        pan.delta = CGPoint(x: 0, y: 140)
        scene.perform(panAction, with: pan)
        try await assertPondAnchor(scene: scene, canvas: canvas, panelOpacity: 0)
        try await capture("map-overhead", in: canvas)

        let pond = try XCTUnwrap(regionButton("pond", in: canvas))
        var opened: CampusRegion?
        scene.onRegion = { opened = $0 }
        pond.sendActions(for: .touchUpInside)
        XCTAssertEqual(opened?.id, "pond")
    }

    func testReleaseSettlesOverzoomAndCanBeInterrupted() async throws {
        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: windowScene)
        let windowID = ObjectIdentifier(window)
        let controller = UIViewController()
        window.rootViewController = controller
        let scene = CampusExploreScene()
        let canvas = scene.makeView()
        canvas.frame = controller.view.bounds
        canvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controller.view.addSubview(canvas)
        window.isHidden = false
        defer {
            scene.suspendForARCamera()
            canvas.removeFromSuperview()
            window.isHidden = true
            window.rootViewController = nil
            window.windowScene = nil
            XCTAssertFalse(windowScene.windows.contains { ObjectIdentifier($0) == windowID })
        }
        scene.setRegionCounts(["pond": 2, "dorm": 3])
        await scene.load()
        XCTAssertTrue(scene.ready)
        window.layoutIfNeeded()
        canvas.layoutIfNeeded()
        let data = try XCTUnwrap(scene.data)
        let map = try XCTUnwrap(canvas.map)
        let camera = try XCTUnwrap(map.scene.anchors.flatMap { Array($0.children) }
            .compactMap { $0 as? PerspectiveCamera }.first)
        let pivot = SIMD3<Float>(32, 2, 1)
        func radius() -> Float { simd_distance(camera.position(relativeTo: nil), pivot) }
        let sites = CampusRegion.campus.compactMap { region -> CampusRegionClustering.Site? in
            guard let place = data.pois.first(where: { $0.id == region.placeID }) else { return nil }
            return .init(id: region.id, anchor: data.world(place.p))
        }
        let clustering = CampusRegionClustering(sites: sites)
        let pair = try XCTUnwrap(clustering.nodes.first { Set($0.siteIDs) == Set(["pond", "dorm"]) })
        let projection = CampusMapProjection(eye: camera.position(relativeTo: nil), yaw: 0, pitch: 1.02,
                                             verticalFOV: 42, viewport: canvas.bounds)
        let splitRadius = clustering.expandedRadius(for: pair, focalLength: projection.focalLength,
                                                    separation: projection.planeSeparation) / 0.88
        let pinch = TestPinch()
        let pinchAction = NSSelectorFromString("pinch:")
        pinch.state = .began
        scene.perform(pinchAction, with: pinch)
        pinch.state = .changed
        pinch.scale = CGFloat(radius() / splitRadius)
        scene.perform(pinchAction, with: pinch)
        XCTAssertTrue(badges(in: canvas).values.contains { $0.alpha > 0.01 && $0.alpha < 0.99 })
        let inFlight = badges(in: canvas)
        pinch.state = .ended
        scene.perform(pinchAction, with: pinch)
        assertSame(badges(in: canvas), as: inFlight)
        try await waitUntil("Pinch release must finish the badge transition") {
            let current = badges(in: canvas)
            return !current.isEmpty && current.values.allSatisfy { $0.alpha == 1 && $0.interactive }
        }
        XCTAssertTrue(badges(in: canvas).values.allSatisfy { $0.alpha == 1 && $0.interactive })

        // Keep a second gesture active. The pinch ending must not move the
        // camera until the remaining gesture ends.
        let pan = TestTilt()
        let panAction = NSSelectorFromString("pan:")
        pan.state = .began
        scene.perform(panAction, with: pan)
        pinch.state = .began
        scene.perform(pinchAction, with: pinch)
        pinch.state = .changed
        pinch.scale = 100
        scene.perform(pinchAction, with: pinch)
        let overzoom = radius()
        XCTAssertLessThan(overzoom, 20)
        XCTAssertGreaterThan(overzoom, 16)
        pinch.state = .ended
        scene.perform(pinchAction, with: pinch)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(radius(), overzoom, accuracy: 0.001)
        pan.state = .ended
        scene.perform(panAction, with: pan)
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertGreaterThan(radius(), overzoom)

        // Re-grab during the return. Scale 1 must preserve the displayed pose
        // and hold it still after the display link is cancelled.
        let interruptedRadius = radius()
        pinch.state = .began
        scene.perform(pinchAction, with: pinch)
        XCTAssertEqual(radius(), interruptedRadius, accuracy: 0.001)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(radius(), interruptedRadius, accuracy: 0.001)
        pinch.state = .changed
        pinch.scale = 0.9
        scene.perform(pinchAction, with: pinch)
        XCTAssertGreaterThan(radius(), interruptedRadius)
        pinch.state = .cancelled
        scene.perform(pinchAction, with: pinch)
        try await waitUntil("Cancelled overzoom must return to the minimum radius") { abs(radius() - 20) < 0.01 }
        XCTAssertEqual(radius(), 20, accuracy: 0.01)

        pinch.state = .began
        scene.perform(pinchAction, with: pinch)
        pinch.state = .changed
        pinch.scale = 0.001
        scene.perform(pinchAction, with: pinch)
        XCTAssertGreaterThan(radius(), 600)
        XCTAssertLessThan(radius(), 720)
        pinch.state = .failed
        scene.perform(pinchAction, with: pinch)
        try await waitUntil("Failed overzoom must return within bounds with opaque badges") {
            let current = badges(in: canvas)
            return radius() <= 600.01 && !current.isEmpty && current.values.allSatisfy { $0.alpha == 1 && $0.interactive }
        }
        XCTAssertLessThanOrEqual(radius(), 600.01)
        XCTAssertTrue(badges(in: canvas).values.allSatisfy { $0.alpha == 1 && $0.interactive })
        try await capture("map-settled-after-bounce", in: canvas)

        pinch.state = .began
        scene.perform(pinchAction, with: pinch)
        pinch.state = .changed
        pinch.scale = 100
        scene.perform(pinchAction, with: pinch)
        pinch.state = .ended
        scene.perform(pinchAction, with: pinch)
        scene.setVisible(false)
        scene.setVisible(true)
        let restoredRadius = radius()
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertGreaterThanOrEqual(radius(), 20)
        XCTAssertEqual(radius(), restoredRadius, accuracy: 0.01)
    }

    func testPanEdgesBounceAndRebaseDuringMultitouch() async throws {
        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: windowScene)
        let windowID = ObjectIdentifier(window)
        let controller = UIViewController()
        window.rootViewController = controller
        let scene = CampusExploreScene()
        let canvas = scene.makeView()
        canvas.frame = controller.view.bounds
        canvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controller.view.addSubview(canvas)
        window.isHidden = false
        defer {
            scene.suspendForARCamera()
            canvas.removeFromSuperview()
            window.isHidden = true
            window.rootViewController = nil
            window.windowScene = nil
            XCTAssertFalse(windowScene.windows.contains { ObjectIdentifier($0) == windowID })
        }
        await scene.load()
        XCTAssertTrue(scene.ready)
        window.layoutIfNeeded()
        canvas.layoutIfNeeded()
        let map = try XCTUnwrap(canvas.map)
        let camera = try XCTUnwrap(map.scene.anchors.flatMap { Array($0.children) }
            .compactMap { $0 as? PerspectiveCamera }.first)
        // The test keeps the overview orbit unchanged and reads its pivot from
        // the actual RealityKit camera, without exposing scene navigation state.
        func pose() -> (target: SIMD3<Float>, radius: Float) {
            let eye = camera.position(relativeTo: nil)
            let radius = (eye.y - 2) / sin(Float(1.02))
            let orbit = SIMD3<Float>(0, sin(1.02), cos(1.02))
            return (eye - orbit * radius, radius)
        }
        let pan = TestTilt()
        pan.touches = 1
        let panAction = NSSelectorFromString("pan:")
        let edgeDeltas = [CGPoint(x: 2000, y: 0), CGPoint(x: -2000, y: 0),
                          CGPoint(x: 0, y: 2000), CGPoint(x: 0, y: -2000), CGPoint(x: 2000, y: 2000)]
        for delta in edgeDeltas {
            scene.showOverview()
            pan.state = .began
            scene.perform(panAction, with: pan)
            pan.state = .changed
            pan.delta = delta
            scene.perform(panAction, with: pan)
            let overrun = pose().target
            let destination = CampusMapMotion.clampedTarget(overrun)
            XCTAssertGreaterThan(simd_distance(overrun, destination), 0.1, "The map must stretch beyond each edge")
            XCTAssertLessThan(simd_distance(overrun, destination), 80)
            XCTAssertEqual(overrun.y, 2, accuracy: 0.001)
            pan.state = .ended
            scene.perform(panAction, with: pan)
            XCTAssertLessThan(simd_distance(pose().target, overrun), 0.001, "Release must start from the displayed map position")
            try await waitUntil("The map must finish returning to its edge or corner") {
                simd_distance(pose().target, destination) < 0.01
            }
            XCTAssertLessThan(simd_distance(pose().target, destination), 0.01, "The map must return to the exact edge or corner")
        }

        scene.showOverview()
        pan.state = .began
        scene.perform(panAction, with: pan)
        pan.state = .changed
        pan.delta = CGPoint(x: 2000, y: 2000)
        scene.perform(panAction, with: pan)
        pan.state = .ended
        scene.perform(panAction, with: pan)
        try await Task.sleep(for: .milliseconds(120))
        let interrupted = pose().target
        pan.state = .began
        scene.perform(panAction, with: pan)
        XCTAssertLessThan(simd_distance(pose().target, interrupted), 0.001)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertLessThan(simd_distance(pose().target, interrupted), 0.001, "Re-grabbing must cancel the old return")
        pan.state = .changed
        pan.delta = .zero
        scene.perform(panAction, with: pan)
        XCTAssertLessThan(simd_distance(pose().target, interrupted), 0.001)
        for touches in [2, 1] {
            pan.touches = touches
            pan.delta = CGPoint(x: 500, y: 500)
            scene.perform(panAction, with: pan)
            XCTAssertLessThan(simd_distance(pose().target, interrupted), 0.001, "Finger-count changes must rebase the touch centroid")
        }
        pan.delta = CGPoint(x: -1, y: -1)
        scene.perform(panAction, with: pan)
        XCTAssertGreaterThan(pose().target.x, interrupted.x)
        XCTAssertGreaterThan(pose().target.z, interrupted.z)

        let pinch = TestPinch()
        let pinchAction = NSSelectorFromString("pinch:")
        pinch.state = .began
        scene.perform(pinchAction, with: pinch)
        pinch.state = .changed
        pinch.scale = 1.4
        scene.perform(pinchAction, with: pinch)
        let simultaneous = pose()
        pan.delta = .zero
        scene.perform(panAction, with: pan)
        XCTAssertLessThan(simd_distance(pose().target, simultaneous.target), 0.001, "Zooming during a drag must not change pan resistance")
        pinch.state = .ended
        scene.perform(pinchAction, with: pinch)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertLessThan(simd_distance(pose().target, simultaneous.target), 0.001, "The remaining pan must hold the map until it ends")
        XCTAssertEqual(pose().radius, simultaneous.radius, accuracy: 0.001)
        pan.state = .cancelled
        scene.perform(panAction, with: pan)
        try await waitUntil("The last simultaneous gesture must settle pan and zoom") {
            let current = pose()
            return simd_distance(current.target, CampusMapMotion.clampedTarget(simultaneous.target)) < 0.01
                && current.radius >= 19.99 && current.radius <= 600.01
        }
        let settled = pose()
        XCTAssertLessThan(simd_distance(settled.target, CampusMapMotion.clampedTarget(simultaneous.target)), 0.01)
        XCTAssertGreaterThanOrEqual(settled.radius, 19.99)
        XCTAssertLessThanOrEqual(settled.radius, 600.01)

        scene.showOverview()
        pan.state = .began
        scene.perform(panAction, with: pan)
        pan.state = .changed
        pan.delta = CGPoint(x: -2000, y: -2000)
        scene.perform(panAction, with: pan)
        let hiddenDestination = CampusMapMotion.clampedTarget(pose().target)
        pan.state = .failed
        scene.perform(panAction, with: pan)
        scene.setVisible(false)
        scene.setVisible(true)
        XCTAssertLessThan(simd_distance(pose().target, hiddenDestination), 0.01)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertLessThan(simd_distance(pose().target, hiddenDestination), 0.01, "Backgrounding must clear the old edge-return motion")
    }

    private func waitUntil(_ description: String, timeout: TimeInterval = 3, condition: () -> Bool,
                           file: StaticString = #filePath, line: UInt = #line) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(min(3, timeout)))
        while !condition(), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(condition(), description, file: file, line: line)
    }

    private func assertPondAnchor(scene: CampusExploreScene, canvas: CampusMapCanvas, panelOpacity: CGFloat) async throws {
        // Wait for RealityKit's renderer to apply the camera before comparing projections.
        try await Task.sleep(for: .milliseconds(350))
        let map = try XCTUnwrap(canvas.map)
        let data = try XCTUnwrap(scene.data)
        let pond = try XCTUnwrap(data.pois.first { $0.id == "97" })
        let projection = try XCTUnwrap(map.project(data.world(pond.p)))
        let button = try XCTUnwrap(regionButton("pond", in: canvas))
        XCTAssertEqual(button.center.x, projection.x, accuracy: 1)
        XCTAssertEqual(button.center.y + button.bounds.height * 0.5 * panelOpacity, projection.y, accuracy: 1)
    }

    private func regionButton(_ id: String, in canvas: CampusMapCanvas) -> UIButton? {
        canvas.subviews.compactMap { $0 as? UIButton }.first {
            !$0.isHidden && $0.accessibilityIdentifier == "campus.region." + id
        }
    }

    private struct Badge {
        let center: CGPoint
        let alpha: CGFloat
        let label: String
        let interactive: Bool
    }

    private func badges(in canvas: CampusMapCanvas) -> [String: Badge] {
        Dictionary(uniqueKeysWithValues: canvas.subviews.compactMap { view -> (String, Badge)? in
            guard let button = view as? UIButton, !button.isHidden, let id = button.accessibilityIdentifier else { return nil }
            return (id, Badge(center: button.center, alpha: button.alpha,
                              label: button.accessibilityLabel ?? "", interactive: button.isUserInteractionEnabled))
        })
    }

    private func assertSame(_ actual: [String: Badge], as expected: [String: Badge],
                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Set(actual.keys), Set(expected.keys), file: file, line: line)
        for (id, badge) in expected {
            guard let current = actual[id] else { continue }
            XCTAssertEqual(current.center.x, badge.center.x, accuracy: 0.01, file: file, line: line)
            XCTAssertEqual(current.center.y, badge.center.y, accuracy: 0.01, file: file, line: line)
            XCTAssertEqual(current.alpha, badge.alpha, accuracy: 0.001, file: file, line: line)
            XCTAssertEqual(current.interactive, badge.interactive, file: file, line: line)
        }
    }

    private func capture(_ name: String, in canvas: CampusMapCanvas) async throws {
        let map = try XCTUnwrap(canvas.map)
        let rendered = await withCheckedContinuation { continuation in
            map.snapshot(saveToHDR: false) { continuation.resume(returning: $0) }
        }
        let image = try XCTUnwrap(rendered)
        let composite = UIGraphicsImageRenderer(bounds: canvas.bounds).image { context in
            image.draw(in: canvas.bounds)
            for overlay in canvas.subviews where overlay !== map && !overlay.isHidden {
                context.cgContext.saveGState()
                context.cgContext.translateBy(x: overlay.frame.minX, y: overlay.frame.minY)
                overlay.layer.render(in: context.cgContext)
                context.cgContext.restoreGState()
            }
        }
        let attachment = XCTAttachment(image: composite)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private final class TestPinch: UIPinchGestureRecognizer {
    private var testState: State = .possible
    private var testScale: CGFloat = 1
    override var state: State {
        get { testState }
        set { testState = newValue }
    }
    override var scale: CGFloat {
        get { testScale }
        set { testScale = newValue }
    }
}

private final class TestTilt: UIPanGestureRecognizer {
    private var testState: State = .possible
    override var state: State {
        get { testState }
        set { testState = newValue }
    }
    var delta = CGPoint.zero
    var touches = 2
    var panVelocity = CGPoint.zero
    override var numberOfTouches: Int { touches }
    override func translation(in view: UIView?) -> CGPoint { delta }
    override func setTranslation(_ translation: CGPoint, in view: UIView?) { delta = translation }
    override func velocity(in view: UIView?) -> CGPoint { panVelocity }
}
