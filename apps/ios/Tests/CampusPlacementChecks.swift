import Foundation
import simd

@main struct CampusPlacementChecks {
    @MainActor static func main() throws {
        let resourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
        var map = try JSONDecoder().decode(CampusMapData.self, from: Data(contentsOf: resourceURL.appending(path: "campus-data.json")))
        map.surface = try CampusHeightField(directory: resourceURL)
        for node in map.graph.values {
            guard let ll = node.wgs84 else { preconditionFailure("Missing source coordinates") }
            let world = map.world(latitude: ll[1], longitude: ll[0])
            let back = map.coordinate(world)
            precondition(abs(back.latitude - ll[1]) < 0.000001 && abs(back.longitude - ll[0]) < 0.000001,
                         "WGS84/map round trip must stay within numeric tolerance")
        }
        let point = map.graph.values.map { map.world($0.p) }.first { map.placementError(at: $0) == nil }!
        let ll = map.coordinate(point)
        let record = CampusPlacement(storyID: "example", latitude: ll.latitude, longitude: ll.longitude)
        let metres = record.offsetMeters(fromLatitude: map.origin[1], longitude: map.origin[0])
        precondition(abs(metres.x * Float(map.unitsPerMeter) - point.x) < 0.001)
        precondition(abs(metres.z * Float(map.unitsPerMeter) - point.z) < 0.001, "AR north axis and map scale must agree")
        precondition(simd_length(record.offsetMeters(fromLatitude: ll.latitude, longitude: ll.longitude)) < 0.001)
        // Selection precision must be measured in real metres, independent of map rotation.
        let scale = Float(map.unitsPerMeter)
        for yaw: Float in [0, .pi / 2, .pi, -.pi / 2] {
            for step in [0.1, 0.5, 1.0] {
                let right = CampusPlacementGeometry.offset(right: 1, forward: 0, meters: step, yaw: yaw, unitsPerMeter: map.unitsPerMeter)
                let up = CampusPlacementGeometry.offset(right: 0, forward: 1, meters: step, yaw: yaw, unitsPerMeter: map.unitsPerMeter)
                precondition(abs(simd_length(right) / scale - Float(step)) < 0.0001)
                precondition(abs(simd_dot(right, up)) < 0.0001, "Screen directions must stay perpendicular")
                let reverse = CampusPlacementGeometry.offset(right: -1, forward: 0, meters: step, yaw: yaw, unitsPerMeter: map.unitsPerMeter)
                precondition(simd_length(right + reverse) < 0.0001)
            }
        }
        let north = CampusPlacementGeometry.offset(right: 0, forward: 1, meters: 1, yaw: 0, unitsPerMeter: map.unitsPerMeter)
        let east = CampusPlacementGeometry.offset(right: 1, forward: 0, meters: 1, yaw: 0, unitsPerMeter: map.unitsPerMeter)
        precondition(north.z < 0 && east.x > 0)
        let movedNorth = map.coordinate(point + north)
        precondition(movedNorth.latitude > ll.latitude)
        precondition(abs(record.distance(latitude: movedNorth.latitude, longitude: movedNorth.longitude) - 1) < 0.01)
        for height in [0.4, 1, 2] {
            let precise = CampusPlacementGeometry.mapScale(heightMeters: height, unitsPerMeter: map.unitsPerMeter, editing: true)
            precondition(abs(precise / scale - Float(height)) < 0.0001, "Editing uses the physical AR height")
            let browse = CampusPlacementGeometry.mapScale(heightMeters: height, unitsPerMeter: map.unitsPerMeter, editing: false)
            precondition(abs(browse / precise - 20) < 0.0001)
        }
        let safeNudge = map.graph.values.compactMap { node -> (SIMD3<Float>, SIMD3<Float>)? in
            let start = map.world(node.p)
            guard map.placementError(at: start) == nil,
                  let end = try? map.nudgedPlacement(from: start, right: 1, forward: 0, meters: 0.1, yaw: 0)
            else { return nil }
            return (start, end)
        }.first!
        precondition(abs((safeNudge.1.x - safeNudge.0.x) / scale - 0.1) < 0.001)
        precondition(safeNudge.1.y == map.surface?.height(x: safeNudge.1.x, z: safeNudge.1.z))
        precondition((try? map.nudgedPlacement(from: SIMD3(10000, 0, 10000), right: 1, forward: 0, meters: 1, yaw: 0)) == nil)
        precondition((try? map.nudgedPlacement(from: point, right: 1, forward: 0, meters: .nan, yaw: 0)) == nil)
        let buildingPoint = map.buildings.compactMap { building -> SIMD3<Float>? in
            guard !building.p.isEmpty else { return nil }
            let x = building.p.map { $0[0] }.reduce(0, +) / Double(building.p.count)
            let y = building.p.map { $0[1] }.reduce(0, +) / Double(building.p.count)
            let p = map.world([x, y])
            return map.contains(p, polygon: building.p) ? p : nil
        }.first!
        precondition((try? map.nudgedPlacement(from: buildingPoint, right: 0, forward: 0, meters: 0.1, yaw: 0)) == nil)
        let now = Date()
        func quality(_ accuracy: Double = 5, age: Double = 0, lat: Double? = nil) -> Bool {
            CampusLocationQuality.allowsPlacement(latitude: lat ?? ll.latitude, longitude: ll.longitude,
                accuracy: accuracy, timestamp: now.addingTimeInterval(-age), target: record, now: now)
        }
        precondition(quality() && quality(15))
        precondition(!quality(-1) && !quality(15.1) && !quality(.nan))
        precondition(!quality(age: 11) && !quality(age: -11) && !quality(lat: ll.latitude + 0.001))

        let directory = FileManager.default.temporaryDirectory.appending(path: "campus-placement-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = LocalCampusPlacementRepository(url: directory.appending(path: "placements.json"))
        let store = CampusPlacementStore(repository: repository)
        store.load(map: map, storyIDs: ["example"])
        precondition(store.ready && store.save(record))
        precondition(store.save(record) && store.placements.count == 1, "Retry must upsert without duplicating")
        let reopened = CampusPlacementStore(repository: repository)
        reopened.load(map: map, storyIDs: ["example"])
        precondition(reopened.placements == [record], "Coordinates, identity and story must survive relaunch")
        precondition(!store.save(CampusPlacement(storyID: "unknown", latitude: ll.latitude, longitude: ll.longitude)))
        precondition(!store.save(CampusPlacement(storyID: "example", latitude: 0, longitude: 0)))
        precondition(!store.save(CampusPlacement(storyID: "example", latitude: .nan, longitude: ll.longitude)))
        precondition(!store.save(CampusPlacement(storyID: "example", latitude: ll.latitude, longitude: ll.longitude, heightMeters: 10)))
        let buildingCenter = map.buildings.compactMap { building -> SIMD3<Float>? in
            guard !building.p.isEmpty else { return nil }
            let sum = building.p.reduce(SIMD2<Double>.zero) { $0 + SIMD2($1[0], $1[1]) } / Double(building.p.count)
            let center = SIMD3<Float>(Float(sum.x), 0, Float(-sum.y))
            return map.contains(center, polygon: building.p) ? center : nil
        }.first!
        precondition(map.placementError(at: buildingCenter) != nil, "Building footprints cannot accept placements")
        precondition(store.placements == [record], "Invalid writes must preserve the previous state")
        let otherPoint = map.graph.values.map { map.world($0.p) }.first {
            simd_distance($0, point) > 5 && map.placementError(at: $0) == nil
        }!
        let otherLL = map.coordinate(otherPoint)
        let moved = CampusPlacement(id: record.id, storyID: record.storyID,
            latitude: otherLL.latitude, longitude: otherLL.longitude,
            heightMeters: record.heightMeters, headingDegrees: record.headingDegrees)
        precondition(store.update(moved) && store.placements == [moved], "Moving must replace the same ID, not create another cucumber")
        let movedReload = CampusPlacementStore(repository: repository)
        movedReload.load(map: map, storyIDs: ["example"])
        precondition(movedReload.placements == [moved], "Moved coordinates and story must persist after relaunch")
        let unknownUpdate = CampusPlacement(storyID: "example", latitude: ll.latitude, longitude: ll.longitude)
        precondition(!store.update(unknownUpdate) && store.placements == [moved], "Editing a deleted/missing ID must not recreate it")
        let invalidMove = CampusPlacement(id: record.id, storyID: record.storyID, latitude: 0, longitude: 0)
        precondition(!store.update(invalidMove) && store.placements == [moved], "Invalid moves must leave the saved coordinates intact")

        for _ in 0..<19 {
            precondition(store.save(CampusPlacement(storyID: "example", latitude: ll.latitude, longitude: ll.longitude)))
        }
        let allIDs = store.placements.map(\.id)
        precondition(store.update(record) && store.placements.count == 20, "Moving is allowed at the placement limit")
        precondition(store.placements.map(\.id) == allIDs, "Moving must preserve the list order and other placements")
        precondition(store.remove(record.id) && store.placements.count == 19)
        let afterDelete = try repository.load()
        precondition(afterDelete.map(\.id) == Array(allIDs.dropFirst()), "Deletion must remove only the selected ID")
        for remaining in store.placements { precondition(store.remove(remaining.id)) }
        let deleted = try repository.load()
        precondition(deleted.isEmpty)
        try Data("invalid JSON".utf8).write(to: repository.url)
        let corrupt = CampusPlacementStore(repository: repository)
        corrupt.load(map: map, storyIDs: ["example"])
        precondition(!corrupt.ready && !corrupt.save(record))
        let original = try String(contentsOf: repository.url, encoding: .utf8)
        precondition(original == "invalid JSON", "Do not overwrite damaged originals")

        let failing = FailingRepository(records: [record])
        let atomicStore = CampusPlacementStore(repository: failing)
        atomicStore.load(map: map, storyIDs: ["example"])
        precondition(!atomicStore.update(moved) && atomicStore.placements == [record], "Failed writes must not publish a move")
        atomicStore.remove(record.id)
        precondition(atomicStore.placements == [record] && atomicStore.error != nil, "Failed disk writes must not publish a deletion")
        print("PASS: \(map.graph.count) coordinate round trips, physical scale, rotated 10/50/100cm nudges, terrain/building/boundary validation, proximity/freshness, move/delete persistence, identity/capacity/order, invalid/corrupt/failed writes")
    }
}

@MainActor private struct FailingRepository: CampusPlacementRepository {
    let records: [CampusPlacement]
    func load() throws -> [CampusPlacement] { records }
    func save(_ placements: [CampusPlacement]) throws { throw CocoaError(.fileWriteNoPermission) }
}
