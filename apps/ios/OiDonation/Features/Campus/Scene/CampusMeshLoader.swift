import Foundation
import RealityKit
import UIKit
import Compression

/// Blender-exported, losslessly compressed RealityKit buffers. Geometry matches the USDZ.
@MainActor enum CampusMeshLoader {
    enum Failure:Error {case invalidAsset}
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
    static func load(url:URL, mapData: CampusMapData? = nil) async throws->Entity {
        let packed=try Data(contentsOf:url,options:.mappedIfSafe)
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
        let root=Entity();root.name="POSTECH v09 native campus"
        func attach(_ result:(Int,MeshResource,SIMD4<Float>)) {
            let (i,mesh,c)=result
            func srgb(_ v:Float)->CGFloat{CGFloat(v<=0.0031308 ? v*12.92:1.055*pow(v,1/2.4)-0.055)}
            let material=SimpleMaterial(color:UIColor(red:srgb(c.x),green:srgb(c.y),blue:srgb(c.z),alpha:CGFloat(c.w)),roughness:0.75,isMetallic:false)
            let entity=ModelEntity(mesh:mesh,materials:[material]);entity.name="campus-tile-\(i)";root.addChild(entity)
        }
        try await withThrowingTaskGroup(of:(Int,MeshResource,SIMD4<Float>).self) { group in
        var pending=0
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
            var descriptor=MeshDescriptor(name:"Campus tile \(i)")
            descriptor.positions=MeshBuffers.Positions(meshPositions);descriptor.normals=MeshBuffers.Normals(meshNormals);descriptor.primitives = .triangles(indices)
            let frozen=descriptor,color=SIMD4(r,g,b,a)
            group.addTask { (i,try await MeshResource(from:[frozen]),color) };pending+=1
            if pending>=8,let result=try await group.next(){attach(result);pending-=1}
        }
        while let result=try await group.next(){attach(result)}
        }
        guard reader.offset==bytes.count else{throw Failure.invalidAsset}
        return root
    }
}
