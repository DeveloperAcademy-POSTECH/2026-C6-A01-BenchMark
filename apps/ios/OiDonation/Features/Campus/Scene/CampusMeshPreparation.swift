//
//  CampusMeshPreparation.swift
//  OiDonation
//
//  Created by Codex on 2026/11/16.
//

import Foundation
import Compression
import CryptoKit
import simd

/// CPU-only campus work. No Entity, UIKit, or GPU resource crosses this worker boundary.
nonisolated enum CampusMeshPreparation {
    enum Failure: Error { case invalidAsset }
    struct Tile: Sendable {
        let index: Int
        let color: SIMD4<Float>
        let positions: [SIMD3<Float>]
        let normals: [SIMD3<Float>]
        let indices: [UInt32]
    }
    struct Asset: Sendable {
        let tiles: [Tile]
        let cacheHit: Bool
        let elapsed: TimeInterval
    }
    private struct Reader {
        let data:Data
        var offset=0
        mutating func uint()throws->UInt32 {
            guard offset+4<=data.count else{throw Failure.invalidAsset};defer{offset+=4}
            return data.withUnsafeBytes{$0.loadUnaligned(fromByteOffset:offset,as:UInt32.self)}.littleEndian
        }
        mutating func vectors(_ n:Int)throws->[SIMD3<Float>] {
            guard n>=0,n<=5_000_000,offset+n*16<=data.count else{throw Failure.invalidAsset};defer{offset+=n*16}
            return data.withUnsafeBytes { bytes in (0..<n).map { i in let v=bytes.loadUnaligned(fromByteOffset:offset+i*16,as:SIMD4<Float>.self);return SIMD3(v.x,v.y,v.z)}}
        }
        mutating func indices(_ n:Int)throws->[UInt32] {
            guard n>=0,n<=15_000_000,offset+n*4<=data.count else{throw Failure.invalidAsset};defer{offset+=n*4}
            return data.withUnsafeBytes{bytes in (0..<n).map{bytes.loadUnaligned(fromByteOffset:offset+$0*4,as:UInt32.self).littleEndian}}
        }
    }

    private static let cacheVersion = "campus-geometry-v2-trees60-seed331305"
    private static let maximumBytes = 256 * 1024 * 1024

    static func load(url: URL, mapData: CampusMapData?, cacheDirectory: URL?) throws -> Asset {
        try Task.checkCancellation()
        let start = Date.timeIntervalSinceReferenceDate
        let packed = try Data(contentsOf: url, options: .mappedIfSafe)
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        var digest = SHA256()
        digest.update(data: Data(cacheVersion.utf8)); digest.update(data: packed)
        digest.update(data: try encoder.encode(mapData))
        if let surface = mapData?.surface { digest.update(data: surface.sourceDigest) }
        let key = digest.finalize().map { String(format: "%02x", $0) }.joined()
        let cache = cacheDirectory?.appendingPathComponent(key + ".oicache")
        if let cache, let bytes = try? Data(contentsOf: cache, options: .mappedIfSafe),
           let tiles = try? readCache(bytes) {
            return Asset(tiles: tiles, cacheHit: true, elapsed: Date.timeIntervalSinceReferenceDate - start)
        }
        try Task.checkCancellation()
        let tiles = try prepare(packed: packed, mapData: mapData)
        // This is a disposable, public geometry cache. A full/missing cache directory must
        // never prevent the bundled original from rendering. Atomic writes preserve retries.
        if let cache, let bytes = try? writeCache(tiles) {
            try? FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? bytes.write(to: cache, options: .atomic)) != nil { pruneCaches(keeping: cache) }
        }
        return Asset(tiles: tiles, cacheHit: false, elapsed: Date.timeIntervalSinceReferenceDate - start)
    }

    private static func prepare(packed: Data, mapData: CampusMapData?) throws -> [Tile] {
        guard packed.count>4 else{throw Failure.invalidAsset}
        let size=packed.withUnsafeBytes{Int($0.loadUnaligned(as:UInt32.self).littleEndian)}
        guard size>12,size<256*1024*1024 else{throw Failure.invalidAsset}
        var bytes=Data(count:size)
        let decoded=bytes.withUnsafeMutableBytes { dst in packed.withUnsafeBytes { src in
            compression_decode_buffer(dst.bindMemory(to:UInt8.self).baseAddress!,size,src.bindMemory(to:UInt8.self).baseAddress!+4,packed.count-4,nil,COMPRESSION_ZLIB)
        }}
        guard decoded==size,bytes.prefix(8)==Data("OICAMP07".utf8) else{throw Failure.invalidAsset}
        var reader=Reader(data:bytes,offset:8);let count=Int(try reader.uint());guard count>0,count<5000 else{throw Failure.invalidAsset}
        // The original mesh batches foliage by material, not by tree. Read trunk
        // centers first so every crown belonging to a removed tree disappears too.
        let landscape = mapData.map { CampusEducationLandscape(data: $0) }
        var trees: [CampusEducationSite.Tree] = []
        var pathCrossings = CampusEducationSite.MeshBuffers(positions: [], normals: [], indices: [])
        if mapData != nil {
            var scan = reader
            for _ in 0..<count {
                let nv = Int(try scan.uint()), ni = Int(try scan.uint())
                let color = SIMD3(Float(bitPattern: try scan.uint()), Float(bitPattern: try scan.uint()), Float(bitPattern: try scan.uint()))
                _ = try scan.uint()
                guard nv <= 5_000_000, ni <= 15_000_000, scan.offset + nv * 32 + ni * 4 <= bytes.count else { throw Failure.invalidAsset }
                let trunk = simd_distance(color, SIMD3<Float>(0.18, 0.14, 0.09)) < 0.001
                let asphalt = simd_distance(color, SIMD3<Float>(0.17, 0.19, 0.19)) < 0.001
                if trunk || asphalt {
                    let positions = try scan.vectors(nv)
                    let normals = try scan.vectors(nv)
                    let indices = try scan.indices(ni)
                    guard ni % 3 == 0, indices.allSatisfy({ $0 < UInt32(nv) }) else { throw Failure.invalidAsset }
                    let source = CampusEducationSite.MeshBuffers(positions: positions, normals: normals, indices: indices)
                    if trunk { trees += CampusEducationSite.trees(in: source) }
                    else if let landscape, mapData?.surface != nil {
                        let patch = landscape.pathCrossings(source), start = UInt32(pathCrossings.positions.count)
                        pathCrossings.positions += patch.positions; pathCrossings.normals += patch.normals
                        pathCrossings.indices += patch.indices.map { $0 + start }
                    }
                } else { scan.offset += nv * 32 + ni * 4 }
            }
        }
        var grass = mapData?.surface.flatMap { surface in landscape?.grass(surface: surface) }
        var tiles: [Tile] = []
        tiles.reserveCapacity(count)
        for i in 0..<count {
            try Task.checkCancellation()
            let nv=Int(try reader.uint()),ni=Int(try reader.uint())
            let r=Float(bitPattern:try reader.uint()),g=Float(bitPattern:try reader.uint()),b=Float(bitPattern:try reader.uint()),a=Float(bitPattern:try reader.uint())
            let positions=try reader.vectors(nv),normals=try reader.vectors(nv)
            var indices=try reader.indices(ni)
            guard ni%3==0,indices.allSatisfy({$0<UInt32(nv)}) else{throw Failure.invalidAsset}
            var meshPositions = positions, meshNormals = normals
            if mapData != nil {
                let source = CampusEducationSite.MeshBuffers(positions: positions, normals: normals, indices: indices)
                let vegetation = [SIMD3<Float>(0.18, 0.14, 0.09), [0.12, 0.23, 0.08], [0.27, 0.33, 0.12]]
                    .contains { simd_distance($0, SIMD3(r,g,b)) < 0.001 }
                let ground = [SIMD3<Float>(0.26,0.32,0.15), [0.17,0.19,0.19], [0.85,0.85,0.77], [0.52,0.52,0.48], [0.71,0.7,0.64]]
                    .contains { simd_distance($0, SIMD3(r,g,b)) < 0.001 }
                var cleared: CampusEducationSite.MeshBuffers
                if vegetation {
                    cleared = CampusEducationSite.clearingVegetation(source, trees: trees, surface: mapData?.surface)
                } else if ground, let landscape, mapData?.surface != nil {
                    let asphalt = simd_distance(SIMD3(r,g,b), SIMD3<Float>(0.17,0.19,0.19)) < 0.001
                    cleared = landscape.clearing(source, preservingFootpaths: !asphalt)
                    // Share the existing grass tile's palette and draw call; a
                    // separate gray parcel underneath the pearl model is unnecessary.
                    if let patch = grass, simd_distance(SIMD3(r,g,b), SIMD3<Float>(0.26,0.32,0.15)) < 0.001,
                       source.positions.contains(where: { CampusEducationLandscape.boundaryDistance([$0.x,$0.z]) > 0 }) {
                        let start = UInt32(cleared.positions.count)
                        cleared.positions += patch.positions; cleared.normals += patch.normals
                        cleared.indices += patch.indices.map { $0 + start }
                        grass = nil
                    }
                    if !pathCrossings.indices.isEmpty, simd_distance(SIMD3(r,g,b), SIMD3<Float>(0.52,0.52,0.48)) < 0.001,
                       source.positions.contains(where: { CampusEducationLandscape.boundaryDistance([$0.x,$0.z]) > 0 }) {
                        let start = UInt32(cleared.positions.count)
                        cleared.positions += pathCrossings.positions; cleared.normals += pathCrossings.normals
                        cleared.indices += pathCrossings.indices.map { $0 + start }
                        pathCrossings = .init(positions: [], normals: [], indices: [])
                    }
                } else { cleared = CampusEducationSite.clearing(source) }
                meshPositions = cleared.positions; meshNormals = cleared.normals; indices = cleared.indices
            }
            if indices.isEmpty { continue }
            tiles.append(Tile(index: i, color: [r,g,b,a], positions: meshPositions, normals: meshNormals, indices: indices))
        }
        guard reader.offset == bytes.count else { throw Failure.invalidAsset }
        return try CampusTreeDensity.apply(to: tiles).tiles
    }

    static func isVegetation(_ color: SIMD4<Float>) -> Bool {
        [SIMD3<Float>(0.18,0.14,0.09), [0.12,0.23,0.08], [0.27,0.33,0.12]]
            .contains { simd_distance($0, SIMD3(color.x,color.y,color.z)) < 0.001 }
    }

    private static func pruneCaches(keeping current: URL) {
        let folder = current.deletingLastPathComponent()
        let files = (try? FileManager.default.contentsOfDirectory(at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
        let older = files.filter { $0 != current && $0.pathExtension == "oicache" }
            .sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
                > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
        for stale in older.dropFirst() { try? FileManager.default.removeItem(at: stale) }
    }

    private static func append<T>(_ values: [T], to data: inout Data) {
        values.withUnsafeBytes { data.append(contentsOf: $0) }
    }

    private static func writeCache(_ tiles: [Tile]) throws -> Data {
        let capacity = 12 + tiles.reduce(0) { $0 + 28 + $1.positions.count * 32 + $1.indices.count * 4 }
        guard capacity < maximumBytes else { throw Failure.invalidAsset }
        var raw = Data("OICP0001".utf8)
        raw.reserveCapacity(capacity)
        append([UInt32(tiles.count)], to: &raw)
        for tile in tiles {
            try Task.checkCancellation()
            append([UInt32(tile.index), UInt32(tile.positions.count), UInt32(tile.indices.count)], to: &raw)
            append([tile.color], to: &raw)
            // SIMD3's fourth lane is padding. Serialize a defined zero lane, never padding bytes.
            append(tile.positions.map { SIMD4($0, 0) }, to: &raw)
            append(tile.normals.map { SIMD4($0, 0) }, to: &raw)
            append(tile.indices, to: &raw)
        }
        guard raw.count < maximumBytes else { throw Failure.invalidAsset }
        var output = Data(count: raw.count + raw.count / 8 + 1024)
        let outputCapacity = output.count
        let size = output.withUnsafeMutableBytes { dst in raw.withUnsafeBytes { src in
            compression_encode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, outputCapacity,
                src.bindMemory(to: UInt8.self).baseAddress!, raw.count, nil, COMPRESSION_LZFSE)
        }}
        guard size > 0 else { throw Failure.invalidAsset }
        output.count = size
        var result = Data()
        append([UInt32(raw.count)], to: &result)
        result.append(contentsOf: SHA256.hash(data: raw))
        result.append(output)
        return result
    }

    private static func readCache(_ packed: Data) throws -> [Tile] {
        guard packed.count > 36 else { throw Failure.invalidAsset }
        let size = packed.withUnsafeBytes { Int($0.loadUnaligned(as: UInt32.self).littleEndian) }
        guard size > 12, size < maximumBytes else { throw Failure.invalidAsset }
        var raw = Data(count: size)
        let n = raw.withUnsafeMutableBytes { dst in packed.withUnsafeBytes { src in
            compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, size,
                src.bindMemory(to: UInt8.self).baseAddress! + 36, packed.count - 36, nil, COMPRESSION_LZFSE)
        }}
        guard n == size, Data(SHA256.hash(data: raw)) == packed.subdata(in: 4..<36),
              raw.prefix(8) == Data("OICP0001".utf8) else { throw Failure.invalidAsset }
        var reader = Reader(data: raw, offset: 8)
        let count = Int(try reader.uint())
        guard count > 0, count < 5000 else { throw Failure.invalidAsset }
        var tiles: [Tile] = [], seen: Set<Int> = []
        for _ in 0..<count {
            try Task.checkCancellation()
            let index = Int(try reader.uint()), nv = Int(try reader.uint()), ni = Int(try reader.uint())
            let c = try (0..<4).map { _ in Float(bitPattern: try reader.uint()) }
            guard seen.insert(index).inserted, index < 5000, c.allSatisfy(\.isFinite) else { throw Failure.invalidAsset }
            let p = try reader.vectors(nv), normals = try reader.vectors(nv), ids = try reader.indices(ni)
            guard ni % 3 == 0, ids.allSatisfy({ $0 < UInt32(nv) }) else { throw Failure.invalidAsset }
            tiles.append(Tile(index: index, color: [c[0],c[1],c[2],c[3]], positions: p, normals: normals, indices: ids))
        }
        guard reader.offset == raw.count else { throw Failure.invalidAsset }
        return tiles
    }
}
