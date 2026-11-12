//
//  ARPostcardPuzzleLayout.swift
//  OiDonationClip
//
//  Created by Jiwon Hong on 11/9/26.
//

#if DEBUG
import CoreGraphics
import Darwin
import simd

struct ARPostcardPuzzleLayout {
    static let columns = 3
    static let tileCount = columns * columns

    private let boardScale: Float = 1.50
    let lipWidth: Float = 0.014
    var boardWidth: Float { 0.27 * boardScale }
    var boardHeight: Float { boardWidth * 502 / 362 }

    private var playWidth: Float { 0.54 * boardScale }
    private var playHeight: Float { 0.70 * boardScale }

    var tileWidth: Float { boardWidth / Float(Self.columns) }
    var tileHeight: Float { boardHeight / Float(Self.columns) }

    func cellCenter(for index: Int) -> SIMD2<Float> {
        let column = Float(index % Self.columns)
        let row = Float(index / Self.columns)
        return [(column - 1) * tileWidth, (1 - row) * tileHeight]
    }

    var startingPositions: [SIMD2<Float>] {
        let centers: [SIMD2<Float>] = [
            [-0.211, 0.155], [-0.205, 0.009], [-0.213, -0.143],
            [0.205, 0.171], [0.216, 0.025], [0.207, -0.125],
            [-0.105, -0.267], [0.002, -0.278], [0.113, -0.260]
        ]
        return centers.map { $0 * boardScale }
    }

    func canRestOutsideBoard(_ index: Int, at center: SIMD2<Float>, among positions: [SIMD2<Float>]) -> Bool {
        let insidePlayArea = abs(center.x) + tileWidth / 2 <= playWidth / 2 &&
            abs(center.y) + tileHeight / 2 <= playHeight / 2
        let clearsBoard = abs(center.x) >= (boardWidth + tileWidth) / 2 + lipWidth ||
            abs(center.y) >= (boardHeight + tileHeight) / 2 + lipWidth
        return insidePlayArea && clearsBoard && !positions.indices.contains { other in
            other != index && overlapsTile(at: center, otherCenter: positions[other])
        }
    }

    func overlapsTile(at center: SIMD2<Float>, otherCenter: SIMD2<Float>) -> Bool {
        let delta = center - otherCenter
        // Assembled tiles share edges without overlapping.
        let edgeTolerance: Float = 0.0001
        return abs(delta.x) < tileWidth - edgeTolerance &&
            abs(delta.y) < tileHeight - edgeTolerance
    }

    func matchesCell(for index: Int, at point: SIMD2<Float>) -> Bool {
        let center = cellCenter(for: index)
        return abs(point.x - center.x) < tileWidth / 2 &&
            abs(point.y - center.y) < tileHeight / 2
    }

    func slideTiles(
        positions: inout [SIMD2<Float>], velocities: inout [SIMD2<Float>],
        locked: Set<Int>, elapsed: Float
    ) {
        let step = min(elapsed, 1 / 30)
        guard step > 0 else { return }
        let friction = exp(-5 * step)
        for index in positions.indices where !locked.contains(index) {
            guard simd_length_squared(velocities[index]) > 0.000025 else {
                velocities[index] = .zero
                continue
            }
            for axis in 0..<2 {
                var next = positions[index]
                next[axis] += velocities[index][axis] * step
                if canRestOutsideBoard(index, at: next, among: positions) {
                    positions[index] = next
                } else {
                    velocities[index][axis] *= -0.32
                }
            }
            velocities[index] *= friction
        }
    }

    static func crop(for index: Int, imageWidth: Int, imageHeight: Int) -> CGRect {
        let column = index % columns
        let row = index / columns
        let left = column * imageWidth / columns
        let top = row * imageHeight / columns
        let right = (column + 1) * imageWidth / columns
        let bottom = (row + 1) * imageHeight / columns
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    static func initialTrayTilt(cameraBackY: Float) -> simd_quatf {
        let start = sin(Float(25) * .pi / 180)
        let floor = sin(Float(60) * .pi / 180)
        let progress = min(max((cameraBackY - start) / (floor - start), 0), 1)
        let eased = progress * progress * (3 - 2 * progress)
        return simd_quatf(angle: -(32 + 58 * eased) * .pi / 180, axis: [1, 0, 0])
    }

    static func trayAnchorTransform(cameraToWorld: simd_float4x4, distance: Float) -> simd_float4x4 {
        let up = SIMD3<Float>(0, 1, 0)
        let backAxis = cameraToWorld.columns.2
        let horizontalBack = SIMD3(backAxis.x, 0, backAxis.z)
        let rightAxis = cameraToWorld.columns.0
        let horizontalRight = SIMD3(rightAxis.x, 0, rightAxis.z)
        let back = simd_length_squared(horizontalBack) > 0.01
            ? simd_normalize(horizontalBack)
            : simd_normalize(simd_cross(horizontalRight, up))
        let right = simd_cross(up, back)
        let facing = simd_quatf(simd_float3x3(right, up, back))
        var tray = simd_float4x4(facing)
        tray.columns.3 = cameraToWorld * SIMD4<Float>(0, 0.055, -distance, 1)
        return tray
    }
}
#endif
