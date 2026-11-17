//
//  MYCollectedCards.swift
//  OiDonation
//
//  Created by Jiwon Hong on 11/16/26.
//

import Foundation

/// One card for MY `수집한 기부`, with the time it was collected when known.
struct MYCollectedCardEntry {
    let card: MYCard
    /// Nil for a card the account has just saved and the server has not dated yet.
    let collectedAt: Date?
}

extension MYLibraryStore {
    /// The service has paged through all stories/collections before publishing this account's snapshot.
    /// Clip records only supply IDs and collection times; card content always comes from a public story.
    func synchronizeCollectedCards(from remote: OiRemoteStore) {
        clipCollection.reload()
        guard remote.account != nil, remote.hasLoadedRemote, !remote.needsReauthentication else {
            synchronize(nickname: "농부", cards: [], favorites: [])
            return
        }
        let stories = Dictionary(uniqueKeysWithValues: remote.stories.map { ($0.id, $0) })
        func entry(storyID: UUID, collectedAt: Date?) -> MYCollectedCardEntry? {
            guard let story = stories[storyID] else { return nil }
            let region = remote.regions.first { $0.id == story.regionId }
            let school = remote.schools.first { $0.id == region?.schoolId }
            let card = MYCard(id: story.id.uuidString, title: story.cucumberName, image: story.cucumberAsset,
                school: MYSchool(id: school?.id ?? "", name: school?.name ?? "학교 정보 확인 중"), order: 0,
                body: story.body, donor: remote.profiles.first { $0.id == story.userId }?.nickname ?? "농부",
                date: story.createdDateLabel, storyID: story.id.uuidString, appearance: story.cardAsset,
                cucumberPortraitPath: story.cucumberArtwork?.path(.portrait), cardArtworkPath: story.cardArtworkPath)
            return MYCollectedCardEntry(card: card, collectedAt: collectedAt)
        }
        let accountEntries = remote.collections.compactMap {
            entry(storyID: $0.storyId, collectedAt: MYCollectedCards.date(from: $0.createdAt))
        }
        let clipEntries = clipCollection.cards.compactMap { record -> MYCollectedCardEntry? in
            guard let id = UUID(uuidString: record.storyID) else { return nil }
            return entry(storyID: id, collectedAt: record.collectedAt)
        }
        synchronize(nickname: remote.profile?.nickname ?? "농부",
            cards: MYCollectedCards.merged(account: accountEntries, clip: clipEntries),
            favorites: Set(remote.favorites.map(\.uuidString)))
    }

    func clipRecord(for card: MYCard) -> CollectedStoryCard? {
        clipCollection.cards.first { $0.storyID.caseInsensitiveCompare(card.id) == .orderedSame }
    }

    @discardableResult
    func importClipCard(_ card: MYCard, into remote: OiRemoteStore) async -> Bool {
        guard let owner = remote.account?.id, remote.hasLoadedRemote, !remote.needsReauthentication,
              !remote.isBusy, !Task.isCancelled, let id = UUID(uuidString: card.id),
              let record = clipRecord(for: card), remote.stories.contains(where: { $0.id == id }) else { return false }
        await remote.perform("collect", payload: ["id": id.uuidString])
        guard !Task.isCancelled, remote.account?.id == owner, !remote.needsReauthentication,
              remote.collections.contains(where: { $0.storyId == id }) else { return false }
        let removed = clipCollection.remove(storyID: record.storyID)
        synchronizeCollectedCards(from: remote)
        return removed
    }
}

/// MY `수집한 기부` shows the account's saved cards and the cards collected in the App Clip as one list (#409).
enum MYCollectedCards {
    /// Newest first. A story in both lists appears once, as the account's card. Undated cards count as newest.
    static func merged(account: [MYCollectedCardEntry], clip: [MYCollectedCardEntry]) -> [MYCard] {
        var seen = Set<String>()
        let unique = (account + clip).filter { seen.insert($0.card.id).inserted }
        return unique.enumerated()
            .sorted { lhs, rhs in
                let left = lhs.element.collectedAt ?? .distantFuture, right = rhs.element.collectedAt ?? .distantFuture
                return left == right ? lhs.offset < rhs.offset : left > right
            }
            .enumerated().map { index, item in
                var card = item.element.card
                card.order = index
                return card
            }
    }

    static func date(from value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
