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
