import Foundation
import simd

/// Same WGS84 ellipsoid/topocentric XY as the v07 Blender export. Terrain Z is separate.
struct CampusGeoreference {
    let longitude:Double,latitude:Double,scale:Double
    private let a=6378137.0,e2=0.0066943799901413165
    private var rotation:simd_double3x3 {
        let l=longitude * .pi/180,p=latitude * .pi/180
        return simd_double3x3(rows:[SIMD3(-sin(l),cos(l),0),SIMD3(-sin(p)*cos(l),-sin(p)*sin(l),cos(p)),SIMD3(cos(p)*cos(l),cos(p)*sin(l),sin(p))])
    }
    private func ecef(_ lon:Double,_ lat:Double)->SIMD3<Double>{
        let l=lon * .pi/180,p=lat * .pi/180,n=a/sqrt(1-e2*sin(p)*sin(p))
        return SIMD3(n*cos(p)*cos(l),n*cos(p)*sin(l),n*(1-e2)*sin(p))
    }
    func xy(longitude lon:Double,latitude lat:Double)->SIMD2<Double>{let v=rotation*(ecef(lon,lat)-ecef(longitude,latitude));return SIMD2(v.x,v.y)*scale}
    func coordinate(x:Double,y:Double)->(latitude:Double,longitude:Double){
        let origin=ecef(longitude,latitude),r=rotation.transpose;var up=0.0,lat=0.0,lon=0.0
        for _ in 0..<9 {
            let v=origin+r*SIMD3(x/scale,y/scale,up),p=hypot(v.x,v.y)
            lon=atan2(v.y,v.x);lat=atan2(v.z,p*(1-e2))
            for _ in 0..<10{let n=a/sqrt(1-e2*sin(lat)*sin(lat));lat=atan2(v.z+e2*n*sin(lat),p)}
            let h=p*cos(lat)+v.z*sin(lat)-a*sqrt(1-e2*sin(lat)*sin(lat));up-=h
        }
        return(lat*180 / .pi,lon*180 / .pi)
    }
}
