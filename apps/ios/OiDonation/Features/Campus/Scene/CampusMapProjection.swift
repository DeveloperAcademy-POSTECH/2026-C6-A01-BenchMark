//
//  CampusMapProjection.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/4/26.
//

import CoreGraphics
import simd

/// The UIKit overlays and the RealityKit camera use the same orbit pose.
struct CampusMapProjection {
    let focalLength: CGFloat
    private let eye: SIMD3<Float>
    private let right: SIMD3<Float>
    private let up: SIMD3<Float>
    private let forward: SIMD3<Float>
    private let center: CGPoint

    init(eye: SIMD3<Float>, yaw: Float, pitch: Float, verticalFOV: Float, viewport: CGRect) {
        self.eye = eye
        right = SIMD3(cos(yaw), 0, -sin(yaw))
        up = SIMD3(-sin(yaw) * sin(pitch), cos(pitch), -cos(yaw) * sin(pitch))
        forward = SIMD3(-sin(yaw) * cos(pitch), -sin(pitch), -cos(yaw) * cos(pitch))
        center = CGPoint(x: viewport.midX, y: viewport.midY)
        focalLength = viewport.height / (2 * tan(CGFloat(verticalFOV) * .pi / 360))
    }

    func point(_ world: SIMD3<Float>) -> CGPoint? {
        project(world)?.point
    }

    func project(_ world: SIMD3<Float>) -> (point: CGPoint, depth: Float)? {
        let offset = world - eye
        let depth = simd_dot(offset, forward)
        guard depth > 0.1, focalLength > 0 else { return nil }
        let scale = focalLength / CGFloat(depth)
        let x = center.x + CGFloat(simd_dot(offset, right)) * scale
        let y = center.y - CGFloat(simd_dot(offset, up)) * scale
        guard x.isFinite, y.isFinite else { return nil }
        return (CGPoint(x: x, y: y), depth)
    }

    func ray(through point: CGPoint) -> (origin: SIMD3<Float>, direction: SIMD3<Float>)? {
        guard focalLength > 0, point.x.isFinite, point.y.isFinite else { return nil }
        let x = Float((point.x - center.x) / focalLength)
        let y = Float((center.y - point.y) / focalLength)
        return (eye, simd_normalize(forward + right * x + up * y))
    }

    /// Ground-plane spacing foreshortens at a shallow camera angle. Measure it
    /// in the camera plane so group boundaries depend on angle, not on panning.
    func planeSeparation(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        let offset = b - a
        return hypot(simd_dot(offset, right), simd_dot(offset, up))
    }

    static func panelOpacity(pitch: Float) -> CGFloat {
        let progress = min(1, max(0, (pitch - 0.84) / (1.06 - 0.84)))
        return CGFloat(1 - progress * progress * (3 - 2 * progress))
    }
}
