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
    let imageURL: URL
}
