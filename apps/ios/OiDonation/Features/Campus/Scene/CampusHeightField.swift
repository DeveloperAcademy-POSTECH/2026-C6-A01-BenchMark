import Foundation
import simd

/// 2m campus samples plus a 25cm library patch. No full-campus physics mesh.
final class CampusHeightField {
    struct Metadata:Decodable {let patches:[Patch];let verticalOffset:Float}
    struct Patch:Decodable {let file:String;let width:Int;let height:Int;let minX:Float;let minY:Float;let step:Float}
    private let patches:[(Patch,[Float])]
    let offset:Float
    init(directory:URL)throws {
        let meta=try JSONDecoder().decode(Metadata.self,from:Data(contentsOf:directory.appendingPathComponent("campus-height.json")));offset=meta.verticalOffset
        patches=try meta.patches.sorted{$0.step<$1.step}.map { p in
            let bytes=try Data(contentsOf:directory.appendingPathComponent(p.file));guard bytes.count==p.width*p.height*4 else{throw CocoaError(.fileReadCorruptFile)}
            var values=[Float](repeating:0,count:p.width*p.height)
            _=values.withUnsafeMutableBytes{bytes.copyBytes(to:$0)}
            return(p,values)
        }
    }
    func height(x:Float,z:Float)->Float?{
        for (p,v) in patches {
            let fx=(x-p.minX)/p.step,fy=(-z-p.minY)/p.step
            guard fx>=0,fy>=0,fx<Float(p.width-1),fy<Float(p.height-1) else{continue}
            let i=Int(fx),j=Int(fy),dx=fx-Float(i),dy=fy-Float(j),k=j*p.width+i
            let a=v[k],b=v[k+1],c=v[k+p.width],d=v[k+p.width+1]
            guard a.isFinite,b.isFinite,c.isFinite,d.isFinite else{continue}
            return ((a*(1-dx)+b*dx)*(1-dy)+(c*(1-dx)+d*dx)*dy)+offset
        };return nil
    }
    func intersect(origin:SIMD3<Float>,direction:SIMD3<Float>)->SIMD3<Float>? {
        var previous:Float?
        for k in 0..<2400 {
            let t=Float(k)*0.5,p=origin+direction*t
            guard let h=height(x:p.x,z:p.z) else{previous=nil;continue}
            if p.y<=h,let old=previous {
                var lo=old,hi=t
                for _ in 0..<15 {let mid=(lo+hi)/2,q=origin+direction*mid;if let z=height(x:q.x,z:q.z),q.y<=z{hi=mid}else{lo=mid}}
                var result=origin+direction*hi;result.y=height(x:result.x,z:result.z) ?? result.y;return result
            };previous=t
        };return nil
    }
}
