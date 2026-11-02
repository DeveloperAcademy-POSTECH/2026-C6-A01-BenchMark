// Created by 이돈혁

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
            for name in ["PearToucan-Regular", "Paperlogy-7Bold"] {
                if let url = Bundle.main.url(forResource: name, withExtension: "ttf") {
                    CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
                }
            }
            checkNormalization()
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
