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
        precondition(store.stories(in: "pond", sortedBy: .oldest).map(\.id) == pond.reversed().map(\.id))
        let first = pond[0], second = pond[1]
        let entry = CampusSearchEntry(story: first, publicID: nil, cucumberName: "오이 농부", code: "OI-0123",
            school: "POSTECH 포스텍", department: "컴퓨터공학과", year: "2026", donorName: "테스트농부")
        precondition(entry.matches(CampusSearchQuery(text: " 오이농부 "), mode: .name))
        precondition(entry.matches(CampusSearchQuery(text: " oi-0123 "), mode: .code))
        precondition(!entry.matches(CampusSearchQuery(text: "0123"), mode: .code))
        precondition(!entry.matches(CampusSearchQuery(), mode: .donor))
        precondition(entry.matches(CampusSearchQuery(school: "postech", name: "테스트농부"), mode: .donor))
        precondition(!entry.matches(CampusSearchQuery(school: "카이스트", name: "테스트농부"), mode: .donor))
        precondition(!entry.matches(CampusSearchQuery(department: "오이"), mode: .donor), "Cucumber name is not a department")
        precondition(entry.matches(CampusSearchQuery(school: "포스텍", department: "컴퓨터", year: "26학번", name: "테스트"), mode: .donor))
        precondition(!entry.matches(CampusSearchQuery(year: "25"), mode: .donor))
        precondition(!entry.matches(CampusSearchQuery(name: "공개닉네임"), mode: .donor))
        let missing = CampusSearchEntry(story: first, publicID: nil, cucumberName: "오이", code: "OI-99", school: "")
        precondition(!missing.matches(CampusSearchQuery(year: "26"), mode: .donor))
        precondition(!missing.matches(CampusSearchQuery(name: "농부"), mode: .donor))
        let byDistance = store.stories(in: "pond", sortedBy: .distance, distances: [first.id: 20, second.id: 1])
        precondition(byDistance.first?.id == second.id, "Distance ordering must reflect the current map center")
        let unknownDistances = store.stories(in: "pond", sortedBy: .distance)
        precondition(unknownDistances.map(\.id) == pond.map(\.id), "Missing distances must have a stable order")
        let popular = store.stories(in: "pond", sortedBy: .popular)
        precondition(zip(popular, popular.dropFirst()).allSatisfy { $0.popularity >= $1.popularity })

        let library = CampusStory(id: "library-0", regionID: "library", title: "Library", image: "OiCats",
                                  tags: [], donor: "Test", location: "Library", date: "", order: 3, popularity: 4, palette: 0)
        store.synchronize(stories: records + [library], collected: [])
        let viewport: Set<String> = [first.id, library.id]
        precondition(store.stories(matching: viewport, sortedBy: .latest).map(\.id) == [first.id, library.id],
                     "A visible viewport may include stories from more than the nearest region")
        precondition(store.stories(in: "pond", sortedBy: .latest).count == records.count)
        precondition(store.stories(matching: [], sortedBy: .latest).isEmpty,
                     "An empty visible area must not fall back to all stories")
        precondition(store.stories(matching: viewport, sortedBy: .oldest).map(\.id) == [library.id, first.id])
        store.synchronize(stories: records, collected: [])
        precondition(store.stories(matching: viewport, sortedBy: .latest).map(\.id) == [first.id],
                     "Removed server records must disappear even when the viewport result IDs are retained")

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

        let examples = CampusStoryExamples.stories
        precondition(examples.count == 3 && Set(examples.map(\.id)).count == 3)
        precondition(examples.allSatisfy { $0.isExample && UUID(uuidString: $0.id) == nil && $0.remoteMediaPaths.isEmpty && $0.latitude == nil })
        precondition(examples[0].example?.galleryImages.count == 11 && examples[0].example?.cardImage != nil)
        precondition(!examples[0].body.isEmpty && examples[1].body.isEmpty && examples[2].body.isEmpty,
                     "Do not invent Figma story bodies when only list metadata exists")
        let fixtureIDs = Set(examples.map(\.id))
        precondition(examples.allSatisfy { Set($0.example?.relatedIDs ?? []).isSubset(of: fixtureIDs) })
        let exampleStore = CampusStoryStore(defaults: defaults, isExample: true)
        exampleStore.synchronize(stories: examples + records, collected: [first.id, examples[0].id])
        precondition(exampleStore.stories == examples && exampleStore.collected.isEmpty)
        var exampleWriteAttempt = false
        exampleStore.collectAction = { _ in exampleWriteAttempt = true }
        exampleStore.collect(examples[0])
        precondition(!exampleWriteAttempt && exampleStore.collected.isEmpty)
        store.synchronize(stories: records + examples, collected: [])
        precondition(store.stories == records, "Examples must never mix into the live map or nearby AR")
        requested = nil
        store.collect(examples[0])
        precondition(requested == nil)
        store.collect(first)
        precondition(requested == first.id, "Example protection must preserve real collection transport")
        print("PASS: live story projection, search, collection and isolated Figma examples")
    }
}
