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

    private var loadedItems: [CollectedStoryLibraryItem] = []
    var items: [CollectedStoryLibraryItem] { loadedItems.filter { !OiContentSafetyStore.shared.isBlocked($0.story.donorID) } }
    private(set) var unavailableRecords: [CollectedStoryCard] = []
    private(set) var isLoading = false

    var records: [CollectedStoryCard] { collectionStore.cards }

    init(repository: any StoryRepository, collectionStore: StoryCollectionStore) {
        self.repository = repository
        self.collectionStore = collectionStore
    }

    var persistenceError: String? { collectionStore.persistenceError }

    @discardableResult
    func removeImported(storyID: String) -> Bool {
        guard collectionStore.remove(storyID: storyID) else { return false }
        loadedItems.removeAll { $0.id == storyID }
        unavailableRecords.removeAll { $0.storyID == storyID }
        return true
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        var loadedItems: [CollectedStoryLibraryItem] = []
        var unavailable: [CollectedStoryCard] = []

        for record in records {
            guard !Task.isCancelled else { return }
            do {
                async let story = repository.fetchPublicStory(storyID: record.storyID)
                async let storyCard = repository.fetchPublicStoryCard(storyID: record.storyID)

                guard let fetchedStory = try await story,
                      let fetchedStoryCard = try await storyCard else {
                    unavailable.append(record)
                    continue
                }

                try Task.checkCancellation()
                loadedItems.append(
                    CollectedStoryLibraryItem(
                        record: record,
                        story: fetchedStory,
                        storyCard: fetchedStoryCard
                    )
                )
            } catch {
                guard !Task.isCancelled, !OiServiceFailure.isCancellation(error) else { return }
                unavailable.append(record)
            }
        }

        guard !Task.isCancelled else { return }
        // The user can import a card while its preview is being refreshed.
        let remainingIDs = Set(records.map(\.storyID))
        self.loadedItems = loadedItems.filter { remainingIDs.contains($0.id) }
        unavailableRecords = unavailable.filter { remainingIDs.contains($0.storyID) }
    }
}
