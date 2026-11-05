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

    private enum StorageError: Error { case invalidRecord }
    private static let storageKey = "collectedStoryCards.v1"
    private static let readFailure = "이 기기의 카드 기록을 읽지 못했어요. 기존 기록은 보존됩니다. 앱을 다시 열어 확인해 주세요."
    private static let writeFailure = "이 기기의 카드 기록을 변경하지 못했어요. 다시 시도해 주세요."
    private static let unavailable = "기기의 공유 카드 저장소를 열 수 없어요. 앱을 다시 열어 확인해 주세요."
    private let defaults: UserDefaults?
    private(set) var cards: [CollectedStoryCard]
    private(set) var persistenceError: String?

    init(defaults: UserDefaults? = nil) {
        let resolved = defaults ?? UserDefaults(suiteName: Self.appGroupIdentifier)
        self.defaults = resolved
        guard let resolved else {
            cards = []
            persistenceError = Self.unavailable
            return
        }
        do { cards = try Self.load(from: resolved) }
        catch { cards = []; persistenceError = Self.readFailure }
    }

    @discardableResult
    func collect(_ storyCard: StoryCard, at collectedAt: Date = .now) -> Bool {
        guard var current = readForMutation() else { return false }
        guard !current.contains(where: { $0.storyID == storyCard.storyID }) else { return false }
        current.append(CollectedStoryCard(storyID: storyCard.storyID, cardID: storyCard.cardID, collectedAt: collectedAt))
        return save(current)
    }

    func contains(storyID: String) -> Bool {
        cards.contains { $0.storyID == storyID }
    }

    @discardableResult
    func remove(storyID: String) -> Bool {
        guard let current = readForMutation() else { return false }
        let remaining = current.filter { $0.storyID != storyID }
        return remaining.count == current.count || save(remaining)
    }

    private func readForMutation() -> [CollectedStoryCard]? {
        guard let defaults else {
            persistenceError = Self.unavailable
            return nil
        }
        do {
            let current = try Self.load(from: defaults)
            cards = current
            persistenceError = nil
            return current
        } catch {
            // An unreadable value is not an empty library. Leave the stored bytes intact.
            persistenceError = Self.readFailure
            return nil
        }
    }

    private func save(_ current: [CollectedStoryCard]) -> Bool {
        guard let defaults else { return false }
        do {
            let data = try JSONEncoder().encode(current)
            defaults.set(data, forKey: Self.storageKey)
            guard defaults.data(forKey: Self.storageKey) == data else { throw StorageError.invalidRecord }
            cards = current
            return true
        } catch {
            persistenceError = Self.writeFailure
            return false
        }
    }

    private static func load(from defaults: UserDefaults) throws -> [CollectedStoryCard] {
        guard let stored = defaults.object(forKey: storageKey) else { return [] }
        guard let data = stored as? Data else { throw StorageError.invalidRecord }
        return try JSONDecoder().decode([CollectedStoryCard].self, from: data)
            .sorted { $0.collectedAt < $1.collectedAt }
    }
}
