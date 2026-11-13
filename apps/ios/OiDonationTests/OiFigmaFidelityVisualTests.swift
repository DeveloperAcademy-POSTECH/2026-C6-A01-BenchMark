//
//  OiFigmaFidelityVisualTests.swift
//  OiDonationTests
//
//  Created by 이돈혁 on 11/3/26.
//

import CoreText
import RealityKit
import SwiftUI
import UIKit
import XCTest
import simd
@testable import OiDonation

/// Captures the production views with local test fixtures for human Figma comparison.
/// The assertions detect missing renders; they do not claim pixel-perfect fidelity.
@MainActor
final class OiFigmaFidelityVisualTests: XCTestCase {
    private struct Variant {
        let name: String
        let size: CGSize
        let dynamicTypeSize: DynamicTypeSize
    }

    private var variants: [Variant] {
        [
            Variant(name: "402x874", size: CGSize(width: 402, height: 874), dynamicTypeSize: .large),
            Variant(name: "375x667", size: CGSize(width: 375, height: 667), dynamicTypeSize: .large),
            Variant(name: "440x956", size: CGSize(width: 440, height: 956), dynamicTypeSize: .large),
            Variant(name: "accessibility5", size: CGSize(width: 402, height: 874), dynamicTypeSize: .accessibility5)
        ]
    }

    func testMYHouseArtworkDoesNotRevealImageMatte() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        let variant = Variant(name: "124x124", size: CGSize(width: 124, height: 124), dynamicTypeSize: .large)
        for isPressed in [false, true] {
            let artwork = CampusMyHouseButtonStyle().makeBody(label: CampusMyHouseButtonArtwork(), isPressed: isPressed)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.74, green: 0.82, blue: 0.66))
            let png = try await capture(artwork, name: isPressed ? "my-house-pressed" : "my-house-idle",
                                        variant: variant, defaults: fixture.defaults, includesSafeArea: false)
            let bitmap = try renderedBitmap(png, size: variant.size)
            let pixels = try XCTUnwrap(bitmap.data).bindMemory(to: UInt8.self, capacity: 124 * 124 * 4)
            for y in [40, 82] {
                // Both samples are inside the circle, on opposite sides of the PNG's left edge.
                let outside = (y * 124 + 21) * 4
                let inside = (y * 124 + 23) * 4
                XCTAssertGreaterThan(Int(pixels[outside]) - Int(pixels[0]), 30,
                                     "The sampled edge must be within the cream button, not the page background")
                for channel in 0..<3 {
                    XCTAssertLessThanOrEqual(abs(Int(pixels[outside + channel]) - Int(pixels[inside + channel])), 8,
                                             "The source image matte must blend through its edge (pressed: \(isPressed))")
                }
            }
        }
    }

    func testPostcardRefreshCaptures() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        var style = Self.customization
        style.card = OiCardDesign()
        style.card?.postcardLayoutVersion = 2
        style.card?.portraitPNG = try XCTUnwrap(UIImage(named: "OiCatsPortrait")?.pngData())
        style.card?.postcardBackground = .init(color: 0xE8EECF, fill: .gradient, preset: "lime")
        for variant in variants.prefix(2) {
            for title in ["내용", "배경", "커스텀", "로고", "스탬프", "이미지"] {
                var selected = style
                if title == "커스텀" {
                    selected.card?.postcardBackground = .init(color: 0xF4E1BE, fill: .gradient,
                        middleColor: 0xF1F4D1, endColor: 0xAFC18C)
                }
                let page = VStack(spacing: 0) {
                    OiCreationProgressHeader(step: 4, onPrevious: {})
                        .padding(.horizontal, 20).padding(.bottom, 8)
                    OiCardCustomizationStep(draft: .constant(Self.draft), customization: .constant(selected),
                        donorName: "가상 작성자", academicAuthor: "기계공학과 19학번", onContinue: {})
                        .tabForTest(title == "커스텀" ? "배경" : title, custom: title == "커스텀")
                }.background(.white)
                try await capture(page, name: "postcard-refresh-\(title)", variant: variant,
                    defaults: fixture.defaults, delay: .milliseconds(300), attach: true)
            }
        }
    }

    func testPostcardRefreshPersistenceAndPrivacy() throws {
        var value = Self.customization
        value.showsCharacter = false
        value.card = OiCardDesign()
        value.card?.postcardLayoutVersion = 2
        value.card?.postcardStamp = 3
        value.card?.postcardLogo = "white"
        value.card?.postcardBackground = .init(color: 0xE8EECF, fill: .gradient, preset: "lime", authorMode: "anonymous")
        XCTAssertEqual(try JSONDecoder().decode(OiDraftCustomization.self, from: JSONEncoder().encode(value)), value)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(try XCTUnwrap(value.card))) as? [String: Any])
        for key in ["postcardLayoutVersion", "postcardStamp", "postcardLogo", "postcardAcademicAuthor"] { legacy.removeValue(forKey: key) }
        let decoded = try JSONDecoder().decode(OiCardDesign.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(decoded.postcardLayoutVersion)
        XCTAssertNil(decoded.postcardStamp)
        let anonymous = try OiDraftCardPreview(draft: Self.draft, customization: value, donorName: "비공개 이름").publication(colorScheme: .light)
        XCTAssertEqual(anonymous.parts.count, 4)
        let front = try XCTUnwrap(UIImage(data: anonymous.png))
        OiPostcardBackgroundMetadata.remember(png: anonymous.png, image: front)
        let metadata = try XCTUnwrap(OiPostcardBackgroundMetadata.style(for: front))
        XCTAssertEqual(metadata.preset, "lime")
        XCTAssertEqual(metadata.authorMode, "anonymous")
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(metadata), as: UTF8.self).contains("비공개 이름"))
        let restored = try OiCardImageExport.publication(front: front, message: Self.draft.body, author: "다른 계정 이름")
        XCTAssertEqual(anonymous.parts[.back], restored.parts[.back], "Reopening a remote card must retain anonymous attribution")
        XCTAssertEqual(OiPostcardAuthor.text(mode: "academic", name: "비공개 이름", academic: ""), "익명")
        XCTAssertEqual(OiPostcardAuthor.text(mode: "academic", name: "이름", academic: "컴퓨터공학과 23학번"), "컴퓨터공학과 23학번")
        XCTAssertEqual(OiPostcardAuthor.text(mode: "name", name: "공개 이름", academic: ""), "공개 이름")
        XCTAssertEqual(OiPostcardAuthor.text(mode: "unknown", name: "비공개 이름", academic: ""), "익명")
        value.card?.postcardBackground = .init(color: 0xFF0000, fill: .gradient, middleColor: 0x00FF00, endColor: 0x0000FF)
        let gradient = try OiDraftCardPreview(draft: Self.draft, customization: value).publication(colorScheme: .light)
        let gradientImage = try XCTUnwrap(UIImage(data: gradient.png))
        OiPostcardBackgroundMetadata.remember(png: gradient.png, image: gradientImage)
        XCTAssertEqual(OiPostcardBackgroundMetadata.style(for: gradientImage), value.card?.postcardBackground)
        XCTAssertNotEqual(anonymous.png, gradient.png)
        for preset in OiPostcardPreset.allCases {
            XCTAssertNotNil(UIImage(named: preset.asset), "Missing original Figma background: \(preset)")
            XCTAssertNotNil(UIImage(named: preset.swatch))
        }
        let lime = try OiCardImageExport.render(OiPostcardBackground(style: .init(color: 0xE8EECF, preset: "lime")))
        let left = try XCTUnwrap(OiPostcardSnapshot.color(lime, x: 150.0 / 362, y: 369.0 / 502))
        let right = try XCTUnwrap(OiPostcardSnapshot.color(lime, x: 158.0 / 362, y: 369.0 / 502))
        for shift in [0, 8, 16] {
            XCTAssertLessThan(abs(Int((left >> shift) & 255) - Int((right >> shift) & 255)), 8,
                              "Native assets must retain the soft blur, not a hard ellipse edge")
        }
        for color in ["white", "black"] {
            for number in 1...6 { XCTAssertNotNil(UIImage(named: "OiPostcardStamp-\(color)\(number)")) }
            XCTAssertNotNil(UIImage(named: "OiPostcardLogo-" + color))
        }
    }

    func testPostcardCustomGradientUsesFigmaFields() throws {
        let colors = OiPostcardPreset.lime.colors
        let image = try XCTUnwrap(OiPostcardBackgroundTexture.image(start: colors.start, middle: colors.middle, end: colors.end))
        XCTAssertTrue(image === OiPostcardBackgroundTexture.image(start: colors.start, middle: colors.middle, end: colors.end))
        let referenceRenderer = ImageRenderer(content: Image(OiPostcardPreset.lime.asset).resizable().frame(width: 362, height: 502))
        referenceRenderer.scale = 1
        let reference = try XCTUnwrap(referenceRenderer.uiImage)
        var totalDifference = 0
        var sampleCount = 0
        for y in stride(from: 30, through: 470, by: 40) {
            for x in stride(from: 30, through: 330, by: 30) {
                let actual = try XCTUnwrap(OiPostcardSnapshot.color(image, x: CGFloat(x) / 362, y: CGFloat(y) / 502))
                let expected = try XCTUnwrap(OiPostcardSnapshot.color(reference, x: CGFloat(x) / 362, y: CGFloat(y) / 502))
                for shift in [0, 8, 16] {
                    totalDifference += abs(Int((actual >> shift) & 255) - Int((expected >> shift) & 255))
                    sampleCount += 1
                }
            }
        }
        XCTAssertLessThan(Double(totalDifference) / Double(sampleCount), 8,
                          "Custom fields must match the Figma preset's positions, spread and opacity")
        let diagnostic = try XCTUnwrap(OiPostcardBackgroundTexture.image(start: 0xFF0000, middle: 0x00FF00, end: 0x0000FF))
        func rgb(_ x: CGFloat, _ y: CGFloat) throws -> (Int, Int, Int) {
            let pixel = try XCTUnwrap(OiPostcardSnapshot.color(diagnostic, x: x / 362, y: y / 502))
            return (Int(pixel >> 16 & 255), Int(pixel >> 8 & 255), Int(pixel & 255))
        }
        let topRight = try rgb(330, 40), bottomLeft = try rgb(30, 440)
        XCTAssertGreaterThan(topRight.0, bottomLeft.0 + 25, "Start color belongs in the upper right")
        XCTAssertGreaterThan(bottomLeft.2, topRight.2 + 25, "End color belongs in the lower left")
        XCTAssertGreaterThan(try rgb(30, 40).1, topRight.1 + 10, "Middle color spans the upper-left diagonal")
        XCTAssertGreaterThan(try rgb(330, 460).1, bottomLeft.1 + 10, "Middle color spans the lower-right diagonal")
        var style = OiPostcardBackgroundStyle(color: colors.middle, preset: "lime", authorMode: "anonymous")
        style.setCustomColor(0x123456, at: 0)
        XCTAssertNil(style.preset)
        XCTAssertEqual(style.customColors, .init(start: 0x123456, middle: colors.middle, end: colors.end))
        style.setCustomColor(0xABCDE0, at: 1)
        XCTAssertEqual(style.customColors, .init(start: 0x123456, middle: 0xABCDE0, end: colors.end))
        XCTAssertEqual(style.authorMode, "anonymous")
        XCTAssertEqual(style.paperColor, 0xABCDE0)
        XCTAssertEqual(try JSONDecoder().decode(OiPostcardBackgroundStyle.self, from: JSONEncoder().encode(style)), style)
        let shot = XCTAttachment(image: image)
        shot.name = "custom-fields-lime-figma-match"; shot.lifetime = .keepAlways; add(shot)
        let diagnosticShot = XCTAttachment(image: diagnostic)
        diagnosticShot.name = "custom-fields-start-red-middle-green-end-blue"; diagnosticShot.lifetime = .keepAlways; add(diagnosticShot)
    }

    func testPostcardColorRingOpensNativePickerAndUpdatesColor() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        var color: UInt32 = 0xE8EECF
        let ring = OiPostcardColorRing(title: "시작", color: Binding(get: { color }, set: { color = $0 }))
            .accessibilityIdentifier("test.postcard.color-ring")
        let host = UIHostingController(rootView: ring.frame(maxWidth: .infinity, maxHeight: .infinity).background(.white))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            host.dismiss(animated: false)
            window.isHidden = true; window.rootViewController = nil; window.windowScene = nil
            previous?.makeKey()
        }
        try await Task.sleep(for: .milliseconds(250))
        func findRing(_ view: UIView) -> UIButton? {
            if let button = view as? UIButton, button.accessibilityIdentifier == "oi.postcard.color-ring.control" { return button }
            for child in view.subviews { if let button = findRing(child) { return button } }
            return nil
        }
        let button = try XCTUnwrap(findRing(host.view), "The ring must expose a real, activatable button")
        let point = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: host.view)
        XCTAssertTrue(host.view.hitTest(point, with: nil) === button, "The visible ring must receive the touch")
        button.sendActions(for: .primaryActionTriggered)
        try await Task.sleep(for: .milliseconds(600))
        func findPicker(_ controller: UIViewController) -> UIColorPickerViewController? {
            if let picker = controller as? UIColorPickerViewController { return picker }
            if let presented = controller.presentedViewController, let found = findPicker(presented) { return found }
            for child in controller.children { if let found = findPicker(child) { return found } }
            return nil
        }
        let picker = try XCTUnwrap(findPicker(host), "Activating the ring must present Apple's real color picker")
        XCTAssertNotNil(picker.viewIfLoaded?.window, "The picker must be visibly attached, not only created")
        XCTAssertGreaterThan(picker.view.bounds.height, 100)
        XCTAssertFalse(picker.supportsAlpha)
        XCTAssertEqual(Color(picker.selectedColor).oiRGB, 0xE8EECF)
        if ProcessInfo.processInfo.environment["OI_HOLD_COLOR_PICKER_CAPTURE"] == "1" {
            FileHandle.standardOutput.write(Data("POSTCARD_NATIVE_PICKER_READY\n".utf8))
            try await Task.sleep(for: .seconds(8))
        }
        picker.delegate?.colorPickerViewController?(picker, didSelect: UIColor(Color(oiRGB: 0x2478A0)), continuously: true)
        XCTAssertEqual(color, 0x2478A0, "Dragging through colors must update the bound card immediately")
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let shot = XCTAttachment(image: screenshot)
        shot.name = "postcard-native-color-picker-open"; shot.lifetime = .keepAlways; add(shot)
        picker.delegate?.colorPickerViewControllerDidFinish?(picker)
    }

    func testPostcardBackLogoColorPersistsWithoutChangingFront() throws {
        var customization = Self.customization
        customization.showsCharacter = false
        customization.card = OiCardDesign()
        customization.card?.postcardLayoutVersion = 2
        customization.card?.postcardLogo = "white"
        customization.card?.postcardBackground = .init(color: 0xE8EECF, preset: "lime")
        func image(_ value: OiDraftCustomization, back: Bool) throws -> Data {
            let renderer = ImageRenderer(content: OiDraftCardPreview(draft: Self.draft, customization: value,
                donorName: "가상 작성자", showingBack: back).frame(width: 362, height: 502))
            renderer.scale = 1
            return try XCTUnwrap(renderer.uiImage?.pngData())
        }
        let originalFront = try image(customization, back: false)
        customization.card?.postcardBackground?.backLogoColor = 0xB03050
        XCTAssertEqual(originalFront, try image(customization, back: false), "Back logo tint must not recolor the front")
        let redBack = try image(customization, back: true)
        customization.card?.postcardBackground?.backLogoColor = 0x246BA0
        let blueBack = try image(customization, back: true)
        XCTAssertNotEqual(redBack, blueBack)
        let before = try renderedBitmap(redBack, size: CGSize(width: 362, height: 502))
        let after = try renderedBitmap(blueBack, size: CGSize(width: 362, height: 502))
        let first = try XCTUnwrap(before.data).bindMemory(to: UInt8.self, capacity: 362 * 502 * 4)
        let second = try XCTUnwrap(after.data).bindMemory(to: UInt8.self, capacity: 362 * 502 * 4)
        var outsideDelta = 0
        for y in 0..<250 {
            for x in 0..<362 {
                let i = (y * 362 + x) * 4
                for channel in 0..<4 { outsideDelta = max(outsideDelta, abs(Int(first[i + channel]) - Int(second[i + channel]))) }
            }
        }
        XCTAssertEqual(outsideDelta, 0, "Paper and text above the watermark must retain their original pixels")
        let encoded = try JSONEncoder().encode(customization)
        XCTAssertEqual(try JSONDecoder().decode(OiDraftCustomization.self, from: encoded), customization)
        let style = try XCTUnwrap(customization.card?.postcardBackground)
        let legacy = try JSONDecoder().decode(OiPostcardBackgroundStyle.self, from: Data(#"{"color":15265487,"fill":"gradient"}"#.utf8))
        XCTAssertNil(legacy.backLogoColor)
        let publication = try OiDraftCardPreview(draft: Self.draft, customization: customization,
            donorName: "가상 작성자").publication(colorScheme: .light)
        let front = try XCTUnwrap(UIImage(data: publication.png))
        OiPostcardBackgroundMetadata.remember(png: publication.png, image: front)
        XCTAssertEqual(OiPostcardBackgroundMetadata.style(for: front)?.backLogoColor, 0x246BA0)
        let restored = try OiCardImageExport.publication(front: front, message: Self.draft.body, author: "가상 작성자")
        XCTAssertEqual(publication.parts[.back], restored.parts[.back], "A reused server front must retain the selected back logo color")
        XCTAssertEqual(publication.parts.count, 4)
        var invalid = style; invalid.backLogoColor = 0x1000000
        let png = try XCTUnwrap(OiPostcardBackgroundMetadata.png(image: front, style: invalid))
        let invalidImage = try XCTUnwrap(UIImage(data: png))
        OiPostcardBackgroundMetadata.remember(png: png, image: invalidImage)
        XCTAssertNil(OiPostcardBackgroundMetadata.style(for: invalidImage))
    }

    func testPostcardBackLogoEditorCaptures() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        var customization = Self.customization
        customization.showsCharacter = false
        customization.card = OiCardDesign()
        customization.card?.postcardLayoutVersion = 2
        customization.card?.postcardBackground = .init(color: 0xE8EECF, preset: "lime", backLogoColor: 0xD0A6AE)
        for variant in variants.prefix(2) {
            let page = PostcardBackLogoLiveFixture(draft: Self.draft, customization: customization, changed: { _ in })
            try await capture(page, name: "postcard-back-logo-editor", variant: variant,
                defaults: fixture.defaults, delay: .milliseconds(300), attach: true)
        }
    }

    func testPostcardBackLogoPickerUpdatesLivePreview() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        var customization = Self.customization
        customization.showsCharacter = false
        customization.card = OiCardDesign()
        customization.card?.postcardLayoutVersion = 2
        customization.card?.postcardBackground = .init(color: 0xE8EECF, preset: "lime", backLogoColor: 0xD0A6AE)
        var selected: UInt32?
        let host = UIHostingController(rootView: PostcardBackLogoLiveFixture(draft: Self.draft,
            customization: customization, changed: { selected = $0 }))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer {
            host.dismiss(animated: false); window.isHidden = true
            window.rootViewController = nil; window.windowScene = nil; previous?.makeKey()
        }
        try await Task.sleep(for: .milliseconds(300))
        func button(in view: UIView) -> UIButton? {
            if let button = view as? UIButton, button.accessibilityIdentifier == "oi.postcard.color-ring.control" { return button }
            for child in view.subviews { if let found = button(in: child) { return found } }
            return nil
        }
        try XCTUnwrap(button(in: host.view)).sendActions(for: .primaryActionTriggered)
        try await Task.sleep(for: .milliseconds(650))
        func colorPicker(in controller: UIViewController) -> UIColorPickerViewController? {
            if let picker = controller as? UIColorPickerViewController { return picker }
            if let presented = controller.presentedViewController, let found = colorPicker(in: presented) { return found }
            for child in controller.children { if let found = colorPicker(in: child) { return found } }
            return nil
        }
        let picker = try XCTUnwrap(colorPicker(in: host))
        XCTAssertNotNil(picker.viewIfLoaded?.window)
        XCTAssertEqual(Color(picker.selectedColor).oiRGB, 0xD0A6AE)
        picker.delegate?.colorPickerViewController?(picker, didSelect: UIColor(Color(oiRGB: 0x246BA0)), continuously: true)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(selected, 0x246BA0, "The actual editor draft must update while the native picker stays open")
        if ProcessInfo.processInfo.environment["OI_HOLD_POSTECH_PICKER_CAPTURE"] == "1" {
            FileHandle.standardOutput.write(Data("POSTCARD_POSTECH_PICKER_READY\n".utf8))
            try await Task.sleep(for: .seconds(8))
        }
        picker.delegate?.colorPickerViewControllerDidFinish?(picker)
    }

    func testPostcardLogosPreserveUnderlyingArtwork() throws {
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { context in
            UIColor.systemPink.setFill(); context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
            UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 32, height: 64))
        }
        let portrait = try XCTUnwrap(UIImage(named: "OiCatsPortrait"))
        var value = Self.customization
        value.card = OiCardDesign()
        value.card?.postcardLayoutVersion = 2
        value.card?.postcardBackground = .init(color: 0xE8EECF, preset: "lime")
        value.card?.backgroundPhoto = photo.pngData()
        value.card?.postcardStamp = 1
        func render(_ style: OiDraftCustomization) throws -> Data {
            let renderer = ImageRenderer(content: OiDraftCardPreview(draft: Self.draft,
                customization: style, portrait: portrait).frame(width: 362, height: 502))
            renderer.scale = 1
            return try XCTUnwrap(renderer.uiImage?.pngData())
        }
        for character in [false, true] {
            value.showsCharacter = character
            value.card?.postcardLogo = nil
            let original = try renderedBitmap(render(value), size: CGSize(width: 362, height: 502))
            let before = try XCTUnwrap(original.data).bindMemory(to: UInt8.self, capacity: 362 * 502 * 4)
            for logo in ["white", "black"] {
                value.card?.postcardLogo = logo
                let png = try render(value)
                let result = try renderedBitmap(png, size: CGSize(width: 362, height: 502))
                let after = try XCTUnwrap(result.data).bindMemory(to: UInt8.self, capacity: 362 * 502 * 4)
                var changed = 0
                var outsideDelta = 0
                for y in 0..<502 {
                    for x in 0..<362 {
                        let offset = (y * 362 + x) * 4
                        for channel in 0..<4 {
                            let delta = abs(Int(before[offset + channel]) - Int(after[offset + channel]))
                            if delta > 0 { changed += 1 }
                            // The original OiD paths occupy only x=46.5...63.5.
                            // Any other changed pixel would obscure the card's underlying layers.
                            if x < 45 || x > 65 { outsideDelta = max(outsideDelta, delta) }
                        }
                    }
                }
                XCTAssertGreaterThan(changed, 100, "Selecting a logo must draw its actual paths")
                XCTAssertEqual(outsideDelta, 0, "\(logo) logo must preserve photo, cucumber, paper and stamp pixels")
                let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
                attachment.name = "transparent-logo-\(logo)-\(character ? "cucumber" : "photo")"
                attachment.lifetime = .keepAlways; add(attachment)
            }
        }
    }

    func testStoryBodyByteLimitAndLongCardExport() throws {
        var body = String(repeating: "가", count: 500)
        let binding = OiStoryWritingStep.limitedStoryText(Binding(get: { body }, set: { body = $0 }))
        binding.wrappedValue += "!"
        XCTAssertEqual(body.utf8.count, 1500)
        binding.wrappedValue = String(repeating: "a", count: 1500)
        XCTAssertEqual(body.count, 1500)
        binding.wrappedValue = String(repeating: "🙂", count: 375)
        XCTAssertEqual(body.utf8.count, 1500)
        binding.wrappedValue += "🙂"
        XCTAssertEqual(body.utf8.count, 1500)
        body = String(repeating: "가", count: 600)
        binding.wrappedValue = String(body.dropLast())
        XCTAssertEqual(body.count, 599, "Over-limit old drafts must be recoverable without truncation")
        binding.wrappedValue += "가"
        XCTAssertEqual(body.count, 599)
        for text in [String(repeating: "가", count: 500), String(repeating: "a", count: 1500)] {
            var draft = Self.draft; draft.body = text
            XCTAssertTrue(OiCreationStep.story.canContinue(draft: draft))
            draft.body += "!"
            XCTAssertFalse(OiCreationStep.story.canContinue(draft: draft))
            XCTAssertGreaterThanOrEqual(try OiCardImageExport.fittingFontSize(text), 6)
        }
    }

    func testStoryWritingCaptures() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        for variant in variants {
            for bottom in [false, true] {
                let page = CreationCapturePage(step: 2, anchor: bottom ? .bottom : .top) {
                    StoryWritingCapture(draft: Self.draft)
                }
                try await capture(page, name: "writing\(bottom ? "-bottom" : "")", variant: variant, defaults: fixture.defaults)
            }
        }
    }

    func testStoryFieldsGrowAfterPastingMultipleLines() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: ScrollView { StoryPasteFixture() })
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            window.windowScene = nil
            previousKeyWindow?.makeKey()
        }

        let pasteboard = UIPasteboard.general
        let previousItems = pasteboard.items
        defer { pasteboard.items = previousItems }
        let pastedText = "캠퍼스의 봄\n친구와 걷던 길\n함께 남긴 이야기"

        func editors(in view: UIView) -> [UITextView] {
            if let editor = view as? UITextView { return [editor] }
            return view.subviews.flatMap { editors(in: $0) }
        }

        try await Task.sleep(for: .milliseconds(300))
        let fields = editors(in: host.view).sorted { $0.convert(.zero, to: host.view).minY < $1.convert(.zero, to: host.view).minY }
        XCTAssertEqual(fields.count, 2)
        for field in fields {
            XCTAssertTrue(field.becomeFirstResponder())
            try await Task.sleep(for: .milliseconds(300))
            let initialHeight = field.bounds.height
            XCTAssertGreaterThan(initialHeight, 0)
            pasteboard.string = pastedText
            field.paste(nil)
            try await Task.sleep(for: .milliseconds(400))
            XCTAssertEqual(field.text, pastedText)
            XCTAssertGreaterThan(field.bounds.height, initialHeight + 20)
            XCTAssertFalse(field.isScrollEnabled)
            field.resignFirstResponder()
        }
    }

    func testStoryTextBindingPreservesLegacyDrafts() {
        let original = String(repeating: "추억", count: 30)
        var text = original
        let binding = OiStoryWritingStep.limitedText(Binding(get: { text }, set: { text = $0 }))
        XCTAssertEqual(binding.wrappedValue, original)

        let shortened = String(original.dropLast())
        binding.wrappedValue = shortened
        XCTAssertEqual(text, shortened, "Deleting one character must preserve all remaining legacy text")
        binding.wrappedValue = shortened + "가"
        XCTAssertEqual(text, shortened, "An over-limit draft may be shortened but not extended")

        let atLimit = String(repeating: "가", count: OiCreationStep.storyTextLimit)
        binding.wrappedValue = atLimit
        XCTAssertEqual(text, atLimit)
        binding.wrappedValue = String(repeating: "나", count: OiCreationStep.storyTextLimit + 1)
        XCTAssertEqual(text, atLimit, "Over-limit pastes must be rejected, not silently truncated")

        binding.wrappedValue = "짧은 이야기"
        binding.wrappedValue += "!"
        XCTAssertEqual(text, "짧은 이야기!")
    }

    private struct StoryPasteFixture: View {
        @State private var draft = OiStoryDraft()
        @FocusState private var focusedField: OiStoryWritingStep.Field?

        var body: some View {
            OiStoryWritingStep(draft: $draft, focusedField: $focusedField)
        }
    }

    private struct StoryWritingCapture: View {
        let draft: OiStoryDraft
        @FocusState private var focusedField: OiStoryWritingStep.Field?

        var body: some View {
            VStack(alignment: .leading, spacing: 50) {
                OiStoryWritingStep(draft: .constant(draft), focusedField: $focusedField)
                OiStoryAttachmentSections(photoCount: 0, latitude: draft.latitude,
                    longitude: draft.longitude, onPhotos: {}, onLocation: {})
            }
        }
    }

    /// Captures the photo settings layout for 0–4 photos (4 = a legacy draft over the limit).
    func testStoryPhotoStepCountCaptures() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        let image = try XCTUnwrap(UIImage(named: "DonationCampus")?.jpegData(compressionQuality: 0.9))
        let ids = (0..<4).map { _ in UUID() }
        let colors: [Color] = [.orange, .teal, .pink, .indigo]
        for variant in [variants[0], variants[3]] {
            for count in variant.dynamicTypeSize.isAccessibilitySize ? [3] : [0, 1, 2, 3, 4] {
                let items = ids.prefix(count).map(OiEditingPhoto.local)
                let step = OiStoryPhotoStep(items: Array(items), uploadedPhotos: [], selections: .constant([]),
                    loadPhoto: { _ in image }, edit: { _, _ in false }, remove: { _ in }, move: { _, _ in },
                    photo: { item in colors[ids.firstIndex { .local($0) == item } ?? 0] })
                let screen = ScrollView { step.padding(.horizontal, 20).padding(.top, 20).frame(maxWidth: .infinity) }
                    .background(Color(white: 38 / 255))
                    .environment(\.colorScheme, .dark)
                try await capture(screen, name: "photo-step-\(count)", variant: variant,
                                  defaults: fixture.defaults, delay: .milliseconds(600), attach: true)
            }
        }
    }

    func testPopulatedPhotoAndLocationCaptures() async throws {
        let fixture = try isolatedDefaults()
        let backend = OiTestBackend(); backend.install()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OiStoreURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let directory = FileManager.default.temporaryDirectory.appending(path: "PhotoLocation-\(UUID())")
        defer {
            withExtendedLifetime(backend) {}
            session.invalidateAndCancel(); OiStoreURLProtocol.handle = nil
            fixture.defaults.removePersistentDomain(forName: fixture.name)
            try? FileManager.default.removeItem(at: directory)
        }
        let store = OiRemoteStore(api: try OiServiceAPI(key: "sb_publishable_testing", session: session),
                                 drafts: OiDraftVault(directory: directory), vault: OiMemorySession())
        await store.start()
        let first = UUID(), second = UUID()
        try await store.saveLocalPhoto(XCTUnwrap(UIImage(named: "DonationCampus")?.jpegData(compressionQuality: 0.9)),
                                       id: first, owner: OiTestBackend.owner)
        try await store.saveLocalPhoto(XCTUnwrap(UIImage(named: "CampusSchoolMap")?.jpegData(compressionQuality: 0.9)),
                                       id: second, owner: OiTestBackend.owner)
        for variant in variants {
            for step in [OiCreationStep.photos, .location] {
                // Capture the production editor route rather than a mocked form wrapper.
                if step == .location && variant.dynamicTypeSize == .accessibility5 { continue }
                var draft = Self.draft; draft.id = UUID()
                draft.latitude = 36.01261057021347; draft.longitude = 129.3197268697784
                let local = OiLocalDraft(draft: draft, photos: [first, second], version: 1, creationStep: step.rawValue)
                try await store.saveLocalDraft(local, owner: OiTestBackend.owner)
                let editor = NavigationStack {
                    OiStoryEditor(remote: store, localID: local.id).environment(\.scenePhase, .active)
                }
                try await capture(editor, name: step == .photos ? "photo-populated" : "location-search-entry",
                                  variant: variant, defaults: fixture.defaults, delay: .seconds(3), attach: true)
            }
        }
    }

    func testExpandedCostumeSetCaptures() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        var customization = Self.customization
        var look = OiWardrobeLook(); look.costume = .baseball
        customization.wardrobe = look
        for variant in variants.prefix(2) {
            for bottom in [false, true] {
                let page = CreationCapturePage(step: 3, anchor: bottom ? .bottom : .top) {
                    OiCucumberCustomizationStep(customization: .constant(customization), canContinue: true, onContinue: {})
                        .environment(\.scenePhase, .active)
                }
                try await capture(page, name: bottom ? "costume-set-bottom" : "costume-set-top",
                                  variant: variant, defaults: fixture.defaults, delay: .seconds(3), attach: true)
            }
        }
    }

    func testCardBackgroundAndBorderColorRegions() throws {
        let size = CGSize(width: 362, height: 502)
        func render(_ style: OiDraftCustomization, name: String) throws -> Data {
            let renderer = ImageRenderer(content:
                OiDraftCardPreview(draft: Self.draft, customization: style)
                    .frame(width: size.width, height: size.height).environment(\.colorScheme, .light))
            renderer.scale = 1
            let png = try XCTUnwrap(renderer.uiImage?.pngData())
            let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
            attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
            return png
        }
        func rgb(_ data: Data, x: Int, y: Int) throws -> [Int] {
            let bitmap = try renderedBitmap(data, size: size)
            let bytes = try XCTUnwrap(bitmap.data).bindMemory(to: UInt8.self, capacity: 362 * 502 * 4)
            let offset = (y * 362 + x) * 4
            return (0..<3).map { Int(bytes[offset + $0]) }
        }
        func distance(_ a: [Int], _ b: [Int]) -> Int { zip(a, b).reduce(0) { $0 + abs($1.0 - $1.1) } }

        var style = OiDraftCustomization()
        style.showsCharacter = false
        style.firstColor = 0xD9D9D9
        style.card = OiCardDesign(borderFill: .solid, borderFirst: 0xFFFFFF)
        let reference = try render(style, name: "card-regions-gray-white")
        style.firstColor = 0x285DB0
        let background = try render(style, name: "card-regions-blue-white")
        style.card?.borderFirst = 0xCE4068
        let border = try render(style, name: "card-regions-blue-pink")

        // The photograph and paper are independent regions of the postcard.
        let inner = CGPoint(x: 180, y: 180)
        let a = try rgb(reference, x: Int(inner.x), y: Int(inner.y))
        let b = try rgb(background, x: Int(inner.x), y: Int(inner.y))
        let c = try rgb(border, x: Int(inner.x), y: Int(inner.y))
        XCTAssertGreaterThan(distance(a, b), 80)
        XCTAssertLessThan(distance(b, c), 6)
        for point in [CGPoint(x: 18, y: 180), CGPoint(x: 180, y: 18)] {
            let a = try rgb(reference, x: Int(point.x), y: Int(point.y))
            let b = try rgb(background, x: Int(point.x), y: Int(point.y))
            let c = try rgb(border, x: Int(point.x), y: Int(point.y))
            XCTAssertLessThan(distance(a, b), 6, "Image color must not tint the paper")
            XCTAssertGreaterThan(distance(b, c), 60, "Paper color must affect the border")
        }
        style.fill = .gradient; style.firstColor = 0xD3DBC4; style.secondColor = 0xF3F7E6
        style.card?.borderFill = .gradient
        style.card?.borderFirst = 0x102841; style.card?.borderSecond = 0x6BA3C9
        _ = try render(style, name: "card-regions-gradient")
        style.card?.pattern = 3; style.showsCharacter = true
        _ = try render(style, name: "card-regions-pattern-character")
    }

    func testPostcardPublicationAndDraftCompatibility() throws {
        var style = Self.customization
        style.showsCharacter = false
        style.card = OiCardDesign()
        style.card?.postcardDate = Date(timeIntervalSince1970: 1_799_779_200)
        style.card?.photoMonochrome = true
        let photo = try XCTUnwrap(UIImage(named: "DonationCampus"))
        style.card?.backgroundPhoto = photo.pngData()
        style.card?.backgroundPlacement = OiCardPlacement(x: 0.42, y: 0.48, scale: 1.3)
        let preview = OiDraftCardPreview(draft: Self.draft, customization: style, donorName: "테스트 농부")
        let publication = try preview.publication(colorScheme: .light)
        let image = try XCTUnwrap(UIImage(data: publication.png))
        XCTAssertEqual(image.cgImage?.width, 1086)
        XCTAssertEqual(image.cgImage?.height, 1506)
        XCTAssertTrue(OiPostcardSnapshot.isPostcard(image), "The scalloped edge must stay transparent in the public PNG")
        XCTAssertNotNil(OiPostcardSnapshot.color(image, x: 0.05, y: 0.10))
        let opaque = UIGraphicsImageRenderer(size: CGSize(width: 362, height: 502)).image { c in
            UIColor.white.setFill(); c.fill(CGRect(x: 0, y: 0, width: 362, height: 502))
        }
        XCTAssertFalse(OiPostcardSnapshot.isPostcard(opaque), "A legacy opaque card must not be mistaken for a postcard")
        let data = try JSONEncoder().encode(style)
        XCTAssertEqual(try JSONDecoder().decode(OiDraftCustomization.self, from: data), style)
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(try XCTUnwrap(style.card))) as? [String: Any])
        old.removeValue(forKey: "postcardDate"); old.removeValue(forKey: "photoMonochrome"); old.removeValue(forKey: "postcardBackground")
        let legacy = try JSONDecoder().decode(OiCardDesign.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertNil(legacy.postcardDate); XCTAssertNil(legacy.photoMonochrome)
        XCTAssertEqual(legacy.backgroundPlacement, style.card?.backgroundPlacement)
        let attachment = XCTAttachment(data: publication.png, uniformTypeIdentifier: "public.png")
        attachment.name = "postcard-published-front"; attachment.lifetime = .keepAlways; add(attachment)
        for back in [false, true] {
            let renderer = ImageRenderer(content: OiDraftCardPreview(draft: Self.draft, customization: style,
                donorName: "테스트 농부", showingBack: back).frame(width: 362, height: 502))
            let png = try XCTUnwrap(renderer.uiImage?.pngData())
            let shot = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
            shot.name = back ? "postcard-back" : "postcard-front"; shot.lifetime = .keepAlways; add(shot)
        }
    }

    func testDuplexPostcardExportsBothSidesAndTracksBackChanges() throws {
        var draft = Self.draft
        var style = Self.customization
        style.showsCharacter = false
        style.card = OiCardDesign()
        style.card?.postcardDate = Date(timeIntervalSince1970: 1_799_779_200)
        let first = try OiDraftCardPreview(draft: draft, customization: style, donorName: "가상 작성자").publication(colorScheme: .light)
        XCTAssertEqual(first.format, 2)
        XCTAssertEqual(first.parts.count, 4)
        for part in StoryCard.Part.allCases {
            let image = try XCTUnwrap(UIImage(data: XCTUnwrap(first.parts[part])))
            XCTAssertEqual(image.cgImage?.width, part == .front || part == .back ? 1086 : 724)
            XCTAssertEqual(image.cgImage?.height, part == .front || part == .back ? 1506 : 1004)
            XCTAssertTrue(OiPostcardSnapshot.isPostcard(image))
            let attachment = XCTAttachment(data: try XCTUnwrap(first.parts[part]), uniformTypeIdentifier: "public.png")
            attachment.name = "duplex-card-\(part.rawValue)"; attachment.lifetime = .keepAlways; add(attachment)
        }
        draft.body = "뒷면 이야기만 수정했습니다."
        let second = try OiDraftCardPreview(draft: draft, customization: style, donorName: "가상 작성자").publication(colorScheme: .light)
        XCTAssertEqual(first.png, second.png, "A back edit keeps the approved front intact")
        XCTAssertNotEqual(first.id, second.id, "The version must include the back, not just the front")
        XCTAssertNotEqual(first.parts[.back], second.parts[.back])
        let images = try OiCardExportImages(second)
        XCTAssertNotNil(images.back)
        XCTAssertNil(try OiCardExportImages(OiStoryCardPublication(png: first.png)).back)
        XCTAssertLessThan(try OiCardImageExport.fittingFontSize(String(repeating: "캠퍼스에서 함께한 추억을 기억합니다. ", count: 30)), 17)
        XCTAssertThrowsError(try OiCardImageExport.fittingFontSize(String(repeating: "긴 이야기\n", count: 4000)))
        var unfinished = OiDraftCustomization()
        unfinished.wardrobe = OiWardrobeLook()
        XCTAssertThrowsError(try OiDraftCardPreview(draft: draft, customization: unfinished).publication(colorScheme: .light),
                             "A missing custom portrait must never export an unrelated fallback character")
    }

    func testDuplexCardExportAndAppClipCaptures() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var style = Self.customization
        style.wardrobe = nil
        let portrait = try XCTUnwrap(UIImage(named: "OiCatsPortrait"))
        let publication = try OiDraftCardPreview(draft: Self.draft, customization: style,
            donorName: "가상 작성자", portrait: portrait).publication(colorScheme: .light)
        let front = directory.appendingPathComponent("front.png")
        let back = directory.appendingPathComponent("back.png")
        try publication.png.write(to: front)
        try XCTUnwrap(publication.parts[.back]).write(to: back)
        let story = Story(storyID: UUID().uuidString, donorID: UUID(), donorDisplayName: "가상 작성자",
            title: "캠퍼스의 추억", content: Self.draft.body, publishedAt: Date(),
            location: .init(locationID: "pond", displayName: "연못"), tags: [], cucumberID: "fixture", cucumberName: "가상 오이")
        let card = StoryCard(cardID: "fixture", storyID: story.storyID, imageURL: front,
            backImageURL: back, frontPreviewURL: front, backPreviewURL: back)
        try await capture(OiCardExportSheet { try OiCardExportImages(publication) }, name: "duplex-export-sheet",
            variant: variants[0], defaults: fixture.defaults, delay: .milliseconds(300), attach: true)
        try await capture(AppClipCardPreview(card: card, story: story), name: "appclip-duplex-front",
            variant: variants[0], defaults: fixture.defaults, delay: .milliseconds(300), attach: true)
    }

    func testUnifiedPostcardBackgroundAndMetadata() throws {
        let style = OiPostcardBackgroundStyle(color: 0xEECFDF, fill: .gradient)
        var customization = Self.customization
        customization.showsCharacter = false
        customization.card = OiCardDesign()
        customization.card?.postcardBackground = style
        let renderer = ImageRenderer(content: OiPostcardBackground(style: style).frame(width: 362, height: 502))
        renderer.scale = 1
        let field = try XCTUnwrap(renderer.uiImage?.pngData())
        let bitmap = try renderedBitmap(field, size: CGSize(width: 362, height: 502))
        let pixels = try XCTUnwrap(bitmap.data).bindMemory(to: UInt8.self, capacity: 362 * 502 * 4)
        func rgb(_ x: Int, _ y: Int) -> [Int] { (0..<3).map { Int(pixels[(y * 362 + x) * 4 + $0]) } }
        XCTAssertGreaterThan(rgb(180, 250)[0], rgb(340, 80)[0] + 5, "The top-right Figma haze must be darker than the center")
        // Sampled from the Figma 5400:6605 PNG, away from the perforated edge.
        for (x, y, reference) in [(180, 180, [230, 194, 214]), (180, 322, [230, 190, 210]),
                                   (18, 180, [233, 191, 212]), (180, 18, [232, 197, 215])] {
            for channel in 0..<3 {
                XCTAssertLessThanOrEqual(abs(rgb(x, y)[channel] - reference[channel]), 6)
            }
        }

        let inner = ImageRenderer(content: OiCardBackground(customization: customization, pattern: nil)
            .frame(width: 296, height: 436))
        inner.scale = 1
        let crop = try renderedBitmap(try XCTUnwrap(inner.uiImage?.pngData()), size: CGSize(width: 296, height: 436))
        let cropPixels = try XCTUnwrap(crop.data).bindMemory(to: UInt8.self, capacity: 296 * 436 * 4)
        for channel in 0..<3 {
            XCTAssertLessThanOrEqual(abs(Int(cropPixels[(100 * 296 + 80) * 4 + channel]) - rgb(113, 133)[channel]), 2,
                                    "Paper and artwork backgrounds must form one continuous field")
        }
        let preview = OiDraftCardPreview(draft: Self.draft, customization: customization)
        let first = try preview.publication(colorScheme: .light)
        let second = try preview.publication(colorScheme: .light)
        XCTAssertEqual(first.id, second.id, "Identical cards must keep a stable review snapshot ID")
        let image = try XCTUnwrap(UIImage(data: first.png))
        OiPostcardBackgroundMetadata.remember(png: first.png, image: image)
        XCTAssertEqual(OiPostcardBackgroundMetadata.style(for: image), style, "A remote image must restore the exact back background")
        XCTAssertEqual(try JSONDecoder().decode(OiDraftCustomization.self, from: JSONEncoder().encode(customization)), customization)
        let blank = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { _ in }
        OiPostcardBackgroundMetadata.remember(png: try XCTUnwrap(blank.pngData()), image: blank)
        XCTAssertNil(OiPostcardBackgroundMetadata.style(for: blank))
        let shot = XCTAttachment(data: field, uniformTypeIdentifier: "public.png")
        shot.name = "figma-rose-background"; shot.lifetime = .keepAlways; add(shot)
    }

    func testPostcardCustomCharacterBackdropPersistsAndExports() throws {
        let portrait = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { _ in }
        var value = Self.customization
        value.showsCharacter = true
        value.card = OiCardDesign()
        value.card?.postcardLayoutVersion = 2
        value.card?.postcardBackground = .init(color: 0xEECFDF, fill: .solid)
        value.card?.characterBackdropEnabled = true
        func render(_ customization: OiDraftCustomization, back: Bool = false) throws -> UIImage {
            let renderer = ImageRenderer(content: OiDraftCardPreview(draft: Self.draft,
                customization: customization, portrait: portrait, showingBack: back).frame(width: 362, height: 502))
            renderer.scale = 1
            return try XCTUnwrap(renderer.uiImage)
        }
        func interior(_ image: UIImage) -> UInt32? {
            OiPostcardSnapshot.color(image, x: 50.0 / 362, y: 180.0 / 502)
        }
        let automatic = try render(value).pngData()
        let back = try render(value, back: true).pngData()
        value.card?.characterBackdropColor = 0x246BA0
        XCTAssertEqual(interior(try render(value)), 0x246BA0)
        XCTAssertEqual(try render(value, back: true).pngData(), back)
        XCTAssertEqual(OiPostcardSnapshot.color(try render(value), x: 18.0 / 362, y: 180.0 / 502), 0xEECFDF)
        value = try JSONDecoder().decode(OiDraftCustomization.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(value.card?.characterBackdropColor, 0x246BA0)
        value.card?.postcardBackground?.color = 0xE8EECF
        XCTAssertEqual(interior(try render(value)), 0x246BA0, "Manual RGB must survive a paper color change")
        value.card?.characterBackdropEnabled = false
        XCTAssertEqual(interior(try render(value)), 0xE8EECF)
        XCTAssertEqual(value.card?.characterBackdropColor, 0x246BA0, "Hiding must retain the chosen RGB")
        value.card?.characterBackdropEnabled = true
        let publication = try OiDraftCardPreview(draft: Self.draft, customization: value, portrait: portrait).publication(colorScheme: .light)
        XCTAssertEqual(interior(try XCTUnwrap(UIImage(data: publication.png))), 0x246BA0)
        XCTAssertEqual(publication.parts.count, 4)
        value.showsCharacter = false
        XCTAssertEqual(interior(try render(value)), 0xE8EECF, "The selection must not affect photo-only cards")
        value.showsCharacter = true
        value.card?.characterBackdropColor = nil
        value.card?.postcardBackground?.color = 0xEECFDF
        XCTAssertEqual(try render(value).pngData(), automatic, "Automatic reset must restore the original pairing")
        value.card?.characterBackdropColor = 0x1000000
        XCTAssertEqual(interior(try render(value)), 0x835C6E, "An invalid restored RGB must safely use the automatic color")
        let legacy = try JSONDecoder().decode(OiCardDesign.self, from: JSONEncoder().encode(OiCardDesign()))
        XCTAssertNil(legacy.characterBackdropColor)
    }

    func testPostcardCharacterBackdropPickerUpdatesLivePreview() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        var value = Self.customization
        value.showsCharacter = true
        value.card = OiCardDesign()
        value.card?.postcardLayoutVersion = 2
        value.card?.postcardBackground = .init(color: 0xEECFDF, fill: .solid)
        value.card?.characterBackdropEnabled = true
        for variant in variants.prefix(2) {
            value.card?.characterBackdropColor = 0x246BA0
            try await capture(PostcardBackdropLiveFixture(draft: Self.draft, customization: value, changed: { _ in }),
                name: "postcard-backdrop-color-editor", variant: variant, defaults: fixture.defaults, attach: true)
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        var selected: OiDraftCustomization?
        value.card?.characterBackdropColor = nil
        let host = UIHostingController(rootView: PostcardBackdropLiveFixture(draft: Self.draft,
            customization: value, changed: { selected = $0 }))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer {
            host.dismiss(animated: false); window.isHidden = true
            window.rootViewController = nil; window.windowScene = nil; previous?.makeKey()
        }
        try await Task.sleep(for: .milliseconds(300))
        func button(in view: UIView) -> UIButton? {
            if let button = view as? UIButton, button.accessibilityIdentifier == "oi.postcard.color-ring.control" { return button }
            for child in view.subviews { if let found = button(in: child) { return found } }
            return nil
        }
        let control = try XCTUnwrap(button(in: host.view))
        XCTAssertTrue(control.isEnabled)
        control.sendActions(for: .primaryActionTriggered)
        try await Task.sleep(for: .milliseconds(650))
        func colorPicker(in controller: UIViewController) -> UIColorPickerViewController? {
            if let picker = controller as? UIColorPickerViewController { return picker }
            if let presented = controller.presentedViewController, let found = colorPicker(in: presented) { return found }
            for child in controller.children { if let found = colorPicker(in: child) { return found } }
            return nil
        }
        let picker = try XCTUnwrap(colorPicker(in: host))
        XCTAssertEqual(Color(picker.selectedColor).oiRGB, 0x835C6E)
        for rgb in [0x246BA0, 0x9B8050] as [UInt32] {
            picker.delegate?.colorPickerViewController?(picker, didSelect: UIColor(Color(oiRGB: rgb)), continuously: true)
            try await Task.sleep(for: .milliseconds(150))
            let updated = try XCTUnwrap(selected)
            XCTAssertEqual(updated.card?.characterBackdropColor, rgb)
            XCTAssertEqual(OiPostcardCharacterBackdrop.color(for: try XCTUnwrap(updated.card)), rgb)
        }
        func resetButton(in view: UIView) -> UIButton? {
            if let button = view as? UIButton, button.accessibilityIdentifier == "oi.postcard.color.reset" { return button }
            for child in view.subviews { if let found = resetButton(in: child) { return found } }
            return nil
        }
        let reset = try XCTUnwrap(resetButton(in: try XCTUnwrap(host.presentedViewController).view))
        XCTAssertTrue(reset.isEnabled)
        let frame = reset.convert(reset.bounds, to: window)
        XCTAssertGreaterThan(frame.midX, window.bounds.midX, "Reset belongs at the top right of the sheet")
        XCTAssertLessThan(frame.minY, picker.view.convert(picker.view.bounds, to: window).minY)
        reset.sendActions(for: .primaryActionTriggered)
        try await Task.sleep(for: .milliseconds(200))
        let restored = try XCTUnwrap(selected)
        XCTAssertNil(restored.card?.characterBackdropColor, "Reset returns to automatic, rather than saving a manual copy")
        XCTAssertTrue(try XCTUnwrap(restored.card).usesCharacterBackdrop, "Reset must not turn off the background")
        XCTAssertEqual(OiPostcardCharacterBackdrop.color(for: try XCTUnwrap(restored.card)), 0x835C6E)
        XCTAssertEqual(Color(picker.selectedColor).oiRGB, 0x835C6E, "The open picker must follow the restored recommendation")
        XCTAssertNotNil(picker.viewIfLoaded?.window, "Reset keeps the live preview picker open")
        if ProcessInfo.processInfo.environment["OI_HOLD_BACKDROP_PICKER_CAPTURE"] == "1" {
            FileHandle.standardOutput.write(Data("POSTCARD_BACKDROP_PICKER_READY\n".utf8))
            try await Task.sleep(for: .seconds(8))
        }
        picker.delegate?.colorPickerViewControllerDidFinish?(picker)
    }

    func testPostcardOptionalCharacterBackdrop() async throws {
        let clear = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { _ in }
        var value = Self.customization
        value.card = OiCardDesign()
        value.card?.postcardLayoutVersion = 2
        value.card?.postcardBackground = .init(color: 0xEECFDF, fill: .solid)
        value.showsCharacter = true
        func render(_ customization: OiDraftCustomization, back: Bool = false) throws -> UIImage {
            let renderer = ImageRenderer(content: OiDraftCardPreview(draft: Self.draft,
                customization: customization, portrait: clear, showingBack: back).frame(width: 362, height: 502))
            renderer.scale = 1
            return try XCTUnwrap(renderer.uiImage)
        }
        XCTAssertFalse(try XCTUnwrap(value.card).usesCharacterBackdrop)
        let original = try render(value).pngData()
        let back = try render(value, back: true).pngData()
        value.card?.characterBackdropEnabled = true
        XCTAssertEqual(OiPostcardSnapshot.color(try render(value), x: 50.0 / 362, y: 180.0 / 502), 0x835C6E)
        XCTAssertEqual(try render(value, back: true).pngData(), back, "A front-only option must preserve the story side")
        XCTAssertEqual(try JSONDecoder().decode(OiDraftCustomization.self, from: JSONEncoder().encode(value)), value)
        value.card?.characterBackdropEnabled = false
        XCTAssertEqual(try render(value).pngData(), original, "Turning off the option must restore the exact original composition")
        value.showsCharacter = false
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { context in
            UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        }
        value.card?.backgroundPhoto = photo.pngData()
        let photoOnly = try render(value).pngData()
        value.card?.characterBackdropEnabled = true
        XCTAssertEqual(try render(value).pngData(), photoOnly, "A saved option must never obscure photo-only cards")
        XCTAssertFalse(OiCardDesign().usesCharacterBackdrop, "Pre-unified drafts retain their own inner gradient")
        var legacy = OiCardDesign()
        legacy.postcardBackground = .init(color: 0xEECFDF, fill: .solid)
        XCTAssertTrue(legacy.usesCharacterBackdrop, "Unified legacy cards retain the previous automatic field")
        var legacyValue = value
        legacy.backgroundPhoto = photo.pngData()
        legacyValue.card = legacy
        legacyValue.showsCharacter = true
        let legacyImage = try render(legacyValue)
        let photoImage = photo
        XCTAssertEqual(OiPostcardSnapshot.color(legacyImage, x: 50.0 / 362, y: 180.0 / 502),
                       OiPostcardSnapshot.color(photoImage, x: 0.5, y: 0.5), "Legacy combined cards must retain their photo behind the cucumber")
        value.showsCharacter = true
        XCTAssertEqual(OiPostcardSnapshot.color(try render(value), x: 50.0 / 362, y: 180.0 / 502), 0x835C6E,
                       "The automatic field must remain visible even when an older card photo is retained")
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        value.card?.backgroundPhoto = nil
        value.card?.portraitPNG = try XCTUnwrap(UIImage(named: "OiCatsPortrait")?.pngData())
        for enabled in [false, true] {
            value.card?.characterBackdropEnabled = enabled
            let page = VStack(spacing: 0) {
                OiCreationProgressHeader(step: 4, onPrevious: {}).padding(.horizontal, 20).padding(.bottom, 8)
                OiCardCustomizationStep(draft: .constant(Self.draft), customization: .constant(value),
                    donorName: "가상 작성자", onContinue: {}).tabForTest("배경")
            }.background(.white)
            try await capture(page, name: "optional-character-backdrop-\(enabled ? "on" : "off")",
                variant: variants[0], defaults: fixture.defaults, attach: true)
        }
    }

    func testPostcardFigmaCompanionPalette() async throws {
        let references: [(paper: UInt32, backdrop: UInt32)] = [
            (0xEECFDF, 0x835C6E), (0xEEE7CF, 0x83785C),
            (0xE8EECF, 0x77835C), (0xCFE1EE, 0x5C7183)
        ]
        let transparent = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { _ in }
        for reference in references {
            var value = Self.customization
            value.showsCharacter = true
            value.card = OiCardDesign()
            value.card?.postcardLayoutVersion = 2
            value.card?.characterBackdropEnabled = true
            value.card?.postcardBackground = .init(color: reference.paper, fill: .solid)
            let publication = try OiDraftCardPreview(draft: Self.draft, customization: value,
                portrait: transparent).publication(colorScheme: .light)
            let front = try XCTUnwrap(UIImage(data: publication.png))
            XCTAssertEqual(OiPostcardSnapshot.color(front, x: 50.0 / 362, y: 180.0 / 502), reference.backdrop,
                "Exported portrait window must use the exact Figma companion color")
            XCTAssertEqual(OiPostcardSnapshot.color(front, x: 18.0 / 362, y: 180.0 / 502), reference.paper)
        }
        for paper in OiPostcardPreset.allCases.map(\.color) + [0xFF0000, 0x00FF00, 0x0000FF, 0x575757] {
            let rgb = OiPostcardCharacterBackdrop.color(for: paper)
            var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
            UIColor(Color(oiRGB: rgb)).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
            XCTAssertLessThanOrEqual(saturation, 0.31, "Automatic companion colors should share the muted Figma saturation")
            XCTAssertLessThanOrEqual(brightness, 0.56)
        }
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        let portrait = try XCTUnwrap(UIImage(named: "OiCatsPortrait"))
        let page = VStack(spacing: 12) {
            Text("자동 추천 배색").font(CampusStyle.semibold(20))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                ForEach(OiPostcardPreset.allCases) { preset in
                    let value: OiDraftCustomization = {
                        var value = Self.customization
                        value.showsCharacter = true
                        value.card = OiCardDesign()
                        value.card?.postcardLayoutVersion = 2
                        value.card?.characterBackdropEnabled = true
                        value.card?.postcardBackground = .init(color: preset.color, fill: .gradient, preset: preset.rawValue)
                        return value
                    }()
                    VStack(spacing: 4) {
                        OiDraftCardPreview(draft: Self.draft, customization: value, portrait: portrait)
                        Text(preset.title).font(CampusStyle.body(12))
                    }
                }
            }
        }.padding(12).frame(maxHeight: .infinity, alignment: .top).background(.white)
        try await capture(page, name: "figma-companion-palette", variant: variants[0],
            defaults: fixture.defaults, includesSafeArea: false, attach: true)
    }

    func testPostcardAutomaticCharacterBackdrop() throws {
        let clearPortrait = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { _ in }
        var customization = Self.customization
        customization.showsCharacter = true
        customization.card = OiCardDesign()
        customization.card?.postcardDate = Date(timeIntervalSince1970: 1_799_779_200)
        func render(_ value: OiDraftCustomization, back: Bool = false) throws -> UIImage {
            let renderer = ImageRenderer(content: OiDraftCardPreview(draft: Self.draft,
                customization: value, portrait: clearPortrait, showingBack: back).frame(width: 362, height: 502))
            renderer.scale = 1
            return try XCTUnwrap(renderer.uiImage)
        }
        func interior(_ image: UIImage) throws -> UInt32 {
            try XCTUnwrap(OiPostcardSnapshot.color(image, x: 50.0 / 362, y: 180.0 / 502))
        }
        customization.card?.postcardBackground = .init(color: 0xEECFDF, fill: .solid)
        let front = try render(customization)
        XCTAssertEqual(try interior(front), 0x835C6E, "The portrait window must match the Figma rose backdrop")
        XCTAssertEqual(OiPostcardSnapshot.color(front, x: 18.0 / 362, y: 180.0 / 502), 0xEECFDF,
                       "The automatic portrait backdrop must not recolor the paper border")
        let backBefore = try render(customization, back: true).pngData()
        customization.showsCharacter = false
        XCTAssertEqual(try interior(render(customization)), 0xEECFDF, "Photo-only cards keep the selected paper background")
        XCTAssertEqual(try render(customization, back: true).pngData(), backBefore,
                       "Showing a cucumber must not change the story side")
        customization.showsCharacter = true
        customization.card?.postcardBackground?.fill = .gradient
        XCTAssertEqual(try interior(render(customization)), 0x835C6E,
                       "The portrait window stays a distinct solid color over gradient paper")
        customization.card?.characterPlacement = .init(x: 0.8, y: 0.2, scale: 1.7)
        XCTAssertEqual(try interior(render(customization)), 0x835C6E,
                       "The background window must not move or resize with the cucumber")

        customization.card?.characterPlacement = OiCardPlacement()
        customization.card?.postcardBackground = .init(color: 0xE8EECF, fill: .solid)
        let green = try interior(render(customization))
        XCTAssertNotEqual(green, 0x835C6E, "Changing the selected paper must update the companion color")
        XCTAssertGreaterThan((green >> 8) & 255, green & 255, "Green paper must produce a green companion")
        for color in [0x000000, 0xFFFFFF, 0x1C3040, 0x86AED0] as [UInt32] {
            customization.card?.postcardBackground?.color = color
            XCTAssertNotEqual(try interior(render(customization)), color, "Custom RGB colors need a distinct image window")
        }
        let darkGray = OiPostcardCharacterBackdrop.color(for: 0x575757)
        let nearbyGray = OiPostcardCharacterBackdrop.color(for: 0x5C5C5C)
        XCTAssertLessThan(abs(Int(darkGray & 255) - Int(nearbyGray & 255)), 10,
                          "Nearby RGB choices must not cause a sudden backdrop brightness jump")
        let publication = try OiDraftCardPreview(draft: Self.draft, customization: customization,
            portrait: clearPortrait).publication(colorScheme: .light)
        let published = try XCTUnwrap(UIImage(data: publication.png))
        XCTAssertEqual(published.cgImage?.width, 1086)
        XCTAssertEqual(published.cgImage?.height, 1506)
        OiPostcardBackgroundMetadata.remember(png: publication.png, image: published)
        XCTAssertEqual(OiPostcardBackgroundMetadata.style(for: published), customization.card?.postcardBackground)

        let portrait = try XCTUnwrap(UIImage(named: "OiCatsPortrait"))
        let sheet = VStack(spacing: 20) {
            ForEach([[0xEECFDF, 0xE8EECF, 0xB6D8E8], [0xEAE4D2, 0xFFFFFF, 0x1C3040]] as [[UInt32]], id: \.self) { row in
                HStack(spacing: 20) {
                    ForEach(row, id: \.self) { color in
                        var style = customization
                        let _ = style.card?.postcardBackground = .init(color: color)
                        OiDraftCardPreview(draft: Self.draft, customization: style, portrait: portrait)
                            .frame(width: 362, height: 502)
                    }
                }
            }
        }.padding(20).background(.black)
        let renderer = ImageRenderer(content: sheet); renderer.scale = 1
        let shot = XCTAttachment(data: try XCTUnwrap(renderer.uiImage?.pngData()), uniformTypeIdentifier: "public.png")
        shot.name = "postcard-automatic-character-backgrounds"; shot.lifetime = .keepAlways; add(shot)
    }

    func testPostcardBundledTypography() throws {
        OiPostcardTypography.registerFonts()
        let handwriting = try XCTUnwrap(UIFont(name: OiPostcardTypography.handwritingName, size: 17),
                                        "The postcard must load the bundled Figma font rather than silently fall back")
        XCTAssertEqual(handwriting.fontName, "NanumEongGeongKwiCe")
        let from = try XCTUnwrap(UIFont(name: OiPostcardTypography.fromName, size: 6))
        XCTAssertEqual(from.fontName, "EduAUVICWANTPre-Regular")
        let characters = Array("함께한 순간을 오래 기억하며, 고마워요. 26.11.12".utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        XCTAssertTrue(CTFontGetGlyphsForCharacters(handwriting as CTFont, characters, &glyphs, characters.count),
                      "Korean postcard text must be supported by the actual handwriting font")
        XCTAssertEqual(handwriting.lineHeight + OiPostcardTypography.lineSpacing, 25.5, accuracy: 0.01)

        let back = OiPostcardBack(backgroundStyle: .init(color: 0xEECFDF),
            message: "함께한 순간을 오래 기억하며\n고마운 마음을 캠퍼스에 남깁니다.\n\n친구들과 나눈 웃음과 응원이\n내일의 작은 용기가 되기를!",
            author: "19학번 기계공학과 신수리")
        let renderer = ImageRenderer(content: back)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage)
        XCTAssertEqual(image.cgImage?.width, 724)
        XCTAssertEqual(image.cgImage?.height, 1004)
        let shot = XCTAttachment(data: try XCTUnwrap(image.pngData()), uniformTypeIdentifier: "public.png")
        shot.name = "postcard-figma-typography"; shot.lifetime = .keepAlways; add(shot)
    }

    func testUnifiedBackgroundEditorCapture() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        var customization = Self.customization
        customization.card = OiCardDesign()
        customization.card?.postcardBackground = OiPostcardBackgroundStyle()
        for variant in variants.prefix(2) {
            let editor = VStack(spacing: 14) {
                OiDraftCardPreview(draft: Self.draft, customization: customization)
                    .frame(width: 150, height: 208)
                ScrollView {
                    OiCardCustomizationStep(draft: .constant(Self.draft), customization: .constant(customization)).backgroundEditor
                        .padding(20)
                }
            }.background(.white)
            try await capture(editor, name: "unified-background-editor", variant: variant,
                              defaults: fixture.defaults, includesSafeArea: true, attach: true)
        }
        let sheet = HStack(spacing: 16) {
            ForEach([0xEECFDF, 0xE8EECF, 0xEECFCF] as [UInt32], id: \.self) { color in
                OiPostcardBack(backgroundStyle: .init(color: color), message: "함께한 순간을 오래 기억하며, 고마운 마음을 캠퍼스에 남깁니다.", author: "오이 농부")
            }
        }.padding(20).background(.black)
        let renderer = ImageRenderer(content: sheet)
        let shot = XCTAttachment(data: try XCTUnwrap(renderer.uiImage?.pngData()), uniformTypeIdentifier: "public.png")
        shot.name = "unified-postcard-gradients"; shot.lifetime = .keepAlways; add(shot)
    }

    func testPostcardCapturesCurrentWardrobePortrait() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let captured = expectation(description: "Current 3D cucumber portrait")
        var png: Data?
        let view = OiCardPortraitCapture(look: OiWardrobeLook(), cacheKey: "postcard-runtime-test", onCapture: { data, _ in
            png = data; captured.fulfill()
        }).frame(width: 220, height: 308).opacity(0.001)
        window.rootViewController = UIHostingController(rootView: view.environment(\.scenePhase, .active))
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        await fulfillment(of: [captured], timeout: 18)
        let image = try XCTUnwrap(png.flatMap(UIImage.init(data:)))
        XCTAssertGreaterThan(image.size.width, 10)
        XCTAssertGreaterThan(image.size.height, 10)
        let cg = try XCTUnwrap(image.cgImage)
        let bitmap = try renderedBitmap(try XCTUnwrap(png), size: CGSize(width: cg.width, height: cg.height))
        let pixels = try XCTUnwrap(bitmap.data).bindMemory(to: UInt8.self, capacity: cg.width * cg.height * 4)
        let green = (0..<(cg.width * cg.height)).filter {
            pixels[$0 * 4 + 3] > 200 && Int(pixels[$0 * 4 + 1]) > Int(pixels[$0 * 4]) + 15
                && Int(pixels[$0 * 4 + 1]) > Int(pixels[$0 * 4 + 2]) + 15
        }.count
        XCTAssertGreaterThan(green, 100, "The hidden surface must still render the green 3D cucumber")
        let attachment = XCTAttachment(data: try XCTUnwrap(png), uniformTypeIdentifier: "public.png")
        attachment.name = "postcard-current-wardrobe-capture"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testPostcardPhotoTintFollowsPaperAndPreservesOriginal() throws {
        let size = CGSize(width: 100, height: 150)
        let original = UIGraphicsImageRenderer(size: size).image { c in
            UIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1).setFill()
            c.fill(CGRect(origin: .zero, size: size))
        }
        let bytes = try XCTUnwrap(original.pngData())
        var style = OiDraftCustomization()
        style.card = OiCardDesign(borderFill: .solid)
        style.card?.backgroundPhoto = bytes
        func pixel(_ style: OiDraftCustomization) throws -> [Int] {
            let renderer = ImageRenderer(content: OiCardBackground(customization: style, pattern: nil)
                .frame(width: size.width, height: size.height))
            let data = try XCTUnwrap(renderer.uiImage?.pngData())
            let bitmap = try renderedBitmap(data, size: size)
            let rgba = try XCTUnwrap(bitmap.data).bindMemory(to: UInt8.self, capacity: 100 * 150 * 4)
            return (0..<3).map { Int(rgba[(75 * 100 + 50) * 4 + $0]) }
        }
        let natural = try pixel(style)
        style.card?.photoMonochrome = true
        style.card?.borderFirst = 0xD99090
        let rose = try pixel(style)
        style.card?.borderFirst = 0x9090D9
        let blue = try pixel(style)
        XCTAssertGreaterThan(rose[0], rose[2] + 20)
        XCTAssertGreaterThan(blue[2], blue[0] + 20)
        style.card?.photoMonochrome = false
        XCTAssertEqual(try pixel(style), natural)
        XCTAssertEqual(style.card?.backgroundPhoto, bytes, "Tinting must not rewrite the original photo")
    }

    func testPostcardHorizontalFlipAndDate() {
        XCTAssertTrue(OiPostcardFlip.accepts(CGSize(width: -100, height: 5)))
        XCTAssertTrue(OiPostcardFlip.accepts(CGSize(width: 100, height: 5)))
        XCTAssertFalse(OiPostcardFlip.accepts(CGSize(width: 10, height: 100)))
        XCTAssertFalse(OiPostcardFlip.accepts(CGSize(width: 25, height: 2)))
        XCTAssertEqual(OiPostcardDate.string(from: "2026.11.12"), "26.11.12")
        XCTAssertEqual(OiPostcardDate.string(from: "2026년 11월 12일"), "26.11.12")
    }

    func testCardPatternsRemainVisibleAcrossBackgrounds() throws {
        let size = CGSize(width: 166, height: 236)
        func render<V: View>(_ view: V, size: CGSize) throws -> Data {
            let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
            renderer.scale = 1
            return try XCTUnwrap(renderer.uiImage?.pngData())
        }
        func luminance(_ png: Data) throws -> [Double] {
            let context = try renderedBitmap(png, size: size)
            let pixels = try XCTUnwrap(context.data).bindMemory(to: UInt8.self, capacity: 166 * 236 * 4)
            return (0..<(166 * 236)).map { i in
                let offset = i * 4
                return (0.2126 * Double(pixels[offset]) + 0.7152 * Double(pixels[offset + 1])
                    + 0.0722 * Double(pixels[offset + 2])) / 255
            }
        }
        let portraitURL = try XCTUnwrap(Bundle.main.url(forResource: OiWardrobeLook.Costume.farmer.thumbnailName,
                                                        withExtension: "png"))
        let portrait = try XCTUnwrap(UIImage(contentsOfFile: portraitURL.path))
        for (name, color): (String, UInt32) in [("white", 0xFFFFFF), ("sage", 0xD3DBC4), ("charcoal", 0x101010)] {
            var customization = OiDraftCustomization()
            customization.firstColor = color
            let baseline = try luminance(render(OiCardBackground(customization: customization, pattern: nil), size: size))
            for number in 1...8 {
                let tones = try luminance(render(OiCardBackground(customization: customization, pattern: number), size: size))
                let mean = tones.reduce(0, +) / Double(tones.count)
                let deviation = sqrt(tones.reduce(0) { $0 + pow($1 - mean, 2) } / Double(tones.count))
                let change = zip(tones, baseline).reduce(0) { $0 + abs($1.0 - $1.1) } / Double(tones.count)
                XCTAssertGreaterThan(deviation, 0.025, "Pattern \(number) lost its detail on \(name)")
                XCTAssertGreaterThan(change, 0.05, "Pattern \(number) is barely visible on \(name)")
            }
            let sheet = VStack(spacing: 12) {
                ForEach(0..<3) { row in
                    HStack(spacing: 12) {
                        ForEach(0..<3) { column in
                            let number = row * 3 + column
                            var example = customization
                            let _ = { example.card = OiCardDesign(pattern: number == 0 ? nil : number) }()
                            VStack(spacing: 4) {
                                Text(number == 0 ? "패턴 없음" : "패턴 \(number)").font(.caption)
                                OiDraftCardPreview(draft: Self.draft, customization: example, portrait: portrait)
                                    .frame(width: 166, height: 230)
                            }
                        }
                    }
                }
            }.padding(12).background(.white)
            let png = try render(sheet, size: CGSize(width: 546, height: 798))
            let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
            attachment.name = "card-patterns-\(name)"; attachment.lifetime = .keepAlways; add(attachment)
        }

        // A photo must remain recognizable, but each texture still has to change
        // its background. Neither a pattern nor removing one mutates saved bytes.
        var photoDesign = OiDraftCustomization()
        let photo = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.systemBlue.setFill(); context.fill(CGRect(origin: .zero, size: size))
            UIColor.systemOrange.setFill(); context.fill(CGRect(x: 0, y: 0, width: 83, height: 236))
        }
        photoDesign.card = OiCardDesign(backgroundPhoto: try XCTUnwrap(photo.pngData()))
        let original = photoDesign
        let baseline = try render(OiCardBackground(customization: photoDesign, pattern: nil), size: size)
        for number in 1...8 {
            let patterned = try render(OiCardBackground(customization: photoDesign, pattern: number), size: size)
            XCTAssertNotEqual(patterned, baseline)
        }
        XCTAssertEqual(try render(OiCardBackground(customization: photoDesign, pattern: nil), size: size), baseline)
        XCTAssertEqual(photoDesign, original)
    }

    func testCustomizationCaptures() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        for variant in variants {
            let cucumber = CreationCapturePage(step: 3) {
                OiCucumberCustomizationStep(customization: .constant(Self.customization), canContinue: true, onContinue: {})
                    .environment(\.scenePhase, .active)
            }
            try await capture(cucumber, name: "cucumber-customization", variant: variant, defaults: fixture.defaults, delay: .seconds(2))
            let card = CreationCapturePage(step: 4) {
                OiCardCustomizationStep(draft: .constant(Self.draft), customization: .constant(Self.customization),
                    canContinue: true, onContinue: {})
            }
            try await capture(card, name: "card-customization", variant: variant, defaults: fixture.defaults, attach: true)
        }
    }

    func testCropToolbarContrastCapture() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        let image = try XCTUnwrap(UIImage(named: "DonationCampus"))
        // Reproduce the light parent and inherited black tint of the creation flow.
        let crop = OiPhotoCropEditor(image: image, apply: { _ in })
            .tint(.black).environment(\.colorScheme, .light)
        try await capture(crop, name: "crop-toolbar-contrast", variant: variants[0],
                          defaults: fixture.defaults, attach: true)
    }

    func testStoryListSeedUICaptures() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        XCTAssertNotNil(UIImage(named: "StorySeedIcon"))
        for variant in variants {
            let reference = NavigationStack {
                OiStoryListView(state: .preview, seedCount: 3,
                    notices: OiStoryListView.listNotices,
                    guidance: OiStoryListView.listGuidance,
                    onAddSeed: {}, onCreateStory: {}, onUseSeed: {})
            }
            try await capture(reference, name: "story-list-seed-reference", variant: variant,
                              defaults: fixture.defaults, attach: true)
            // The actual screen displays zero until a seed service is connected.
            let store = OiRemoteStore(vault: OiMemorySession())
            let live = NavigationStack { OiStoryListScreen(remote: store) }
            try await capture(live, name: "story-list-seed-unconnected", variant: variant,
                              defaults: fixture.defaults, attach: true)
        }
    }

    func testMapCucumberCustomizationCaptures() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        XCTAssertNotNil(UIImage(named: "StorySeedIcon"))
        XCTAssertNotNil(UIImage(named: "SeedCucumberBody"))
        for layer in OiSeedCucumberLayer.allCases {
            let image = try XCTUnwrap(UIImage(named: layer.asset)?.cgImage)
            XCTAssertEqual(image.width, Int(layer.sourceFrame.width))
            XCTAssertEqual(image.height, Int(layer.sourceFrame.height))
        }
        var edited = OiSeedCucumberAppearance()
        edited[.eyes] = .init(x: -45, y: -35, size: 1.4)
        edited[.mouth] = .init(x: 25, y: 35, size: 1.15)
        edited.eyeSpacing = 1.25
        edited.stemLength = 1.65
        edited.stemAngle = -72
        var resized = edited
        resized.bodyWidth = 1.30
        resized.bodyHeight = 0.85
        for variant in variants {
            let store = CampusStoryStore(defaults: fixture.defaults)
            let home = HomeView(container: .pilot, store: store, myDemo: MYLibraryStore(),
                                isCameraCoverActive: false, onOpenProfile: {}, onOpenStory: { _ in })
            if variant.name == "402x874" {
                try await capture(NavigationStack { home }, name: "campus-cucumber-entry", variant: variant,
                                  defaults: fixture.defaults, delay: .seconds(2), attach: true)
            }
            let destination = NavigationStack(path: .constant([MYDestination.cucumberCustomization])) { home }
            try await capture(destination, name: "seed-cucumber-customization", variant: variant,
                              defaults: fixture.defaults, attach: true)
            if variant.name == "402x874" {
                let spacedDestination = NavigationStack {
                    OiSeedCucumberCustomizationView(appearance: edited, selection: .eyes)
                }
                try await capture(spacedDestination, name: "seed-cucumber-customization-eye-spacing",
                                  variant: variant, defaults: fixture.defaults, attach: true)
            }
            let editedDestination = NavigationStack {
                OiSeedCucumberCustomizationView(appearance: edited, selection: .stem)
            }
            try await capture(editedDestination, name: "seed-cucumber-customization-edited", variant: variant,
                              defaults: fixture.defaults, attach: true)
            let bodyDestination = NavigationStack {
                OiSeedCucumberCustomizationView(appearance: resized, selection: .body)
            }
            try await capture(bodyDestination, name: "seed-cucumber-customization-body", variant: variant,
                              defaults: fixture.defaults, attach: true)
        }
    }

    func testSeedCucumber3DModelKeepsEditedPartsOnSkin() async throws {
        typealias Appearance = OiSeedCucumberAppearance
        let original = Appearance()
        let edited = editedSeedCucumber3DAppearance()
        var narrow = original
        narrow.bodyWidth = Appearance.widthRange.lowerBound
        narrow.bodyHeight = Appearance.heightRange.upperBound
        narrow.eyeSpacing = Appearance.eyeSpacingRange.lowerBound
        narrow[.eyes] = .init(x: 65, y: -65, size: 0.75)
        narrow[.mouth] = .init(x: -60, y: 55, size: 0.8)
        narrow.stemLength = Appearance.lengthRange.lowerBound
        narrow.stemAngle = Appearance.angleRange.upperBound

        let appearances = [original, edited, narrow]
        var roots: [Entity] = []
        for appearance in appearances {
            roots.append(try await OiSeedCucumberModel.make(appearance: appearance))
        }
        for (index, root) in roots.enumerated() {
            let body = try XCTUnwrap(root.findEntity(named: "Body"))
            let bounds = body.visualBounds(relativeTo: root)
            XCTAssertEqual(root.visualBounds(relativeTo: root).min.y, 0, accuracy: 0.005, "Pose \(index)")
            XCTAssertGreaterThan(bounds.extents.z, bounds.extents.x * 0.25, "Pose \(index) must have body depth")
            for name in ["LeftArm", "RightArm", "LeftLeg", "RightLeg"] {
                let limb = try XCTUnwrap(root.findEntity(named: name))
                XCTAssertGreaterThan(limb.visualBounds(relativeTo: root).extents.z, 0.01, "\(name) in pose \(index)")
            }

            let bodyTriangles = try cucumberTriangles(named: "Body", in: root)
            var bodyRows: [Int: [CucumberTriangle]] = [:]
            for triangle in bodyTriangles {
                let firstRow = cucumberDepthRow(min(triangle.0.y, triangle.1.y, triangle.2.y))
                let lastRow = cucumberDepthRow(max(triangle.0.y, triangle.1.y, triangle.2.y))
                for row in firstRow...lastRow {
                    bodyRows[row, default: []].append(triangle)
                }
            }
            for name in ["LeftEye", "RightEye", "Mouth"] {
                let face = try XCTUnwrap(root.findEntity(named: name))
                XCTAssertGreaterThan(face.visualBounds(relativeTo: root).min.z, 0, "\(name) must face +Z")
                let triangles = try cucumberTriangles(named: name, in: root)
                for offset in stride(from: 0, to: triangles.count, by: max(1, triangles.count / 24)) {
                    let triangle = triangles[offset]
                    let center = (triangle.0 + triangle.1 + triangle.2) / 3
                    let row = bodyRows[cucumberDepthRow(center.y), default: []]
                    let skin = try XCTUnwrap(cucumberDepth(at: center, in: row), "\(name) left the body in pose \(index)")
                    XCTAssertLessThan(abs(center.z - skin.upperBound), 0.025, "\(name) detached from the front skin in pose \(index)")
                }
            }

            let stem = try XCTUnwrap(root.findEntity(named: "Stem"))
            let stemTriangles = try cucumberTriangles(named: "Stem", in: root)
            XCTAssertGreaterThan(stem.visualBounds(relativeTo: root).max.y, bounds.max.y, "Pose \(index) must show the stem")
            XCTAssertTrue(stemTriangles.contains { triangle in
                let center = (triangle.0 + triangle.1 + triangle.2) / 3
                guard let skin = cucumberDepth(at: center, in: bodyRows[cucumberDepthRow(center.y), default: []]) else { return false }
                return center.z > skin.lowerBound && center.z < skin.upperBound
            }, "The stem must enter the body in pose \(index)")
        }

        func partBounds(_ name: String, pose: Int) throws -> BoundingBox {
            let root = roots[pose]
            return try XCTUnwrap(root.findEntity(named: name)).visualBounds(relativeTo: root)
        }
        let originalBody = try partBounds("Body", pose: 0)
        let wideBody = try partBounds("Body", pose: 1)
        let tallBody = try partBounds("Body", pose: 2)
        XCTAssertGreaterThan(wideBody.extents.x, originalBody.extents.x)
        XCTAssertLessThan(wideBody.extents.y, originalBody.extents.y)
        XCTAssertLessThan(tallBody.extents.x, originalBody.extents.x)
        XCTAssertGreaterThan(tallBody.extents.y, originalBody.extents.y)
        let originalLeft = try partBounds("LeftEye", pose: 0)
        let originalRight = try partBounds("RightEye", pose: 0)
        let editedLeft = try partBounds("LeftEye", pose: 1)
        let editedRight = try partBounds("RightEye", pose: 1)
        XCTAssertLessThan(editedLeft.center.x + editedRight.center.x, originalLeft.center.x + originalRight.center.x)
        XCTAssertGreaterThan(editedRight.center.x - editedLeft.center.x, originalRight.center.x - originalLeft.center.x)
        XCTAssertGreaterThan(editedLeft.extents.x, originalLeft.extents.x)
        XCTAssertGreaterThan(try partBounds("Mouth", pose: 1).center.x, try partBounds("Mouth", pose: 0).center.x)
        XCTAssertLessThan(try partBounds("Mouth", pose: 1).center.y, try partBounds("Mouth", pose: 0).center.y)
        XCTAssertLessThan(try partBounds("Stem", pose: 1).min.x, try partBounds("Stem", pose: 0).min.x)
    }

    func testSeedCucumber3DPreviewCapturesRealModel() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        let variant = try XCTUnwrap(variants.first { $0.name == "402x874" })
        let original = OiSeedCucumberAppearance()
        let poses: [(name: String, appearance: OiSeedCucumberAppearance, yaw: Float)] = [
            ("default", original, 0),
            ("rear", original, .pi),
            ("edited", editedSeedCucumber3DAppearance(), 0)
        ]
        for pose in poses {
            let screen = OiSeedCucumber3DPreview(appearance: pose.appearance)
                .environment(\.scenePhase, .active)
            try await capture(screen, name: "seed-cucumber-3d-\(pose.name)", variant: variant, defaults: fixture.defaults,
                              delay: .seconds(1), attach: true, cucumberCameraYaw: pose.yaw)
        }
    }

    private func editedSeedCucumber3DAppearance() -> OiSeedCucumberAppearance {
        var appearance = OiSeedCucumberAppearance()
        appearance.bodyWidth = OiSeedCucumberAppearance.widthRange.upperBound
        appearance.bodyHeight = OiSeedCucumberAppearance.heightRange.lowerBound
        appearance[.eyes] = .init(x: -45, y: -35, size: 1.4)
        appearance[.mouth] = .init(x: 25, y: 35, size: 1.15)
        appearance.eyeSpacing = OiSeedCucumberAppearance.eyeSpacingRange.upperBound
        appearance.stemLength = OiSeedCucumberAppearance.lengthRange.upperBound
        appearance.stemAngle = -72
        return appearance
    }

    private typealias CucumberTriangle = (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)

    private func cucumberTriangles(named name: String, in root: Entity) throws -> [CucumberTriangle] {
        let entity = try XCTUnwrap(root.findEntity(named: name))
        let mesh = try XCTUnwrap(entity.components[ModelComponent.self]?.mesh)
        let contents = mesh.contents
        let triangles = try contents.instances.flatMap { instance in
            let model = try XCTUnwrap(contents.models.first { $0.id == instance.model })
            return try model.parts.flatMap { part -> [CucumberTriangle] in
                let points = part.positions.elements.map { vertex in
                    let point = instance.transform * SIMD4<Float>(vertex, 1)
                    return entity.convert(position: SIMD3<Float>(point.x, point.y, point.z), to: root)
                }
                let indices = try XCTUnwrap(part.triangleIndices?.elements).map(Int.init)
                XCTAssertEqual(indices.count % 3, 0)
                guard indices.count.isMultiple(of: 3), indices.allSatisfy(points.indices.contains) else {
                    XCTFail("Invalid indices in \(name)")
                    return []
                }
                return stride(from: 0, to: indices.count, by: 3).map { offset in
                    (points[indices[offset]], points[indices[offset + 1]], points[indices[offset + 2]])
                }
            }
        }
        XCTAssertFalse(triangles.isEmpty, "\(name) must contain renderable triangles")
        return triangles
    }

    private func cucumberDepthRow(_ y: Float) -> Int {
        Int(floor(y * 100))
    }

    private func cucumberDepth(at point: SIMD3<Float>, in triangles: [CucumberTriangle]) -> ClosedRange<Float>? {
        var front = -Float.infinity
        var back = Float.infinity
        for (a, b, c) in triangles {
            let side = b - a
            let other = c - a
            let offset = point - a
            let determinant = side.x * other.y - side.y * other.x
            guard abs(determinant) > 0.0000000001 else { continue }
            let u = (offset.x * other.y - offset.y * other.x) / determinant
            let v = (side.x * offset.y - side.y * offset.x) / determinant
            guard u >= -0.0001, v >= -0.0001, u + v <= 1.0001 else { continue }
            let depth = a.z + u * side.z + v * other.z
            front = max(front, depth)
            back = min(back, depth)
        }
        return back <= front ? back...front : nil
    }

    func testSeedCucumberEditingGeometry() {
        typealias Appearance = OiSeedCucumberAppearance
        for canvasSize in [CGSize(width: 375, height: 315), CGSize(width: 440, height: 440)] {
            let view = UIView(frame: CGRect(origin: .zero, size: canvasSize))
            let viewport = OiSeedCucumberViewport(size: canvasSize)
            var appearance = Appearance()
            var selection: OiSeedCucumberPart = .stem
            let surface = OiSeedCucumberTouchSurface(
                appearance: Binding(get: { appearance }, set: { appearance = $0 }),
                selection: Binding(get: { selection }, set: { selection = $0 })
            )
            let coordinator = surface.makeCoordinator()
            XCTAssertNil(viewport.hitPart(at: .zero, appearance: appearance, selection: selection))

            for part in OiSeedCucumberPart.faceParts {
                appearance = Appearance()
                appearance.bodyWidth = 1.25
                appearance.bodyHeight = 0.85
                let initial = appearance
                let layers = OiSeedCucumberLayer.allCases.filter { $0.part == part }
                let original = layers.map(appearance.faceFrame)
                for frame in original {
                    let center = viewport.location(of: CGPoint(x: frame.midX, y: frame.midY))
                    XCTAssertEqual(viewport.hitPart(at: center, appearance: appearance, selection: selection), part)
                }
                guard let frame = original.last else {
                    XCTFail("Editable parts must contain at least one layer")
                    continue
                }
                let center = viewport.location(of: CGPoint(x: frame.midX, y: frame.midY))

                let drag = SeedCucumberTestPan()
                view.addGestureRecognizer(drag)
                drag.point = CGPoint(x: center.x + 6, y: center.y - 4)
                drag.delta = CGPoint(x: 6, y: -4)
                drag.state = .began
                coordinator.pan(drag)
                XCTAssertEqual(selection, part)
                let expectedY = Appearance.clamp(-40, to: initial.faceVerticalRange(for: part))
                drag.delta = CGPoint(x: 30 * viewport.scale * appearance.bodyWidth,
                                     y: -40 * viewport.scale * appearance.bodyHeight)
                drag.state = .changed
                coordinator.pan(drag)
                XCTAssertEqual(appearance[part].x, 30, accuracy: 0.001)
                XCTAssertEqual(appearance[part].y, expectedY, accuracy: 0.001)
                for (layer, frame) in zip(layers, original) {
                    let moved = appearance.faceFrame(layer)
                    XCTAssertEqual(moved.midX - frame.midX, 30 * appearance.bodyWidth, accuracy: 0.001)
                    XCTAssertEqual(moved.midY - frame.midY, expectedY * appearance.bodyHeight, accuracy: 0.001)
                }
                drag.delta = CGPoint(x: 300 * viewport.scale, y: -300 * viewport.scale)
                drag.state = .ended
                coordinator.pan(drag)
                XCTAssertEqual(appearance[part].x, Appearance.horizontalRange.upperBound)
                XCTAssertEqual(appearance[part].y, initial.faceVerticalRange(for: part).lowerBound, accuracy: 0.001)

                let moved = layers.map(appearance.faceFrame)
                let pinch = UIPinchGestureRecognizer()
                view.addGestureRecognizer(pinch)
                pinch.state = .began
                pinch.scale = 1
                coordinator.pinch(pinch)
                pinch.state = .changed
                pinch.scale = 1.5
                coordinator.pinch(pinch)
                for (layer, frame) in zip(layers, moved) {
                    let enlarged = appearance.faceFrame(layer)
                    XCTAssertEqual(enlarged.width, frame.width * 1.5, accuracy: 0.001)
                    XCTAssertEqual(enlarged.height, frame.height * 1.5, accuracy: 0.001)
                    XCTAssertEqual(enlarged.midX, frame.midX, accuracy: 0.001)
                    XCTAssertEqual(enlarged.midY, frame.midY, accuracy: 0.001)
                }
                pinch.scale = 9
                coordinator.pinch(pinch)
                XCTAssertEqual(appearance[part].size, Appearance.sizeRange.upperBound)
                pinch.state = .ended
                pinch.scale = 0.1
                coordinator.pinch(pinch)
                XCTAssertEqual(appearance[part].size, Appearance.sizeRange.lowerBound)
                for layer in OiSeedCucumberLayer.allCases where layer.part != part && layer.part != .stem {
                    XCTAssertEqual(appearance.faceFrame(layer), initial.faceFrame(layer))
                }
                view.removeGestureRecognizer(drag)
                view.removeGestureRecognizer(pinch)
            }

            appearance = Appearance()
            appearance.bodyWidth = 1.30
            appearance.bodyHeight = 0.85
            var desired = appearance
            desired.stemLength = 1.65
            desired.stemAngle = -72
            let tip = viewport.location(of: appearance.stemTip)
            let destination = viewport.location(of: desired.stemTip)
            let drag = SeedCucumberTestPan()
            view.addGestureRecognizer(drag)
            drag.point = tip
            drag.state = .began
            coordinator.pan(drag)
            XCTAssertEqual(selection, .stem)
            drag.delta = CGPoint(x: destination.x - tip.x, y: destination.y - tip.y)
            drag.state = .changed
            coordinator.pan(drag)
            XCTAssertEqual(appearance.stemLength, desired.stemLength, accuracy: 0.001)
            XCTAssertEqual(appearance.stemAngle, desired.stemAngle, accuracy: 0.001)
            let joinedBase = appearance.stemPoint(for: Appearance.stemBase)
            XCTAssertEqual(joinedBase.x, appearance.stemAttachment.x, accuracy: 0.001)
            XCTAssertEqual(joinedBase.y, appearance.stemAttachment.y, accuracy: 0.001)
            let nearRoot = CGPoint(x: Appearance.stemBase.x + 12, y: Appearance.stemBase.y - 8)
            let rootPoint = appearance.stemPoint(for: nearRoot)
            XCTAssertEqual(rootPoint.x - joinedBase.x, 12, accuracy: 0.001)
            XCTAssertEqual(rootPoint.y - joinedBase.y, -8, accuracy: 0.001)
            let mappedTip = appearance.stemPoint(for: Appearance.stemDefaultTip)
            XCTAssertEqual(mappedTip.x, appearance.stemTip.x, accuracy: 0.001)
            XCTAssertEqual(mappedTip.y, appearance.stemTip.y, accuracy: 0.001)
            let base = viewport.location(of: appearance.stemAttachment)
            for x in [-1.0, 1.0] {
                drag.delta = CGPoint(x: base.x + x - tip.x, y: base.y + 10 - tip.y)
                coordinator.pan(drag)
                XCTAssertEqual(appearance.stemAngle, desired.stemAngle, accuracy: 0.001)
            }
            drag.delta = CGPoint(x: base.x + 1000 * viewport.scale - tip.x, y: base.y - tip.y)
            drag.state = .ended
            coordinator.pan(drag)
            XCTAssertEqual(appearance.stemLength, Appearance.lengthRange.upperBound)
            XCTAssertEqual(appearance.stemAngle, Appearance.angleRange.upperBound)
        }
    }

    func testSeedCucumberEyeSpacingKeepsPairCenterAndSize() {
        typealias Appearance = OiSeedCucumberAppearance
        var appearance = Appearance()
        appearance.bodyWidth = 1.3
        appearance.bodyHeight = 0.85
        appearance[.eyes] = .init(x: 20, y: -30, size: 1.6)
        let left = appearance.faceFrame(.leftEye)
        let right = appearance.faceFrame(.rightEye)
        let mouth = appearance.faceFrame(.mouth)
        let viewport = OiSeedCucumberViewport(size: CGSize(width: 375, height: 315))

        for spacing in [Appearance.eyeSpacingRange.lowerBound, Appearance.eyeSpacingRange.upperBound] {
            appearance.eyeSpacing = spacing
            let spacedLeft = appearance.faceFrame(.leftEye)
            let spacedRight = appearance.faceFrame(.rightEye)
            XCTAssertEqual(spacedRight.midX - spacedLeft.midX, (right.midX - left.midX) * spacing, accuracy: 0.001)
            XCTAssertEqual(spacedLeft.midX + spacedRight.midX, left.midX + right.midX, accuracy: 0.001)
            XCTAssertEqual(spacedLeft.midY, left.midY, accuracy: 0.001)
            XCTAssertEqual(spacedRight.midY, right.midY, accuracy: 0.001)
            XCTAssertEqual(spacedLeft.size, left.size)
            XCTAssertEqual(spacedRight.size, right.size)
            XCTAssertEqual(appearance.faceFrame(.mouth), mouth)
            for eye in [spacedLeft, spacedRight] {
                let center = viewport.location(of: CGPoint(x: eye.midX, y: eye.midY))
                XCTAssertEqual(viewport.hitPart(at: center, appearance: appearance, selection: .mouth), .eyes)
            }
        }
    }

    func testSeedCucumberFaceCannotCrossDuringSliderOrDragUpdates() {
        typealias Appearance = OiSeedCucumberAppearance
        func gap(_ appearance: Appearance) -> CGFloat {
            appearance.faceFrame(.mouth).midY
                - max(appearance.faceFrame(.leftEye).midY, appearance.faceFrame(.rightEye).midY)
        }

        for height in [Appearance.heightRange.lowerBound, Appearance.heightRange.upperBound] {
            let size = CGSize(width: 375, height: 315)
            let view = UIView(frame: CGRect(origin: .zero, size: size))
            let viewport = OiSeedCucumberViewport(size: size)
            var appearance = Appearance()
            var selection: OiSeedCucumberPart = .stem
            let surface = OiSeedCucumberTouchSurface(
                appearance: Binding(get: { appearance }, set: { appearance = $0 }),
                selection: Binding(get: { selection }, set: { selection = $0 })
            )
            let coordinator = surface.makeCoordinator()
            for (part, layer, direction) in [(OiSeedCucumberPart.eyes, OiSeedCucumberLayer.rightEye, CGFloat(1)),
                                              (.mouth, .mouth, -1)] {
                var initial = Appearance()
                initial.bodyHeight = height
                initial.eyeSpacing = Appearance.eyeSpacingRange.upperBound
                initial[.eyes].size = Appearance.sizeRange.upperBound
                initial[.mouth].size = Appearance.sizeRange.upperBound
                var slider = initial
                let limit = direction * 1000
                slider[part].y = limit
                XCTAssertEqual(gap(slider), Appearance.minimumEyeMouthGap, accuracy: 0.001)
                XCTAssertNotEqual(slider[part].y, limit)

                appearance = initial
                let frame = appearance.faceFrame(layer)
                let drag = SeedCucumberTestPan()
                view.addGestureRecognizer(drag)
                drag.point = viewport.location(of: CGPoint(x: frame.midX, y: frame.midY))
                drag.state = .began
                coordinator.pan(drag)
                XCTAssertEqual(selection, part)
                drag.delta = CGPoint(x: 0, y: direction * 500)
                drag.state = .changed
                coordinator.pan(drag)
                XCTAssertEqual(appearance[part].y, slider[part].y, accuracy: 0.001)
                XCTAssertEqual(gap(appearance), Appearance.minimumEyeMouthGap, accuracy: 0.001)
                drag.state = .ended
                coordinator.pan(drag)
                XCTAssertEqual(gap(appearance), Appearance.minimumEyeMouthGap, accuracy: 0.001)
                view.removeGestureRecognizer(drag)
            }
        }

        var compressed = Appearance()
        compressed.bodyHeight = Appearance.heightRange.upperBound
        compressed[.eyes].y = compressed.faceVerticalRange(for: .eyes).upperBound
        XCTAssertEqual(gap(compressed), Appearance.minimumEyeMouthGap, accuracy: 0.001)
        let previousEyeY = compressed[.eyes].y
        let mouthY = compressed[.mouth].y
        compressed.bodyHeight = Appearance.heightRange.lowerBound
        XCTAssertEqual(gap(compressed), Appearance.minimumEyeMouthGap, accuracy: 0.001)
        XCTAssertLessThan(compressed[.eyes].y, previousEyeY)
        XCTAssertEqual(compressed[.mouth].y, mouthY)
    }

    func testSeedCucumberBodyScaleKeepsFootAndFacialGeometry() {
        typealias Appearance = OiSeedCucumberAppearance
        let original = Appearance()
        let left = original.faceFrame(.leftEye)
        let right = original.faceFrame(.rightEye)
        let initialSpacing = CGSize(width: right.midX - left.midX, height: right.midY - left.midY)

        for (width, height) in [(0.90, 1.0), (1.30, 1.0), (1.0, 0.85), (1.0, 1.20)] as [(CGFloat, CGFloat)] {
            var resized = original
            resized.bodyWidth = width
            resized.bodyHeight = height
            XCTAssertEqual(resized.bodyFrame.width, original.bodyFrame.width * width, accuracy: 0.001)
            XCTAssertEqual(resized.bodyFrame.height, original.bodyFrame.height * height, accuracy: 0.001)
            let foot = Appearance.bodyPivot.applying(resized.bodyTransform)
            XCTAssertEqual(foot.x, Appearance.bodyPivot.x, accuracy: 0.001)
            XCTAssertEqual(foot.y, Appearance.bodyPivot.y, accuracy: 0.001)

            let left = resized.faceFrame(.leftEye)
            let right = resized.faceFrame(.rightEye)
            XCTAssertEqual(right.midX - left.midX, initialSpacing.width, accuracy: 0.001)
            XCTAssertEqual(right.midY - left.midY, initialSpacing.height, accuracy: 0.001)
            let initialCenter = CGPoint(x: original.faceFrame(.leftEye).midX + initialSpacing.width / 2,
                                        y: original.faceFrame(.leftEye).midY + initialSpacing.height / 2)
            let center = initialCenter.applying(resized.bodyTransform)
            XCTAssertEqual((left.midX + right.midX) / 2, center.x, accuracy: 0.001)
            XCTAssertEqual((left.midY + right.midY) / 2, center.y, accuracy: 0.001)
            XCTAssertEqual(resized.faceFrame(.mouth).size, original.faceFrame(.mouth).size)

            let base = Appearance.stemBase.applying(resized.bodyTransform)
            XCTAssertEqual(resized.stemAttachment.x, base.x, accuracy: 0.001)
            XCTAssertEqual(resized.stemAttachment.y, base.y, accuracy: 0.001)
            XCTAssertEqual(resized.stemTip.x - base.x, original.stemTip.x - original.stemAttachment.x, accuracy: 0.001)
            XCTAssertEqual(resized.stemTip.y - base.y, original.stemTip.y - original.stemAttachment.y, accuracy: 0.001)
        }
    }

    private final class SeedCucumberTestPan: UIPanGestureRecognizer {
        var point = CGPoint.zero
        var delta = CGPoint.zero

        override func location(in view: UIView?) -> CGPoint { point }
        override func translation(in view: UIView?) -> CGPoint { delta }
    }

    func testUpdatedConsentCaptures() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        for variant in variants {
            let page = VStack(spacing: 0) {
                OiCreationProgressHeader(step: 1).padding(.horizontal, 20)
                OiStoryConsentView(clauses: OiStoryConsentClause.writingClauses, showsHeader: false)
            }
            try await capture(page, name: "consent-three-clauses", variant: variant,
                              defaults: fixture.defaults, attach: true)
        }
    }

    func testFinishedCustomizationAndConsentCaptures() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        for variant in variants {
            let cucumber = CreationCapturePage(step: 3, showsNavigation: true) {
                OiCucumberCustomizationStep(customization: .constant(Self.customization), isFinished: true, onContinue: {})
                    .environment(\.scenePhase, .active)
            }
            try await capture(cucumber, name: "cucumber-finished", variant: variant, defaults: fixture.defaults, delay: .seconds(2), attach: true)
            let card = CreationCapturePage(step: 4, showsNavigation: true) {
                OiCardCustomizationStep(draft: .constant(Self.draft), customization: .constant(Self.customization),
                    isFinished: true, onContinue: {})
            }
            try await capture(card, name: "card-finished", variant: variant, defaults: fixture.defaults, attach: true)
            try await capture(NavigationStack { OiStoryConsentView(clauses: OiStoryConsentClause.writingClauses) },
                name: "consent-footprints", variant: variant, defaults: fixture.defaults, attach: true)
        }
    }

    func testLocationSearchFirstCapture() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        for variant in variants {
            let picker = OiLocationPicker(latitude: .constant(nil), longitude: .constant(nil))
            try await capture(picker, name: "location-search-first", variant: variant,
                defaults: fixture.defaults, attach: true)
        }
    }

    func testThreeDimensionalLocationPickerCapture() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        let picker = OiLocationPicker(latitude: .constant(36.01261057021347), longitude: .constant(129.3197268697784), focusPlaceID: "53")
            .environment(\.scenePhase, .active)
        try await capture(picker, name: "location-3D-picker", variant: try XCTUnwrap(variants.first),
            defaults: fixture.defaults, delay: .seconds(3), attach: true)
    }

    func testSharedCardAndCollectionResultCaptures() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        for variant in variants {
            let card = VStack {
                MYCardArtwork(card: Self.card).frame(maxWidth: 320)
            }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color("OiLight"))
            try await capture(card, name: "story-card", variant: variant, defaults: fixture.defaults)
            let result = ARCollectionResultView(name: Self.draft.cucumberName, tags: ["고마움", "우정"],
                donor: "검증용 농부", location: "POSTECH 지곡회관 · 연못", date: "2026.11.03",
                isCollected: false, onCollect: {}, onCancel: {}) {
                    OiStoryCardArtwork(name: Self.draft.cucumberName, introduction: Self.draft.body,
                        donor: "검증용 농부", date: "2026.11.03", tags: ["고마움", "우정"], assetName: "OiCats")
                }
            try await capture(result, name: "collection-result", variant: variant, defaults: fixture.defaults)
        }
    }

    func testCardRequestInboxCaptures() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        let now = Date.now
        let rows = [
            OiCardRequestInboxItem(id: UUID(), requesterName: "검증용 농부", storyTitle: "캠퍼스에 남긴 이야기",
                schoolName: "POSTECH", portraitURL: nil, createdAt: now.addingTimeInterval(-180)),
            OiCardRequestInboxItem(id: UUID(), requesterName: "검증용 농부", storyTitle: "같은 농부가 요청한 또 다른 카드",
                schoolName: nil, portraitURL: nil, createdAt: now.addingTimeInterval(-1_620)),
            OiCardRequestInboxItem(id: UUID(), requesterName: "긴 닉네임의 검증용 농부", storyTitle: "긴 카드 제목을 줄이지 않고 보여주는지 확인하는 이야기",
                schoolName: nil, portraitURL: nil, createdAt: now.addingTimeInterval(-86_400)),
            OiCardRequestInboxItem(id: UUID(), requesterName: "검증용 농부", storyTitle: "가장 오래된 카드 요청",
                schoolName: nil, portraitURL: nil, createdAt: now.addingTimeInterval(-1_468_800))
        ]
        let states: [(name: String, rows: [OiCardRequestInboxItem], error: String?)] = [
            ("card-requests-inbox", rows, nil),
            ("card-requests-empty", [], nil),
            ("card-requests-error", [], "연결을 확인한 뒤 다시 시도해 주세요.")
        ]
        for variant in variants {
            for state in states {
                let inbox = OiCardRequestInboxView(requests: state.rows, isLoading: false, loadError: state.error,
                    pendingRequestID: nil, actionError: nil, onReload: {}, onDecision: { _, _ in })
                try await capture(inbox, name: state.name, variant: variant, defaults: fixture.defaults, attach: true)
            }
        }
        // Compare the sheet content at the Figma node's own dimensions. The
        // dark backing makes its 70% fill visible without depending on live map data.
        let sheetVariant = Variant(name: "402x803-sheet", size: CGSize(width: 402, height: 803), dynamicTypeSize: .large)
        let emptySheet = OiCardRequestInboxView(requests: [], isLoading: false, loadError: nil,
            pendingRequestID: nil, actionError: nil, onReload: {}, onDecision: { _, _ in })
        try await capture(emptySheet.background(Color(white: 0.117)), name: "card-requests-empty",
            variant: sheetVariant, defaults: fixture.defaults, includesSafeArea: false, attach: true)

        let reference = try XCTUnwrap(variants.first)
        let unconfirmed = OiCardRequestInboxView(requests: [], isLoading: false, loadError: nil,
            pendingRequestID: nil, actionError: "처리 결과를 확인하지 못했어요. 같은 응답을 다시 확인해 주세요.",
            onReload: {}, onDecision: { _, _ in }, onRetryDecision: {})
        try await capture(unconfirmed, name: "card-requests-unconfirmed-decision",
            variant: reference, defaults: fixture.defaults, attach: true)
    }

    func testMYScreenCapturesWithoutRemoteStore() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        let library = MYLibraryStore()
        library.synchronize(nickname: "검증용 농부", cards: [], favorites: [])
        for variant in variants {
            let workshop = NavigationStack {
                MYWorkshopView(demo: library, remote: nil)
            }
            try await capture(workshop, name: "my-workshop", variant: variant, defaults: fixture.defaults)
            let farmer = NavigationStack { MYFarmerCustomizationView(remote: nil) }
            try await capture(farmer, name: "my-farmer", variant: variant, defaults: fixture.defaults)
            let settings = NavigationStack {
                MYSettingsView(demo: library, remote: nil)
            }
            try await capture(settings, name: "my-settings", variant: variant, defaults: fixture.defaults)
        }
    }

    func testMYCollectionCaptures() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        let collectionStore = StoryCollectionStore(defaults: fixture.defaults)
        let collectionVariants = variants + [Variant(name: "small-accessibility5", size: CGSize(width: 375, height: 667), dynamicTypeSize: .accessibility5)]
        for populated in [false, true] {
            for filter in MYCollectionFilter.allCases {
                let library = MYLibraryStore()
                let cards = populated ? (0..<7).map { index in
                    MYCard(id: "my-capture-\(index)", title: "검증용 오이 \(index + 1)", image: "OiCats",
                        school: .postech, order: index, body: Self.draft.body, donor: "검증용 농부", date: "2026.11.05")
                } : []
                library.synchronize(nickname: "검증용 농부", cards: cards, favorites: [])
                library.collectionFilter = filter
                for variant in collectionVariants {
                    let view = NavigationStack {
                        MYCollectionView(demo: library, storyRepository: AppContainer.preview.storyRepository,
                            collectionStore: collectionStore)
                    }
                    try await capture(view, name: "my-collection-\(filter == .all ? "all" : "schools")-\(populated ? "content" : "empty")",
                        variant: variant, defaults: fixture.defaults, attach: true)
                }
                if filter == .schools {
                    for variant in collectionVariants {
                        let view = NavigationStack {
                            MYCollectionView(demo: library, school: .postech, storyRepository: AppContainer.preview.storyRepository,
                                collectionStore: collectionStore)
                        }
                        try await capture(view, name: "my-collection-school-\(populated ? "content" : "empty")",
                            variant: variant, defaults: fixture.defaults, attach: true)
                    }
                }
            }
        }
    }

    func testFarmerWardrobeAssetsAndSelectionContract() throws {
        let wardrobe = try MYFarmerWardrobe.loaded.get()
        XCTAssertEqual(wardrobe.items.count, 120)
        XCTAssertEqual(wardrobe.items.filter { $0.character == "kyu" }.count, 64)
        XCTAssertEqual(wardrobe.items.filter { $0.character == "cumber" }.count, 56)
        XCTAssertEqual(wardrobe.items.filter { !$0.wearables.isEmpty }.count, 117)
        XCTAssertFalse(wardrobe.items(character: "kyu", slot: .accessory).contains { $0.id == "kyu-3927-3879" })
        XCTAssertFalse(wardrobe.items(character: "cumber", slot: .set).contains { $0.id == "cumber-4148-5133" })
        XCTAssertFalse(wardrobe.items(character: "cumber", slot: .accessory).contains { $0.id == "cumber-4148-5283" })
        let canvases = Array(wardrobe.bodies.values) + wardrobe.items.flatMap { [$0.thumbnail] + $0.wearables }
        for canvas in canvases {
            XCTAssertGreaterThan(canvas.width, 0)
            XCTAssertGreaterThan(canvas.height, 0)
            XCTAssertFalse(canvas.layers.isEmpty)
            for layer in canvas.layers {
                XCTAssertNotNil(UIImage(named: layer.asset), "Missing bundled original: \(layer.asset)")
                XCTAssertGreaterThan(layer.width, 0)
                XCTAssertGreaterThan(layer.height, 0)
                for matrix in [layer.matrix, layer.crop] {
                    XCTAssertEqual(matrix.count, 2)
                    XCTAssertTrue(matrix.allSatisfy { $0.count == 3 && $0.allSatisfy(\.isFinite) })
                    let transform = MYFarmerCanvasArtwork.transform(matrix)
                    XCTAssertGreaterThan(abs(transform.a * transform.d - transform.b * transform.c), 0.000001)
                }
            }
        }
        XCTAssertTrue(wardrobe.validates(.legacy(.classic)))
        XCTAssertTrue(wardrobe.validates(.legacy(.casual)))
        XCTAssertFalse(wardrobe.validates(OiFarmerOutfit(character: "other", slots: [:])))
        for character in ["kyu", "cumber"] {
            let top = try XCTUnwrap(wardrobe.items(character: character, slot: .top).first)
            let bottom = try XCTUnwrap(wardrobe.items(character: character, slot: .bottom).first)
            let set = try XCTUnwrap(wardrobe.items(character: character, slot: .set).first)
            let initial = OiFarmerOutfit(character: character, slots: [:])
            let separates = initial.selecting(top).selecting(bottom)
            XCTAssertTrue(wardrobe.validates(separates))
            XCTAssertEqual(separates.slots.count, 2)
            let onePiece = separates.selecting(set)
            XCTAssertEqual(onePiece.slots, ["set": set.id])
            XCTAssertEqual(onePiece.selecting(top).slots, ["top": top.id])
            XCTAssertFalse(wardrobe.validates(OiFarmerOutfit(character: character, slots: ["shoes": top.id])))
        }
    }

    func testFarmerWearableAndThumbnailContactSheets() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        let wardrobe = try MYFarmerWardrobe.loaded.get()
        for character in ["kyu", "cumber"] {
            for slot in [MYFarmerSlot.top, .bottom, .shoes, .set, .accessory] {
                let items = wardrobe.items(character: character, slot: slot)
                let rows = (items.count + 1) / 2
                let variant = Variant(name: "contact", size: CGSize(width: 402, height: CGFloat(rows * 180 + 28)), dynamicTypeSize: .large)
                let gallery = LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(items) { item in
                        VStack(spacing: 4) {
                            HStack(spacing: 8) {
                                MYFarmerLayeredArtwork(outfit: OiFarmerOutfit(character: character, slots: [slot.rawValue: item.id]), wardrobe: wardrobe)
                                    .frame(width: 90, height: 125)
                                Color.clear.frame(width: 60, height: 72)
                                    .overlay(alignment: .topLeading) {
                                        MYFarmerCanvasArtwork(canvas: item.thumbnail)
                                            .scaleEffect(60 / item.thumbnail.width, anchor: .topLeading)
                                    }.clipped()
                            }
                            Text(item.name).font(.system(size: 12)).multilineTextAlignment(.center).frame(height: 35)
                        }.frame(maxWidth: .infinity)
                    }
                }.padding(14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).background(.white)
                try await capture(gallery, name: "farmer-\(character)-\(slot.rawValue)", variant: variant,
                    defaults: fixture.defaults, includesSafeArea: false, attach: true)
            }
        }
    }

    func testEmptyCollectionCaptures() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        let collectionStore = StoryCollectionStore(defaults: fixture.defaults)
        XCTAssertTrue(collectionStore.cards.isEmpty)
        XCTAssertNil(collectionStore.persistenceError)
        XCTAssertNotNil(UIImage(named: "MYEmptyCollection"))

        for filter in [MYCollectionFilter.all, .schools] {
            let library = MYLibraryStore()
            library.collectionFilter = filter
            let name = filter == .all ? "my-collection-empty" : "my-collection-schools-empty"
            for variant in variants {
                let collection = NavigationStack {
                    MYCollectionView(demo: library, storyRepository: UnconnectedPilotRepository(),
                        collectionStore: collectionStore)
                }
                try await capture(collection, name: name, variant: variant, defaults: fixture.defaults, attach: true)
            }
        }
    }

    func testCampusSearchStatesDoNotConfusePromptFailureAndEmptyResults() {
        for hasMatches in [false, true] {
            XCTAssertEqual(CampusSearchContentState(hasSearched: false, hasMatches: hasMatches,
                hasLoaded: false, isLoading: true, hasError: false), .prompt)
        }
        XCTAssertEqual(CampusSearchContentState(hasSearched: true, hasMatches: false,
            hasLoaded: false, isLoading: false, hasError: false), .loading)
        XCTAssertEqual(CampusSearchContentState(hasSearched: true, hasMatches: false,
            hasLoaded: true, isLoading: true, hasError: false), .loading)
        for hasLoaded in [false, true] {
            XCTAssertEqual(CampusSearchContentState(hasSearched: true, hasMatches: false,
                hasLoaded: hasLoaded, isLoading: false, hasError: true), .failed)
        }
        XCTAssertEqual(CampusSearchContentState(hasSearched: true, hasMatches: true,
            hasLoaded: true, isLoading: false, hasError: true), .results)
        XCTAssertEqual(CampusSearchContentState(hasSearched: true, hasMatches: false,
            hasLoaded: true, isLoading: false, hasError: false), .noMatches)
    }

    func testCampusSearchPromptCaptures() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        let story = CampusStory(id: "prompt-fixture", regionID: "pond", title: "테스트오이", image: "OiCats",
            tags: [], donor: "가상 기부자", location: "테스트", date: "", order: 0, popularity: 0, palette: 0)
        for mode in CampusSearchMode.allCases {
            for variant in variants {
                let screen = CampusSearchView(mode: mode, entries: [.example(story)], isExample: false,
                    onSelect: { _ in XCTFail("No search has been submitted") })
                let png = try await capture(screen, name: "campus-search-\(mode.rawValue)-prompt", variant: variant,
                    defaults: fixture.defaults, attach: true)
                if variant.name == "402x874" {
                    let bitmap = try renderedBitmap(png, size: variant.size)
                    let pixels = try XCTUnwrap(bitmap.data).bindMemory(to: UInt8.self, capacity: bitmap.width * bitmap.height * 4)
                    var greenPixels = 0
                    for y in 250..<800 {
                        for x in 20..<382 {
                            let i = (y * bitmap.width + x) * 4
                            let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
                            if g > r + 12 && g > b + 25 { greenPixels += 1 }
                        }
                    }
                    XCTAssertGreaterThan(greenPixels, 2500, "The initial screen must actually render the green cucumber, not only text")
                }
            }
        }
    }

    func testCampusSearchEmptyResultCaptures() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        XCTAssertNotNil(UIImage(named: "CampusSearchNoResults"))

        for mode in CampusSearchMode.allCases {
            let query = CampusSearchQuery(text: "없는 오이", name: "없는 농부")
            for variant in variants {
                let result = CampusSearchView(mode: mode, entries: [], isExample: false, initialQuery: query,
                    onSelect: { _ in XCTFail("Empty search must offer no selection") })
                try await capture(result, name: "campus-search-\(mode.rawValue)-no-matches", variant: variant,
                    defaults: fixture.defaults, attach: true)
            }
        }
    }

    func testSchoolSearchEmptyResultCaptures() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        XCTAssertNotNil(UIImage(named: "CampusSearchNoResults"))
        for variant in variants {
            let screen = CampusSchoolSearchView(initialQuery: "없는 학교") {
                XCTFail("A school with no matching result must not be selected")
            }
            let png = try await capture(screen, name: "school-search-no-matches", variant: variant,
                defaults: fixture.defaults, attach: true)
            if variant.name == "402x874" {
                let bitmap = try renderedBitmap(png, size: variant.size)
                let pixels = try XCTUnwrap(bitmap.data).bindMemory(to: UInt8.self, capacity: bitmap.width * bitmap.height * 4)
                var greenPixels = 0
                for y in 280..<610 {
                    for x in 100..<302 {
                        let i = (y * bitmap.width + x) * 4
                        let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
                        if g > r + 12 && g > b + 25 { greenPixels += 1 }
                    }
                }
                XCTAssertGreaterThan(greenPixels, 2500, "The school empty state must render its original cucumber illustration")
            }
        }
        let reference = try XCTUnwrap(variants.first)
        for (name, query) in [("initial", ""), ("matched", "postech")] {
            try await capture(CampusSchoolSearchView(initialQuery: query, onSelect: {}),
                name: "school-search-\(name)", variant: reference, defaults: fixture.defaults, attach: true)
        }
    }

    func testLocationSearchEmptyResultCaptures() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        let query = "location-fixture-no-match"
        let places = try CampusMapData.load().pois
        XCTAssertFalse(places.isEmpty)
        XCTAssertFalse(places.contains { $0.name.localizedCaseInsensitiveContains(query) })

        for variant in variants {
            let location = OiStoryLocationStep(initialQuery: query, choose: { _ in })
            try await capture(location, name: "location-search-no-matches", variant: variant,
                defaults: fixture.defaults, attach: true)
        }
    }

    func testMYSettingsCapturesWithOfflineAccounts() async throws {
        let fixture = try isolatedDefaults()
        let previousHandler = OiStoreURLProtocol.handle
        let backend = OiTestBackend()
        backend.configure { profile in
            profile.nickname = "검증용 농부"
            profile.schoolID = "postech"
            profile.schoolProfileEnabled = true
            profile.farmerOutfitEnabled = true
            profile.farmName = "오이농장주인"
        }
        backend.install()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OiStoreURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MYSettings-\(UUID().uuidString)", isDirectory: true)
        defer {
            fixture.defaults.removePersistentDomain(forName: fixture.name)
            withExtendedLifetime(backend) {}
            session.invalidateAndCancel()
            OiStoreURLProtocol.handle = previousHandler
            if FileManager.default.fileExists(atPath: directory.path) {
                XCTAssertNoThrow(try FileManager.default.removeItem(at: directory))
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        }

        let api = try OiServiceAPI(key: "sb_publishable_testing", session: session)
        let signedInDrafts = OiDraftVault(directory: directory.appendingPathComponent("signed-in", isDirectory: true))
        let signedIn = OiRemoteStore(api: api, drafts: signedInDrafts, vault: OiMemorySession())
        let emptySession = OiMemorySession()
        try emptySession.write(nil)
        let signedOut = OiRemoteStore(api: api,
            drafts: OiDraftVault(directory: directory.appendingPathComponent("signed-out", isDirectory: true)),
            vault: emptySession)
        await signedIn.start()
        await signedOut.start()
        XCTAssertTrue(signedIn.hasLoadedRemote)
        XCTAssertTrue(signedIn.isFarmerOutfitAvailable)
        XCTAssertEqual(signedIn.profile?.nickname, "검증용 농부")
        XCTAssertEqual(signedIn.profile?.schoolId, "postech")
        XCTAssertTrue(signedOut.hasLoadedRemote)
        XCTAssertTrue(signedOut.isConfigured)
        XCTAssertNil(signedOut.account)

        for variant in variants {
            let workshop = NavigationStack { MYWorkshopView(demo: MYLibraryStore(), remote: signedIn) }
            try await capture(workshop, name: "my-workshop-signed-in", variant: variant, defaults: fixture.defaults, attach: true)
            let farmer = NavigationStack { MYFarmerCustomizationView(remote: signedIn) }
            try await capture(farmer, name: "my-farmer-signed-in", variant: variant, defaults: fixture.defaults, attach: true)
            let settings = NavigationStack(path: .constant([true])) {
                Color.white.navigationDestination(for: Bool.self) { _ in
                    MYSettingsView(remote: signedIn).environment(\.scenePhase, .active)
                }
            }
            try await capture(settings, name: "my-settings-signed-in", variant: variant,
                defaults: fixture.defaults, delay: .milliseconds(450), attach: true)

            let signIn = NavigationStack(path: .constant([true])) {
                Color.white.navigationDestination(for: Bool.self) { _ in
                    MYSettingsView(remote: signedOut).environment(\.scenePhase, .active)
                }
            }
            try await capture(signIn, name: "my-settings-signed-out-auth", variant: variant,
                defaults: fixture.defaults, delay: .milliseconds(450), attach: true)
        }

        let reference = try XCTUnwrap(variants.first)
        let account = NavigationStack(path: .constant([true])) {
            Color.white.navigationDestination(for: Bool.self) { _ in
                MYSettingsView(remote: signedIn).defaultScrollAnchor(.bottom).environment(\.scenePhase, .active)
            }
        }
        try await capture(account, name: "my-settings-signed-in-auth", variant: reference,
            defaults: fixture.defaults, delay: .milliseconds(450), attach: true)
        let steps: [(String, OiSchoolEvidenceView.Step)] = [
            ("profile", .profile), ("affiliation", .affiliation),
            ("student-document", .document(.student)), ("graduate-document", .document(.graduate)),
            ("attachment", .attachment(.graduate, .diploma))
        ]
        for variant in variants {
            for (name, step) in steps {
                let screen = NavigationStack {
                    OiSchoolEvidenceView(remote: signedIn, initialStep: step)
                }
                try await capture(screen, name: "school-evidence-" + name, variant: variant,
                    defaults: fixture.defaults, delay: .milliseconds(450), attach: true)
            }
        }

        for outcome in [OiSchoolEvidenceOutcome.completed, .rejected, .documentNeeded, .retakeNeeded, .manualReviewNeeded] {
            let owner = try XCTUnwrap(signedIn.account?.id)
            try await signedInDrafts.saveSchoolEvidenceReview(.init(outcome: outcome, reviewedAt: .now), owner: owner)
            for variant in variants {
                let screen = NavigationStack { OiSchoolEvidenceView(remote: signedIn) }
                try await capture(screen, name: "school-evidence-result-\(outcome.rawValue)", variant: variant,
                    defaults: fixture.defaults, delay: .milliseconds(450), attach: true)
            }
        }
    }

    func testCampusDetailAndSummaryCaptures() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        let store = CampusStoryStore(defaults: fixture.defaults, isExample: true)
        store.synchronize(stories: CampusStoryExamples.stories, collected: [])
        let story = try XCTUnwrap(store.stories.first)
        XCTAssertTrue(story.isExample)
        XCTAssertTrue(story.remoteMediaPaths.isEmpty, "This capture must use only bundled example images")
        XCTAssertNil(story.latitude, "The example must not start a live MapKit tile request")
        XCTAssertNil(story.longitude)
        for variant in variants {
            for bottom in [false, true] {
                let detail = NavigationStack {
                    CampusStoryDetailView(story: story, store: store)
                        .defaultScrollAnchor(bottom ? .bottom : .top)
                }
                try await capture(detail, name: "campus-detail\(bottom ? "-bottom" : "")",
                    variant: variant, defaults: fixture.defaults)
            }
            let summary = NavigationStack {
                CampusSummaryView(story: story, store: store).environment(\.scenePhase, .active)
            }
            try await capture(summary, name: "campus-summary", variant: variant,
                defaults: fixture.defaults, delay: .seconds(2))
        }
    }

    func testSampleExperienceCaptures() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        XCTAssertNotNil(UIImage(named: "OiStoryCardCats"))
        for variant in variants {
            try await capture(OiSampleExperienceView(), name: "sample-map", variant: variant,
                defaults: fixture.defaults, attach: true)
            try await capture(NavigationStack { OiSampleMapView(isExpanded: true).modifier(OiSampleNoticeModifier()) }, name: "sample-list", variant: variant,
                defaults: fixture.defaults, attach: true)
            for expanded in [false, true] {
                let bottomList = NavigationStack {
                    OiSampleMapView(isExpanded: expanded)
                        .defaultScrollAnchor(.bottom, for: .initialOffset)
                        .modifier(OiSampleNoticeModifier())
                }
                try await capture(bottomList, name: "sample-\(expanded ? "list" : "map")-bottom", variant: variant,
                    defaults: fixture.defaults, attach: true)
            }
            let story = CampusStoryExamples.stories[0]
            try await capture(NavigationStack { OiSampleSummaryView(story: story, onCollect: {}).modifier(OiSampleNoticeModifier()) },
                name: "sample-summary", variant: variant, defaults: fixture.defaults, attach: true)
            try await capture(NavigationStack { OiSampleStoryDetailView(story: story, onCollect: {}).modifier(OiSampleNoticeModifier()) },
                name: "sample-detail", variant: variant, defaults: fixture.defaults, attach: true)
            for collected in [false, true] {
                try await capture(OiSampleCollectionResult(isCollected: collected, onCollect: {}, onClose: {}),
                    name: "sample-collection-\(collected)", variant: variant, defaults: fixture.defaults, attach: true)
            }
        }
    }

    func testSampleARArtworkAndCollectionOutline() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        let loaded = await CucumberArtwork.load(imageURL: nil, assetName: "OiStoryCardCats")
        let image = try XCTUnwrap(loaded)
        let outline = try XCTUnwrap(CucumberArtwork.collectionOutline(image))
        XCTAssertEqual(image.size, outline.size, "Empty and filled slots must fit the same normalized AR texture")
        let source = try XCTUnwrap(image.cgImage)
        let edge = try XCTUnwrap(outline.cgImage)
        XCTAssertEqual(source.width, edge.width)
        XCTAssertEqual(source.height, edge.height)
        let sourceBytes = try XCTUnwrap(source.dataProvider?.data) as Data
        let edgeBytes = try XCTUnwrap(edge.dataProvider?.data) as Data
        XCTAssertNotEqual(sourceBytes, edgeBytes, "The slot is an outline, not the original photograph")
        for collected in [0, 1, 3] {
            let hud = ZStack {
                Color(white: 0.25)
                ARGameHUD(remainingSeconds: 30, collectedCount: collected, targetCount: 3, artwork: image)
            }
            try await capture(hud, name: "sample-ar-slots-\(collected)", variant: variants[0],
                defaults: fixture.defaults, delay: .milliseconds(600), attach: true)
        }
        for name in ["OiSampleMap", "OiSampleSummaryMap", "OiCatsPortrait", "OiCatsExampleCard",
                     "OiFarmer", "OiStoryLocation", "OiPoka"] + (1...11).map({ String(format: "OiSampleGallery%02d", $0) }) {
            XCTAssertNotNil(UIImage(named: name), name)
        }
    }

    func testCampusSummaryShowsActionForVerifiedLocation() async throws {
        let fixture = try isolatedDefaults()
        let previousHandler = OiStoreURLProtocol.handle
        let backend = OiTestBackend()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OiStoreURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let directory = FileManager.default.temporaryDirectory.appending(path: "CampusCardLocation-\(UUID())")
        defer {
            fixture.defaults.removePersistentDomain(forName: fixture.name)
            withExtendedLifetime(backend) {}
            session.invalidateAndCancel()
            OiStoreURLProtocol.handle = previousHandler
            if FileManager.default.fileExists(atPath: directory.path) {
                XCTAssertNoThrow(try FileManager.default.removeItem(at: directory))
            }
        }
        var draft = Self.draft
        draft.grantId = OiTestBackend.grant
        draft.latitude = 36.01261057021347
        draft.longitude = 129.3197268697784
        var published = try draft.payload()
        published["user_id"] = OiTestBackend.owner.uuidString
        published["status"] = "published"
        published["created_at"] = "2026-10-28T00:00:00Z"
        backend.configure { $0.story = published }
        backend.install()
        let vault = OiMemorySession()
        try vault.write(nil)
        let remote = OiRemoteStore(api: try OiServiceAPI(key: "sb_publishable_testing", session: session),
            drafts: OiDraftVault(directory: directory), vault: vault)
        await remote.start()
        let story = remote.campusStory(try XCTUnwrap(remote.stories.first))
        let store = CampusStoryStore(defaults: fixture.defaults)
        store.synchronize(stories: [story], collected: [])
        let reference = try XCTUnwrap(variants.first)
        let states: [(String, CampusCardProximity?)] = [
            ("pohang-collect", .near),
            ("outside-pohang-request", .away),
            ("unknown-location-request", nil)
        ]
        for (name, proximity) in states {
            let summary = NavigationStack { CampusSummaryView(story: story, store: store) }
                .environment(remote)
                .environment(\.campusCardProximity) { _ in
                    guard let proximity else { throw CampusCardLocationError.permissionDenied }
                    return proximity
                }
                .environment(\.scenePhase, .active)
            try await capture(summary, name: name, variant: reference,
                defaults: fixture.defaults, delay: .seconds(2), attach: true)
        }
        XCTAssertTrue(backend.snapshot().cardSendPayloads.isEmpty, "Checking the location must not send a request")
    }

    func testFarmCapturesWithOfflineOwnedStory() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        let previousHandler = OiStoreURLProtocol.handle
        let backend = OiTestBackend()
        backend.configure { $0.nickname = "공개 작성자"; $0.farmName = "햇살" }
        backend.install()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OiStoreURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Figma132-Farm-\(UUID().uuidString)", isDirectory: true)
        defer {
            withExtendedLifetime(backend) {}
            session.invalidateAndCancel()
            OiStoreURLProtocol.handle = previousHandler
            if FileManager.default.fileExists(atPath: directory.path) {
                XCTAssertNoThrow(try FileManager.default.removeItem(at: directory))
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        }
        let api = try OiServiceAPI(key: "sb_publishable_testing", session: session)
        let remote = OiRemoteStore(api: api, drafts: OiDraftVault(directory: directory), vault: OiMemorySession())
        await remote.start()
        XCTAssertTrue(remote.hasLoadedRemote)
        XCTAssertEqual(remote.account?.id, OiTestBackend.owner)
        XCTAssertTrue(remote.ownStories.isEmpty)
        for variant in variants {
            let empty = NavigationStack { MYFarmView(remote: remote) }
            try await capture(empty, name: "my-farm-empty", variant: variant, defaults: fixture.defaults)
        }
        var draft = Self.draft
        draft.grantId = OiTestBackend.grant
        draft.latitude = 36.01261057021347
        draft.longitude = 129.3197268697784
        let receipt = await remote.save(draft)
        let saved = try XCTUnwrap(receipt, "The existing offline mutation path must create the owned story")
        XCTAssertEqual(saved.status, "draft")
        XCTAssertEqual(remote.ownStories.map(\.id), [saved.id])
        for variant in variants {
            let populated = NavigationStack { MYFarmView(remote: remote) }
            try await capture(populated, name: "my-farm-populated", variant: variant, defaults: fixture.defaults)
        }
    }

    func testFarmerAppearancePersistsForItsOwnerOnly() throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        let firstOwner = OiTestBackend.owner
        let secondOwner = OiTestBackend.other
        XCTAssertEqual(MYFarmerAppearanceStore.read(ownerID: firstOwner, defaults: fixture.defaults), .classic)
        XCTAssertEqual(MYFarmerAppearanceStore.read(ownerID: secondOwner, defaults: fixture.defaults), .classic)
        MYFarmerAppearanceStore.save(.casual, ownerID: firstOwner, defaults: fixture.defaults)
        let restoredDefaults = try XCTUnwrap(UserDefaults(suiteName: fixture.name))
        XCTAssertEqual(MYFarmerAppearanceStore.read(ownerID: firstOwner, defaults: restoredDefaults), .casual)
        XCTAssertEqual(MYFarmerAppearanceStore.read(ownerID: secondOwner, defaults: restoredDefaults), .classic)
        MYFarmerAppearanceStore.save(.classic, ownerID: secondOwner, defaults: fixture.defaults)
        XCTAssertEqual(MYFarmerAppearanceStore.read(ownerID: firstOwner, defaults: restoredDefaults), .casual)
        MYFarmerAppearanceStore.save(.casual, ownerID: nil, defaults: fixture.defaults)
        XCTAssertNil(fixture.defaults.object(forKey: MYFarmerAppearanceStore.key(ownerID: nil)))
        XCTAssertEqual(MYFarmerAppearanceStore.read(ownerID: nil, defaults: restoredDefaults), .classic)
    }

    @discardableResult
    private func capture<V: View>(_ view: V, name: String, variant: Variant, defaults: UserDefaults,
                                 includesSafeArea: Bool = true,
                                 delay: Duration = .milliseconds(180), attach: Bool = false,
                                 checksBottomSheet: Bool = false, cucumberCameraYaw: Float? = nil) async throws -> Data {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first, "The isolated simulator test host must have a window scene")
        let existingWindows = scene.windows.map { (id: ObjectIdentifier($0), hidden: $0.isHidden, key: $0.isKeyWindow) }
        let window = UIWindow(windowScene: scene)
        let windowID = ObjectIdentifier(window)
        let root = UIViewController()
        let host = UIHostingController(rootView: view
            .environment(\.dynamicTypeSize, variant.dynamicTypeSize)
            .environment(\.colorScheme, .light)
            .defaultAppStorage(defaults))
        if !includesSafeArea { host.safeAreaRegions = [] }
        window.frame = CGRect(origin: .zero, size: variant.size)
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = root
        root.view.frame = window.bounds
        root.addChild(host)
        host.view.frame = root.view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        root.view.addSubview(host.view)
        host.didMove(toParent: root)
        // Showing this owned window without making it key preserves all existing windows.
        window.isHidden = false
        defer {
            if checksBottomSheet { root.dismiss(animated: false) }
            releaseCampusRenderers(in: host.view)
            host.willMove(toParent: nil)
            host.view.removeFromSuperview()
            host.removeFromParent()
            window.isHidden = true
            window.rootViewController = nil
            window.windowScene = nil
            XCTAssertFalse(scene.windows.contains { ObjectIdentifier($0) == windowID }, "The capture window must detach, including hidden windows")
            for previous in existingWindows {
                if let existing = scene.windows.first(where: { ObjectIdentifier($0) == previous.id }) {
                    XCTAssertEqual(existing.isHidden, previous.hidden, "A pre-existing test-host window must retain its visibility")
                    XCTAssertEqual(existing.isKeyWindow, previous.key, "A capture must never take key-window ownership")
                }
            }
        }
        window.layoutIfNeeded()
        root.view.layoutIfNeeded()
        host.view.setNeedsLayout()
        try await Task.sleep(for: delay)
        host.view.layoutIfNeeded()
        if checksBottomSheet {
            let presented = try XCTUnwrap(root.presentedViewController ?? host.presentedViewController)
            let sheet = try XCTUnwrap(presented.presentationController)
            XCTAssertTrue(sheet is UISheetPresentationController)
            let frame = sheet.frameOfPresentedViewInContainerView
            let bounds = try XCTUnwrap(sheet.containerView?.bounds)
            XCTAssertGreaterThan(frame.minY, bounds.minY)
            XCTAssertEqual(frame.maxY, bounds.maxY, accuracy: 1)
        }
        let renderView: UIView = checksBottomSheet ? window : host.view
        let realitySnapshot: (image: UIImage, frame: CGRect)?
        if let cucumberCameraYaw {
            realitySnapshot = try await captureCucumberSurface(in: renderView, yaw: cucumberCameraYaw)
        } else {
            realitySnapshot = nil
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        var rendered = false
        let png = UIGraphicsImageRenderer(size: variant.size, format: format).pngData { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: variant.size))
            rendered = renderView.drawHierarchy(in: renderView.bounds, afterScreenUpdates: true)
            if let realitySnapshot {
                realitySnapshot.image.draw(in: realitySnapshot.frame)
            }
        }
        XCTAssertTrue(rendered, "The attached production view must draw its hierarchy")
        try assertNonemptyRender(png, size: variant.size)
        if attach {
            let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
            attachment.name = "\(name)-\(variant.name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        let directory = try XCTUnwrap(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
            .appendingPathComponent("Figma132", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = directory.appendingPathComponent("\(name)-\(variant.name).png")
        try png.write(to: output, options: .atomic)
        XCTAssertEqual(try Data(contentsOf: output).count, png.count, "The saved capture must contain the rendered PNG")
        print("Figma132 capture: \(output.path)")
        return png
    }

    private func captureCucumberSurface(in view: UIView, yaw: Float) async throws -> (image: UIImage, frame: CGRect) {
        var surface = cucumberSurface(in: view)
        for _ in 0..<15 where surface == nil {
            try await Task.sleep(for: .milliseconds(100))
            surface = cucumberSurface(in: view)
        }
        let renderer = try XCTUnwrap(surface, "The real preview must install its RealityKit surface")
        if yaw != 0 {
            let cameras = renderer.scene.anchors.flatMap { anchor in
                anchor.children.compactMap { $0 as? PerspectiveCamera }
            }
            let camera = try XCTUnwrap(cameras.first)
            let model = try XCTUnwrap(renderer.scene.findEntity(named: "SeedCucumber"))
            let bounds = model.visualBounds(relativeTo: nil)
            var pose = OiSeedCucumber3DCamera()
            pose.orbit(yaw: yaw, pitch: 0)
            let position = pose.position(center: bounds.center, radius: simd_length(bounds.extents) / 2,
                                         viewport: renderer.bounds.size)
            camera.look(at: bounds.center, from: position, relativeTo: nil)
            try await Task.sleep(for: .milliseconds(100))
        }
        // UIKit's view snapshot omits the Metal surface.
        let snapshot: UIImage? = await withCheckedContinuation { continuation in
            renderer.snapshot(saveToHDR: false) { continuation.resume(returning: $0) }
        }
        let image = try XCTUnwrap(snapshot, "RealityKit must render the preview")
        let pixels = try XCTUnwrap(image.cgImage)
        let data = try XCTUnwrap(image.pngData())
        try assertNonemptyRender(data, size: CGSize(width: pixels.width, height: pixels.height))
        return (image, renderer.convert(renderer.bounds, to: view))
    }

    private func cucumberSurface(in view: UIView) -> RealityKit.ARView? {
        if let surface = view as? RealityKit.ARView, surface.accessibilityIdentifier == "seedCucumber.3D.canvas" {
            return surface
        }
        return view.subviews.lazy.compactMap { self.cucumberSurface(in: $0) }.first
    }

    private func releaseCampusRenderers(in view: UIView) {
        if let canvas = view as? CampusMapCanvas {
            canvas.removeRenderer()
            XCTAssertNil(canvas.map, "The owned summary renderer must be released before the next capture")
        }
        for child in view.subviews { releaseCampusRenderers(in: child) }
    }

    private func assertNonemptyRender(_ data: Data, size: CGSize) throws {
        let context = try renderedBitmap(data, size: size)
        let bytes = try XCTUnwrap(context.data).bindMemory(to: UInt8.self, capacity: context.width * context.height * 4)
        var colors = Set<UInt32>()
        for y in stride(from: 0, to: context.height, by: 8) {
            for x in stride(from: 0, to: context.width, by: 8) {
                let offset = (y * context.width + x) * 4
                colors.insert(UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16
                    | UInt32(bytes[offset + 2]) << 8 | UInt32(bytes[offset + 3]))
            }
        }
        XCTAssertGreaterThan(colors.count, 8, "A blank or uniform host is not a valid capture of these views")
    }

    private func renderedBitmap(_ data: Data, size: CGSize) throws -> CGContext {
        let image = try XCTUnwrap(UIImage(data: data)?.cgImage)
        XCTAssertEqual(image.width, Int(size.width))
        XCTAssertEqual(image.height, Int(size.height))
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return context
    }

    private func isolatedDefaults() throws -> (name: String, defaults: UserDefaults) {
        let name = "OiFigmaFidelityVisualTests.\(UUID().uuidString)"
        return (name, try XCTUnwrap(UserDefaults(suiteName: name)))
    }

    private static var draft: OiStoryDraft {
        var draft = OiStoryDraft()
        draft.title = "시각 검증용 이야기"
        draft.body = "함께한 순간을 캠퍼스에 남기는 화면 검증용 문장입니다. 이 자료는 테스트에만 사용되며 서버로 제출하지 않습니다."
        draft.theme = "우정"
        draft.emotion = "고마움"
        draft.cucumberName = "검증용오이"
        return draft
    }

    private static var customization: OiDraftCustomization {
        var customization = OiDraftCustomization()
        customization.fill = .gradient
        customization.firstColor = 0xD3DBC4
        customization.secondColor = 0xF3F7E6
        return customization
    }

    private static var card: MYCard {
        MYCard(id: "figma132-visual-fixture", title: draft.cucumberName, image: "OiCats", school: .postech,
            order: 0, body: draft.body, donor: "검증용 농부", date: "2026.11.03")
    }
}

private struct PostcardBackdropLiveFixture: View {
    @State var draft: OiStoryDraft
    @State var customization: OiDraftCustomization
    let changed: (OiDraftCustomization) -> Void
    var body: some View {
        VStack(spacing: 0) {
            OiCreationProgressHeader(step: 4, onPrevious: {}).padding(.horizontal, 20).padding(.bottom, 8)
            OiCardCustomizationStep(draft: $draft, customization: $customization,
                donorName: "가상 작성자", onContinue: {}).tabForTest("배경")
        }.background(.white)
            .onChange(of: customization) { _, value in changed(value) }
    }
}

private struct PostcardBackLogoLiveFixture: View {
    @State var draft: OiStoryDraft
    @State var customization: OiDraftCustomization
    let changed: (UInt32?) -> Void
    var body: some View {
        VStack(spacing: 0) {
            OiCreationProgressHeader(step: 4, onPrevious: {}).padding(.horizontal, 20).padding(.bottom, 8)
            OiCardCustomizationStep(draft: $draft, customization: $customization,
                donorName: "가상 작성자", onContinue: {}).tabForTest("로고", back: true)
        }.background(.white)
            .onChange(of: customization) { _, value in changed(value.card?.postcardBackground?.backLogoColor) }
    }
}

private struct CreationCapturePage<Content: View>: View {
    let step: Int
    var anchor: UnitPoint = .top
    var showsNavigation = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            OiCreationProgressHeader(step: step, onPrevious: {})
                .padding(.horizontal, 20).padding(.top, 1).padding(.bottom, 29)
            Group {
                if step == 3 || step == 4 { content() }
                else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) { content() }
                            .padding(.horizontal, 20).padding(.bottom, 24)
                    }.defaultScrollAnchor(anchor)
                }
            }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if step == 2 || showsNavigation {
                        OiCreationNavigationBar(onPrevious: {}, onNext: {}, onSaveAndExit: {})
                    }
                }
        }.background(Color(.systemBackground))
    }
}
