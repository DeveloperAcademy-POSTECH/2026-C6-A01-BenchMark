// Created by 이돈혁

import Foundation

private struct LibraryCheckRepository: StoryRepository {
    func fetchPublicStory(storyID: String) async throws -> Story? {
        guard storyID == "collected-story" else { return nil }
        return Story(
            storyID: storyID,
            donorID: UUID(),
            donorDisplayName: "Test donor",
            title: "Collected story",
            content: "Collected content",
            publishedAt: Date(timeIntervalSince1970: 0),
            location: StoryLocation(locationID: "test", displayName: "Test location"),
            tags: ["Test"],
            cucumberID: "test-cucumber",
            cucumberName: "Test cucumber"
        )
    }

    func fetchPublicStoryCard(storyID: String) async throws -> StoryCard? {
        guard storyID == "collected-story" else { return nil }
        return StoryCard(
            cardID: "collected-card",
            storyID: storyID,
            imageURL: URL(string: "https://example.com/collected-card.png")!
        )
    }
}

@main
struct MYDemoChecks {
    @MainActor static func main() async {
        let demo = MYDemoStore()
        precondition(demo.cards.count == 23)
        precondition(Set(demo.cards.map(\.id)).count == demo.cards.count)
        precondition(demo.visibleCards(filter: .all, school: .postech, sort: .latest).count == 15)
        precondition(demo.visibleCards(filter: .all, school: .apple, sort: .latest).count == 8)
        precondition(demo.visibleCards(filter: .favorites, school: nil, sort: .latest).isEmpty)
        let newest = demo.collectionCards(school: nil, sort: .latest, pinnedOnly: false)
        let oldest = demo.collectionCards(school: nil, sort: .oldest, pinnedOnly: false)
        precondition(newest.map(\.id) == oldest.reversed().map(\.id))
        precondition(demo.collectionCards(school: nil, sort: .latest, pinnedOnly: true).isEmpty)
        let first = demo.cards[0]
        let apple = demo.cards[15]
        demo.toggleFavorite(first)
        demo.toggleFavorite(apple)
        precondition(demo.visibleCards(filter: .favorites, school: nil, sort: .latest).count == 2)
        precondition(demo.visibleCards(filter: .favorites, school: .postech, sort: .latest).map(\.id) == [first.id])
        precondition(demo.collectionCards(school: .postech, sort: .oldest, pinnedOnly: true).map(\.id) == [first.id])
        demo.toggleFavorite(first)
        precondition(demo.favorites == [apple.id])
        for school in MYSchool.allCases {
            let distance = demo.visibleCards(filter: .all, school: school, sort: .distance)
            precondition(zip(distance, distance.dropFirst()).allSatisfy { $0.distance <= $1.distance })
            let popular = demo.visibleCards(filter: .all, school: school, sort: .popular)
            precondition(zip(popular, popular.dropFirst()).allSatisfy { $0.popularity >= $1.popularity })
        }
        precondition(MYDemoStore().favorites.isEmpty)
        demo.collectionFilter = .schools
        precondition(demo.collectionFilter == .schools)
        precondition(MYDemoStore().collectionFilter == .all)

        let suite = "MYDemoChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let collectionStore = StoryCollectionStore(defaults: defaults)
        collectionStore.collect(
            StoryCard(
                cardID: "collected-card",
                storyID: "collected-story",
                imageURL: URL(string: "https://example.com/collected-card.png")!
            )
        )
        collectionStore.collect(
            StoryCard(
                cardID: "missing-card",
                storyID: "missing-story",
                imageURL: URL(string: "https://example.com/missing-card.png")!
            )
        )
        let library = CollectedStoryLibrary(
            repository: LibraryCheckRepository(),
            collectionStore: collectionStore
        )
        await library.load()
        precondition(library.items.map(\.id) == ["collected-story"])
        precondition(library.unavailableRecords.map(\.storyID) == ["missing-story"])
        defaults.removePersistentDomain(forName: suite)

        print("PASS: demo collection behavior and App Clip record loading into the full-app library")
    }
}
