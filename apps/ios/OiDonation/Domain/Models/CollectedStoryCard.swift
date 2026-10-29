//
//  CollectedStoryCard.swift
//  OiDonation
//
//  Created by jiwon hong on 10/29/26.
//

import Foundation
import Observation

struct CollectedStoryCard: Codable, Identifiable, Sendable, Equatable {
    var id: String { storyID }
    let storyID: String
    let cardID: String
    let collectedAt: Date
}

@MainActor
@Observable
final class StoryCollectionStore {
    nonisolated static let appGroupIdentifier = "group.com.Spero.OiDonation"

    private static let storageKey = "collectedStoryCards.v1"
    private let defaults: UserDefaults
    private(set) var cards: [CollectedStoryCard]

    init(defaults: UserDefaults? = nil) {
        if let defaults {
            self.defaults = defaults
        } else if let sharedDefaults = UserDefaults(suiteName: Self.appGroupIdentifier) {
            self.defaults = sharedDefaults
        } else {
            preconditionFailure("Unable to open the shared App Group defaults")
        }
        cards = Self.load(from: self.defaults)
    }

    @discardableResult
    func collect(_ storyCard: StoryCard, at collectedAt: Date = .now) -> Bool {
        guard !contains(storyID: storyCard.storyID) else { return false }

        cards.append(
            CollectedStoryCard(
                storyID: storyCard.storyID,
                cardID: storyCard.cardID,
                collectedAt: collectedAt
            )
        )
        save()
        return true
    }

    func contains(storyID: String) -> Bool {
        cards.contains { $0.storyID == storyID }
    }

    func remove(storyID: String) {
        let previousCount = cards.count
        cards.removeAll { $0.storyID == storyID }
        guard cards.count != previousCount else { return }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(cards) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private static func load(from defaults: UserDefaults) -> [CollectedStoryCard] {
        guard let data = defaults.data(forKey: storageKey),
              let cards = try? JSONDecoder().decode([CollectedStoryCard].self, from: data) else {
            return []
        }
        return cards.sorted { $0.collectedAt < $1.collectedAt }
    }
}
