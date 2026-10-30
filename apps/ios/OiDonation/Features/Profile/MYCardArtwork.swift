// Created by 이돈혁

import SwiftUI

/// Composes a card from the stored story, never a bitmap containing another donor's story.
struct MYCardArtwork: View {
    let card: MYCard

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(card.title).font(.custom("Paperlogy-6SemiBold", size: 16, relativeTo: .headline))
                .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            Image(card.image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)
            Text(card.body).font(.caption).lineLimit(3)
            Text(card.donor).font(.caption2).lineLimit(1)
            Text(card.date).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(10).aspectRatio(114 / 158, contentMode: .fit)
        .foregroundStyle(Color(red: 0.2, green: 0.28, blue: 0.13))
        .background(background, in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(CampusStyle.green.opacity(0.5)) }
        .accessibilityElement(children: .combine)
    }
    private var background: Color {
        switch card.appearance {
        case "MYBlueCard": Color(red: 0.84, green: 0.93, blue: 0.99)
        case "MYRedCard": Color(red: 0.99, green: 0.88, blue: 0.87)
        default: Color(red: 0.92, green: 0.96, blue: 0.85)
        }
    }

}
