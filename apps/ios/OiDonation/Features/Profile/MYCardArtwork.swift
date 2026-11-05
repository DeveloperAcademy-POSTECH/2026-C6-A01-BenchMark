//
//  MYCardArtwork.swift
//  OiDonation
//
//  Created by 이돈혁 on 10/30/26.
//

import SwiftUI

/// Composes a card from the stored story, never a bitmap containing another donor's story.
struct MYCardArtwork: View {
    let card: MYCard

    var body: some View {
        OiStoryCardArtwork(name: card.title, introduction: card.body, donor: card.donor,
                           date: card.date, assetName: card.image, appearance: card.appearance)
    }
}
