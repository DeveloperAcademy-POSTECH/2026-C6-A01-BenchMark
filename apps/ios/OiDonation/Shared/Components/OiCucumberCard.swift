//
//  OiCucumberCard.swift
//  OiDonation
//
//  Created by Jiwon Hong on 11/16/26.
//

import SwiftUI

/// Figma sizes, shrunk by the story list only as far as needed to fit its four slots without scrolling.
struct OiCucumberCardMetrics: Equatable {
    var cardHeight: CGFloat = 110
    static let standard = OiCucumberCardMetrics()
    /// Name, tag row and title without the gaps between them.
    static let textHeight: CGFloat = 59
    /// Figma 12pt top and bottom padding, 8pt only when the card is shortened.
    var cardPadding: CGFloat { cardHeight >= 104 ? 12 : 8 }
    /// Figma 8pt + 12pt between name, tags and title, tightened with the card.
    var textSpacing: CGFloat { min(20, max(8, cardHeight - cardPadding * 2 - Self.textHeight)) }
    var imageHeight: CGFloat { min(86, cardHeight - cardPadding * 2) }
}

/// Figma `5441:17267` (오이가로): name, tags and donor, then the story title, with the cucumber on the right.
/// Shared by the story list and the map's region list (#399).
struct OiCucumberCard<Portrait: View>: View {
    let name: String
    let tags: [String]
    let donor: String
    let title: String
    var metrics = OiCucumberCardMetrics.standard
    /// A thin border for screens that use an outlined card instead of a shadow (#411).
    var outline: Color?
    var selectionOutline: Color?
    var showsShadow = true
    var portraitIsDecorative = true
    @ViewBuilder let portrait: () -> Portrait

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var usesAccessibilityLayout: Bool { dynamicTypeSize.isAccessibilitySize }

    private static var tagColor: Color { Color(red: 79 / 255, green: 110 / 255, blue: 223 / 255) }
    private static var donorColor: Color { Color(red: 83 / 255, green: 83 / 255, blue: 83 / 255) }

    var body: some View {
        Group {
            if usesAccessibilityLayout {
                VStack(alignment: .leading, spacing: 12) { text; image }
            } else {
                HStack(spacing: 10) { text; image }
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.vertical, metrics.cardPadding)
        .frame(maxWidth: .infinity, minHeight: metrics.cardHeight,
               maxHeight: usesAccessibilityLayout ? nil : metrics.cardHeight, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 28)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(showsShadow ? 0.25 : 0), radius: 2)
        }
        .overlay {
            if let selectionOutline {
                RoundedRectangle(cornerRadius: 28).strokeBorder(selectionOutline, lineWidth: 2)
                    .allowsHitTesting(false)
            } else if let outline {
                RoundedRectangle(cornerRadius: 28).strokeBorder(outline, lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 28))
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: metrics.textSpacing * 0.6) {
            VStack(alignment: .leading, spacing: metrics.textSpacing * 0.4) {
                Text(name)
                    .font(.custom("YANGJIN", size: 22, relativeTo: .title2))
                    .tracking(0.44)
                    .foregroundStyle(.black)
                    .lineLimit(usesAccessibilityLayout ? nil : 1)
                    .minimumScaleFactor(usesAccessibilityLayout ? 1 : 0.8)
                    .frame(minHeight: 20, alignment: .bottomLeading)
                tagsAndDonor
            }
            if !title.isEmpty {
                Text(title)
                    .font(.custom("Paperlogy-3Light", size: 18, relativeTo: .body))
                    .foregroundStyle(.black)
                    .lineLimit(usesAccessibilityLayout ? nil : 1)
                    .frame(minHeight: 18, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var tagsAndDonor: some View {
        let tagViews = HStack(spacing: 4) {
            ForEach(Array(tags.prefix(2).enumerated()), id: \.offset) { _, tag in
                Text("#" + tag).foregroundStyle(Self.tagColor)
            }
        }
        let donorView = Text(donor).foregroundStyle(Self.donorColor)
        Group {
            if usesAccessibilityLayout {
                VStack(alignment: .leading, spacing: 4) { tagViews; donorView }
            } else {
                HStack(spacing: 6) { tagViews; donorView }
            }
        }
        .font(.custom("Paperlogy-4Regular", size: 12, relativeTo: .caption))
        .tracking(0.24)
        .lineLimit(usesAccessibilityLayout ? nil : 1)
    }

    private var image: some View {
        portrait()
            .frame(width: 50 * metrics.imageHeight / 86, height: 78 * metrics.imageHeight / 86)
            .frame(width: 66 * metrics.imageHeight / 86, height: metrics.imageHeight)
            .background(Color(red: 239 / 255, green: 239 / 255, blue: 239 / 255), in: RoundedRectangle(cornerRadius: 16))
            .accessibilityHidden(portraitIsDecorative)
    }
}
