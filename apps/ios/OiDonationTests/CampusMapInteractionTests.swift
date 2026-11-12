//
//  CampusMapInteractionTests.swift
//  OiDonationTests
//
//  Created by 이돈혁 on 11/4/26.
//

import RealityKit
import CryptoKit
import UIKit
import XCTest
@testable import OiDonation

@MainActor
final class CampusMapInteractionTests: XCTestCase {
    func testOverviewRevealsPublicCharactersWithoutOpeningRegion() async throws {
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
            canvas.removeFromSuperview()
            window.isHidden = true
            window.rootViewController = nil
            window.windowScene = nil
        }
        // Exercise data arriving before the map, as well as later refreshes.
        let data = try CampusMapData.load()
        let coordinate = data.coordinate(SIMD3(32, 0, 1))
        var story = CampusStory(id: "map-visibility-fixture", regionID: "pond", title: "지도 표시 검증",
            image: "OiCats", tags: [], donor: "", location: "", date: "", order: 0, popularity: 0, palette: 0,
            latitude: coordinate.latitude, longitude: coordinate.longitude)
        scene.setOverviewStories([story])
        await scene.load()
        XCTAssertTrue(scene.ready, scene.error ?? "Map should load")
        window.layoutIfNeeded()
        canvas.layoutIfNeeded()
        func pin() throws -> UIButton {
            try XCTUnwrap(canvas.subviews.compactMap { $0 as? UIButton }
                .first { $0.accessibilityIdentifier == "campus.pin.\(story.id)" })
        }
        func character() -> Entity? {
            canvas.map?.scene.anchors.compactMap { $0.findEntity(named: "campus.story.\(story.id)") }.first
        }
        XCTAssertTrue(try pin().isHidden, "Overview should show counts rather than overlapping characters")
        XCTAssertNil(character(), "Overview must not decode offscreen wardrobe models")
        XCTAssertTrue(badges(in: canvas).values.contains { $0.label.contains("오이 1개") })

        let pinch = TestPinch()
        pinch.state = .began
        scene.perform(NSSelectorFromString("pinch:"), with: pinch)
        pinch.state = .changed; pinch.scale = 5
        scene.perform(NSSelectorFromString("pinch:"), with: pinch)
        XCTAssertFalse(try pin().isHidden, "Pinching the map must reveal placed characters without tapping a region")
        XCTAssertEqual(try pin().alpha, 1)
        XCTAssertTrue(try pin().isUserInteractionEnabled)
        try await waitUntil("The close map must load the actual USDZ mesh", timeout: 20) { character() != nil }
        XCTAssertNil(try pin().image(for: .normal), "The hit target must not display a flat portrait")
        let model = try XCTUnwrap(character())
        let bounds = model.visualBounds(relativeTo: nil)
        XCTAssertGreaterThan(bounds.extents.z, 1, "Character must have actual depth")
        XCTAssertEqual(bounds.min.y, model.position.y, accuracy: 0.01, "Feet must sit on the sampled terrain")
        XCTAssertEqual(model.position, data.world(latitude: coordinate.latitude, longitude: coordinate.longitude))
        XCTAssertTrue(badges(in: canvas).isEmpty, "Count panels must not cover the close-up characters")
        var openedID: String?
        scene.onStory = { openedID = $0 }
        try pin().sendActions(for: .touchUpInside)
        XCTAssertEqual(openedID, story.id)
        try await capture("public-character-direct-zoom", in: canvas)

        let orientation = model.orientation
        let turn = TestRotation()
        turn.state = .began
        scene.perform(NSSelectorFromString("rotate:"), with: turn)
        turn.state = .changed; turn.rotation = .pi / 2
        scene.perform(NSSelectorFromString("rotate:"), with: turn)
        XCTAssertEqual(model.orientation, orientation, "Orbiting the camera must not billboard the model")
        try await capture("public-character-3d-side", in: canvas)
        turn.rotation = .pi / 2
        scene.perform(NSSelectorFromString("rotate:"), with: turn)
        try await capture("public-character-3d-back", in: canvas)
        turn.rotation = -.pi
        scene.perform(NSSelectorFromString("rotate:"), with: turn)
        turn.state = .ended
        scene.perform(NSSelectorFromString("rotate:"), with: turn)

        let map = try XCTUnwrap(canvas.map)
        let camera = try XCTUnwrap(map.scene.anchors.flatMap { Array($0.children) }.compactMap { $0 as? PerspectiveCamera }.first)
        let cameraTransform = camera.transform
        let moved = data.coordinate(SIMD3(34, 0, 1))
        story.latitude = moved.latitude
        story.longitude = moved.longitude
        let previousPin = try pin()
        let previousCenter = previousPin.center
        scene.setOverviewStories([story])
        XCTAssertTrue(character() === model, "Refreshing unchanged assets must reuse the mesh")
        XCTAssertNil(previousPin.superview)
        XCTAssertEqual(camera.transform, cameraTransform)
        XCTAssertNotEqual(try pin().center, previousCenter)
        XCTAssertFalse(try pin().isHidden, "Live refresh must update pins while staying in overview navigation")
        pinch.scale = 0.2
        scene.perform(NSSelectorFromString("pinch:"), with: pinch)
        XCTAssertTrue(try pin().isHidden, "Zooming back out must restore count markers")
        XCTAssertFalse(badges(in: canvas).isEmpty)
        pinch.scale = 5
        scene.perform(NSSelectorFromString("pinch:"), with: pinch)
        XCTAssertFalse(try pin().isHidden, "Refreshing public stories must not cancel the ongoing pinch")
        pinch.state = .ended
        scene.perform(NSSelectorFromString("pinch:"), with: pinch)
        scene.suspendForARCamera()
        scene.setVisible(true)
        XCTAssertFalse(try pin().isHidden, "Returning from a story/AR must restore the map character")
        XCTAssertNotNil(character(), "Returning to a new renderer must clone the cached 3D template")
        XCTAssertFalse(character() === model)

        scene.setOverviewStories([])
        XCTAssertNil(character(), "Deleted stories must leave neither an entity nor a hit target")
        XCTAssertFalse(canvas.subviews.contains { $0.accessibilityIdentifier == "campus.pin.\(story.id)" })
        scene.setOverviewStories([story])
        XCTAssertFalse(try pin().isHidden, "Data first arriving after load must also be visible")
        scene.focus(try XCTUnwrap(CampusRegion.campus.first), stories: [story])
        scene.showOverview()
        XCTAssertTrue(try pin().isHidden)
        XCTAssertTrue(badges(in: canvas).values.contains { $0.label.contains("오이 1개") })
    }

    func testPublicCharacterAssetsAndCancelledLoads() async throws {
        XCTAssertEqual(CampusStoryModels.resource(for: "OiCats"), "wardrobe-costume-cat-bear")
        XCTAssertEqual(CampusStoryModels.resource(for: "OiGardener"), "wardrobe-costume-farmer")
        XCTAssertEqual(CampusStoryModels.resource(for: "OiWizard"), "wardrobe-tshirt-long")
        // Public identifiers cannot turn into arbitrary file paths.
        XCTAssertEqual(CampusStoryModels.resource(for: "../../private"), "wardrobe-tshirt-long")
        for costume in OiWardrobeLook.Costume.allCases {
            XCTAssertEqual(CampusStoryModels.resource(for: costume.thumbnailName), costume.modelName)
            XCTAssertNoThrow(try OiWardrobeAsset.url(costume.modelName, folder: "Wardrobe"))
        }
        let models = CampusStoryModels()
        let root = Entity()
        models.attach(to: root)
        let story = CampusStory(id: "cancelled-load", regionID: "pond", title: "테스트", image: "OiGardener",
            tags: [], donor: "", location: "", date: "", order: 0, popularity: 0, palette: 0)
        models.setStories([story], positions: [story.id: .zero])
        models.update(visible: [story.id], opacity: 1, height: 5.4)
        models.setStories([], positions: [:])
        models.update(visible: [], opacity: 0, height: 5.4)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertNil(root.findEntity(named: "campus.story.\(story.id)"))
        models.setStories([story], positions: [story.id: SIMD3(1, 2, 3)])
        models.onChange = { [weak models] in models?.update(visible: [story.id], opacity: 1, height: 5.4) }
        models.update(visible: [story.id], opacity: 1, height: 5.4)
        try await waitUntil("Farmer preset must load after cancelling an old request", timeout: 20) { models.isReady(story.id) }
        XCTAssertEqual(root.findEntity(named: "campus.story.\(story.id)")?.position, SIMD3(1, 2, 3))
        models.suspend()
        XCTAssertTrue(root.children.isEmpty)
    }

    func testMapAppearancePreservesCameraGeometryAndOriginalColors() async throws {
        let previous = CampusMapAppearance.saved
        defer { previous.save() }
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
            canvas.removeFromSuperview()
            window.isHidden = true
            window.rootViewController = nil
            window.windowScene = nil
        }
        scene.setAppearance(.original)
        await scene.load()
        XCTAssertTrue(scene.ready, scene.error ?? "Map should load")
        window.layoutIfNeeded()
        canvas.layoutIfNeeded()
        func root() throws -> Entity {
            try XCTUnwrap(canvas.map?.scene.anchors.flatMap { Array($0.children) }
                .first { $0.name.hasPrefix("POSTECH v09") })
        }
        func colors(_ entity: Entity) -> [String: UIColor] {
            Dictionary(uniqueKeysWithValues: entity.children.compactMap { child in
                guard let model = child as? ModelEntity,
                      let material = model.model?.materials.first as? SimpleMaterial else { return nil }
                return (child.name, material.color.tint)
            })
        }
        func assertBackdropBelowMap() throws {
            let layers = try XCTUnwrap(canvas.layer.sublayers)
            let backdropIndex = try XCTUnwrap(layers.firstIndex(of: canvas.backdrop))
            let mapIndex = try XCTUnwrap(layers.firstIndex(of: try XCTUnwrap(canvas.map).layer))
            XCTAssertLessThan(backdropIndex, mapIndex, "The opaque gradient must not cover the rendered map")
        }
        try assertBackdropBelowMap()
        let original = try root()
        let originalColors = colors(original)
        let bounds = original.visualBounds(relativeTo: nil)
        let camera = try XCTUnwrap(canvas.map?.scene.anchors.flatMap { Array($0.children) }.compactMap { $0 as? PerspectiveCamera }.first)
        let cameraTransform = camera.transform
        try await capture("palette-original-overview", in: canvas)
        scene.setAppearance(.apricotCream)
        XCTAssertNil(scene.error)
        XCTAssertFalse(try XCTUnwrap(canvas.map).isOpaque)
        XCTAssertEqual(canvas.backdrop.colors as? [CGColor], CampusMapAppearance.apricotCream.backdropColors.map(\.cgColor))
        let litView = try XCTUnwrap(canvas.map)
        let sun = try XCTUnwrap(litView.scene.anchors.first?.findEntity(named: "campus-sun") as? DirectionalLight)
        XCTAssertNotNil(sun.shadow)
        XCTAssertNotNil(litView.environment.lighting.resource)
        XCTAssertEqual(litView.environment.lighting.intensityExponent, 1)
        let apricot = try root()
        XCTAssertEqual(apricot.children.count, original.children.count)
        XCTAssertEqual(apricot.visualBounds(relativeTo: nil).extents, bounds.extents)
        XCTAssertEqual(apricot.visualBounds(relativeTo: nil).center, bounds.center)
        XCTAssertEqual(camera.transform, cameraTransform)
        XCTAssertNotEqual(colors(apricot), originalColors)
        XCTAssertEqual(colors(original), originalColors, "Recoloring a clone must not mutate the template")
        try await capture("palette-apricot-overview", in: canvas)
        scene.focus(try XCTUnwrap(CampusRegion.campus.first { $0.id == "pond" }), stories: [])
        try await capture("palette-apricot-pond", in: canvas)
        let focusedCamera = camera.transform
        let mapData = try XCTUnwrap(scene.data)
        let pondRegion = try XCTUnwrap(CampusRegion.campus.first { $0.id == "pond" })
        let pond = mapData.world(try XCTUnwrap(mapData.pois.first { $0.id == pondRegion.placeID }).p)
        camera.look(at: pond + SIMD3(0, 5, 0), from: pond + SIMD3(4, 23, 43), relativeTo: nil)
        try await capture("palette-apricot-low-angle", in: canvas)
        camera.transform = focusedCamera
        scene.setAppearance(.original)
        XCTAssertEqual(canvas.backdrop.colors as? [CGColor], CampusMapAppearance.original.backdropColors.map(\.cgColor))
        XCTAssertEqual(colors(try root()), originalColors)
        XCTAssertEqual(camera.transform, focusedCamera)
        let originalSun = try XCTUnwrap(litView.scene.anchors.first?.findEntity(named: "campus-sun") as? DirectionalLight)
        XCTAssertEqual(originalSun.shadow?.depthBias, DirectionalLight().shadow?.depthBias)
        XCTAssertNil(litView.environment.lighting.resource)
        XCTAssertEqual(originalSun.light.intensity, 2200)
        try await capture("palette-original-pond", in: canvas)
        scene.setAppearance(.apricotCream)
        scene.suspendForARCamera()
        scene.setVisible(true)
        try assertBackdropBelowMap()
        XCTAssertEqual(canvas.backdrop.colors as? [CGColor], CampusMapAppearance.apricotCream.backdropColors.map(\.cgColor))
        XCTAssertEqual(colors(try root()), colors(apricot), "Renderer recreation must retain the chosen palette")
        XCTAssertNotNil(canvas.map?.environment.lighting.resource)
        XCTAssertNotNil((canvas.map?.scene.anchors.first?.findEntity(named: "campus-sun") as? DirectionalLight)?.shadow)
        XCTAssertEqual(CampusMapAppearance.saved, .apricotCream)
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
        let point = try XCTUnwrap(data.graph.values.map { data.world($0.p) }.first { p in
            [-1, 0, 1].allSatisfy { x in
                [-1, 0, 1].allSatisfy { z in
                    data.placementError(at: p + SIMD3(Float(x), 0, Float(z))) == nil
                }
            }
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
        let deadline = clock.now.advanced(by: .seconds(min(30, timeout)))
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
            guard let button = view as? UIButton, !button.isHidden, let id = button.accessibilityIdentifier,
                  id.hasPrefix("campus.region.") || id.hasPrefix("campus.cluster.") else { return nil }
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
        // Allow lighting/shadow buffers to settle before a visual comparison.
        try await Task.sleep(for: .milliseconds(350))
        let rendered = await withCheckedContinuation { continuation in
            map.snapshot(saveToHDR: false) { continuation.resume(returning: $0) }
        }
        let image = try XCTUnwrap(rendered)
        let composite = UIGraphicsImageRenderer(bounds: canvas.bounds).image { context in
            canvas.backdrop.render(in: context.cgContext)
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

private final class TestRotation: UIRotationGestureRecognizer {
    private var testState: State = .possible
    private var testRotation: CGFloat = 0
    override var state: State { get { testState } set { testState = newValue } }
    override var rotation: CGFloat { get { testRotation } set { testRotation = newValue } }
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

@MainActor
final class CampusEducationDistrictTests: XCTestCase {
    func testBundledGeometryIsTheCompleteWebSurface() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "education-district-points", withExtension: "bin"))
        let bytes = try Data(contentsOf: url)
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        // Golden export of fine-packed-building-surfaces-5: no random or strided sampling.
        XCTAssertEqual(hash, "ac8678bd21dd839682914ff169f0dfe790a40c7c2d8cf9929e42f6c32207d8a4")
        let source = try CampusEducationDistrict.geometry()
        XCTAssertEqual(source.points.count, 96_000)
        XCTAssertEqual(source.shell.count, 106_398)
        XCTAssertEqual(source.groundOffset, 2.18, accuracy: 0.00001)
    }

    func testBatchedBuildingAndLevelOfDetailSharePlacement() throws {
        let data = try CampusMapData.load()
        let entity = try CampusEducationDistrict.makeEntity(data: data)
        let position = entity.position
        let orientation = entity.orientation
        let bounds = entity.visualBounds(recursive: false, relativeTo: entity)
        XCTAssertEqual(Set(entity.children.map(\.name)), ["education.cleared-parcel", "education.library-connector"])
        XCTAssertNil(entity.findEntity(named: "education.surface-depth"), "Surface pearls must not have an opaque building behind them")
        let bridge = try XCTUnwrap(entity.findEntity(named: "education.library-connector") as? ModelEntity)
        XCTAssertTrue(bridge.children.isEmpty, "The library connector must also be made only of pearls")
        XCTAssertEqual(entity.collision?.shapes.count, 1)
        XCTAssertEqual(entity.name, "campus.education-district")
        XCTAssertGreaterThan(bounds.extents.x, 10)
        XCTAssertLessThan(bounds.extents.y, 6)
        CampusEducationDistrict.update(entity, near: true)
        XCTAssertEqual(entity.position, position)
        XCTAssertEqual(entity.orientation, orientation)
        let close = entity.visualBounds(recursive: false, relativeTo: entity)
        XCTAssertLessThan(simd_distance(close.extents, bounds.extents), 0.6)
        XCTAssertFalse(data.buildings.contains { $0.id != CampusEducationDistrict.retiredBuildingID && data.contains(position, polygon: $0.p) })
    }

    func testSiteClearsPosvilleButPreservesLibraryAndC5AndConnectsBridge() throws {
        let data = try CampusMapData.load()
        let retired = try XCTUnwrap(data.buildings.first { $0.id == CampusEducationSite.retiredBuildingID })
        for p in retired.p { XCTAssertTrue(CampusEducationSite.contains([Float(p[0]), 0, Float(-p[1])])) }
        for id in [CampusEducationSite.libraryID, CampusEducationSite.c5ID] {
            let building = try XCTUnwrap(data.buildings.first { $0.id == id })
            for p in building.p { XCTAssertFalse(CampusEducationSite.contains([Float(p[0]), 0, Float(-p[1])])) }
        }
        let library = try XCTUnwrap(data.buildings.first { $0.id == CampusEducationSite.libraryID })
        let landing = try XCTUnwrap(CampusEducationSite.libraryLanding(data: data))
        XCTAssertTrue(data.contains(landing, polygon: library.p), "The gallery must touch the actual library wall")
        XCTAssertEqual(CampusEducationSite.local(landing).z, -0.185, accuracy: 0.001)
        let front = CampusEducationSite.world([0, 0, 1]) - CampusEducationSite.center
        let towardC5 = SIMD3<Float>(62.19, CampusEducationSite.center.y, 35.25) - CampusEducationSite.center
        XCTAssertGreaterThan(simd_dot(simd_normalize(front), simd_normalize(towardC5)), 0.8)
        XCTAssertEqual(data.grounded([53.4, 7, 39.4]).y, CampusEducationSite.elevation)
    }

    func testClearingRemovesIntersectingGroundAndWallsWithoutCentroidGaps() {
        // A large triangle crosses the entire site while its centroid is outside it.
        let positions: [SIMD3<Float>] = [[40,0,25], [80,0,25], [55,0,80],
            [50.18,0,40.04], [56.07,0,37.47], [50.18,3,40.04],
            [20,0,20], [21,0,20], [20,1,20]]
        let source = CampusEducationSite.MeshBuffers(positions: positions,
            normals: Array(repeating: [0,1,0], count: positions.count), indices: Array(0..<9))
        let result = CampusEducationSite.clearing(source)
        XCTAssertEqual(result.positions.count, result.normals.count)
        XCTAssertTrue(result.indices.suffix(3).elementsEqual([6,7,8]), "Unrelated geometry must remain unchanged")
        XCTAssertFalse(result.indices.contains(3), "Posville's boundary wall must be removed too")
        for i in stride(from: 0, to: result.indices.count, by: 3) {
            let a = result.positions[Int(result.indices[i])]
            let b = result.positions[Int(result.indices[i + 1])]
            let c = result.positions[Int(result.indices[i + 2])]
            for weights: SIMD3<Float> in [[0.333,0.333,0.334], [0.8,0.1,0.1], [0.1,0.8,0.1], [0.1,0.1,0.8]] {
                XCTAssertFalse(CampusEducationSite.contains(a * weights.x + b * weights.y + c * weights.z))
            }
        }
    }

    func testParcelBoundaryTreesAreRemovedWholeAcrossMaterialSeams() {
        let positions: [SIMD3<Float>] = [
            [49.3,2,43.8], [50.0,2,43.8], [49.65,2.5,44.2],
            [49.3,2,43.8], [49.65,2.5,44.2], [49.65,2,44.4],
            [47.0,2,44.8], [47.6,2,44.8], [47.3,2.5,45.2]
        ]
        let source = CampusEducationSite.MeshBuffers(positions: positions,
            normals: Array(repeating: [0,1,0], count: positions.count), indices: Array(0..<9))
        let trees = [CampusEducationSite.Tree(center: [49.666,44.078]), .init(center: [47.313,45.034])]
        let cleared = CampusEducationSite.clearingVegetation(source, trees: trees)
        XCTAssertEqual(cleared.indices, [6,7,8], "Remove the entire boundary crown, preserving the neighboring tree")
        XCTAssertEqual(cleared.positions, source.positions)
        XCTAssertEqual(cleared.normals, source.normals)
    }

    func testNativeMapEducationSiteFromEveryDirection() async throws {
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
            scene.suspendForARCamera(); canvas.removeFromSuperview()
            window.isHidden = true; window.rootViewController = nil; window.windowScene = nil
        }
        await scene.load()
        XCTAssertTrue(scene.ready)
        window.layoutIfNeeded(); canvas.layoutIfNeeded()
        scene.selectEducationDistrict()
        try await Task.sleep(for: .seconds(1))
        let map = try XCTUnwrap(canvas.map)
        let camera = try XCTUnwrap(map.scene.anchors.flatMap { Array($0.children) }.compactMap { $0 as? PerspectiveCamera }.first)
        // Inspect the actual loaded map, after its parcel triangles were removed.
        for (name, yaw, pitch, radius) in [("front", Float(0), Float(0.5), Float(35)),
             ("left", -.pi / 2, 0.55, 35), ("right", .pi / 2, 0.55, 35),
             ("back", .pi, 0.55, 35), ("site-overhead", -CampusEducationSite.heading, 1.56, 48)] {
            let angle = yaw + CampusEducationSite.heading
            let target = CampusEducationSite.center + SIMD3<Float>(0, 1.5, 0)
            camera.look(at: target, from: target + SIMD3(sin(angle) * cos(pitch), sin(pitch), cos(angle) * cos(pitch)) * radius, relativeTo: nil)
            try await Task.sleep(for: .milliseconds(500))
            let rendered = await withCheckedContinuation { continuation in
                map.snapshot(saveToHDR: false) { continuation.resume(returning: $0) }
            }
            let attachment = XCTAttachment(image: try XCTUnwrap(rendered))
            attachment.name = "education-" + name; attachment.lifetime = .keepAlways; add(attachment)
        }
    }
}
