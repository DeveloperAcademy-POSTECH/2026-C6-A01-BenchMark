//
//  CampusMapInteractionTests.swift
//  OiDonationTests
//
//  Created by 이돈혁 on 11/4/26.
//

import RealityKit
import UIKit
import SwiftUI
import XCTest
import CryptoKit
import Compression
import WebKit
@testable import OiDonation

@MainActor
final class CampusMapInteractionTests: XCTestCase {
    func testTreeReductionKeepsWholeTreesAndCompactsOnlyVegetation() throws {
        func tile(_ index: Int, color: SIMD4<Float>, crown: Bool) -> CampusMeshPreparation.Tile {
            var positions: [SIMD3<Float>] = [], indices: [UInt32] = []
            for x in [Float(0), 3, 6, 9, 12] {
                let start = UInt32(positions.count)
                positions += crown ? [[x-0.4,1.2,3.6], [x+0.4,1.2,3.6], [x,2,4.4]] : [[x-0.1,0,4], [x+0.1,0,4], [x,1,4]]
                indices += [start, start+1, start+2]
            }
            return .init(index: index, color: color, positions: positions,
                normals: Array(repeating: [0,1,0], count: positions.count), indices: indices)
        }
        let original = [tile(0, color: [0.18,0.14,0.09,1], crown: false),
                        tile(1, color: [0.12,0.23,0.08,1], crown: true),
                        tile(2, color: [0.27,0.33,0.12,1], crown: true),
                        tile(3, color: [0.26,0.32,0.15,1], crown: false)]
        let reduced = try CampusTreeDensity.apply(to: original)
        let reordered = try CampusTreeDensity.apply(to: original.reversed())
        XCTAssertEqual(reduced.originalCount, 5); XCTAssertEqual(reduced.removedCount, 3)
        for index in 0..<3 {
            let part = try XCTUnwrap(reduced.tiles.first { $0.index == index })
            let buffers = CampusEducationSite.MeshBuffers(positions: part.positions, normals: part.normals, indices: part.indices)
            let centers = CampusEducationSite.components(buffers).map { CampusEducationSite.componentCenter($0, in: buffers).x }.sorted()
            XCTAssertEqual(centers, [0,9], "The prototype's fixed seed must retain the same complete trees")
            XCTAssertEqual(part.positions.count, 6); XCTAssertEqual(part.normals.count, 6)
            XCTAssertEqual(Set(part.indices), Set(UInt32(0)..<UInt32(6)), "Upload only vertices used by retained trees")
            XCTAssertEqual(part.positions, reordered.tiles.first { $0.index == index }?.positions)
        }
        let ground = try XCTUnwrap(reduced.tiles.first { $0.index == 3 })
        XCTAssertEqual(ground.positions, original[3].positions)
        XCTAssertEqual(ground.normals, original[3].normals)
        XCTAssertEqual(ground.indices, original[3].indices)
        XCTAssertEqual(ground.color, original[3].color)
    }

    func testBundledTreeDensityAndWarmCacheRetain1200Trees() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let result = try await Task.detached {
            let data = try CampusMapData.load()
            let url = try XCTUnwrap(Bundle.main.url(forResource: "campus-mobile", withExtension: "oimesh"))
            let cold = try CampusMeshPreparation.load(url: url, mapData: data, cacheDirectory: directory)
            let warm = try CampusMeshPreparation.load(url: url, mapData: data, cacheDirectory: directory)
            func count(_ asset: CampusMeshPreparation.Asset) -> (Int, Int) {
                let vegetation = asset.tiles.filter { CampusMeshPreparation.isVegetation($0.color) }
                let trees = vegetation.filter { simd_distance($0.color, SIMD4<Float>(0.18,0.14,0.09,1)) < 0.001 }.reduce(0) {
                    $0 + CampusEducationSite.components(.init(positions: $1.positions, normals: $1.normals, indices: $1.indices)).count
                }
                return (trees, vegetation.reduce(0) { $0 + $1.indices.count / 3 })
            }
            return (cold.cacheHit, warm.cacheHit, count(cold), count(warm))
        }.value
        XCTAssertFalse(result.0); XCTAssertTrue(result.1)
        XCTAssertEqual(result.2.0, 1200); XCTAssertEqual(result.3.0, 1200, "Reading a cache must not reduce the trees a second time")
        XCTAssertLessThan(result.2.1, 100_000, "Retained tree geometry must stay within the reviewed density budget")
        XCTAssertEqual(result.2.1, result.3.1, "The warm cache must preserve the complete retained geometry")
    }

    func testCampusColdLoadResponsiveness() async throws {
        let scene = CampusExploreScene()
        let controller = UIViewController()
        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = controller
        let canvas = scene.makeView()
        canvas.frame = controller.view.bounds
        canvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controller.view.addSubview(canvas)
        window.isHidden = false
        defer {
            scene.suspendRendering()
            window.isHidden = true
            window.rootViewController = nil
            window.windowScene = nil
        }
        var longestGap: Double = 0
        var previous = CACurrentMediaTime()
        var samples = 0
        let heartbeat = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(10))
                let now = CACurrentMediaTime()
                longestGap = max(longestGap, now - previous)
                previous = now
                samples += 1
            }
        }
        await Task.yield()
        let start = CACurrentMediaTime()
        await scene.load()
        let elapsed = CACurrentMediaTime() - start
        heartbeat.cancel()
        await heartbeat.value
        XCTAssertTrue(scene.ready, scene.error ?? "Map did not load")
        XCTAssertGreaterThan(samples, 0)
        print("CAMPUS_COLD_LOAD seconds=\(elapsed) maxMainActorGap=\(longestGap) samples=\(samples)")
    }

    private func meshFixture(x: Float = 0) throws -> Data {
        var data = Data("OICAMP07".utf8)
        func append<T>(_ values: [T]) { values.withUnsafeBytes { data.append(contentsOf: $0) } }
        append([UInt32(1), UInt32(3), UInt32(3)])
        append([Float(0.3), 0.4, 0.5, 1])
        append([SIMD4<Float>(x,0,0,0), [1,0,0,0], [0,0,1,0]])
        append([SIMD4<Float>(0,1,0,0), [0,1,0,0], [0,1,0,0]])
        append([UInt32(0), 2, 1])
        var packed = Data(count: 2048)
        let count = packed.withUnsafeMutableBytes { dst in data.withUnsafeBytes { src in
            compression_encode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, 2048,
                src.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
        }}
        XCTAssertGreaterThan(count, 0)
        packed.count = count
        var result = Data()
        var size = UInt32(data.count)
        withUnsafeBytes(of: &size) { result.append(contentsOf: $0) }
        result.append(packed)
        return result
    }

    func testGeometryCachePreservesBuffersAndInvalidatesChangedSource() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("campus.oimesh"), cache = directory.appendingPathComponent("cache")
        try meshFixture().write(to: url)
        let cold = try CampusMeshPreparation.load(url: url, mapData: nil, cacheDirectory: cache)
        let warm = try CampusMeshPreparation.load(url: url, mapData: nil, cacheDirectory: cache)
        XCTAssertFalse(cold.cacheHit); XCTAssertTrue(warm.cacheHit)
        XCTAssertEqual(warm.tiles.count, 1)
        XCTAssertEqual(warm.tiles[0].positions, cold.tiles[0].positions)
        XCTAssertEqual(warm.tiles[0].normals, cold.tiles[0].normals)
        XCTAssertEqual(warm.tiles[0].indices, [0,2,1])
        XCTAssertEqual(warm.tiles[0].color, cold.tiles[0].color)
        try meshFixture(x: 0.25).write(to: url)
        let changed = try CampusMeshPreparation.load(url: url, mapData: nil, cacheDirectory: cache)
        XCTAssertFalse(changed.cacheHit)
        XCTAssertEqual(changed.tiles[0].positions[0].x, 0.25)
        try meshFixture(x: 0.5).write(to: url)
        _ = try CampusMeshPreparation.load(url: url, mapData: nil, cacheDirectory: cache)
        XCTAssertLessThanOrEqual(try FileManager.default.contentsOfDirectory(atPath: cache.path).count, 2)
    }

    func testBrokenOrUnavailableGeometryCacheFallsBackToBundledSource() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("campus.oimesh"), cache = directory.appendingPathComponent("cache")
        try meshFixture().write(to: url)
        _ = try CampusMeshPreparation.load(url: url, mapData: nil, cacheDirectory: cache)
        let entry = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil).first)
        var corrupt = try Data(contentsOf: entry); corrupt[8] ^= 1; try corrupt.write(to: entry)
        let recovered = try CampusMeshPreparation.load(url: url, mapData: nil, cacheDirectory: cache)
        XCTAssertFalse(recovered.cacheHit)
        XCTAssertEqual(recovered.tiles[0].positions.count, 3)
        XCTAssertTrue(try CampusMeshPreparation.load(url: url, mapData: nil, cacheDirectory: cache).cacheHit)
        let blocked = directory.appendingPathComponent("not-a-directory")
        try Data([1]).write(to: blocked)
        let uncached = try CampusMeshPreparation.load(url: url, mapData: nil, cacheDirectory: blocked)
        XCTAssertFalse(uncached.cacheHit); XCTAssertEqual(uncached.tiles.count, 1)
    }

    func testCancelledGeometryPreparationDoesNotWriteCache() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("campus.oimesh"), cache = directory.appendingPathComponent("cache")
        try meshFixture().write(to: url)
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try CampusMeshPreparation.load(url: url, mapData: nil, cacheDirectory: cache)
        }
        do { _ = try await task.value; XCTFail("Cancelled work must stop before reading/writing geometry") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
    }

    func testMapProjectsOverlaysWhenViewportOrArtworkChanges() {
        let canvas = CampusMapCanvas(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        var layouts = 0
        canvas.didLayout = { layouts += 1 }

        canvas.layoutSubviews()
        canvas.layoutSubviews()
        XCTAssertEqual(layouts, 1)

        canvas.bounds.size.width = 420
        canvas.layoutSubviews()
        XCTAssertEqual(layouts, 2)

        canvas.invalidateProjection()
        canvas.invalidateProjection()
        canvas.layoutSubviews()
        canvas.layoutSubviews()
        XCTAssertEqual(layouts, 3)
    }

    func testPublicOiAppearsAndOpensOnOverviewBeforeSelectingARegion() async throws {
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
            scene.suspendRendering()
            window.isHidden = true
            window.rootViewController = nil
            window.windowScene = nil
        }
        await scene.load()
        window.layoutIfNeeded()
        canvas.layoutIfNeeded()

        let data = try XCTUnwrap(scene.data)
        let region = try XCTUnwrap(CampusRegion.campus.first { $0.id == "pond" })
        let place = try XCTUnwrap(data.pois.first { $0.id == region.placeID })
        let coordinate = data.coordinate(data.world(place.p))
        let story = CampusStory(id: UUID().uuidString, regionID: region.id, title: "공개 오이",
            image: "OiCats", tags: [], donor: "다른 작성자", location: region.title, date: "",
            order: 0, popularity: 0, palette: 0, cucumberPortraitPath: "approved/portrait.png",
            latitude: coordinate.latitude, longitude: coordinate.longitude, heightMeters: 1.25)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let portrait = UIGraphicsImageRenderer(size: CGSize(width: 30, height: 40), format: format).image { context in
            UIColor.systemPurple.setFill()
            context.fill(CGRect(x: 7, y: 8, width: 16, height: 27))
        }
        var paths: [String] = []
        scene.loadCucumberPortrait = { path in paths.append(path); return portrait }
        var opened: String?
        scene.onStory = { opened = $0 }

        // The public feed can arrive after the overview has already loaded.
        scene.setOverviewStories([story])
        let markerID = "campus.pin." + story.id
        let marker = try XCTUnwrap(canvas.subviews.first { $0.accessibilityIdentifier == markerID } as? UIButton)
        XCTAssertFalse(marker.isHidden)
        XCTAssertTrue(scene.visibleStoryIDs().contains(story.id))
        XCTAssertTrue(badges(in: canvas).values.contains { $0.label.contains("오이 1개") })
        XCTAssertTrue(canvas.hitTest(marker.center, with: nil) === marker, "The character is tappable above the region count")
        marker.sendActions(for: .touchUpInside)
        XCTAssertEqual(opened, story.id)
        try await waitUntil("The approved portrait must lose its transparent padding") {
            marker.currentImage?.size == CGSize(width: 16, height: 27)
        }
        XCTAssertEqual(paths, ["approved/portrait.png"])

        let map = try XCTUnwrap(canvas.map)
        let camera = try XCTUnwrap(map.scene.anchors.flatMap { Array($0.children) }
            .compactMap { $0 as? PerspectiveCamera }.first)
        let artwork = try XCTUnwrap(marker.imageView)
        let ground = data.world(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let pivot = SIMD3<Float>(32, 2, 1)
        func cameraRadius() -> Float { simd_distance(camera.position(relativeTo: nil), pivot) }
        func artworkFrame() -> CGRect {
            marker.layoutIfNeeded()
            return canvas.convert(artwork.bounds, from: artwork)
        }
        func assertGrounded(_ message: String) async throws {
            try await waitUntil(message) {
                guard let projected = map.project(ground) else { return false }
                let frame = artworkFrame()
                return abs(frame.midX - projected.x) < 1 && abs(frame.maxY - projected.y) < 1
            }
        }

        canvas.layoutIfNeeded()
        try await assertGrounded("At the default zoom the visible foot must match the terrain coordinate")
        let initialHeight = artworkFrame().height
        XCTAssertEqual(initialHeight, 28, accuracy: 0.5)
        let pinch = TestPinch()
        let pinchAction = NSSelectorFromString("pinch:")
        pinch.state = .began
        scene.perform(pinchAction, with: pinch)
        pinch.state = .changed
        pinch.scale = 0.8
        scene.perform(pinchAction, with: pinch)
        let middleHeight = artworkFrame().height
        XCTAssertEqual(middleHeight, initialHeight, accuracy: 0.5, "Distant markers must stay compact")
        pinch.scale = 0.25
        scene.perform(pinchAction, with: pinch)
        XCTAssertGreaterThan(cameraRadius(), 600, "The gesture must reach the elastic end of the zoom range")
        pinch.state = .ended
        scene.perform(pinchAction, with: pinch)
        try await waitUntil("The map must settle at the far zoom limit") {
            cameraRadius() <= 600.01 && badges(in: canvas).values.allSatisfy { $0.alpha == 1 && $0.interactive }
        }
        let farHeight = artworkFrame().height
        XCTAssertEqual(farHeight, initialHeight, accuracy: 0.5)
        XCTAssertLessThan(farHeight, 44)
        XCTAssertGreaterThanOrEqual(marker.bounds.width, 44)
        XCTAssertGreaterThanOrEqual(marker.bounds.height, 44)
        XCTAssertFalse(marker.isHidden)
        try await assertGrounded("Zooming out must keep the visible foot on the same terrain coordinate")

        let farTap = CGPoint(x: marker.frame.minX + 1, y: marker.frame.midY)
        XCTAssertFalse(artworkFrame().contains(farTap))
        let farHit = try XCTUnwrap(canvas.hitTest(farTap, with: nil) as? UIButton)
        XCTAssertTrue(farHit === marker, "The area outside the artwork must still open the story")
        opened = nil
        farHit.sendActions(for: .touchUpInside)
        XCTAssertEqual(opened, story.id)

        let tilt = TestTilt()
        let panAction = NSSelectorFromString("pan:")
        tilt.state = .began
        scene.perform(panAction, with: tilt)
        tilt.state = .changed
        tilt.delta = CGPoint(x: 35, y: -100)
        scene.perform(panAction, with: tilt)
        try await assertGrounded("Rotating and tilting the map must keep the foot on the terrain")
        tilt.delta = CGPoint(x: -60, y: 190)
        scene.perform(panAction, with: tilt)
        try await assertGrounded("The foot must stay anchored when looking down from above")
        tilt.state = .ended
        scene.perform(panAction, with: tilt)

        scene.focus(region, stories: [story])
        XCTAssertEqual(canvas.subviews.filter { $0.accessibilityIdentifier == markerID }.count, 1)
        func currentHeight() throws -> CGFloat {
            let button = try XCTUnwrap(canvas.subviews.first { $0.accessibilityIdentifier == markerID } as? UIButton)
            button.layoutIfNeeded()
            return try XCTUnwrap(button.imageView).bounds.height
        }
        let nearHeight = try currentHeight()
        XCTAssertGreaterThan(nearHeight, initialHeight)
        pinch.state = .began
        scene.perform(pinchAction, with: pinch)
        pinch.state = .changed
        pinch.scale = 1.2
        scene.perform(pinchAction, with: pinch)
        let closerHeight = try currentHeight()
        XCTAssertGreaterThan(closerHeight, nearHeight, "The portrait should grow smoothly at close zoom")
        pinch.state = .ended
        scene.perform(pinchAction, with: pinch)

        var shorter = story
        shorter.heightMeters = 0.5
        scene.showStoriesInCurrentArea(region, stories: [shorter])
        XCTAssertLessThan(try currentHeight(), closerHeight, "Close markers must reflect the saved height")
        scene.showOverview()
        XCTAssertEqual(canvas.subviews.filter { $0.accessibilityIdentifier == markerID }.count, 1)
        scene.setOverviewStories([])
        XCTAssertFalse(canvas.subviews.contains { $0.accessibilityIdentifier == markerID })
        XCTAssertFalse(scene.visibleStoryIDs().contains(story.id))
    }

    func testPublicOiKeepsItsWorldHeadingAndFootWhenTheMapRotates() async throws {
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
            scene.suspendRendering()
            window.isHidden = true
            window.rootViewController = nil
            window.windowScene = nil
        }
        await scene.load()
        window.layoutIfNeeded()
        canvas.layoutIfNeeded()

        let data = try XCTUnwrap(scene.data)
        let region = try XCTUnwrap(CampusRegion.campus.first { $0.id == "pond" })
        let place = try XCTUnwrap(data.pois.first { $0.id == region.placeID })
        let path = try XCTUnwrap(data.graph[place.node])
        let coordinate = data.coordinate(data.world(path.p))
        let ground = data.world(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let story = CampusStory(id: UUID().uuidString, regionID: region.id, title: "공개 오이",
            image: "OiCats", tags: [], donor: "다른 작성자", location: region.title, date: "",
            order: 0, popularity: 0, palette: 0, cucumberPortraitPath: "approved/portrait.png",
            latitude: coordinate.latitude, longitude: coordinate.longitude, heightMeters: 1.25, headingDegrees: 150)
        var modelRequests: [CampusStory] = []
        scene.loadPublicCucumberModel = { requested in
            modelRequests.append(requested)
            var outfit = OiWardrobeLook()
            outfit.costume = .catBear
            return try await OiWardrobeAsset.loadForPlacement(outfit)
        }
        scene.setOverviewStories([story])
        let map = try XCTUnwrap(canvas.map)
        let name = "public:" + story.id
        func marker() throws -> UIButton {
            try XCTUnwrap(canvas.subviews.first { $0.accessibilityIdentifier == "campus.pin." + story.id } as? UIButton)
        }
        try await waitUntil("The approved character must load as a 3D entity") { map.scene.findEntity(named: name) != nil }
        let button = try marker()
        let countBadge = try XCTUnwrap(canvas.subviews.compactMap { $0 as? UIButton }.first {
            !$0.isHidden && $0.isUserInteractionEnabled && $0.accessibilityLabel?.hasSuffix("오이 1개") == true
        })
        XCTAssertEqual(modelRequests, [story])
        XCTAssertTrue(try XCTUnwrap(button.imageView).isHidden)
        XCTAssertFalse(countBadge.frame.intersects(button.frame), "The count must not obscure the 3D character")
        XCTAssertTrue(canvas.hitTest(countBadge.center, with: nil) === countBadge)
        XCTAssertTrue(canvas.hitTest(button.center, with: nil) === button)
        try await capture("public-oi-on-overview", in: canvas)

        scene.focus(region, stories: [story])
        let model = try XCTUnwrap(map.scene.findEntity(named: name))
        let camera = try XCTUnwrap(map.scene.anchors.flatMap { Array($0.children) }.compactMap { $0 as? PerspectiveCamera }.first)
        func facing() -> SIMD3<Float> { model.orientation(relativeTo: nil).act([0, 0, 1]) }
        let forward = facing()
        let angle = Float(story.headingDegrees * .pi / 180)
        XCTAssertLessThan(simd_distance(forward, SIMD3(sin(angle), 0, -cos(angle))), 0.001)
        XCTAssertGreaterThan(simd_dot(camera.position(relativeTo: nil) - ground, forward), 0)
        try await capture("public-oi-front", in: canvas)

        let gesture = TestTilt()
        let panAction = NSSelectorFromString("pan:")
        gesture.state = .began
        scene.perform(panAction, with: gesture)
        gesture.state = .changed
        gesture.delta = CGPoint(x: -.pi / 0.006, y: -70)
        scene.perform(panAction, with: gesture)
        XCTAssertLessThan(simd_dot(camera.position(relativeTo: nil) - ground, forward), 0, "The camera reached the back of the character")
        XCTAssertLessThan(simd_distance(facing(), forward), 0.001)
        XCTAssertLessThan(simd_distance(model.position(relativeTo: nil), ground), 0.001)
        XCTAssertEqual(model.visualBounds(relativeTo: nil).min.y, ground.y, accuracy: 0.01)
        try await capture("public-oi-back", in: canvas)
        let rotated = try marker()
        XCTAssertFalse(rotated.isHidden)
        XCTAssertGreaterThanOrEqual(rotated.bounds.width, 44)
        XCTAssertGreaterThanOrEqual(rotated.bounds.height, 44)
        XCTAssertTrue(canvas.hitTest(rotated.center, with: nil) === rotated)
        var opened: String?
        scene.onStory = { opened = $0 }
        rotated.sendActions(for: .touchUpInside)
        XCTAssertEqual(opened, story.id)

        scene.suspendRendering()
        scene.setVisible(true)
        let restored = try XCTUnwrap(canvas.map?.scene.findEntity(named: name))
        XCTAssertLessThan(simd_distance(restored.orientation(relativeTo: nil).act([0, 0, 1]), forward), 0.001)
        scene.showStoriesInCurrentArea(region, stories: [])
        XCTAssertNil(canvas.map?.scene.findEntity(named: name))
        XCTAssertEqual(modelRequests, [story])
    }

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
            scene.suspendRendering()
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

        var publishedStory = story("published", revision: 4)
        publishedStory.heightMeters = 2
        publishedStory.headingDegrees = 35
        let published = try XCTUnwrap(CampusAuthoredPlacement(story: publishedStory, owner: owner, localDraft: local))
        scene.setAuthoredPlacements([published])
        let publicStory = CampusStory(id: storyID.uuidString, regionID: region.id, title: pending.cucumberName,
            image: pending.cucumberAsset, tags: [], donor: "테스트 작성자", location: region.title, date: "",
            order: 0, popularity: 0, palette: 0, latitude: coordinate.latitude, longitude: coordinate.longitude)
        scene.focus(region, stories: [publicStory], placement: published.placement)
        let publicPinID = "campus.pin." + storyID.uuidString
        XCTAssertFalse(canvas.subviews.contains { $0.accessibilityIdentifier == publicPinID })
        XCTAssertEqual(canvas.subviews.filter { $0.accessibilityIdentifier == markerID }.count, 1)
        let publishedMarker = try XCTUnwrap(canvas.subviews.first { $0.accessibilityIdentifier == markerID } as? UIButton)
        XCTAssertEqual(publishedMarker.accessibilityLabel, "보라색 오이, 공개 중 · 내 오이")
        XCTAssertLessThan(publishedMarker.bounds.width, 120)
        XCTAssertLessThan(publishedMarker.bounds.height, 40)

        func assertLabelAboveModel() throws {
            let map = try XCTUnwrap(canvas.map)
            let entity = try XCTUnwrap(map.scene.findEntity(named: modelName))
            let bounds = entity.visualBounds(relativeTo: nil)
            let head = try XCTUnwrap(map.project(SIMD3(bounds.center.x, bounds.max.y, bounds.center.z)))
            XCTAssertFalse(publishedMarker.isHidden)
            XCTAssertLessThan(publishedMarker.frame.maxY, head.y, "Even the tallest model should clear its label")
        }

        try await capture("authored-oi-published-label", in: canvas)
        try assertLabelAboveModel()
        let tilt = TestTilt()
        tilt.state = .began
        scene.perform(NSSelectorFromString("pan:"), with: tilt)
        tilt.state = .changed
        tilt.delta = CGPoint(x: 80, y: 170)
        scene.perform(NSSelectorFromString("pan:"), with: tilt)
        try await capture("authored-oi-published-label-overhead", in: canvas)
        try assertLabelAboveModel()
        tilt.state = .ended
        scene.perform(NSSelectorFromString("pan:"), with: tilt)

        scene.suspendRendering()
        scene.setVisible(true)
        XCTAssertNotNil(canvas.map?.scene.findEntity(named: modelName))

        scene.setAuthoredPlacements([])
        XCTAssertNil(canvas.map?.scene.findEntity(named: modelName))
        XCTAssertFalse(canvas.subviews.contains { $0.accessibilityIdentifier == markerID })
        XCTAssertTrue(canvas.subviews.contains { $0.accessibilityIdentifier == publicPinID })
        scene.setOverviewStories([publicStory])
        scene.showOverview()
        scene.setAuthoredPlacements([published])
        XCTAssertFalse(canvas.subviews.contains { $0.accessibilityIdentifier == publicPinID })
        scene.setAuthoredPlacements([])
        XCTAssertEqual(canvas.subviews.filter { $0.accessibilityIdentifier == publicPinID }.count, 1)
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
            scene.suspendRendering()
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
            scene.suspendRendering()
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
        scene.suspendRendering(); scene.setVisible(true)
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
            scene.suspendRendering()
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
            scene.suspendRendering()
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
            scene.suspendRendering()
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

    func testMapStartsInApricotCreamDespiteLegacyPreference() {
        let key = "campus.map.appearance"
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: key)
        defer {
            if let previous { defaults.set(previous, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        for legacyValue in [nil, "original", "apricotCream"] as [String?] {
            defaults.set(legacyValue, forKey: key)
            XCTAssertEqual(CampusExploreScene().appearance, .apricotCream)
        }
    }

    func testMapAppearancePreservesCameraGeometryAndOriginalColors() async throws {
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
            scene.suspendRendering()
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
        XCTAssertEqual(litView.environment.lighting.intensityExponent, 0.8)
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
        scene.suspendRendering()
        scene.setVisible(true)
        try assertBackdropBelowMap()
        XCTAssertEqual(canvas.backdrop.colors as? [CGColor], CampusMapAppearance.apricotCream.backdropColors.map(\.cgColor))
        XCTAssertEqual(colors(try root()), colors(apricot), "Renderer recreation must retain the chosen palette")
        XCTAssertNotNil(canvas.map?.environment.lighting.resource)
        XCTAssertNotNil((canvas.map?.scene.anchors.first?.findEntity(named: "campus-sun") as? DirectionalLight)?.shadow)
        XCTAssertEqual(CampusExploreScene().appearance, .apricotCream)
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

@MainActor
final class CampusEducationDistrictTests: XCTestCase {
    private func installReferenceCatalogFixture(_ model: EducationLightWebModel) {
        model.webView.stopLoading()
        let script = """
        const referenceRoot='https://kfzfzarslqdqmrazohej.supabase.co/storage/v1/object/public/oi-education-reference/';
        const fetchOriginal=window.fetch.bind(window);
        window.fetch=(input,options)=>String(input)===referenceRoot+'catalog-v1.json'
          ?Promise.resolve(new Response(JSON.stringify({version:1,stories:[{
            id:'postech-900001',origin:'postech',kind:'Synthetic reference',category:'Synthetic',title:'Synthetic shared title',author:'Synthetic author',affiliation:'Synthetic affiliation',fund:'Synthetic fund',message:'Synthetic shared story body',
            photo:referenceRoot+'postech-900001/'+'a'.repeat(64)+'.webp',photoAlt:'Synthetic portrait',sourceUrl:'https://vision.postech.ac.kr/web/?top=support&sub=story&key=detail&code=900001',sourceTitle:'Synthetic source',publishedAt:'2026-11-16',isSummary:true
          }]}),{headers:{'Content-Type':'application/json'}}))
          :fetchOriginal(input,options);
        """
        model.webView.configuration.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        model.load()
    }

    func testEducationWriterSavesThroughNativeAccountWithoutMapPlacement() async throws {
        let backend = OiTestBackend(); backend.install()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OiStoreURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let remote = OiRemoteStore(api: try OiServiceAPI(key: "sb_publishable_testing", session: session),
            drafts: OiDraftVault(directory: directory), vault: OiMemorySession())
        await remote.start()
        let original = OiStoreURLProtocol.handle
        let saved = expectation(description: "Education draft saved using native session")
        let photoStored = expectation(description: "Draft photo attached after native upload")
        OiStoreURLProtocol.handle = { request, client in
            guard request.url?.path == "/rest/v1/rpc/oi_education_mutate" else { original?(request, client); return }
            do {
                let body = try XCTUnwrap(JSONSerialization.jsonObject(with: OiTestBackend.body(request)) as? [String: Any])
                var row = try XCTUnwrap(body["p_payload"] as? [String: Any])
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-a")
                for key in ["latitude", "longitude", "placement", "grant_id", "appearance"] { XCTAssertNil(row[key]) }
                if body["p_action"] as? String == "save" {
                    XCTAssertEqual(row["title"] as? String, "가상의 캠퍼스 추억"); saved.fulfill()
                } else {
                    XCTAssertEqual(body["p_action"] as? String, "attach_media")
                    let paths = try XCTUnwrap(row["paths"] as? [String]); XCTAssertEqual(paths.count, 1)
                    XCTAssertTrue(paths[0].contains("/education/")); XCTAssertTrue(paths[0].contains("/photos/"))
                    XCTAssertEqual(backend.snapshot().uploads.count, 1); photoStored.fulfill()
                    row["display_name"] = "가상 작성자"; row["title"] = "가상의 캠퍼스 추억"
                    row["body"] = "테스트용 이야기입니다."; row["theme"] = "응원"; row["emotion"] = "따뜻함"
                }
                row["revision"] = (row["revision"] as? Int ?? 0) + 1
                row["status"] = "draft"; row["origin"] = "education"
                row["storage_owner_id"] = OiTestBackend.owner.uuidString.lowercased()
                client.respond(200, try JSONSerialization.data(withJSONObject: row))
            } catch { XCTFail(String(describing: error)); client.respond(400, Data()) }
        }
        let model = EducationLightWebModel(); installReferenceCatalogFixture(model); model.connectEducation(remote)
        let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow }
        let window = UIWindow(windowScene: try XCTUnwrap(previous?.windowScene))
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let controller = UIViewController(); window.rootViewController = controller
        model.webView.frame = window.frame; controller.view.addSubview(model.webView); window.makeKeyAndVisible()
        defer {
            model.setActive(false); model.webView.removeFromSuperview(); window.isHidden = true; previous?.makeKeyAndVisible()
            session.invalidateAndCancel(); OiStoreURLProtocol.handle = nil; withExtendedLifetime(backend) {}
            try? FileManager.default.removeItem(at: directory)
        }
        for _ in 0..<150 { if !model.loading { break }; try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertNil(model.failure)
        _ = try await model.webView.evaluateJavaScript("document.querySelector('#storiesButton').click()")
        var sharedReferenceVisible = false
        for _ in 0..<50 {
            if (try await model.webView.evaluateJavaScript("document.querySelector('#educationDialog').textContent.includes('Synthetic shared title')") as? Bool) == true { sharedReferenceVisible = true; break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(sharedReferenceVisible, "Native WebKit must display the same server reference title, not a bundled fictional story")
        _ = try await model.webView.evaluateJavaScript("document.querySelector('#educationDialog').close()")
        _ = try await model.webView.evaluateJavaScript("document.querySelector('#writeButton').click()")
        for _ in 0..<50 {
            if try await model.webView.evaluateJavaScript("!!document.querySelector('.education-form')") as? Bool == true { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        _ = try await model.webView.callAsyncJavaScript("""
        const c=document.createElement('canvas');c.width=c.height=16;c.getContext('2d').fillRect(0,0,16,16);
        const blob=await new Promise(resolve=>c.toBlob(resolve,'image/png'));
        const transfer=new DataTransfer();transfer.items.add(new File([blob],'synthetic.png',{type:'image/png'}));
        const picker=document.querySelector('.education-form input[type=file]');picker.files=transfer.files;picker.dispatchEvent(new Event('change'));
        """, arguments: [:], in: nil, in: .page)
        for _ in 0..<30 {
            if try await model.webView.evaluateJavaScript("!document.querySelector('.education-photo-preview').hidden") as? Bool == true { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let editor = try await model.webView.evaluateJavaScript("""
        (()=>{const form=document.querySelector('.education-form');if(!form)return false;
        for(const [name,value] of Object.entries({theme:'응원',emotion:'따뜻함',display_name:'가상 작성자',title:'가상의 캠퍼스 추억',body:'테스트용 이야기입니다.'}))form.elements[name].value=value;
        [...form.querySelectorAll('button')].find(b=>b.textContent==='서버에 초안 저장').click();return true;})()
        """)
        XCTAssertEqual(editor as? Bool, true)
        await fulfillment(of: [saved, photoStored], timeout: 5)
        for _ in 0..<30 {
            if (try await model.webView.evaluateJavaScript("document.querySelector('.education-status')?.textContent") as? String)?.contains("저장했어요") == true { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("The WebKit editor must receive the native save receipt")
    }

    func testBundledGeometryIsTheCompleteWebSurface() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "education-district-points", withExtension: "bin"))
        let bytes = try Data(contentsOf: url)
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        // Golden export of the latest reviewed four-view web surface.
        XCTAssertEqual(hash, "a1d41bd69331402833d94c4c374b1c3c0455234c9e635e3b4d8e4664c233a008")
        let source = try CampusEducationDistrict.geometry()
        XCTAssertEqual(source.points.count, 110_869)
        XCTAssertEqual(source.shell.count, 60_810)
        XCTAssertEqual(source.groundOffset, 2.299, accuracy: 0.00001)
    }

    func testFullModelFitsRoadConstrainedSiteAtUniformEstimatedScale() throws {
        let source = try CampusEducationDistrict.geometry()
        for sample in source.points {
            XCTAssertTrue(CampusEducationSite.contains(CampusEducationSite.world(sample.position)), "A supplied-model surface is outside the cleared site")
        }
        let data = try CampusMapData.load()
        let library = try XCTUnwrap(data.buildings.first { $0.id == CampusEducationSite.libraryID })
        let libraryArea = abs(library.p.indices.reduce(0.0) { value, i in
            let a = library.p[i], b = library.p[(i + 1) % library.p.count]
            return value + a[0] * b[1] - a[1] * b[0]
        }) / 2 / (0.12 * 0.12)
        let boundary = CampusEducationSite.boundary
        let parcelArea = abs(boundary.indices.reduce(0.0) { value, i in
            let a = boundary[i], b = boundary[(i + 1) % boundary.count]
            return value + Double(a.x * b.y - a.y * b.x)
        }) / 2 / (data.unitsPerMeter * data.unitsPerMeter)
        XCTAssertGreaterThan(parcelArea / libraryArea, 1.8)
        XCTAssertLessThan(parcelArea / libraryArea, 2.0)
        XCTAssertEqual(14.6684234 * Double(CampusEducationSite.scale) / 0.12, 136.905, accuracy: 0.01)
        let roads = CampusEducationSite.TerrainGrading(data: data).roads
        XCTAssertFalse(roads.isEmpty)
        for road in roads {
            let minimum = source.points.reduce(Float.greatestFiniteMagnitude) { distance, sample in
                let p = CampusEducationSite.world(sample.position)
                return min(distance, CampusEducationSite.TerrainGrading.segmentDistance([p.x,p.z], road.a, road.b))
            }
            // Include the physical radius of the largest pearl, not just its center.
            XCTAssertGreaterThan(minimum - 0.031 * CampusEducationSite.scale, road.radius - 0.035)
        }
    }

    func testOfflineExperienceLoadsLatestPearlGarden() async throws {
        let model = EducationLightWebModel()
        let previousWindow = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow }
        let window = UIWindow(windowScene: try XCTUnwrap(previousWindow?.windowScene))
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let controller = UIViewController()
        window.rootViewController = controller
        model.webView.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        model.webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controller.view.addSubview(model.webView)
        window.makeKeyAndVisible()
        defer { model.setActive(false); model.webView.removeFromSuperview(); window.isHidden = true; previousWindow?.makeKeyAndVisible() }
        for _ in 0..<300 {
            if !model.loading { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertFalse(model.loading, "Offline pearl garden did not load")
        let errors = try await model.webView.evaluateJavaScript("JSON.stringify(window.__educationLoadErrors)")
        guard model.failure == nil else { XCTFail("Web renderer: \(String(describing: errors))"); return }
        let result = try await model.webView.evaluateJavaScript("window.prototypeDiagnostics()")
        let diagnostics = try XCTUnwrap(result as? [String: Any])
        XCTAssertEqual(diagnostics["revision"] as? String, "education-pearl-texture-screen-v30")
        XCTAssertEqual(diagnostics["capacity"] as? Int, 44_006)
        XCTAssertEqual(diagnostics["spacePearlCount"] as? Int, 10_000)
        XCTAssertEqual(diagnostics["webgl"] as? Bool, true)
        XCTAssertEqual(diagnostics["gpuScatter"] as? Bool, true)
        XCTAssertEqual(diagnostics["shaderErrors"] as? Int, 0)
        XCTAssertLessThanOrEqual(diagnostics["pixelRatio"] as? Double ?? 100, 1.25)
        XCTAssertEqual(diagnostics["transmissionScale"] as? Double, 0.5)
        XCTAssertLessThan(diagnostics["fitPoints"] as? Int ?? 1000, 300)
        XCTAssertLessThan(diagnostics["triangles"] as? Int ?? 100_000_000, 10_000_000)
        let page = try await model.webView.evaluateJavaScript("""
        ({title:document.querySelector('#pageTitle').textContent,
          decorations:document.querySelectorAll('.funding-rays,.action-rays').length,
          smoothDock:!!document.querySelector('.bottom-dock'),
          stamps:document.querySelectorAll('.garden-note').length,
          nativeLayout:document.querySelector('.experience').classList.contains('native-viewer'),
          directionsInMenu:[...document.querySelectorAll('[data-view]')].every(b=>!!b.closest('#viewerMenu')),
          toolbarHeight:document.querySelector('#writeButton').getBoundingClientRect().height,
          noVerticalOverflow:document.documentElement.scrollHeight<=innerHeight+1,
          base:document.baseURI})
        """)
        let presentation = try XCTUnwrap(page as? [String: Any])
        XCTAssertTrue((presentation["title"] as? String)?.contains("작은 마음이 모여") == true)
        XCTAssertEqual(presentation["decorations"] as? Int, 0)
        XCTAssertEqual(presentation["smoothDock"] as? Bool, true)
        XCTAssertEqual(presentation["stamps"] as? Int, 0)
        XCTAssertEqual(presentation["nativeLayout"] as? Bool, true)
        XCTAssertEqual(presentation["directionsInMenu"] as? Bool, true)
        XCTAssertGreaterThanOrEqual(presentation["toolbarHeight"] as? Double ?? 0, 44)
        XCTAssertEqual(presentation["noVerticalOverflow"] as? Bool, true)
        XCTAssertEqual(presentation["base"] as? String, "oi-education://bundle/")

        let input = """
        const c=document.querySelector('#building'),r=c.getBoundingClientRect();
        function fire(type,id,x,y){c.dispatchEvent(new PointerEvent(type,{bubbles:true,pointerId:id,pointerType:'touch',isPrimary:id===1,button:0,buttons:type==='pointerup'?0:1,clientX:x,clientY:y}));}
        """
        let drag = try await model.webView.evaluateJavaScript("""
        (()=>{\(input)
          const yaw=window.building3DDiagnostics().yaw,x=r.width*.5,y=r.height*.5;
          fire('pointerdown',1,x,y);fire('pointermove',1,x+40,y);fire('pointermove',1,x,y);fire('pointerup',1,x,y);
          return !document.querySelector('.experience').classList.contains('is-scattered')&&window.building3DDiagnostics().scatter===0;
        })()
        """)
        XCTAssertEqual(drag as? Bool, true, "A drag returning to its origin must not unfold the building")
        let pinch = try await model.webView.evaluateJavaScript("""
        (()=>{\(input)
          const x=r.width*.5,y=r.height*.5;
          fire('pointerdown',1,x-30,y);fire('pointerdown',2,x+30,y);fire('pointermove',2,x+60,y);
          fire('pointerup',2,x+60,y);fire('pointermove',1,x-29,y);fire('pointerup',1,x-29,y);
          const valid=window.building3DDiagnostics().zoom>1&&!document.querySelector('.experience').classList.contains('is-scattered');
          document.querySelector('[data-view="front"]').click();return valid;
        })()
        """)
        XCTAssertEqual(pinch as? Bool, true, "Lifting fingers after a pinch must not activate the building")
        let cancelled = try await model.webView.evaluateJavaScript("""
        (()=>{\(input)
          const x=r.width*.5,y=r.height*.5;fire('pointerdown',1,x,y);fire('pointercancel',1,x,y);fire('pointerup',1,x,y);
          fire('pointerdown',1,r.left+1,r.top+1);fire('pointerup',1,r.left+1,r.top+1);
          return !document.querySelector('.experience').classList.contains('is-scattered');
        })()
        """)
        XCTAssertEqual(cancelled as? Bool, true, "Cancelled or empty-canvas taps must not unfold")
        let tapped = try await model.webView.evaluateJavaScript("""
        (()=>{\(input)
          let point;for(let y=.25;y<.82;y+=.025){const x=r.left+r.width*.5,cy=r.top+r.height*y;if(window.educationBuildingHitTest(x,cy)){point=[x,cy];break;}}
          if(!point)return false;
          const [x,y]=point;fire('pointerdown',1,x,y);fire('pointermove',1,x+2,y+2);fire('pointermove',1,x,y);
          if(document.querySelector('.experience').classList.contains('is-scattered'))return false;
          fire('pointerup',1,x,y);return document.querySelector('.experience').classList.contains('is-scattered');
        })()
        """)
        XCTAssertEqual(tapped as? Bool, true, "A real building hit with small finger jitter must unfold on release")
        for _ in 0..<50 {
            if try await model.webView.evaluateJavaScript("window.building3DDiagnostics().scatter===1") as? Bool == true { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(model.scattered)
        let unfolded = try await model.webView.evaluateJavaScript("""
        ({background:getComputedStyle(document.querySelector('.viewer-dimmer')).opacity,
          space:document.querySelectorAll('.night-backdrop,.space-mascot').length,
          hidden:['.viewer-header-controls','#viewerGestureHint','.bottom-dock'].every(s=>getComputedStyle(document.querySelector(s)).display==='none'),
          noReturnButton:document.querySelectorAll('#viewerReturn').length===0,
          aimLayout:(()=>{const a=document.querySelector('#viewerAim').getBoundingClientRect(),p=document.querySelector('#viewerAimStory').getBoundingClientRect();return Math.abs(a.left+a.width/2-innerWidth/2)<1&&Math.abs(a.top+a.height/2-innerHeight*.74)<1&&p.bottom<=innerHeight*.5&&a.top>innerHeight*.5;})(),
          aimed:document.querySelector('#building-stage').dataset.aimPearl!==undefined,
          story:document.querySelector('.aim-story-message').textContent,
          shaderErrors:window.building3DDiagnostics().shaderErrors,
          versions:window.building3DDiagnostics().instanceVersions})
        """)
        let unfoldedState = try XCTUnwrap(unfolded as? [String: Any])
        XCTAssertEqual(unfoldedState["background"] as? String, "0.78")
        XCTAssertEqual(unfoldedState["space"] as? Int, 0)
        XCTAssertEqual(unfoldedState["hidden"] as? Bool, true)
        XCTAssertEqual(unfoldedState["noReturnButton"] as? Bool, true)
        XCTAssertEqual(unfoldedState["aimLayout"] as? Bool, true)
        XCTAssertEqual(unfoldedState["aimed"] as? Bool, true)
        XCTAssertFalse((unfoldedState["story"] as? String ?? "").isEmpty)
        XCTAssertEqual(unfoldedState["shaderErrors"] as? Int, 0)
        XCTAssertEqual(unfoldedState["versions"] as? [Int], diagnostics["instanceVersions"] as? [Int], "GPU morph must not upload every pearl matrix on each frame")
        let gathering = try await model.webView.evaluateJavaScript("""
        (()=>{\(input)
          const stage=document.querySelector('#building-stage'),x=r.width*.5,y=r.height*.74;
          fire('pointerdown',1,x,y);fire('pointerup',1,x,y);
          const started=stage.dataset.scatterTransition==='gathering';
          fire('pointerdown',1,x,y);fire('pointerup',1,x,y);document.querySelector('.brand').click();
          return started&&stage.dataset.scatterTransition==='gathering';
        })()
        """)
        XCTAssertEqual(gathering as? Bool, true, "A tap returns while repeated taps cannot restart scattering")
        for _ in 0..<50 {
            if try await model.webView.evaluateJavaScript("window.building3DDiagnostics().scatter===0") as? Bool == true { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertFalse(model.scattered)
        let returned = try await model.webView.evaluateJavaScript("document.querySelector('#building').getAttribute('role')==='button'&&document.querySelectorAll('#viewerReturn').length===0")
        XCTAssertEqual(returned as? Bool, true)
        model.setActive(false)
        let paused = try await model.webView.evaluateJavaScript("window.prototypeDiagnostics().nativePaused")
        XCTAssertEqual(paused as? Bool, true)
        model.setActive(true)
        let resumed = try await model.webView.evaluateJavaScript("window.prototypeDiagnostics().nativePaused")
        XCTAssertEqual(resumed as? Bool, false)
        _ = try await model.webView.evaluateJavaScript("document.querySelector('#viewerClose').click()")
        for _ in 0..<10 {
            if model.closeRequested { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(model.closeRequested)
    }

    func testAimedStoriesRotateBelowTheCloudAndTapRestoresTheOriginalPose() async throws {
        let model = EducationLightWebModel()
        let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow }
        let window = UIWindow(windowScene: try XCTUnwrap(previous?.windowScene))
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = UIHostingController(rootView: EducationLightExperience(model: model))
        window.makeKeyAndVisible()
        defer { model.setActive(false); window.isHidden = true; previous?.makeKeyAndVisible() }
        for _ in 0..<300 {
            if !model.loading { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertFalse(model.loading)
        XCTAssertNil(model.failure)
        let originalResult = try await model.webView.evaluateJavaScript("JSON.stringify(window.building3DDiagnostics())")
        let original = try XCTUnwrap(originalResult as? String)
        _ = try await model.webView.evaluateJavaScript("document.querySelector('#building').dispatchEvent(new KeyboardEvent('keydown',{key:'Enter'}))")
        for _ in 0..<50 {
            if try await model.webView.evaluateJavaScript("window.building3DDiagnostics().scatter===1") as? Bool == true { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let first = try await model.webView.evaluateJavaScript("document.querySelector('#building-stage').dataset.aimPearl")
        XCTAssertNotNil(first as? String)
        let input = """
        const c=document.querySelector('#building'),r=c.getBoundingClientRect(),x=r.width*.5,y=r.height*.74;
        function fire(type,id,x,y){c.dispatchEvent(new PointerEvent(type,{bubbles:true,pointerId:id,pointerType:'touch',isPrimary:id===1,button:0,buttons:type==='pointerup'?0:1,clientX:x,clientY:y}));}
        """
        _ = try await model.webView.evaluateJavaScript("""
        (()=>{\(input)fire('pointerdown',1,x,y);fire('pointermove',1,x+180,y-400);fire('pointerup',1,x+180,y-400);})()
        """)
        try await Task.sleep(for: .milliseconds(150))
        let explored = try await model.webView.evaluateJavaScript("""
        ({pitch:window.building3DDiagnostics().pitch,scatter:window.building3DDiagnostics().scatter,
          selected:document.querySelector('#building-stage').dataset.aimPearl,
          story:document.querySelector('.aim-story-message').textContent,
          returnButtons:document.querySelectorAll('#viewerReturn').length,
          hiddenNote:document.querySelector('#pearlStoryNote').hidden,
          shaderErrors:window.building3DDiagnostics().shaderErrors})
        """)
        let state = try XCTUnwrap(explored as? [String: Any])
        XCTAssertLessThan(state["pitch"] as? Double ?? 0, -1.5)
        XCTAssertEqual(state["scatter"] as? Double, 1)
        XCTAssertNotEqual(state["selected"] as? String, first as? String)
        XCTAssertFalse((state["story"] as? String ?? "").isEmpty)
        XCTAssertEqual(state["returnButtons"] as? Int, 0)
        XCTAssertEqual(state["hiddenNote"] as? Bool, true)
        XCTAssertEqual(state["shaderErrors"] as? Int, 0)
        _ = try await model.webView.evaluateJavaScript("""
        (()=>{\(input)fire('pointerdown',1,x,y);fire('pointerup',1,x,y);})()
        """)
        for _ in 0..<50 {
            if !model.scattered { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let restored = try await model.webView.evaluateJavaScript("""
        (()=>{const before=JSON.parse(\(String(reflecting: original))),after=window.building3DDiagnostics();return after.scatter===0&&Math.abs(before.yaw-after.yaw)<.0001&&Math.abs(before.pitch-after.pitch)<.0001&&Math.abs(before.zoom-after.zoom)<.0001;})()
        """)
        XCTAssertEqual(restored as? Bool, true, "Gathering must restore the original camera as well as the same pearl positions")
        XCTAssertFalse(model.scattered)
    }

    func testOfflineGardenAssetCatalogIsCompleteAndScoped() throws {
        let catalog = try EducationLightAssetCatalog.load()
        XCTAssertEqual(catalog.revision, "education-pearl-texture-screen-v30")
        XCTAssertGreaterThan(catalog.assets.count, 20)
        for (path, asset) in catalog.assets {
            let request = try XCTUnwrap(URL(string: "oi-education://bundle" + path))
            XCTAssertNotNil(catalog.asset(for: request))
            let resource = try XCTUnwrap(asset.bundleURL(), "Missing packaged asset: \(path)")
            XCTAssertGreaterThan(try Data(contentsOf: resource).count, 0)
        }
        for text in ["oi-education://other/assets/building-v25/model.json",
                     "https://bundle/assets/building-v25/model.json",
                     "oi-education://bundle/Service.local.plist",
                     "oi-education://bundle/../Info.plist"] {
            XCTAssertNil(catalog.asset(for: try XCTUnwrap(URL(string: text))))
        }
        XCTAssertNil(EducationLightAssetCatalog.Asset(resource: "../Info.plist", mime: "text/plain").bundleURL())
    }

    func testBatchedBuildingAndLevelOfDetailSharePlacement() throws {
        let data = try CampusMapData.load()
        let entity = try CampusEducationDistrict.makeEntity(data: data)
        let position = entity.position
        let orientation = entity.orientation
        let bounds = entity.visualBounds(recursive: false, relativeTo: entity)
        XCTAssertEqual(Set(entity.children.map(\.name)), ["education.library-connector"])
        XCTAssertNil(entity.findEntity(named: "education.cleared-parcel"), "The campus grass replaces the old gray pad")
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
        XCTAssertEqual(CampusEducationSite.local(landing).z, CampusEducationSite.bridgeAnchor.z, accuracy: 0.001)
        let front = CampusEducationSite.world([0, 0, 1]) - CampusEducationSite.center
        let towardC5 = SIMD3<Float>(62.19, CampusEducationSite.center.y, 35.25) - CampusEducationSite.center
        XCTAssertGreaterThan(simd_dot(simd_normalize(front), simd_normalize(towardC5)), 0.8)
        XCTAssertEqual(data.grounded([53.4, 7, 39.4]).y, CampusEducationSite.elevation)
    }

    func testGradingMeetsPadAndPreservesRoadsAndFoundations() throws {
        let data = try CampusMapData.load()
        let field = try XCTUnwrap(data.surface)
        let grading = try XCTUnwrap(field.grading)
        for p in CampusEducationSite.boundary {
            XCTAssertEqual(try XCTUnwrap(field.height(x:p.x,z:p.y)), CampusEducationSite.elevation, accuracy: 0.001)
        }
        for road in grading.roads {
            for t: Float in [0,0.25,0.5,0.75,1] {
                let p = road.a + (road.b-road.a)*t
                XCTAssertEqual(field.height(x:p.x,z:p.y), field.rawHeight(x:p.x,z:p.y), "Do not move existing road elevations")
            }
        }
        for id in [CampusEducationSite.libraryID, CampusEducationSite.c5ID] {
            let building = try XCTUnwrap(data.buildings.first { $0.id == id })
            for p in building.p {
                XCTAssertEqual(field.height(x:Float(p[0]),z:Float(-p[1])), field.rawHeight(x:Float(p[0]),z:Float(-p[1])))
            }
        }
        // Sample uphill from the rear parcel edge: continuous grading, not a cliff.
        var changed = 0
        for x in stride(from: Float(41), through: 49, by: 0.1) {
            let a = try XCTUnwrap(field.height(x:x,z:42))
            let b = try XCTUnwrap(field.height(x:x+0.01,z:42))
            XCTAssertLessThan(abs(b-a), 0.08)
            if abs(field.gradingDelta(x:x,z:42)) > 0.01 { changed += 1 }
        }
        XCTAssertGreaterThan(changed, 20)
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

    func testParkingAndAccessSpursBecomeGrassButMainRoadRemains() throws {
        let data = try CampusMapData.load()
        let landscape = CampusEducationLandscape(data:data)
        let field = try XCTUnwrap(data.surface)
        // An old pavement spans the site and main road. Clipping must preserve
        // the road portion instead of deleting the entire intersecting triangle.
        let positions: [SIMD3<Float>] = [[38,0.5,28],[38,0.5,54],[65,0.5,54],[65,0.5,28]]
        let old = CampusEducationSite.MeshBuffers(positions:positions,
            normals:Array(repeating:[0,1,0],count:4),indices:[0,1,2,0,2,3])
        let pavement = landscape.clearing(old, preservingFootpaths:false)
        let pathCrossings = landscape.pathCrossings(old)
        let grass = landscape.grass(surface:field)
        func covered(_ p: SIMD2<Float>, by mesh: CampusEducationSite.MeshBuffers) -> Bool {
            stride(from:0,to:mesh.indices.count,by:3).contains { i in
                let triangle = mesh.indices[i..<i+3].map { mesh.positions[Int($0)] }.map { SIMD2($0.x,$0.z) }
                let signs = triangle.indices.map { j in
                    CampusEducationSite.cross(triangle[(j+1)%3]-triangle[j],p-triangle[j])
                }
                return signs.allSatisfy { $0 >= -0.00001 } || signs.allSatisfy { $0 <= 0.00001 }
            }
        }
        // Old parking below the building, its remaining east edge, and both spurs.
        for p: SIMD2<Float> in [[53,44],[56,48],[58.4,44],[56.9,35.7],[58.7,39.35]] {
            XCTAssertTrue(landscape.contains(p))
            XCTAssertFalse(covered(p,by:pavement), "Old gray pavement remains at \(p)")
            XCTAssertTrue(covered(p,by:grass), "Restored ground has a hole at \(p)")
        }
        for p: SIMD2<Float> in [[58.024,35.25],[59.71,38.9],[62.526,45.005],[55.437,50.186]] {
            XCTAssertFalse(landscape.contains(p))
            XCTAssertTrue(covered(p,by:pavement), "Existing main/library road was removed")
            XCTAssertFalse(covered(p,by:grass), "New grass overlaps a protected road")
        }
        for p: SIMD2<Float> in [[56.483,35.877],[58.367,39.526]] {
            XCTAssertFalse(covered(p,by:pavement), "No leftover asphalt bars where retired spurs crossed a footpath")
            XCTAssertTrue(covered(p,by:pathCrossings), "Keep the existing footpath continuous through each former crossing")
        }
        XCTAssertFalse(covered([59.71,38.9],by:pathCrossings), "Do not recolor the main road as a footpath")
        XCTAssertLessThan(grass.positions.count,20_000)
        XCTAssertEqual(grass.positions.count,grass.normals.count)
        for (p,n) in zip(grass.positions,grass.normals) {
            XCTAssertEqual(p.y,try XCTUnwrap(field.groundHeight(x:p.x,z:p.z)),accuracy:0.0001)
            XCTAssertEqual(simd_length(n),1,accuracy:0.0001)
            XCTAssertGreaterThan(n.y,0)
        }
        for i in stride(from:0,to:grass.indices.count,by:3) {
            let a = grass.positions[Int(grass.indices[i])], b = grass.positions[Int(grass.indices[i+1])], c = grass.positions[Int(grass.indices[i+2])]
            XCTAssertGreaterThanOrEqual(simd_cross(b-a,c-a).y,0, "No folded or vertical grass skirts")
        }
    }

    func testParcelBoundaryTreesAreRemovedWholeAcrossMaterialSeams() {
        let positions: [SIMD3<Float>] = [
            [49.3,2,43.8], [50.0,2,43.8], [49.65,2.5,44.2],
            [49.3,2,43.8], [49.65,2.5,44.2], [49.65,2,44.4],
            [40.0,2,44.8], [40.6,2,44.8], [40.3,2.5,45.2]
        ]
        let source = CampusEducationSite.MeshBuffers(positions: positions,
            normals: Array(repeating: [0,1,0], count: positions.count), indices: Array(0..<9))
        let trees = [CampusEducationSite.Tree(center: [49.666,44.078]), .init(center: [40.313,45.034])]
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
            scene.suspendRendering(); canvas.removeFromSuperview()
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
        for (name, yaw, pitch, radius) in [("front", Float(0), Float(0.5), Float(50)),
             ("left", -.pi / 2, 0.55, 50), ("right", .pi / 2, 0.55, 50),
             ("back", .pi, 0.55, 50), ("site-overhead", -CampusEducationSite.heading, 1.56, 62)] {
            let angle = yaw + CampusEducationSite.heading
            let target = CampusEducationSite.center + SIMD3<Float>(0, 2.5, 0)
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
