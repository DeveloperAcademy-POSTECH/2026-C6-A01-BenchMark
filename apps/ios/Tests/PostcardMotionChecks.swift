//
//  PostcardMotionChecks.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/18/26.
//

import Darwin
import simd
import SwiftUI
import UIKit

private struct CheckFailure: Error { let message: String }

private struct MotionEnvironmentProbe: View {
    @Environment(\.dynamicTypeSize) private var size
    @State private var identity = UUID()
    let onRead: (DynamicTypeSize, UUID) -> Void

    var body: some View {
        Color.clear
            .onAppear { onRead(size, identity) }
            .onChange(of: size) { _, value in onRead(value, identity) }
    }
}

private struct MotionEnvironmentFixture: View {
    let size: DynamicTypeSize
    let isEnabled: Bool
    let onRead: (DynamicTypeSize, UUID) -> Void

    var body: some View {
        ScratchPostcardMotionEffect(isEnabled: isEnabled) {
            MotionEnvironmentProbe(onRead: onRead)
        }
        .frame(width: 100, height: 100)
        .environment(\.dynamicTypeSize, size)
    }
}

@main struct PostcardMotionChecks {
    @MainActor static func main() {
        UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(PostcardMotionChecksDelegate.self))
    }

    @MainActor static func run(window: UIWindow) async throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try checkFilter()
        try checkMotionEffects(window: window)
        try await checkEnvironmentAndIdentity(window: window)
        guard let fixture = UIImage(named: "AppClipStoryCardPreview.png") else {
            throw CheckFailure(message: "Missing existing card fixture")
        }
        for width: CGFloat in [320, 402, 440] {
            try await render(fixture: fixture, width: width, angle: 0, tilted: false, window: window, into: directory)
            try await render(fixture: fixture, width: width, angle: 0, tilted: true, window: window, into: directory)
        }
        try await render(fixture: fixture, width: 402, angle: 180, tilted: true, window: window, into: directory)
        try require(window.rootViewController?.view.subviews.isEmpty == true, "Test views must be removed after rendering")
        try "PASS".write(to: directory.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
        print("PASS: relative quaternion baseline, shortest rotation, smoothing, limits, reset, invalid/stale samples, orientation; UIKit install/remove/detach/dismantle, SwiftUI environment/state identity and seven deterministic card renders")
    }

    @MainActor private static func checkEnvironmentAndIdentity(window: UIWindow) async throws {
        guard let root = window.rootViewController else { throw CheckFailure(message: "Missing test root") }
        var readings: [(DynamicTypeSize, UUID)] = []
        let read: (DynamicTypeSize, UUID) -> Void = { readings.append(($0, $1)) }
        let controller = UIHostingController(rootView: MotionEnvironmentFixture(size: .accessibility2, isEnabled: false, onRead: read))
        root.addChild(controller)
        root.view.addSubview(controller.view)
        controller.didMove(toParent: root)
        controller.view.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        controller.view.layoutIfNeeded()
        defer {
            controller.willMove(toParent: nil)
            controller.view.removeFromSuperview()
            controller.removeFromParent()
        }
        try await Task.sleep(for: .milliseconds(150))
        guard let first = readings.last else { throw CheckFailure(message: "Environment probe never appeared") }
        try require(first.0 == .accessibility2, "Nested motion host must receive the caller's Dynamic Type override")
        controller.rootView = MotionEnvironmentFixture(size: .large, isEnabled: true, onRead: read)
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        guard let updated = readings.last else { throw CheckFailure(message: "Environment probe did not update") }
        try require(updated.0 == .large, "Caller environment changes must cross the motion host boundary")
        try require(updated.1 == first.1, "Updating the environment and motion state must preserve the card's SwiftUI identity")
        controller.rootView = MotionEnvironmentFixture(size: .accessibility2, isEnabled: false, onRead: read)
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        try require(readings.last?.0 == .accessibility2 && readings.last?.1 == first.1,
                    "Pausing motion must preserve state while restoring the caller's accessibility override")
        print("PASS: nested UIKit motion host propagates caller Dynamic Type and preserves SwiftUI state across enable/disable updates")
    }

    @MainActor private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw CheckFailure(message: message) }
    }

    @MainActor private static func quaternion(_ degrees: Double, axis: SIMD3<Double> = SIMD3(1, 0, 0)) -> SIMD4<Double> {
        simd_quatd(angle: degrees * .pi / 180, axis: axis).vector
    }

    @MainActor private static func checkFilter() throws {
        var filter = OiPostcardMotionFilter()
        let baseline = simd_quatd(vector: quaternion(50))
        try require(filter.update(quaternion: baseline.vector, timestamp: 1) == .zero, "Initial holding pose must be neutral")
        let moved = baseline * simd_quatd(vector: quaternion(5))
        guard let relative = filter.update(quaternion: moved.vector, timestamp: 2) else {
            throw CheckFailure(message: "Valid relative sample rejected")
        }
        try require(relative.x > 0.99 && relative.x <= 1 && abs(relative.y) < 0.000001, "Rotation must be relative to the holding pose")
        try require(filter.update(quaternion: quaternion(-90), timestamp: 2) == relative, "Duplicate timestamps must not move the card")
        try require(filter.update(quaternion: quaternion(-90), timestamp: 1.5) == relative, "Out-of-order samples must not move the card")
        for sample in [SIMD4<Double>.zero, SIMD4(.nan, 0, 0, 1), SIMD4(.infinity, 0, 0, 1)] {
            try require(filter.update(quaternion: sample, timestamp: 3) == nil, "Invalid quaternion must be rejected")
        }
        try require(filter.update(quaternion: moved.vector, timestamp: .nan) == nil, "Invalid timestamp must be rejected")
        filter.reset()
        try require(filter.tilt == .zero, "Stopping must clear filtered tilt")
        try require(filter.update(quaternion: quaternion(179), timestamp: 10) == .zero, "Restart must recenter")
        guard let wrapped = filter.update(quaternion: quaternion(-179), timestamp: 11) else {
            throw CheckFailure(message: "Wrapped attitude rejected")
        }
        try require(wrapped.x > 0.39 && wrapped.x < 0.41, "179 to -179 degrees must take the short rotation")
        filter.reset()
        _ = filter.update(quaternion: quaternion(0), timestamp: 0)
        let signEquivalent = -quaternion(0)
        try require(filter.update(quaternion: signEquivalent, timestamp: 1) == .zero, "Opposite quaternion signs represent the same attitude")
        for index in 2...20 {
            guard let tilt = filter.update(quaternion: quaternion(index.isMultiple(of: 2) ? 120 : -120,
                axis: simd_normalize(SIMD3(1, 1, 0))), timestamp: Double(index)) else {
                throw CheckFailure(message: "Bounded sample rejected")
            }
            try require(abs(tilt.x) <= 4 && abs(tilt.y) <= 4, "Tilt must stay within four degrees")
        }
        var oneStep = OiPostcardMotionFilter(), fourSteps = OiPostcardMotionFilter()
        _ = oneStep.update(quaternion: quaternion(0), timestamp: 0)
        _ = fourSteps.update(quaternion: quaternion(0), timestamp: 0)
        _ = oneStep.update(quaternion: quaternion(5), timestamp: 0.12)
        for index in 1...4 { _ = fourSteps.update(quaternion: quaternion(5), timestamp: Double(index) * 0.03) }
        try require(abs(oneStep.tilt.x - fourSteps.tilt.x) < 0.000001, "Smoothing must be based on elapsed time, not callback count")
        let pose = OiPostcardTilt(x: 1, y: 2)
        try require(pose.oriented(for: .portrait) == pose, "Portrait orientation")
        try require(pose.oriented(for: .portraitUpsideDown) == OiPostcardTilt(x: -1, y: -2), "Upside-down orientation")
        try require(pose.oriented(for: .landscapeLeft) == OiPostcardTilt(x: -2, y: 1), "Landscape-left orientation")
        try require(pose.oriented(for: .landscapeRight) == OiPostcardTilt(x: 2, y: -1), "Landscape-right orientation")
        try require(pose.oriented(for: .unknown) == .zero, "Unknown scene orientation must be static")
    }

    @MainActor private static func checkMotionEffects(window: UIWindow) throws {
        guard let container = window.rootViewController?.view else { throw CheckFailure(message: "Missing test window") }
        let motion = ScratchPostcardMotionEffectView()
        let flip = UIView()
        flip.layer.transform = CATransform3DMakeRotation(.pi / 4, 0, 1, 0)
        let originalFlip = flip.layer.transform
        motion.addSubview(flip)
        motion.setMotionEnabled(true)
        try require(motion.motionEffects.isEmpty, "Detached views must not subscribe")
        container.addSubview(motion)
        defer { motion.stopMotionEffects(); motion.removeFromSuperview() }
        guard let group = motion.motionEffects.first as? UIMotionEffectGroup else {
            throw CheckFailure(message: "Attached enabled view must install a group")
        }
        for _ in 0..<20 { motion.setMotionEnabled(true) }
        try require(motion.motionEffects.count == 1 && motion.motionEffects.first === group, "Updates must reuse one effect group")
        try require(group.motionEffects?.count == 2, "Both tilt axes must be configured")
        for effect in group.motionEffects ?? [] {
            _ = try endpointValues(effect, offset: UIOffset(horizontal: 1, vertical: 1))
            _ = try endpointValues(effect, offset: UIOffset(horizontal: -1, vertical: -1))
        }
        motion.setMotionEnabled(false)
        try require(motion.motionEffects.isEmpty && CATransform3DIsIdentity(motion.layer.transform), "Disabling must remove effects and reset the outer transform")
        try require(CATransform3DEqualToTransform(flip.layer.transform, originalFlip), "Disabling tilt must preserve the inner flip transform")
        motion.setMotionEnabled(true)
        motion.removeFromSuperview()
        try require(motion.motionEffects.isEmpty && CATransform3DIsIdentity(motion.layer.transform), "Window detach must stop motion")
        container.addSubview(motion)
        try require(motion.motionEffects.count == 1, "Reattachment may install only one group")
        motion.stopMotionEffects()
        motion.removeFromSuperview(); container.addSubview(motion)
        try require(motion.motionEffects.isEmpty, "Explicit stop must not restart on reattachment")
        let controller = ScratchPostcardMotionEffectController(content: EmptyView(), isEnabled: true)
        container.addSubview(controller.view)
        try require(controller.motionView.motionEffects.count == 1, "Representable controller must install effects")
        ScratchPostcardMotionEffect<EmptyView>.dismantleUIViewController(controller, coordinator: ())
        try require(controller.motionView.motionEffects.isEmpty && CATransform3DIsIdentity(controller.motionView.layer.transform),
                    "Representable teardown must release effects")
        controller.view.removeFromSuperview()
    }

    @MainActor private static func endpointValues(_ effect: UIMotionEffect, offset: UIOffset) throws -> [String: Any] {
        guard let interpolator = effect as? UIInterpolatingMotionEffect,
              let minimum = interpolator.minimumRelativeValue as? NSNumber,
              let maximum = interpolator.maximumRelativeValue as? NSNumber else {
            throw CheckFailure(message: "Missing configured interpolator")
        }
        let values = effect.keyPathsAndRelativeValues(forViewerOffset: offset) ?? [:]
        try require(values.count == 1, "Each interpolator must change only its own axis")
        let position = interpolator.type == .tiltAlongHorizontalAxis ? offset.horizontal : offset.vertical
        let expected = position > 0 ? maximum.doubleValue : minimum.doubleValue
        guard let value = values[interpolator.keyPath] as? NSNumber else {
            throw CheckFailure(message: "Missing numeric rotation for \(interpolator.keyPath)")
        }
        try require(abs(expected) > 0.06 && abs(value.doubleValue - expected) < 0.000001,
                    "Interpolator endpoint must be nonzero with configured sign/magnitude: \(interpolator.keyPath), actual \(value), expected \(expected)")
        return values
    }

    /// Applies the official interpolator's deterministic output, not synthetic sensor readings.
    @MainActor private static func render(fixture: UIImage, width: CGFloat, angle: Double, tilted: Bool,
                                         window: UIWindow, into directory: URL) async throws {
        guard let root = window.rootViewController else { throw CheckFailure(message: "Missing test root") }
        let card = FlipCard(angle: angle) {
            Image(uiImage: fixture).resizable().scaledToFit()
        } back: {
            Color(red: 0.70, green: 0.79, blue: 0.54).overlay { Text("뒤집기 검증").foregroundStyle(.black) }
        }
        let controller = ScratchPostcardMotionEffectController(content: card, isEnabled: true)
        root.addChild(controller)
        root.view.addSubview(controller.view)
        controller.didMove(toParent: root)
        defer {
            controller.stopMotionEffects()
            controller.willMove(toParent: nil)
            controller.view.removeFromSuperview()
            controller.removeFromParent()
        }
        let group = controller.motionView.motionEffects.first as? UIMotionEffectGroup
        controller.update(content: card, isEnabled: false)
        let cardWidth = min(292, width - 40)
        controller.view.frame = CGRect(x: (width - cardWidth) / 2, y: 24, width: cardWidth, height: cardWidth * 502 / 362)
        root.view.frame = CGRect(x: 0, y: 0, width: width, height: 454)
        root.view.backgroundColor = UIColor(white: 0.94, alpha: 1)
        controller.view.layoutIfNeeded()
        // Removing UIMotionEffect and hosting the card both schedule layout/presentation work.
        // Let that settle before applying the deterministic endpoint transform.
        try await Task.sleep(for: .milliseconds(200))
        root.view.layoutIfNeeded()
        if tilted {
            guard let group else { throw CheckFailure(message: "Missing interpolator for deterministic render") }
            var perspective = CATransform3DIdentity
            perspective.m34 = ScratchPostcardMotionEffectView.perspective
            controller.motionView.layer.transform = perspective
            for effect in group.motionEffects ?? [] {
                for (key, value) in try endpointValues(effect, offset: UIOffset(horizontal: 1, vertical: -1)) {
                    controller.motionView.setValue(value, forKeyPath: key)
                }
            }
            try require(abs(controller.motionView.layer.transform.m13) > 0.03
                && abs(controller.motionView.layer.transform.m23) > 0.03, "Tilt must reach the actual outer layer transform")
        }
        CATransaction.flush()
        try await Task.sleep(for: .milliseconds(100))
        if tilted {
            try require(abs(controller.motionView.layer.transform.m13) > 0.03
                && abs(controller.motionView.layer.transform.m23) > 0.03, "Pending UIKit updates must not overwrite deterministic tilt")
        }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        var rendered = false
        let image = UIGraphicsImageRenderer(size: root.view.bounds.size, format: format).image { context in
            rendered = root.view.drawHierarchy(in: root.view.bounds, afterScreenUpdates: true)
        }
        try require(rendered, "UIKit must finish drawing the transformed hierarchy")
        guard let png = image.pngData(), png.count > 2_000 else { throw CheckFailure(message: "Empty card render") }
        let name = "card-\(Int(width))-\(angle == 180 ? "back" : "front")-\(tilted ? "tilted" : "static").png"
        if tilted && angle == 0 {
            guard let reference = UIImage(contentsOfFile: directory.appendingPathComponent("card-\(Int(width))-front-static.png").path) else {
                throw CheckFailure(message: "Missing static comparison")
            }
            let changed = try changedPixels(image, reference)
            try require(changed > 500, "Tilted card must visibly differ from static card; changed pixels: \(changed)")
            print("PASS: \(Int(width))pt deterministic tilted card changes \(changed) pixels")
        }
        try png.write(to: directory.appendingPathComponent(name))
    }

    @MainActor private static func changedPixels(_ lhs: UIImage, _ rhs: UIImage) throws -> Int {
        guard let left = lhs.cgImage, let right = rhs.cgImage,
              left.width == right.width, left.height == right.height else {
            throw CheckFailure(message: "Comparison images must have matching dimensions")
        }
        func pixels(_ image: CGImage) throws -> [UInt8] {
            var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
            try bytes.withUnsafeMutableBytes { storage in
                guard let context = CGContext(data: storage.baseAddress, width: image.width, height: image.height,
                    bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                    throw CheckFailure(message: "Cannot decode comparison pixels")
                }
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            }
            return bytes
        }
        let a = try pixels(left), b = try pixels(right)
        return stride(from: 0, to: a.count, by: 4).reduce(0) { count, offset in
            let difference = (0..<3).map { abs(Int(a[offset + $0]) - Int(b[offset + $0])) }.max() ?? 0
            return count + (difference > 16 ? 1 : 0)
        }
    }
}

@MainActor final class PostcardMotionChecksDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Checks", sessionRole: session.role)
        configuration.delegateClass = PostcardMotionChecksScene.self
        return configuration
    }
}

@MainActor final class PostcardMotionChecksScene: NSObject, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIViewController()
        self.window = window
        window.makeKeyAndVisible()
        Task {
            do { try await PostcardMotionChecks.run(window: window); exit(0) }
            catch { print("FAIL: \(error)"); exit(1) }
        }
    }
}
