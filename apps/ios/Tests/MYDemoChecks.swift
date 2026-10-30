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
        let libraryStore = MYLibraryStore()
        precondition(libraryStore.cards.isEmpty && libraryStore.favorites.isEmpty)
        let school = MYSchool(id: "school-b", name: "School B")
        let first = MYCard(id: "one", title: "One", image: "OiCats", school: .postech, order: 0, body: "First", donor: "Owner", date: "")
        let second = MYCard(id: "two", title: "Two", image: "OiGardener", school: school, order: 1, body: "Second", donor: "Owner", date: "")
        libraryStore.synchronize(nickname: "Owner", cards: [first,second], favorites: [second.id,"missing"])
        precondition(libraryStore.favorites == [second.id])
        precondition(libraryStore.collectionCards(school: nil, sort: .oldest, pinnedOnly: false).map(\.id) == [second.id,first.id])
        precondition(libraryStore.collectionCards(school: .postech, sort: .latest, pinnedOnly: true).isEmpty)
        precondition(libraryStore.collectionCards(school: school, sort: .latest, pinnedOnly: true).map(\.id) == [second.id])
        libraryStore.toggleFavorite(first)
        precondition(libraryStore.favorites == [second.id], "No local success before a server receipt")
        var requested: String?
        libraryStore.favoriteAction = { requested = $0.id }
        libraryStore.toggleFavorite(first)
        precondition(requested == first.id && !libraryStore.favorites.contains(first.id))
        libraryStore.synchronize(nickname: "Other", cards: [], favorites: [])
        precondition(libraryStore.cards.isEmpty && libraryStore.favorites.isEmpty)
        libraryStore.pinnedOnly = true; libraryStore.collectionSort = .oldest
        libraryStore.resetFilters()
        precondition(!libraryStore.pinnedOnly && libraryStore.collectionSort == .latest)

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

        print("PASS: live library projection, server receipt boundary and account isolation and App Clip record loading into the full-app library")
    }
}
