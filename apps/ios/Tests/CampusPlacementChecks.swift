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
        reopened.remove(record.id)
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
        atomicStore.remove(record.id)
        precondition(atomicStore.placements == [record] && atomicStore.error != nil, "Failed disk writes must not publish a deletion")
        print("PASS: \(map.graph.count) coordinate round trips, metre scale/north axis, proximity/freshness, persistence, story IDs, invalid/corrupt/failed writes")
    }
}

@MainActor private struct FailingRepository: CampusPlacementRepository {
    let records: [CampusPlacement]
    func load() throws -> [CampusPlacement] { records }
    func save(_ placements: [CampusPlacement]) throws { throw CocoaError(.fileWriteNoPermission) }
}
