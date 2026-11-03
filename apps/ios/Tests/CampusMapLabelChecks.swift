import Foundation
import CoreGraphics
import simd

@main struct CampusMapLabelChecks {
    static func main() throws {
        let url = URL(fileURLWithPath: CommandLine.arguments[1]).appending(path: "campus-data.json")
        let data = try JSONDecoder().decode(CampusMapData.self, from: Data(contentsOf: url))
        let labels = CampusBuildingLabel.catalog(data)
        precondition(!labels.isEmpty && Set(labels.map(\.id)).count == labels.count)
        for label in labels {
            let building = data.buildings.first { $0.id == label.id }!
            precondition(data.contains(label.anchor, polygon: building.p), "Names must anchor on their own roof, including concave buildings")
            precondition(label.anchor.y > Float(building.modelRoofZ!), "Names use model roof height, not terrain height")
            precondition(!label.title.isEmpty && Double(label.title) == nil)
            precondition(label.roof.count == building.p.count)
        }
        for title in ["C5", "생명공학연구센터", "박태준학술정보관", "지곡회관", "학생회관"] {
            precondition(labels.contains { $0.title == title }, "Missing actual campus building: \(title)")
        }
        let rist = data.buildingLabelGroups!.first { $0.id == "rist-labs" }!
        precondition(rist.name == "RIST 실험동" && Set(rist.buildingIDs).count == 8)
        precondition(CampusBuildingLabel.groups(data).contains { $0.id == rist.id && $0.title == rist.name })
        for id in rist.buildingIDs {
            let original = data.buildings.first { $0.id == id }!
            precondition(original.name?.isEmpty == true, "Shared label must not fabricate an official wing name")
            precondition(labels.first { $0.id == id }?.title == "RIST 실험동")
        }
        precondition(labels.filter { $0.title == "RIST 실험동" }.count == 8)
        precondition(labels.first { $0.id == "294906154" }?.title == "포항산업과학연구원 연구1동",
                     "Southern RIST research buildings must keep their own names")

        // A single C/L-shaped building with multiple POIs must not produce overlapping room names.
        let concave = CampusMapData.Building(id: "concave", p: [[0, 0], [8, 0], [8, 1], [1, 1], [1, 8], [0, 8]],
            name: "테스트관 (Test Hall)", levels: nil, kind: nil, modelRoofZ: 12)
        let unnamed = CampusMapData.Building(id: "unnamed", p: concave.p, name: nil, levels: nil, kind: nil, modelRoofZ: 12)
        let numeric = CampusMapData.Building(id: "number", p: concave.p, name: "101", levels: nil, kind: nil, modelRoofZ: 12)
        let malformed = CampusMapData.Building(id: "malformed", p: [[0], [1, 1], [2, 3]], name: "invalid", levels: nil, kind: nil, modelRoofZ: 12)
        let sample = CampusMapData(coordinateSystem: nil, initialView: nil, origin: [0, 0], unitsPerMeter: 1,
            bounds: [], buildings: [concave, unnamed, numeric, malformed], pois: [], graph: [:])
        let sampleLabels = CampusBuildingLabel.catalog(sample)
        precondition(sampleLabels.count == 1 && sampleLabels[0].title == "테스트관")
        precondition(sample.contains(sampleLabels[0].anchor, polygon: concave.p))
        precondition(CampusBuildingLabel.groups(sample).isEmpty, "Older map data without label groups remains supported")

        typealias Layout = CampusMapLabelLayout
        precondition(Layout.level(pixelsPerUnit: 4, previous: .areas) == .areas)
        precondition(Layout.level(pixelsPerUnit: 7, previous: .areas) == .buildings)
        precondition(Layout.level(pixelsPerUnit: 6, previous: .buildings) == .buildings)
        precondition(Layout.level(pixelsPerUnit: 6, previous: .areas) == .areas, "Small pinch reversals must not flicker")
        precondition(Layout.level(pixelsPerUnit: 5, previous: .buildings) == .areas)
        precondition(Layout.canNameBuilding(footprint: CGRect(x: 0, y: 0, width: 100, height: 40)))
        precondition(!Layout.canNameBuilding(footprint: CGRect(x: 0, y: 0, width: 30, height: 20)))
        precondition(!Layout.canNameBuilding(footprint: CGRect(x: 0, y: 0, width: 100, height: 8)), "A nearly edge-on roof must not get a name")
        precondition(!Layout.canNameBuilding(footprint: .null))

        let viewport = CGRect(x: 0, y: 100, width: 400, height: 500)
        let first = CGRect(x: 100, y: 200, width: 80, height: 20)
        let alternate = CGRect(x: 100, y: 260, width: 80, height: 20)
        let items: [Layout.Candidate] = [
            .init(id: "landmark", frame: first),
            .init(id: "overlap", frame: first.offsetBy(dx: 20, dy: 0)),
            .init(id: "header", frame: CGRect(x: 20, y: 80, width: 80, height: 20)),
            .init(id: "area", frame: first, alternatives: [alternate]),
            .init(id: "button", frame: CGRect(x: 300, y: 500, width: 70, height: 20))
        ]
        let placements = Layout.placements(items, viewport: viewport,
            obstacles: [CGRect(x: 300, y: 480, width: 80, height: 80)])
        precondition(placements == ["landmark": first, "area": alternate], "Names avoid markers, controls, other names and clipped edges")
        precondition(Layout.placements(items, viewport: .zero, obstacles: []).isEmpty)
        print("Campus map labels: PASS (\(labels.count) named roofs, concave anchors, zoom hysteresis, footprint visibility, collision layout)")
    }
}
