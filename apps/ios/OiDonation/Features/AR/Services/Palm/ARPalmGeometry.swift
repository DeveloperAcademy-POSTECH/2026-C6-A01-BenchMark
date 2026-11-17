//
//  ARPalmGeometry.swift
//  OiDonation
//
//  Created by Codex on 2026/11/17.
//  Projection and palm geometry adapted from the existing AR palm experiment.
//

import Foundation
import simd
import CoreGraphics

/// Approximate depth from a 7 cm index-to-little MCP span, not a measured hand mesh.
nonisolated enum ARPalmGeometry {
    /// Vision's upright bottom-left points back to sensor UVs, then ARKit's aspect-fill viewport.
    static func viewportPoint(_ vision: SIMD2<Float>, quarterTurns: Int, displayTransform: CGAffineTransform) -> SIMD2<Float> {
        let upright = CGPoint(x: CGFloat(vision.x), y: CGFloat(1 - vision.y))
        let sensor: CGPoint
        switch quarterTurns {
        case 1: sensor = CGPoint(x: upright.y, y: 1 - upright.x)
        case 2: sensor = CGPoint(x: 1 - upright.x, y: 1 - upright.y)
        case 3: sensor = CGPoint(x: 1 - upright.y, y: upright.x)
        default: sensor = upright
        }
        let point = sensor.applying(displayTransform)
        return SIMD2(Float(point.x), Float(point.y))
    }

    /// Put the contact point inside the palm, not near the finger bases.
    static func center(wrist: SIMD2<Float>, knuckles: [SIMD2<Float>]) -> SIMD2<Float> {
        guard !knuckles.isEmpty else { return wrist }
        return (wrist * 2 + knuckles.reduce(.zero, +)) / Float(knuckles.count + 2)
    }

    static func depth(indexDirection: SIMD3<Float>, littleDirection: SIMD3<Float>, forward: SIMD3<Float>, physicalSpan: Float = 0.07) -> Float? {
        let a = simd_dot(indexDirection, forward)
        let b = simd_dot(littleDirection, forward)
        guard a > 0.0001, b > 0.0001 else { return nil }
        let width = simd_distance(indexDirection / a, littleDirection / b)
        let depth = physicalSpan / width
        return depth.isFinite && (0.15...1.5).contains(depth) ? depth : nil
    }

    /// Reproject with the camera that captured the observation, never a later render pose.
    static func contact(origin: SIMD3<Float>, direction: SIMD3<Float>, forward: SIMD3<Float>, depth: Float) -> SIMD3<Float>? {
        let alignment = simd_dot(direction, forward)
        guard alignment.isFinite, alignment > 0.0001, depth.isFinite, (0.15...1.5).contains(depth) else { return nil }
        let point = origin + direction * (depth / alignment)
        return point.x.isFinite && point.y.isFinite && point.z.isFinite ? point : nil
    }
    /// Screen coordinates and camera pose must describe the same captured frame.
    static func ray(point: SIMD2<Float>, inverseProjection: simd_float4x4,
                    cameraToWorld: simd_float4x4) -> SIMD3<Float>? {
        guard point.x.isFinite, point.y.isFinite else { return nil }
        let clip = inverseProjection * SIMD4<Float>(2 * point.x - 1, 1 - 2 * point.y, 1, 1)
        guard clip.z.isFinite, abs(clip.z) > 0.00001 else { return nil }
        let cameraRay = SIMD3(clip.x, clip.y, clip.z) / -clip.z
        let world = cameraToWorld * SIMD4(cameraRay.x, cameraRay.y, cameraRay.z, 0)
        let direction = SIMD3(world.x, world.y, world.z)
        return direction.x.isFinite && direction.y.isFinite && direction.z.isFinite ? direction : nil
    }

    /// Smooth depth against the previous WORLD point seen from this capture pose,
    /// rather than the previous camera's depth. This compensates camera translation.
    static func stabilizedDepth(measured: Float, previousWorld: SIMD3<Float>?,
                                origin: SIMD3<Float>, forward: SIMD3<Float>) -> Float {
        guard let previousWorld else { return measured }
        let predicted = simd_dot(previousWorld - origin, forward)
        guard predicted.isFinite, (0.15...1.5).contains(predicted) else { return measured }
        return predicted + (measured - predicted) * 0.35
    }

    /// A wrist plus two reliable MCPs is sufficient; one obscured finger is not hand loss.
    static func sample(points: [SIMD2<Float>], confidence: [Float]) -> ARPalmSample? {
        guard points.count == 5, confidence.count == 5 else { return nil }
        func reliable(_ i: Int) -> Bool {
            confidence[i] >= 0.3 && confidence[i].isFinite
                && points[i].x.isFinite && points[i].y.isFinite
                && (0...1).contains(points[i].x) && (0...1).contains(points[i].y)
        }
        guard reliable(0) else { return nil }
        let visible = (1...4).filter(reliable)
        guard visible.count >= 2 else { return nil }
        let knuckles = visible.map { points[$0] }
        let average = knuckles.reduce(.zero, +) / Float(knuckles.count)
        return ARPalmSample(center: center(wrist: points[0], knuckles: knuckles),
                            index: reliable(1) ? points[1] : nil,
                            little: reliable(4) ? points[4] : nil,
                            wrist: points[0], knuckles: average)
    }

    /// Prefer the less foreshortened axis; fall back to the last established depth
    /// only while a reliable 2D palm observation still exists.
    static func resolvedDepth(width: Float?, length: Float?, previous: Float?) -> Float? {
        [width, length].compactMap { $0 }.filter { $0.isFinite && (0.15...1.5).contains($0) }.min()
            ?? previous.flatMap { $0.isFinite && (0.15...1.5).contains($0) ? $0 : nil }
    }
    static let lifetime: TimeInterval = 0.35
    static let recoveryLifetime: TimeInterval = 0.9
    static func canRecover(sample: TimeInterval?, now: TimeInterval) -> Bool {
        guard let sample else { return false }
        return now >= sample && now - sample <= recoveryLifetime
    }
    static func isFresh(sample: TimeInterval?, now: TimeInterval) -> Bool {
        guard let sample else { return false }
        return now >= sample && now - sample <= lifetime
    }
}

/// Normalized top-left viewport coordinates from the submitted image.
nonisolated struct ARPalmSample: Sendable {
    let center: SIMD2<Float>
    let index: SIMD2<Float>?
    let little: SIMD2<Float>?
    let wrist: SIMD2<Float>
    let knuckles: SIMD2<Float>
}

/// Immutable image-time camera data travels alongside the Vision result.
nonisolated struct ARPalmObservation: Sendable {
    let hand: ARPalmSample
    let cameraToWorld: simd_float4x4
    let inverseProjection: simd_float4x4
    let timestamp: TimeInterval
    var origin: SIMD3<Float> {
        SIMD3(cameraToWorld.columns.3.x, cameraToWorld.columns.3.y, cameraToWorld.columns.3.z)
    }
    var forward: SIMD3<Float> {
        -SIMD3(cameraToWorld.columns.2.x, cameraToWorld.columns.2.y, cameraToWorld.columns.2.z)
    }
    func ray(_ point: SIMD2<Float>) -> SIMD3<Float>? {
        ARPalmGeometry.ray(point: point, inverseProjection: inverseProjection, cameraToWorld: cameraToWorld)
    }
}
