import Foundation

@main
struct CampusStoryChecks {
    @MainActor static func main() {
        let suite = "campus-checks-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CampusStoryStore(defaults: defaults)
        precondition(Set(store.stories.map(\.id)).count == store.stories.count, "Story routes must have unique identifiers")
        for region in CampusRegion.examples {
            precondition(store.stories(in: region.id, sortedBy: .latest).count == region.sampleCount, "Map counts must match the region list")
        }
        precondition(store.story("missing") == nil)
        precondition(store.stories(in: "missing", sortedBy: .latest).isEmpty)

        let pond = store.stories(in: "pond", sortedBy: .latest)
        let first = pond[0], second = pond[1]
        let byDistance = store.stories(in: "pond", sortedBy: .distance, distances: [first.id: 20, second.id: 1])
        precondition(byDistance.first?.id == second.id, "Distance ordering must reflect the current map center")
        let unknownDistances = store.stories(in: "pond", sortedBy: .distance)
        precondition(unknownDistances.map(\.id) == pond.map(\.id), "Missing distances must have a stable order")
        let popular = store.stories(in: "pond", sortedBy: .popular)
        precondition(zip(popular, popular.dropFirst()).allSatisfy { $0.popularity >= $1.popularity })

        precondition(store.collected.isEmpty)
        store.collect(first)
        store.collect(first)
        precondition(store.collected == [first.id], "Repeated taps must not create duplicate collection records")
        let reopened = CampusStoryStore(defaults: defaults)
        precondition(reopened.collected == [first.id], "Collection must survive reopening the app")
        reopened.collect(second)
        precondition(reopened.collected == [first.id, second.id])
        precondition(store.stories.count == reopened.stories.count, "Collecting must not remove map stories")
        print("PASS: unique routes, map counts, distance/popularity sorting, idempotent persistent collection")
    }
}
