//
//  Story.swift
//  OiDonation
//
//  Created by jiwon hong on 10/9/26.
//

import Foundation

struct StoryLocation: Sendable {
    let locationID: String
    let displayName: String
}

struct Story: Identifiable, Sendable {
    var id: String { storyID }
    let storyID: String
    let donorID: UUID
    let donorDisplayName: String
    let title: String
    let content: String
    let publishedAt: Date
    let location: StoryLocation
    let tags: [String]
    let cucumberID: String
    let cucumberName: String
    let cucumberImageURL: URL?

    init(
        storyID: String,
        donorID: UUID,
        donorDisplayName: String,
        title: String,
        content: String,
        publishedAt: Date,
        location: StoryLocation,
        tags: [String],
        cucumberID: String,
        cucumberName: String,
        cucumberImageURL: URL? = nil
    ) {
        self.storyID = storyID
        self.donorID = donorID
        self.donorDisplayName = donorDisplayName
        self.title = title
        self.content = content
        self.publishedAt = publishedAt
        self.location = location
        self.tags = tags
        self.cucumberID = cucumberID
        self.cucumberName = cucumberName
        self.cucumberImageURL = cucumberImageURL
    }
}
