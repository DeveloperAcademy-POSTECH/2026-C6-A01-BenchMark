//
//  CampusCucumberCameraSubject.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/15/26.
//

import Foundation
import RealityKit

@MainActor
enum CampusCucumberCameraSubject {
    static func make(story: CampusStory, remote: OiRemoteStore) -> ARCameraSubject? {
        guard !story.isExample, let id = UUID(uuidString: story.id),
              let latitude = story.latitude, let longitude = story.longitude,
              let placement = CampusPlacement.story(id: id, latitude: latitude, longitude: longitude,
                  heightMeters: story.heightMeters, headingDegrees: story.headingDegrees) else { return nil }
        var subject = ARCameraSubject(id: id, title: story.title, heightMeters: Float(story.heightMeters), placement: placement) {
            // Recheck the public role on each load/retry; never render a private draft
            // or fall back to a different character when approved artwork fails.
            let current = try await remote.publishedStory(id)
            // Never use an old coordinate/height after a story has been edited.
            guard current.campusPlacement == placement else { throw OiServiceError.unavailable }
            if let artwork = current.cucumberArtwork { return try await remote.cucumberModel(artwork) }
            return try await CampusOiAsset.load()
        }
        subject.loadThumbnail = {
            let current = try await remote.publishedStory(id)
            guard current.campusPlacement == placement, let path = current.cucumberArtwork?.path(.portrait) else {
                throw OiServiceError.unavailable
            }
            return try await remote.cucumberImage(path)
        }
        return subject
    }
}
