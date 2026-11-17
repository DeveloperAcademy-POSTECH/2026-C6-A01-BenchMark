//
//  ARCameraMascotTests.swift
//  OiDonationTests
//
//  Created by Codex on 2026/11/17.
//

import XCTest
import ARKit
import RealityKit
import UIKit
import SwiftUI
@testable import OiDonation

@MainActor final class ARCameraMascotTests: XCTestCase {
    func testRotationChangesOnlyCurrentModesAngleAndBlocksCaptureStates() async {
        let camera = ARSessionController()
        camera.ready = true
        camera.locked = true
        let height = camera.settings.height
        camera.rotateCharacter(to: 420)
        XCTAssertEqual(camera.settings.palmRotation, 60)
        XCTAssertEqual(camera.settings.rotation, 0)
        camera.settings.placementMode = .floor
        camera.rotateCharacter(to: -30)
        XCTAssertEqual(camera.settings.rotation, 330)
        XCTAssertEqual(camera.settings.palmRotation, 60)
        XCTAssertEqual(camera.settings.height, height)
        XCTAssertEqual(camera.settings.floorOffset, 0)
        camera.capturing = true
        camera.rotateCharacter(to: 120)
        XCTAssertEqual(camera.settings.rotation, 330)
        camera.capturing = false
        camera.videoRecording = true
        camera.rotateCharacter(to: 120)
        XCTAssertEqual(camera.settings.rotation, 330)
        camera.videoRecording = false
        camera.rotateCharacter(to: .nan)
        XCTAssertEqual(camera.settings.rotation, 330)
        camera.stop()
        camera.rotateCharacter(to: 120)
        XCTAssertEqual(camera.settings.rotation, 330)
    }

    func testRotationControlRendersFigmaVectorAtOriginalSize() async throws {
        let asset = try XCTUnwrap(UIImage(named: "ARCharacterRotationArrow"))
        XCTAssertEqual(asset.size.width, 58, accuracy: 1)
        let renderer = ImageRenderer(content: ARCharacterRotationControl(angle: 0, rotate: { _ in })
            .background(.white))
        renderer.scale = 3
        let image = try XCTUnwrap(renderer.uiImage)
        XCTAssertEqual(image.size.width, 104)
        XCTAssertEqual(image.size.height, 48)
        let attachment = XCTAttachment(image: image)
        attachment.name = "AR-rotation-Figma-5719-9948"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testSelectableCampusMascotsAreBundledAndLoadWithPalmNormalization() async throws {
        let loader = ARCharacterController()
        for character in ARCharacter.selectableCases where character.wardrobeCostumeID == nil {
            XCTAssertNotNil(Bundle.main.url(forResource: (character.modelFilename as NSString).deletingPathExtension, withExtension: "usdz"),
                "Selectable mascots must be included in the app target: " + character.title)
            let loaded = try await loader.load(character)
            let bounds = loaded.root.visualBounds(relativeTo: nil)
            XCTAssertEqual(bounds.extents.y, 1, accuracy: 0.005, character.title)
            XCTAssertEqual(bounds.min.y, 0, accuracy: 0.005, character.title)
            loaded.root.scale = SIMD3(repeating: 0.065)
            XCTAssertEqual(loaded.root.visualBounds(relativeTo: nil).extents.y, 0.065, accuracy: 0.001, character.title)
        }
    }

    func testCampusCucumberDefaultsToPalmAndRequiresExplicitLocationMode() async throws {
        let placement = try XCTUnwrap(CampusPlacement.story(id: UUID(), latitude: 36.0125, longitude: 129.325,
            heightMeters: 1.5, headingDegrees: 30))
        let subject = ARCameraSubject(id: placement.id, title: "선택한 오이", heightMeters: 1.5, placement: placement) { Entity() }
        let camera = ARSessionController(subject: subject)
        XCTAssertTrue(camera.isPalmMode)
        XCTAssertFalse(camera.usesGeographicPlacement)
        XCTAssertTrue(camera.canUseLocationMode)
        XCTAssertEqual(camera.makeSessionConfiguration().worldAlignment, .gravity)
        camera.applyGeographicStatus(.outsideRange(100), locationMessage: nil)
        XCTAssertTrue(camera.locationNotice.isEmpty)
        XCTAssertFalse(camera.message.contains("저장 위치"))
        var previous = camera.settings
        camera.settings.placementMode = .location
        camera.update(from: previous)
        XCTAssertTrue(camera.usesGeographicPlacement)
        XCTAssertFalse(camera.isPalmMode)
        camera.applyGeographicStatus(.outsideRange(100), locationMessage: nil)
        XCTAssertTrue(camera.locationNotice.contains("이동"))
        previous = camera.settings
        camera.settings.placementMode = .floor
        camera.update(from: previous)
        XCTAssertFalse(camera.usesGeographicPlacement)
        XCTAssertFalse(camera.isPalmMode)
        XCTAssertTrue(camera.locationNotice.isEmpty)
        XCTAssertFalse(camera.message.contains("저장 위치"))
        camera.stop()
    }

    func testMascotCannotEnableLocationWithoutSavedCoordinates() async {
        let camera = ARSessionController()
        XCTAssertTrue(camera.isPalmMode)
        let previous = camera.settings
        camera.settings.placementMode = .location
        camera.update(from: previous)
        XCTAssertEqual(camera.placementMode, .palm)
        XCTAssertFalse(camera.usesGeographicPlacement)
        camera.stop()
    }

    func testTransparentMascotPortraitsRenderFromOriginalModels() async throws {
        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: windowScene)
        let controller = UIViewController()
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 500)
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil; window.windowScene = nil }
        let scene = OiWardrobeScene()
        let view = scene.install()
        view.frame = window.bounds
        controller.view.addSubview(view)
        defer { scene.uninstall(view); view.removeFromSuperview() }
        for id in ["dinosaur", "cat", "baseball", "farmer", "sportswear"] {
            var look = OiWardrobeLook()
            look.costume = try XCTUnwrap(OiWardrobeLook.Costume(rawValue: id))
            scene.update(look)
            for _ in 0..<200 where scene.loading { try await Task.sleep(for: .milliseconds(100)) }
            XCTAssertFalse(scene.loading, id)
            XCTAssertNil(scene.error, id)
            try await Task.sleep(for: .milliseconds(500))
            let captured = await scene.cardPortrait()
            let portrait = try XCTUnwrap(captured, id)
            let data = try XCTUnwrap(portrait.pngData(), id)
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
            attachment.name = "ar-transparent-" + id
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testRetiredStadiumBackgroundCannotReactivateInPalmOrFloorMode() async throws {
        let camera = ARSessionController()
        // Existing photo JSON still decodes, but cannot reinstall a compositor.
        var legacy = ARCaptureSettings()
        legacy.background = .stadium
        legacy.directLight = false
        legacy.intensity = 1400
        camera.settings = try JSONDecoder().decode(ARCaptureSettings.self, from: JSONEncoder().encode(legacy))
        camera.applySettings()
        XCTAssertEqual(camera.settings.background, .original)
        XCTAssertFalse(camera.settings.directLight, "Preserve explicitly saved lighting")
        XCTAssertEqual(camera.settings.intensity, 1400)
        XCTAssertNil(camera.view.renderCallbacks.prepareWithDevice)
        XCTAssertNil(camera.view.renderCallbacks.postProcess)
        camera.settings.placementMode = .palm
        let previous = camera.settings
        camera.settings.background = .stadium
        camera.update(from: previous)
        XCTAssertEqual(camera.settings.background, .original)
        camera.settings.placementMode = .floor
        let floor = camera.settings
        camera.settings.background = .stadium
        camera.update(from: floor)
        XCTAssertEqual(camera.settings.background, .original)
        camera.stop()
    }

    func testRepeatedOriginalSelectionPreservesMascotSettingsAndIdentity() async {
        let subject = ARCameraSubject(id: UUID(), title: "지도 오이", heightMeters: 1.5) { Entity() }
        let camera = ARSessionController(subject: subject)
        camera.selectMascot(.ponix)
        camera.settings.placementMode = .palm
        camera.settings.palmHeight = 0.08
        camera.restoreOriginalSubject()
        camera.restoreOriginalSubject()
        camera.selectMascot(.oiCat)
        XCTAssertTrue(camera.isPalmMode)
        XCTAssertEqual(camera.settings.palmHeight, 0.08)
        XCTAssertNil(camera.settings.cucumberStoryID)
        XCTAssertNil(camera.settings.cucumberName)
        camera.stop()
    }

    func testWardrobeMascotsLoadBundledModelsAndThumbnails() async throws {
        let loader = ARCharacterController()
        for character in ARCharacter.selectableCases where character.wardrobeCostumeID != nil {
            let url = try XCTUnwrap(Bundle.main.url(forResource: character.previewImageName,
                withExtension: "png", subdirectory: "ARThumbnails")
                ?? Bundle.main.url(forResource: character.previewImageName, withExtension: "png"), character.title)
            let image = try XCTUnwrap(UIImage(contentsOfFile: url.path)?.cgImage, character.title)
            var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
            try pixels.withUnsafeMutableBytes { bytes in
                let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                    bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            }
            XCTAssertEqual(pixels[3], 0, "The background must be transparent: " + character.title)
            XCTAssertGreaterThan(stride(from: 3, to: pixels.count, by: 4).filter { pixels[$0] > 230 }.count, 1000,
                "The character and light clothes must remain visible: " + character.title)
            let loaded = try await loader.load(character)
            let bounds = loaded.root.visualBounds(relativeTo: nil)
            XCTAssertEqual(bounds.extents.y, 1, accuracy: 0.005, character.title)
            XCTAssertEqual(bounds.min.y, 0, accuracy: 0.005, character.title)
        }
    }

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
        XCTAssertTrue(camera.isPalmMode)
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
