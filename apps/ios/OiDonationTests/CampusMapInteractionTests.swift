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
        try await Task.sleep(for: .milliseconds(950))
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
        try await Task.sleep(for: .milliseconds(950))
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
        try await Task.sleep(for: .milliseconds(950))
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
    override var numberOfTouches: Int { 2 }
    override func translation(in view: UIView?) -> CGPoint { delta }
    override func setTranslation(_ translation: CGPoint, in view: UIView?) { delta = translation }
}
