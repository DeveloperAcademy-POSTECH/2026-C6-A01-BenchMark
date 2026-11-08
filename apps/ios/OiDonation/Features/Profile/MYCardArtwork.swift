//
//  MYCardArtwork.swift
//  OiDonation
//
//  Created by 이돈혁 on 10/30/26.
//

import SwiftUI

/// Uses the approved artwork when available and composes cards for legacy stories.
struct MYCardArtwork: View {
    let card: MYCard
    @Environment(OiRemoteStore.self) private var remote: OiRemoteStore?

    var body: some View {
        if let path = card.cardArtworkPath {
            OiCucumberPortraitImage(path: path, label: "\(card.title) 카드", load: load)
                .aspectRatio(362 / 502, contentMode: .fit)
        } else {
            OiStoryCardArtwork(name: card.title, introduction: card.body, donor: card.donor,
                date: card.date, assetName: card.image, appearance: card.appearance,
                portraitPath: card.cucumberPortraitPath, loadPortrait: load)
        }
    }

    private func load(_ path: String) async throws -> UIImage {
        guard let remote else { throw OiServiceError.unavailable }
        return try await remote.cucumberImage(path)
    }
}
