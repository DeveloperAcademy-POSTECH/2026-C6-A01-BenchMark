// Created by 이돈혁

import ImageIO
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Darwin

// The isolated simulator app provides UIKit scenes for real SwiftUI control rendering.
@main struct CollageImageChecks {
    @MainActor static func main() {
        UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(CollageChecksDelegate.self))
    }

    @MainActor static func run() async throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let loader = CollageImageLoader()
        let sizes = [CGSize(width: 900, height: 1200), CGSize(width: 1200, height: 600),
                     CGSize(width: 800, height: 800), CGSize(width: 600, height: 1000)]
        let colors: [UIColor] = [.systemRed, .systemBlue, .systemOrange, .systemGreen]
        let photos = zip(sizes.indices, sizes).map { index, size in
            CollagePhoto(image: fixture(size: size, color: colors[index], number: index + 1))
        }
        for count in 1...4 {
            let selection = Array(photos.prefix(count))
            let arrangement = CollageArrangement.automatic(aspectRatios: selection.map { $0.image!.size.width / $0.image!.size.height })!
            let image = try CollageRenderer.render(photos: selection, arrangement: arrangement, cropped: false)
            assert(max(image.size.width, image.size.height) == 2048)
            try image.pngData()!.write(to: directory.appendingPathComponent("automatic-\(count).png"))
        }
        for template in CollageTemplate.allCases {
            let arrangement = CollageArrangement(aspectRatio: 9 / 16, frames: template.frames)
            let selection = Array(photos.prefix(template.frames.count))
            let image = try CollageRenderer.render(photos: selection, arrangement: arrangement, cropped: true)
            assert(image.size == CGSize(width: 1152, height: 2048))
            try image.pngData()!.write(to: directory.appendingPathComponent("layout-\(template.rawValue).png"))
        }
        do {
            _ = try await loader.decode(Data([0, 1, 2]))
            assertionFailure("Corrupt image must fail")
        } catch CollageImageError.unreadable { }
        do {
            _ = try CollageRenderer.render(photos: [CollagePhoto()],
                arrangement: CollageArrangement(aspectRatio: 1, frames: [CGRect(x: 0, y: 0, width: 1, height: 1)]), cropped: true)
            assertionFailure("Empty slot must fail")
        } catch CollageImageError.incomplete { }

        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, photos[1].image!.cgImage!, [kCGImagePropertyOrientation: 6] as CFDictionary)
        assert(CGImageDestinationFinalize(destination))
        let rotated = try await loader.decode(data as Data)
        assert(rotated.imageOrientation == .up && rotated.size.width < rotated.size.height)
        try rotated.pngData()!.write(to: directory.appendingPathComponent("orientation-normalized.png"))

        let large = fixture(size: CGSize(width: 3000, height: 600), color: .purple, number: 5)
        let downsampled = try await loader.decode(large.pngData()!)
        assert(max(downsampled.size.width, downsampled.size.height) <= 2048)
        for width: CGFloat in [320, 393, 440] {
            try await snapshot(NavigationStack { PhotoTestView() }, width: width, height: 700, name: "menu-\(Int(width))", into: directory)
        }
        try await snapshot(NavigationStack { PhotoTestView() }.environment(\.dynamicTypeSize, .accessibility3),
                     width: 320, height: 900, name: "menu-accessibility", into: directory)
        try await snapshot(NavigationStack { PhotoCollageEditor(manual: true) }, width: 393, height: 1000, name: "editor-layout", into: directory)
        try await snapshot(NavigationStack { PhotoCollageEditor(manual: false) }, width: 320, height: 800, name: "editor-automatic", into: directory)
        try await snapshot(NavigationStack { PhotoCollageEditor(manual: true) }.environment(\.dynamicTypeSize, .accessibility3),
                           width: 320, height: 900, name: "editor-accessibility", into: directory)
        let arrangement = CollageArrangement(aspectRatio: 4 / 5, frames: CollageTemplate.grid.frames)
        try await snapshot(CollageCanvas(photos: .constant(photos), arrangement: arrangement, manual: true,
                                   selectedSlot: 0, onSelect: { _, _ in }),
                     width: 393, height: 500, name: "canvas-filled", into: directory)
        print("PASS: 1–4 photo exports, six template exports, incomplete/corrupt input, EXIF orientation, downsampling and eight offscreen UI renders")
        try "PASS".write(to: directory.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
    }

    @MainActor private static func fixture(size: CGSize, color: UIColor, number: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setStroke()
            let diameter = min(size.width, size.height) * 0.6
            context.cgContext.setLineWidth(12)
            context.cgContext.strokeEllipse(in: CGRect(x: (size.width - diameter) / 2, y: (size.height - diameter) / 2,
                                                       width: diameter, height: diameter))
            ("\(number)" as NSString).draw(at: CGPoint(x: size.width / 2 - 25, y: size.height / 2 - 45),
                                         withAttributes: [.font: UIFont.systemFont(ofSize: 80), .foregroundColor: UIColor.white])
        }
    }

    @MainActor private static func snapshot<V: View>(_ view: V, width: CGFloat, height: CGFloat, name: String, into directory: URL) async throws {
        let size = CGSize(width: width, height: height)
        let host = UIHostingController(rootView: view.frame(width: width, height: height).background(Color.white))
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { throw CollageImageError.exportFailed }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(400))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            host.view.layer.render(in: context.cgContext)
        }
        guard let data = image.pngData() else { throw CollageImageError.exportFailed }
        let pixelCount = Int(width) * Int(height)
        var pixels = [UInt8](repeating: 255, count: pixelCount * 4)
        guard let context = CGContext(data: &pixels, width: Int(width), height: Int(height), bitsPerComponent: 8,
                                      bytesPerRow: Int(width) * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let cgImage = image.cgImage else {
            throw CollageImageError.exportFailed
        }
        context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        let coloredPixels = (0..<pixelCount).filter { index in
            pixels[index * 4] < 240 || pixels[index * 4 + 1] < 240 || pixels[index * 4 + 2] < 240
        }.count
        assert(coloredPixels > 500, "UI snapshot must contain visible content: \(name)")
        try data.write(to: directory.appendingPathComponent("\(name).png"))
    }
}

@MainActor final class CollageChecksDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Checks", sessionRole: session.role)
        configuration.delegateClass = CollageChecksScene.self
        return configuration
    }
}

@MainActor final class CollageChecksScene: NSObject, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        window = UIWindow(windowScene: scene)
        window?.rootViewController = UIViewController()
        window?.makeKeyAndVisible()
        Task {
            do {
                try await CollageImageChecks.run()
                exit(0)
            } catch {
                print("FAIL: \(error)")
                exit(1)
            }
        }
    }
}
