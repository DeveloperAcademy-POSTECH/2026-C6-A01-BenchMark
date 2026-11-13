//
//  StoryCard.swift
//  OiDonation
//
//  Created by jiwon hong on 10/28/26.
//

import Foundation

struct StoryCard: Identifiable, Sendable {
    var id: String { cardID }
    let cardID: String
    let storyID: String
    let imageURL: URL?

    static func artworkPath(owner: UUID, story: UUID, snapshot: UUID) -> String {
        "\(owner.uuidString.lowercased())/\(story.uuidString.lowercased())/card/\(snapshot.uuidString.lowercased()).png"
    }

    /// Postcard back rendered next to the front (#291). Shares the reviewed snapshot ID, so approving
    /// a card publishes its matching back. Stories submitted before this have no back file.
    static func backArtworkPath(owner: UUID, story: UUID, snapshot: UUID) -> String {
        "\(owner.uuidString.lowercased())/\(story.uuidString.lowercased())/card/\(snapshot.uuidString.lowercased())-back.png"
    }
}
