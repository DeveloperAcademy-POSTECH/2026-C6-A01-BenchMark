//
//  OiRecentStories.swift
//  OiDonation
//
//  Created by Jiwon Hong on 11/16/26.
//

import Foundation

/// The stories an account opened most recently, newest first. Kept on the device only (#411):
/// the story form lists them as the targets a new donation can continue from.
enum OiRecentStories {
    /// Stored beyond the five the picker shows, so the stories left after removing the account's own still fill it.
    static let storedLimit = 20
    static let pickerLimit = 5

    private static func key(owner: UUID) -> String { "oi.recentStories.v1.\(owner.uuidString.lowercased())" }

    static func record(_ storyID: String, owner: UUID, defaults: UserDefaults = .standard) {
        var ids = self.ids(owner: owner, defaults: defaults)
        ids.removeAll { $0 == storyID }
        ids.insert(storyID, at: 0)
        defaults.set(Array(ids.prefix(storedLimit)), forKey: key(owner: owner))
    }

    static func ids(owner: UUID, defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: key(owner: owner)) ?? []
    }

    /// Up to five recently opened stories that are still public, none of them the account's own.
    static func pickerStories(owner: UUID, defaults: UserDefaults = .standard,
                              story lookup: (String) -> CampusStory?) -> [CampusStory] {
        let stories = ids(owner: owner, defaults: defaults).compactMap(lookup)
            .filter { !$0.isExample && $0.authorID != owner }
        return Array(stories.prefix(pickerLimit))
    }
}
