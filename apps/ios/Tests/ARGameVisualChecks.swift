//
//  ARGameVisualChecks.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/2/26.
//

import CoreText
import SwiftUI
import UIKit

@main
final class ARGameVisualChecks: UIResponder, UIApplicationDelegate {
    static func main() { UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(Self.self)) }

    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "ARGameChecks", sessionRole: session.role)
        configuration.delegateClass = ARGameVisualScene.self
        return configuration
    }
}

private final class ARGameVisualScene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { preconditionFailure("Missing test scene") }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        self.window = window
        Task { await run() }
    }

    private func run() async {
        do {
            let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let fontNames = ["Paperlogy-2ExtraLight", "Paperlogy-3Light", "Paperlogy-4Regular",
                             "Paperlogy-6SemiBold", "Paperlogy-7Bold"]
            for name in fontNames {
                guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else {
                    preconditionFailure("Missing packaged font: \(name)")
                }
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
            for name in fontNames {
                precondition(UIFont(name: name, size: 20)?.fontName == name, "Packaged font must resolve without fallback: \(name)")
            }
            for name in ["OiStoryCardFrame", "OiStoryCardHeader", "OiStoryCardTexture", "OiStoryCardCats", "OiStoryCardMark"] {
                precondition(UIImage(named: name) != nil, "Generated story cards need the packaged design asset: \(name)")
            }
            checkNormalization()
            try await AppClipPublicStoryChecks.run()
            let fallback = await CucumberArtwork.load(imageURL: nil)
            for name in ["61272", "0e35d", "9ac42", "aeb3a"] {
                guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
                      let artwork = await CucumberArtwork.load(imageURL: url) else {
                    preconditionFailure("Packaged story character must load")
                }
                precondition(artwork !== fallback, "A selected preset must not silently become the space-cucumber fallback")
            }
            print("Reduce Motion: \(UIAccessibility.isReduceMotionEnabled)")
            let sizes: [(String, CGSize)] = [
                ("402x874", CGSize(width: 402, height: 874)),
                ("375x667", CGSize(width: 375, height: 667)),
                ("440x956", CGSize(width: 440, height: 956))
            ]
            for (name, size) in sizes {
                try await snapshot(intro, size: size, output: output.appendingPathComponent("intro-\(name).png"), delay: 0.2)
                try await snapshot(ARGameFailureView(onRetry: {}), size: size, output: output.appendingPathComponent("failure-\(name).png"), delay: UIAccessibility.isReduceMotionEnabled ? 0.03 : 1.9)
                try checkFailureSnapshot(output.appendingPathComponent("failure-\(name).png"), size: size)
            }
            for seconds in [30, 9] {
                try await snapshot(ZStack {
                    Color.gray
                    ARGameHUD(remainingSeconds: seconds, collectedCount: 1, targetCount: 3, cucumberImageURL: nil)
                }.ignoresSafeArea(), size: sizes[0].1,
                   output: output.appendingPathComponent("hud-\(seconds).png"), delay: 0.2)
            }
            try await snapshot(intro.environment(\.dynamicTypeSize, .accessibility5), size: sizes[0].1,
                               output: output.appendingPathComponent("intro-accessibility5.png"), delay: 0.2)
            try await snapshot(ARGameFailureView(onRetry: {}).environment(\.dynamicTypeSize, .accessibility5),
                               size: sizes[0].1, output: output.appendingPathComponent("failure-accessibility5.png"),
                               delay: UIAccessibility.isReduceMotionEnabled ? 0.3 : 1.9)
            try checkFailureSnapshot(output.appendingPathComponent("failure-accessibility5.png"), size: sizes[0].1)
            try await snapshot(intro.environment(\.dynamicTypeSize, .accessibility5).defaultScrollAnchor(.bottom),
                               size: sizes[0].1, output: output.appendingPathComponent("intro-accessibility5-bottom.png"), delay: 0.2)
            try await snapshot(ARGameSuccessView(onFinished: {}), size: sizes[0].1,
                               output: output.appendingPathComponent("success.png"), delay: 1)
            try await snapshot(ZStack {
                Color.gray
                ARGameHUD(remainingSeconds: 30, collectedCount: 0, targetCount: 3, cucumberImageURL: nil)
                ARGameStartOverlay(onFinished: {})
            }.ignoresSafeArea(), size: sizes[0].1,
                               output: output.appendingPathComponent("start-assembled.png"), delay: UIAccessibility.isReduceMotionEnabled ? 0.1 : 0.82)
            try await snapshot(ARGameFailureView(onRetry: {}), size: sizes[0].1,
                               output: output.appendingPathComponent("failure-midpoint.png"), delay: 0.6)
            for scheme: ColorScheme in [.light, .dark] {
                let suffix = scheme == .dark ? "dark" : "light"
                for (name, size) in sizes {
                    try await snapshot(storyCard(hasImage: true).preferredColorScheme(scheme), size: size,
                                       output: output.appendingPathComponent("story-card-\(name)-\(suffix).png"), delay: 0.3)
                    if name == "402x874" { try checkStoryCardSnapshot(output.appendingPathComponent("story-card-\(name)-\(suffix).png")) }
                }
                try await snapshot(storyCard(hasImage: false).preferredColorScheme(scheme), size: sizes[0].1,
                                   output: output.appendingPathComponent("story-card-no-image-\(suffix).png"), delay: 0.3)
                try checkStoryCardSnapshot(output.appendingPathComponent("story-card-no-image-\(suffix).png"))
            }
            try await snapshot(storyCard(hasImage: false, hasCharacter: false).preferredColorScheme(.light),
                               size: sizes[0].1, output: output.appendingPathComponent("story-card-no-character.png"), delay: 0.3)
            try checkGeneratedCardCharacter(
                output.appendingPathComponent("story-card-no-image-light.png"),
                placeholder: output.appendingPathComponent("story-card-no-character.png")
            )
            try await snapshot(storyCard(hasImage: false, imageURL: URL(fileURLWithPath: "/missing-card-image.png")),
                               size: sizes[0].1, output: output.appendingPathComponent("story-card-file-error.png"), delay: 0.3)
            try await snapshot(storyCard(hasImage: true).environment(\.dynamicTypeSize, .accessibility5)
                               .defaultScrollAnchor(.bottom), size: sizes[0].1,
                               output: output.appendingPathComponent("story-card-accessibility5-bottom.png"), delay: 0.3)
            try await snapshot(storyCard(hasImage: true).environment(\.dynamicTypeSize, .xxxLarge)
                               .defaultScrollAnchor(.bottom), size: sizes[0].1,
                               output: output.appendingPathComponent("story-card-xxxlarge-bottom.png"), delay: 0.3)
            try "PASS\n".write(to: output.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
            print("PASS: transparent-image normalization and AR game visual captures")
            exit(0)
        } catch {
            print("FAIL: \(error)")
            exit(1)
        }
    }

    private var intro: some View {
        ARGameIntroView(cucumberName: "화성갈끄니까오이", cucumberImageURL: nil,
                        targetCount: 3, timeLimitSeconds: 30, onBack: {}, onStart: {})
    }

    private func storyCard(hasImage: Bool, imageURL: URL? = nil, hasCharacter: Bool = true) -> some View {
        guard let cucumberImageURL = Bundle.main.url(forResource: "61272", withExtension: "png") else {
            preconditionFailure("Missing actual packaged story character fixture")
        }
        let story = Story(storyID: "visual-story", donorID: UUID(), donorDisplayName: "20학번 디벨로퍼학과 신예은",
                          title: "화성갈끄니까오이", content: "검증용 이야기", publishedAt: Date(timeIntervalSince1970: 1_792_724_400),
                          location: StoryLocation(locationID: "visual-location", displayName: "포항공과대학교 지곡회관 옆 연못길"),
                          tags: ["기대감", "미래"], cucumberID: "visual-cucumber", cucumberName: "화성오이",
                          cucumberImageURL: hasCharacter ? cucumberImageURL : nil)
        let card = StoryCard(cardID: "visual-card", storyID: story.storyID,
                             imageURL: imageURL ?? (hasImage ? Bundle.main.url(forResource: "AppClipStoryCardPreview", withExtension: "png") : nil))
        return AppClipStoryCardView(experience: AppClipExperience(story: story, storyCard: card),
                                   isCollected: false, onCollect: {}, onCancel: {})
    }

    private func snapshot<V: View>(_ view: V, size: CGSize, output: URL, delay: Double) async throws {
        guard let root = window?.rootViewController else { preconditionFailure("Missing task window") }
        let host = UIHostingController(rootView: view)
        root.addChild(host)
        host.view.frame = CGRect(origin: .zero, size: size)
        root.view.addSubview(host.view)
        host.didMove(toParent: root)
        defer {
            host.willMove(toParent: nil)
            host.view.removeFromSuperview()
            host.removeFromParent()
        }
        try await Task.sleep(for: .seconds(delay))
        host.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let png = renderer.pngData { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
        try png.write(to: output)
    }

    private func checkStoryCardSnapshot(_ url: URL) throws {
        guard let image = UIImage(data: try Data(contentsOf: url))?.cgImage,
              let context = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let bytes = context.data else { preconditionFailure("Missing story card capture") }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pixels = bytes.bindMemory(to: UInt8.self, capacity: image.width * image.height * 4)
        if url.lastPathComponent.hasPrefix("story-card-no-image-") {
            // The generated card rounds in from (41, 104), so its extreme corner should show the page.
            let corner = (105 * image.width + 42) * 4
            let background = (105 * image.width + 30) * 4
            precondition((0..<3).allSatisfy { abs(Int(pixels[corner + $0]) - Int(pixels[background + $0])) <= 8 },
                         "The generated card must not paint a square backing behind its rounded artwork")
        }
        var colorPixels = 0
        for y in 104..<548 {
            for x in 41..<361 {
                let i = (y * image.width + x) * 4
                let channels = [pixels[i], pixels[i + 1], pixels[i + 2]]
                if Int(channels.max() ?? 0) - Int(channels.min() ?? 0) > 30 { colorPixels += 1 }
            }
        }
        precondition(colorPixels > 10_000, "The actual card artwork must render; a text block must fail this regression check")
    }

    private func checkNormalization() {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 120), format: format).image { context in
            UIColor.green.setFill()
            context.fill(CGRect(x: 20, y: 30, width: 40, height: 60))
        }
        let trimmed = CucumberArtwork.normalized(image)
        precondition(trimmed?.size == CGSize(width: 40, height: 60), "Transparent padding must be removed exactly")
        let repeated = trimmed.flatMap(CucumberArtwork.normalized)
        precondition(repeated?.size == trimmed?.size, "Normalization must be idempotent")
        let empty = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10), format: format).image { _ in }
        precondition(CucumberArtwork.normalized(empty) == nil, "Empty artwork must not become an invisible collectible")
    }

    private func checkGeneratedCardCharacter(_ url: URL, placeholder: URL) throws {
        func pixels(at url: URL) throws -> [UInt8] {
            guard let image = UIImage(data: try Data(contentsOf: url))?.cgImage,
                  image.width == 402, image.height == 874,
                  let context = CGContext(data: nil, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                  let bytes = context.data else { preconditionFailure("Missing generated card capture") }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return Array(UnsafeBufferPointer(start: bytes.bindMemory(to: UInt8.self, capacity: image.width * image.height * 4),
                                             count: image.width * image.height * 4))
        }
        let artworkPixels = try pixels(at: url)
        let placeholderPixels = try pixels(at: placeholder)
        var changedPixels = 0
        // Exclude the summary and compare only the printed card's character region.
        for y in 150..<520 {
            for x in 65..<337 {
                let index = (y * 402 + x) * 4
                let difference = (0..<3).reduce(0) {
                    $0 + abs(Int(artworkPixels[index + $1]) - Int(placeholderPixels[index + $1]))
                }
                if difference > 60 { changedPixels += 1 }
            }
        }
        precondition(changedPixels > 5_000,
                     "A card without a full-card URL must render the story's character, not the missing-character placeholder")
    }

    private func checkFailureSnapshot(_ url: URL, size: CGSize) throws {
        guard let image = UIImage(data: try Data(contentsOf: url))?.cgImage,
              let context = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let bytes = context.data else { preconditionFailure("Missing capture") }
        context.draw(image, in: CGRect(origin: .zero, size: size))
        let pixels = bytes.bindMemory(to: UInt8.self, capacity: image.width * image.height * 4)
        var minX = image.width, minY = image.height, maxX = 0, maxY = 0
        for y in 0..<Int(size.height * 0.75) {
            for x in 0..<image.width where pixels[(y * image.width + x) * 4] > 240 {
                minX = min(minX, x); minY = min(minY, y)
                maxX = max(maxX, x + 1); maxY = max(maxY, y + 1)
            }
        }
        let scale = min(size.width / 402, size.height / 874)
        let expectedX = (size.width - 402 * scale) / 2 + 128.517578 * scale
        let expectedY = (size.height - 874 * scale) / 2 + 405.2 * scale
        precondition(abs(Double(minX) - expectedX) < 2 && abs(Double(minY) - expectedY) < 2,
                     "Final failure glyph origin must match Figma")
        precondition(abs(Double(maxX - minX) - 143.376564 * scale) < 3 && abs(Double(maxY - minY) - 62.64 * scale) < 3,
                     "Final failure glyph extent must match Figma")
        let buttonX = Int(size.width / 2 - 100)
        let buttonY = Int(size.height - 68 - 35)
        precondition(pixels[(buttonY * image.width + buttonX) * 4] > 240,
                     "Retry button must appear at the fixed 68pt bottom inset")
    }
}
