import Foundation
import simd

struct CampusMapData: Decodable {
    struct Place: Decodable, Identifiable {let id:String;let name:String;let category:String;let p:[Double];let node:String;let buildingId:String?}
    struct Node: Decodable {let p:[Double];let links:[String];let wgs84:[Double]?}
    struct Building: Decodable {let id:String;let p:[[Double]];let name:String?;let levels:Double?;let kind:String?;let modelRoofZ:Double?}
    struct CoordinateSystem:Decodable {let horizontalFrameVersion:String?}
    struct InitialView:Decodable {let walkingStart:[Double]}
    let coordinateSystem:CoordinateSystem?
    let initialView:InitialView?
    var surface:CampusHeightField?
    enum CodingKeys:String,CodingKey {case origin,unitsPerMeter,bounds,buildings,pois,graph,coordinateSystem,initialView}
    private var enu:Bool {coordinateSystem?.horizontalFrameVersion?.hasPrefix("WGS84_ENU") == true}
    private var frame:CampusGeoreference{CampusGeoreference(longitude:origin[0],latitude:origin[1],scale:unitsPerMeter)}
    let origin:[Double]
    let unitsPerMeter:Double
    let bounds:[[[Double]]]
    let buildings:[Building]
    let pois:[Place]
    let graph:[String:Node]
    static func load() throws -> Self {
        guard let url=Bundle.main.url(forResource:"campus-data",withExtension:"json") else {throw CocoaError(.fileNoSuchFile)}
        var data=try JSONDecoder().decode(Self.self,from:Data(contentsOf:url));if data.enu {data.surface=try CampusHeightField(directory:url.deletingLastPathComponent())};return data
    }
    func grounded(_ p:SIMD3<Float>)->SIMD3<Float>{var q=p;q.y=surface?.height(x:p.x,z:p.z) ?? p.y;return q}
    func world(_ p:[Double])->SIMD3<Float>{grounded(SIMD3(Float(p[0]),p.count>2 ? Float(p[2]):0.15,Float(-p[1])))}
    func coordinate(_ p:SIMD3<Float>)->(latitude:Double,longitude:Double){
        if enu{return frame.coordinate(x:Double(p.x),y:Double(-p.z))}
        return (origin[1]-Double(p.z)/(111320*unitsPerMeter),origin[0]+Double(p.x)/(111320*cos(origin[1] * .pi/180)*unitsPerMeter))
    }
    func world(latitude:Double,longitude:Double)->SIMD3<Float>{
        if enu{let p=frame.xy(longitude:longitude,latitude:latitude);return world([p.x,p.y])}
        return SIMD3(Float((longitude-origin[0])*111320*cos(origin[1] * .pi/180)*unitsPerMeter),0.15,Float(-(latitude-origin[1])*111320*unitsPerMeter))
    }
    func contains(_ point:SIMD3<Float>,polygon:[[Double]])->Bool {
        guard polygon.count>2 else{return false}
        let x=Double(point.x),y=Double(-point.z);var result=false;var j=polygon.count-1
        for i in polygon.indices {let a=polygon[i],b=polygon[j]
            if (a[1]>y) != (b[1]>y), x < (b[0]-a[0])*(y-a[1])/(b[1]-a[1])+a[0] {result.toggle()};j=i
        };return result
    }
    func placementError(at point:SIMD3<Float>)->String? {
        guard point.x.isFinite,point.z.isFinite,bounds.contains(where:{contains(point,polygon:$0)}) else{return "캠퍼스 경계 안의 바깥 공간을 선택해 주세요."}
        if buildings.contains(where:{contains(point,polygon:$0.p)}) {return "건물 내부입니다. 바깥 공간을 선택해 주세요."}
        return nil
    }
    func nearestNode(to point:SIMD3<Float>)->String? {graph.min{simd_distance_squared(world($0.value.p),point)<simd_distance_squared(world($1.value.p),point)}?.key}
    func nextNode(from node:String,previous:String?)->String? {
        guard let n=graph[node] else{return nil}
        let valid=n.links.filter{graph[$0] != nil && $0 != node}
        return valid.filter{$0 != previous}.randomElement() ?? valid.first
    }
}
