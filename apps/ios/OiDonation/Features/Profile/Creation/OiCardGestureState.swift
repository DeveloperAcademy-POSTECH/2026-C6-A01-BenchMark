//
//  OiCardGestureState.swift
//  OiDonation
//
//  Created by Codex on 11/6/26.
//

import Foundation

/// Input history lasts until ALL fingers lift. Changing the touch count rebases
/// the sample instead of treating the new centroid as an intentional movement.
struct OiCardGestureState {
    private var previous: [Int: CGPoint] = [:]
    private var usedMultipleFingers = false

    mutating func update(points: [Int: CGPoint], bounds: CGSize,
                         placement: inout OiCardPlacement, orientation: inout OiCardOrientation?) {
        guard !points.isEmpty else { previous = [:]; usedMultipleFingers = false; return }
        if points.count > 1 { usedMultipleFingers = true }
        defer { previous = points }
        guard Set(points.keys) == Set(previous.keys), bounds.width > 0, bounds.height > 0,
              points.values.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return }

        if points.count == 1, (!usedMultipleFingers || orientation == nil),
           let id = points.keys.first, let point = points[id], let old = previous[id] {
            placement.x += (point.x - old.x) / bounds.width
            placement.y += (point.y - old.y) / bounds.height
        } else if points.count == 2 {
            let ids = points.keys.sorted()
            guard let a = points[ids[0]], let b = points[ids[1]],
                  let oldA = previous[ids[0]], let oldB = previous[ids[1]] else { return }
            let dx = (a.x + b.x - oldA.x - oldB.x) / 2
            let dy = (a.y + b.y - oldA.y - oldB.y) / 2
            if let angle = orientation {
                orientation = angle.rotated(horizontal: dx, vertical: dy)
            } else {
                // Background photos retain two-finger translation while pinching.
                placement.x += dx / bounds.width; placement.y += dy / bounds.height
            }
            let before = hypot(oldA.x - oldB.x, oldA.y - oldB.y)
            let after = hypot(a.x - b.x, a.y - b.y)
            if before > 1, after > 1 { placement.scale *= after / before }
        }
        placement = placement.normalized
    }
}
