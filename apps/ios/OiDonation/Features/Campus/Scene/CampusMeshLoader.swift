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
    static func load(url:URL) async throws->Entity {
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
            let positions=try reader.vectors(nv),normals=try reader.vectors(nv),indices=try reader.indices(ni)
            guard ni%3==0,indices.allSatisfy({$0<UInt32(nv)}) else{throw Failure.invalidAsset}
            var descriptor=MeshDescriptor(name:"Campus tile \(i)")
            descriptor.positions=MeshBuffers.Positions(positions);descriptor.normals=MeshBuffers.Normals(normals);descriptor.primitives = .triangles(indices)
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
