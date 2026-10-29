// Created by 이돈혁

import Foundation
import simd

/// Display exaggeration never changes the stored coordinate or the physical AR height.
enum CampusPlacementGeometry {
    static func mapScale(heightMeters: Double, unitsPerMeter: Double, editing: Bool) -> Float {
        Float(heightMeters * unitsPerMeter * (editing ? 1 : 20))
    }

    /// Screen-right / screen-up on the ground plane, including a rotated map camera.
    static func offset(right: Float, forward: Float, meters: Double, yaw: Float,
                       unitsPerMeter: Double) -> SIMD3<Float> {
        let horizontal = SIMD3<Float>(cos(yaw), 0, -sin(yaw))
        let upward = SIMD3<Float>(-sin(yaw), 0, -cos(yaw))
        return (horizontal * right + upward * forward) * Float(meters * unitsPerMeter)
    }
}

extension CampusMapData {
    /// Re-sample terrain after every nudge; reject destinations inside buildings or outside the map.
    func nudgedPlacement(from point: SIMD3<Float>, right: Float, forward: Float,
                         meters: Double, yaw: Float) throws -> SIMD3<Float> {
        guard [point.x, point.y, point.z, right, forward, yaw].allSatisfy(\.isFinite),
              meters.isFinite, meters > 0, meters <= 1 else { throw CampusPlacementError.invalid }
        let moved = point + CampusPlacementGeometry.offset(right: right, forward: forward,
            meters: meters, yaw: yaw, unitsPerMeter: unitsPerMeter)
        guard placementError(at: moved) == nil,
              let height = surface?.height(x: moved.x, z: moved.z), height.isFinite
        else { throw CampusPlacementError.outside }
        return SIMD3(moved.x, height, moved.z)
    }
}
