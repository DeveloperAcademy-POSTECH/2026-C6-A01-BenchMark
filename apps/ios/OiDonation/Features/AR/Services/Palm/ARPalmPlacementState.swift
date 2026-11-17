//
//  ARPalmPlacementState.swift
//  OiDonation
//
//  Created by Codex on 2026/11/17.
//

import Foundation
import simd

/// Only new observations are unprojected; camera motion never reprojects old hand pixels.
nonisolated struct ARPalmPlacementState {
    private(set) var position: SIMD3<Float>?
    private var target: SIMD3<Float>?
    private var timestamp: TimeInterval?

    mutating func reset() { position = nil; target = nil; timestamp = nil }
    func isFresh(at now: TimeInterval) -> Bool { ARPalmGeometry.isFresh(sample: timestamp, now: now) }

    @discardableResult mutating func observe(_ observation: ARPalmObservation) -> Bool {
        guard timestamp.map({ observation.timestamp > $0 }) ?? true else { return false }
        if !ARPalmGeometry.canRecover(sample: timestamp, now: observation.timestamp) { position = nil; target = nil }
        let sample = observation.hand, origin = observation.origin, forward = observation.forward
        func depth(_ a: SIMD2<Float>?, _ b: SIMD2<Float>?, span: Float) -> Float? {
            guard let a, let b, let first = observation.ray(a), let second = observation.ray(b) else { return nil }
            return ARPalmGeometry.depth(indexDirection: first, littleDirection: second, forward: forward, physicalSpan: span)
        }
        let predicted = target.map { simd_dot($0 - origin, forward) }
        guard let measured = ARPalmGeometry.resolvedDepth(width: depth(sample.index, sample.little, span: 0.07),
            length: depth(sample.wrist, sample.knuckles, span: 0.075), previous: predicted),
            let direction = observation.ray(sample.center),
            let point = ARPalmGeometry.contact(origin: origin, direction: direction, forward: forward,
                depth: ARPalmGeometry.stabilizedDepth(measured: measured, previousWorld: target, origin: origin, forward: forward)) else { return false }
        target = point
        timestamp = observation.timestamp
        return true
    }

    mutating func update(at now: TimeInterval, deltaTime: TimeInterval) -> SIMD3<Float>? {
        guard ARPalmGeometry.canRecover(sample: timestamp, now: now), let target else { reset(); return nil }
        if let previous = position {
            position = previous + (target - previous) * Float(1 - exp(-22 * min(0.1, max(0, deltaTime))))
        } else { position = target }
        return position
    }
}
