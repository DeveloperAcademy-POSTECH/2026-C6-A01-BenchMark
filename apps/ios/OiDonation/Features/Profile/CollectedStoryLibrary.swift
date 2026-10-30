// Created by jiwon hong

import Foundation
import Observation

struct CollectedStoryLibraryItem: Identifiable, Sendable {
    var id: String { record.storyID }
    let record: CollectedStoryCard
    let story: Story
    let storyCard: StoryCard
}

@MainActor
@Observable
final class CollectedStoryLibrary {
    private let repository: any StoryRepository
    private let collectionStore: StoryCollectionStore

    private(set) var items: [CollectedStoryLibraryItem] = []
    private(set) var unavailableRecords: [CollectedStoryCard] = []
    private(set) var isLoading = false

    var records: [CollectedStoryCard] { collectionStore.cards }

    init(repository: any StoryRepository, collectionStore: StoryCollectionStore) {
        self.repository = repository
        self.collectionStore = collectionStore
    }

    func removeImported(storyID: String) {
        collectionStore.remove(storyID: storyID)
        items.removeAll { $0.id == storyID }
        unavailableRecords.removeAll { $0.storyID == storyID }
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        var loadedItems: [CollectedStoryLibraryItem] = []
        var unavailable: [CollectedStoryCard] = []

        for record in records {
            do {
                async let story = repository.fetchPublicStory(storyID: record.storyID)
                async let storyCard = repository.fetchPublicStoryCard(storyID: record.storyID)

                guard let fetchedStory = try await story,
                      let fetchedStoryCard = try await storyCard else {
                    unavailable.append(record)
                    continue
                }

                loadedItems.append(
                    CollectedStoryLibraryItem(
                        record: record,
                        story: fetchedStory,
                        storyCard: fetchedStoryCard
                    )
                )
            } catch {
                unavailable.append(record)
            }
        }

        items = loadedItems
        unavailableRecords = unavailable
    }
}
