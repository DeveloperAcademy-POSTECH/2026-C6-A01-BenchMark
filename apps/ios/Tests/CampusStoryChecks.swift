import Foundation

@main
struct CampusStoryChecks {
    @MainActor static func main() {
        let suite = "campus-checks-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["pond-0"], forKey: "campus.designExample.collectedIDs.v1")
        defaults.set("preserved", forKey: "unrelated-user-setting")
        let store = CampusStoryStore(defaults: defaults)
        precondition(defaults.object(forKey: "campus.designExample.collectedIDs.v1") == nil)
        precondition(defaults.string(forKey: "unrelated-user-setting") == "preserved")
        precondition(store.stories.isEmpty && store.collected.isEmpty)
        let records = (0..<3).map { index in
            CampusStory(id: "test-\(index)", regionID: "pond", title: "Test", image: "OiCats", tags: [], donor: "Test", location: "Test", date: "", order: index, popularity: index, palette: 0)
        }
        store.synchronize(stories: records, collected: [])
        precondition(store.story("missing") == nil)
        precondition(Set(store.stories.map(\.id)).count == records.count)
        let pond = store.stories(in: "pond", sortedBy: .latest)
        let first = pond[0], second = pond[1]
        let byDistance = store.stories(in: "pond", sortedBy: .distance, distances: [first.id: 20, second.id: 1])
        precondition(byDistance.first?.id == second.id, "Distance ordering must reflect the current map center")
        let unknownDistances = store.stories(in: "pond", sortedBy: .distance)
        precondition(unknownDistances.map(\.id) == pond.map(\.id), "Missing distances must have a stable order")
        let popular = store.stories(in: "pond", sortedBy: .popular)
        precondition(zip(popular, popular.dropFirst()).allSatisfy { $0.popularity >= $1.popularity })

        store.collect(first)
        precondition(store.collected.isEmpty, "Missing transport cannot report a successful collection")
        var requested: String?
        store.collectAction = { requested = $0.id }
        store.collect(first)
        precondition(requested == first.id && store.collected.isEmpty)
        store.synchronize(stories: records, collected: [first.id])
        precondition(store.collected == [first.id])
        let reopened = CampusStoryStore(defaults: defaults)
        precondition(reopened.collected.isEmpty, "No account data restored from an unrelated local fixture cache")
        print("PASS: live story projection, ordering and server-confirmed collection")
    }
}
