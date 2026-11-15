//
//  ARCameraGeoPlacement.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/15/26.
//

import Foundation
import simd

/// Resolves one saved location into the heading-aligned AR world. GPS is used
/// once per placement, rather than moving a placed character with every fix.
struct ARCameraGeoPlacement {
    struct Fix {
        let latitude: Double
        let longitude: Double
        let accuracy: Double
        let timestamp: Date
    }
    enum Status: Equatable {
        case waitingForLocation, waitingForTracking, waitingForGround, waitingForSynchronizedLocation
        case outsideRange(Double)
        case ready(SIMD3<Float>)
    }
    let target: CampusPlacement
    private(set) var position: SIMD3<Float>?

    mutating func reset() { position = nil }

    mutating func update(fix: Fix?, trackingNormal: Bool, cameraAtFix: SIMD3<Float>?, now: Date = Date(),
                         groundHeight: (SIMD3<Float>) -> Float?) -> Status {
        guard let fix, CampusLocationQuality.allowsFix(latitude: fix.latitude, longitude: fix.longitude,
            accuracy: fix.accuracy, timestamp: fix.timestamp, now: now) else { return .waitingForLocation }
        let distance = target.distance(latitude: fix.latitude, longitude: fix.longitude)
        guard distance <= CampusLocationQuality.radiusMeters else { return .outsideRange(distance) }
        guard trackingNormal else { return .waitingForTracking }
        if let position { return .ready(position) }
        guard let cameraAtFix else { return .waitingForSynchronizedLocation }
        let offset = target.offsetMeters(fromLatitude: fix.latitude, longitude: fix.longitude)
        let candidate = cameraAtFix + offset
        guard candidate.x.isFinite, candidate.y.isFinite, candidate.z.isFinite,
              let height = groundHeight(candidate), height.isFinite else { return .waitingForGround }
        let resolved = SIMD3(candidate.x, height, candidate.z)
        position = resolved
        return .ready(resolved)
    }
}

/// Positions only: never retain ARFrames or their camera pixel buffers. Frame
/// timestamps and the lookup timestamp are in the same monotonic media clock.
struct ARCameraPoseHistory {
    private struct Sample {
        let timestamp: TimeInterval
        let position: SIMD3<Float>
    }
    private static let retainedDuration: TimeInterval = 12
    private static let maximumInterpolationGap: TimeInterval = 0.25
    private var samples: [Sample] = []

    mutating func reset() { samples.removeAll(keepingCapacity: true) }

    mutating func record(position: SIMD3<Float>, timestamp: TimeInterval) {
        guard timestamp.isFinite, position.x.isFinite, position.y.isFinite, position.z.isFinite,
              samples.last.map({ timestamp > $0.timestamp }) ?? true else { return }
        samples.append(Sample(timestamp: timestamp, position: position))
        samples.removeAll { timestamp - $0.timestamp > Self.retainedDuration }
    }

    func position(at timestamp: TimeInterval) -> SIMD3<Float>? {
        guard timestamp.isFinite, let first = samples.first, let last = samples.last,
              timestamp >= first.timestamp, timestamp <= last.timestamp,
              let index = samples.firstIndex(where: { $0.timestamp >= timestamp }) else { return nil }
        let after = samples[index]
        if after.timestamp == timestamp { return after.position }
        guard index > 0 else { return nil }
        let before = samples[index - 1]
        let gap = after.timestamp - before.timestamp
        // Do not interpolate across tracking interruptions or missing callbacks.
        guard gap > 0, gap <= Self.maximumInterpolationGap else { return nil }
        let fraction = Float((timestamp - before.timestamp) / gap)
        return before.position + (after.position - before.position) * fraction
    }
}
