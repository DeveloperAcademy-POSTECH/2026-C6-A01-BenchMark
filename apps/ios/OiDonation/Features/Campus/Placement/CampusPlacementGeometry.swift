import Foundation
import simd

/// Display exaggeration never changes the stored coordinate or the physical AR height.
enum CampusPlacementGeometry {
    /// All map symbols use the former 1m baseline, independent of the saved AR height.
    static func mapScale(unitsPerMeter: Double, editing: Bool) -> Float {
        Float(unitsPerMeter * (editing ? 1 : 20))
    }

    /// Screen-right / screen-up on the ground plane, including a rotated map camera.
    static func offset(right: Float, forward: Float, meters: Double, yaw: Float,
                       unitsPerMeter: Double) -> SIMD3<Float> {
        let horizontal = SIMD3<Float>(cos(yaw), 0, -sin(yaw))
        let upward = SIMD3<Float>(-sin(yaw), 0, -cos(yaw))
        return (horizontal * right + upward * forward) * Float(meters * unitsPerMeter)
    }
}

/// The map treats a touch sequence as multi-finger until every finger is lifted.
struct CampusPlacementGestureState {
    enum Change {
        case move(CGPoint)
        case transform(horizontal: CGFloat, scale: CGFloat, rotation: Double)
    }

    private var previous: [Int: CGPoint] = [:]
    private var usedMultipleFingers = false
    private var dragOrigin: CGPoint?
    private var dragging = false

    mutating func update(_ points: [Int: CGPoint]) -> Change? {
        guard !points.isEmpty else { self = Self(); return nil }
        if points.count > 1 { usedMultipleFingers = true }
        defer { previous = points }
        guard Set(points.keys) == Set(previous.keys) else {
            dragOrigin = points.count == 1 ? points.values.first : nil
            dragging = false
            return nil
        }
        if points.count == 1, !usedMultipleFingers, let id = points.keys.first,
           let point = points[id], let origin = dragging ? previous[id] : dragOrigin {
            let delta = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
            guard dragging || hypot(delta.x, delta.y) >= 6 else { return nil }
            dragging = true
            return .move(delta)
        }
        guard points.count == 2 else { return nil }
        let ids = points.keys.sorted()
        guard let a = points[ids[0]], let b = points[ids[1]],
              let oldA = previous[ids[0]], let oldB = previous[ids[1]] else { return nil }
        let horizontal = (a.x - oldA.x + b.x - oldB.x) / 2
        let before = CGVector(dx: oldB.x - oldA.x, dy: oldB.y - oldA.y)
        let after = CGVector(dx: b.x - a.x, dy: b.y - a.y)
        let oldDistance = hypot(before.dx, before.dy), newDistance = hypot(after.dx, after.dy)
        guard oldDistance > 1, newDistance > 1 else { return .transform(horizontal: horizontal, scale: 1, rotation: 0) }
        let cross = before.dx * after.dy - before.dy * after.dx
        let dot = before.dx * after.dx + before.dy * after.dy
        return .transform(horizontal: horizontal, scale: newDistance / oldDistance,
                          rotation: atan2(Double(cross), Double(dot)))
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
