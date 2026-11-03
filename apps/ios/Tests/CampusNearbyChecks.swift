import Foundation

@main struct CampusNearbyChecks {
    static func main() {
        let now = Date()
        // Locations A/B/C are 100m apart, so walking must replace the visible story IDs.
        let lat = 36.017, lon = 129.32
        func item(_ metres: Double, source: CampusNearbyOi.Source = .device, id: UUID = UUID()) -> CampusNearbyOi {
            CampusNearbyOi(placement: CampusPlacement(id: id, storyID: String(metres),
                latitude: lat + metres / 6_371_000 * 180 / .pi, longitude: lon), source: source)
        }
        let a = item(0), b = item(100, source: .shared), c = item(200)
        let sites = [a, b, c]
        func select(_ items: [CampusNearbyOi] = sites, at metres: Double = 0,
                    retained: Set<String> = [], accuracy: Double = 5, age: Double = 0) -> [CampusNearbyOi] {
            CampusNearbySelection.select(items, latitude: lat + metres / 6_371_000 * 180 / .pi,
                longitude: lon, accuracy: accuracy, timestamp: now.addingTimeInterval(-age), retained: retained, now: now)
        }
        precondition(select() == [a])
        precondition(select(at: 100, retained: [a.id]) == [b])
        precondition(select(at: 200, retained: [b.id]) == [c])
        precondition(select(at: 0, retained: [c.id]) == [a])
        precondition(select(at: 50, retained: [a.id, b.id]).isEmpty)
        // Enter at 25m, retain only already-visible objects through the 25–35m band.
        precondition(select([a], at: 24.9) == [a])
        precondition(select([a], at: 25.1).isEmpty)
        precondition(select([a], at: 30, retained: [a.id]) == [a])
        precondition(select([a], at: 34.9, retained: [a.id]) == [a])
        precondition(select([a], at: 35.1, retained: [a.id]).isEmpty)
        for accuracy in [-1.0, 15.1, .nan, .infinity] { precondition(select(accuracy: accuracy).isEmpty) }
        precondition(select(accuracy: 15) == [a])
        precondition(select(age: 10).isEmpty && select(age: -10).isEmpty)
        precondition(CampusNearbySelection.select(sites, latitude: .nan, longitude: lon,
            accuracy: 1, timestamp: now, retained: [], now: now).isEmpty)
        // Deletion/withdrawal removes a retained object; an edit changes its target rather than creating a duplicate.
        precondition(select([], retained: [a.id]).isEmpty)
        let moved = item(100, id: a.placement.id)
        precondition(select([moved], retained: [a.id]).isEmpty)
        precondition(select([moved], at: 100).first?.id == a.id)
        let sharedA = item(0, source: .shared, id: a.placement.id)
        precondition(a.id != sharedA.id)
        precondition(select([a, a, sharedA]).count == 2)
        let group = (0..<30).map { item(Double($0) / 2) }
        let first = select(group)
        precondition(first.count == CampusNearbySelection.maximumVisible)
        precondition(Set(select(group.reversed()).map(\.id)) == Set(first.map(\.id)))
        // No churn when slight location changes alter nearest ordering at a busy spot.
        precondition(Set(select(group, at: 4, retained: Set(first.map(\.id))).map(\.id)) == Set(first.map(\.id)))
        precondition(select([item(0, id: a.placement.id)], retained: [a.id]).first?.placement.storyID == "0.0")
        print("PASS: nearby AR A→B→C movement, multiple sources, hysteresis, stale/invalid GPS, edits/deletes, deduplication and bounded stable selection")
    }
}
