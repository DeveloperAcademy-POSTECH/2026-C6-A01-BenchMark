//
//  ARCameraMascotTests.swift
//  OiDonationTests
//
//  Created by Codex on 2026/11/17.
//

import XCTest
import ARKit
import RealityKit
@testable import OiDonation

@MainActor final class ARCameraMascotTests: XCTestCase {
    func testMascotSwitchRestoresOriginalStoryAndItsSettings() async throws {
        let id = UUID()
        let placement = try XCTUnwrap(CampusPlacement.story(id: id, latitude: 36.0125, longitude: 129.325,
            heightMeters: 1.5, headingDegrees: 30))
        let subject = ARCameraSubject(id: id, title: "원래 오이", heightMeters: 1.5, placement: placement) { Entity() }
        let camera = ARSessionController(subject: subject)
        camera.settings.height = 1.1
        camera.settings.rotation = 45
        camera.selectMascot(.ponix)
        XCTAssertNil(camera.subject)
        XCTAssertFalse(camera.usesGeographicPlacement)
        XCTAssertEqual(camera.settings.character, .ponix)
        XCTAssertNil(camera.settings.cucumberStoryID)
        camera.settings.placementMode = .palm
        camera.settings.palmHeight = 0.08
        camera.restoreOriginalSubject()
        XCTAssertEqual(camera.subject?.id, id)
        XCTAssertEqual(camera.subject?.placement, placement)
        XCTAssertEqual(camera.settings.cucumberStoryID, id)
        XCTAssertEqual(camera.settings.height, 1.1)
        XCTAssertEqual(camera.settings.rotation, 45)
        XCTAssertFalse(camera.isPalmMode)
        camera.selectMascot(.neopjuk)
        XCTAssertTrue(camera.isPalmMode)
        XCTAssertEqual(camera.settings.palmHeight, 0.08)
        camera.stop()
    }

    func testPalmConfigurationSkipsUnusedWorldReconstructionAndOcclusion() async {
        let camera = ARSessionController()
        camera.settings.placementMode = .palm
        camera.settings.peopleOcclusion = true
        camera.settings.sceneOcclusion = true
        let config = camera.makeSessionConfiguration()
        XCTAssertTrue(config.planeDetection.isEmpty)
        XCTAssertTrue(config.sceneReconstruction.isEmpty)
        XCTAssertFalse(config.frameSemantics.contains(.personSegmentationWithDepth))
        XCTAssertEqual(config.environmentTexturing, .none)
        if ARWorldTrackingConfiguration.supportedVideoFormats.contains(where: { $0.framesPerSecond == 30 }) {
            XCTAssertEqual(config.videoFormat.framesPerSecond, 30)
        }
        camera.settings.placementMode = .floor
        XCTAssertTrue(camera.makeSessionConfiguration().planeDetection.contains(.horizontal))
        camera.stop()
    }

    func testPalmCannotCaptureWithoutAFreshVisibleHand() async {
        let camera = ARSessionController()
        camera.settings.placementMode = .palm
        XCTAssertTrue(camera.isPalmMode)
        XCTAssertFalse(camera.palmTracking)
        XCTAssertFalse(camera.canCapture)
        camera.pause()
        XCTAssertFalse(camera.palmTracking)
        camera.stop()
    }
}
