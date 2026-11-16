//
//  CampusTreeDensity.swift
//  OiDonation
//
//  Created by Codex on 2026/11/16.
//

import Foundation
import simd

/// The reviewed 60% reduction. Match entire crowns to trunks across material tiles,
/// using the same spatial ranking as the 2026-11-16 prototype.
nonisolated enum CampusTreeDensity {
    static let reductionPercent = 60

    struct Result: Sendable {
        let tiles: [CampusMeshPreparation.Tile]
        let originalCount: Int
        let removedCount: Int
    }

    static func apply(to tiles: [CampusMeshPreparation.Tile]) throws -> Result {
        let vegetation = tiles.filter { CampusMeshPreparation.isVegetation($0.color) }
        guard !vegetation.isEmpty else { return Result(tiles: tiles, originalCount: 0, removedCount: 0) }
        let buffers = vegetation.map {
            CampusEducationSite.MeshBuffers(positions: $0.positions, normals: $0.normals, indices: $0.indices)
        }
        let groups = buffers.map { CampusEducationSite.components($0) }
        let centers = buffers.indices.map { i in
            groups[i].map { CampusEducationSite.componentCenter($0, in: buffers[i]) }
        }
        var trunks: [SIMD2<Float>] = []
        var trunkIDs: [Int: [Int]] = [:]
        for i in vegetation.indices where simd_distance(vegetation[i].color, SIMD4<Float>(0.18,0.14,0.09,1)) < 0.001 {
            trunkIDs[i] = centers[i].map { center in trunks.append(center); return trunks.count - 1 }
        }
        guard !trunks.isEmpty else { throw CampusMeshPreparation.Failure.invalidAsset }
        let order = trunks.indices.sorted {
            let a = spatialHash(trunks[$0]), b = spatialHash(trunks[$1])
            return a == b ? (trunks[$0].x == trunks[$1].x ? trunks[$0].y < trunks[$1].y : trunks[$0].x < trunks[$1].x) : a < b
        }
        let removedCount = Int((Double(trunks.count) * Double(reductionPercent) / 100).rounded())
        let removed = Set(order.prefix(removedCount))
        func cell(_ p: SIMD2<Float>) -> SIMD2<Int32> { SIMD2(Int32(floor(p.x)), Int32(floor(p.y))) }
        var grid: [SIMD2<Int32>: [Int]] = [:]
        for id in trunks.indices { grid[cell(trunks[id]), default: []].append(id) }
        var replacements: [Int: CampusMeshPreparation.Tile] = [:]
        var empty: Set<Int> = []
        for i in vegetation.indices {
            try Task.checkCancellation()
            var discarded: Set<UInt32> = []
            for j in groups[i].indices {
                let id: Int
                if let ids = trunkIDs[i] { id = ids[j] }
                else {
                    let center = centers[i][j], key = cell(center)
                    var closest: Int?, distance = Float.greatestFiniteMagnitude
                    for x in -2...2 { for z in -2...2 {
                        for candidate in grid[key &+ SIMD2(Int32(x), Int32(z))] ?? [] {
                            let d = simd_distance_squared(trunks[candidate], center)
                            if d < distance { distance = d; closest = candidate }
                        }
                    }}
                    guard let closest, distance < 2.25 else { throw CampusMeshPreparation.Failure.invalidAsset }
                    id = closest
                }
                if removed.contains(id) { discarded.formUnion(groups[i][j]) }
            }
            let tile = vegetation[i]
            let indices = tile.indices.filter { !discarded.contains($0) }
            if indices.isEmpty { empty.insert(tile.index); continue }
            if indices.count == tile.indices.count { continue }
            // Remove unused vertices too, reducing uploaded buffers as well as draw work.
            let used = Set(indices).sorted()
            var remap = [UInt32](repeating: 0, count: tile.positions.count)
            for (new, old) in used.enumerated() { remap[Int(old)] = UInt32(new) }
            replacements[tile.index] = CampusMeshPreparation.Tile(index: tile.index, color: tile.color,
                positions: used.map { tile.positions[Int($0)] }, normals: used.map { tile.normals[Int($0)] },
                indices: indices.map { remap[Int($0)] })
        }
        return Result(tiles: tiles.compactMap { empty.contains($0.index) ? nil : replacements[$0.index] ?? $0 },
            originalCount: trunks.count, removedCount: removedCount)
    }

    private static func spatialHash(_ p: SIMD2<Float>) -> UInt64 {
        let x = UInt64(bitPattern: Int64((p.x * 10_000).rounded()))
        let z = UInt64(bitPattern: Int64((p.y * 10_000).rounded()))
        var n = x &* 0x9E3779B97F4A7C15 ^ z &* 0xBF58476D1CE4E5B9 ^ 331305
        n = (n ^ (n >> 30)) &* 0xBF58476D1CE4E5B9
        n = (n ^ (n >> 27)) &* 0x94D049BB133111EB
        return n ^ (n >> 31)
    }
}
