//
//  AppClipStoryCardView.swift
//  OiDonationClip
//
//  Created by jiwon hong on 10/28/26.
//

import SwiftUI
import UIKit

struct AppClipStoryCardView: View {
    let experience: AppClipExperience
    let isCollected: Bool
    let onCollect: () -> Void
    let onCancel: () -> Void

    private var story: Story { experience.story }

    var body: some View {
        GeometryReader { geometry in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 38) {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(story.cucumberName).font(.title.bold())
                        Text(story.content).font(.body)
                        Text(story.donorDisplayName).font(.caption)
                    }.padding(24).frame(minHeight: 300).background(.background, in: RoundedRectangle(cornerRadius: 20))
                        .aspectRatio(320 / 444, contentMode: .fit)
                        .frame(width: min(320, geometry.size.width - 32))
                        .shadow(color: .black.opacity(0.25), radius: 3.5, x: 3, y: 6)

                    summaryCard
                        .frame(maxWidth: 380)
                        .padding(.horizontal, 11)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 52)
                .padding(.bottom, max(34, geometry.safeAreaInsets.bottom + 8))
            }
        }
        .background(storyCardBackground.ignoresSafeArea())
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 5) {
                Text(story.cucumberName)
                    .font(.custom("KIMWILDgag-BOLD", size: 30, relativeTo: .title))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)

                verifiedBadge

                Spacer(minLength: 8)

                tags
            }

            Text(metadataText)
                .font(.custom("GriunOMIRI-Regular", size: 10, relativeTo: .caption2))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .padding(.top, 1)

            Text("“ \(story.content)”")
                .font(.custom("GriunOMIRI-Regular", size: 18, relativeTo: .body))
                .tracking(-0.72)
                .lineSpacing(2)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 11)

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Button(action: onCollect) {
                    HStack(spacing: 5) {
                        if isCollected {
                            Image(systemName: "checkmark")
                        }
                        Text(isCollected ? "이 기기에 보관됨" : "이 기기에 보관하기")
                    }
                        .font(.custom("Paperlogy-6SemiBold", size: 14, relativeTo: .callout))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(collectButtonGradient, in: RoundedRectangle(cornerRadius: 20))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("appclip.storyCard.collect")

                Button("취소", action: onCancel)
                    .buttonStyle(.plain)
                    .font(.custom("Paperlogy-6SemiBold", size: 14, relativeTo: .callout))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 44)
                    .background(Color(red: 0.867, green: 0.867, blue: 0.867), in: Capsule())
                    .accessibilityIdentifier("appclip.storyCard.cancel")
            }
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 19)
        .padding(.vertical, 17)
        .frame(maxWidth: .infinity, minHeight: 213)
        .background(.white, in: RoundedRectangle(cornerRadius: 30))
        .shadow(color: .black.opacity(0.25), radius: 3, x: 2, y: 3)
    }

    private var tags: some View {
        HStack(spacing: 4) {
            ForEach(story.tags.prefix(2), id: \.self) { tag in
                Text(tag)
                    .font(.custom("Mona12TextKR-Regular", size: 13, relativeTo: .caption))
                    .tracking(-0.52)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                    .background(Color(red: 0.941, green: 0.941, blue: 0.941), in: Capsule())
            }
        }
    }

    private var verifiedBadge: some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.831, green: 0.714, blue: 0.345))
            Image(systemName: "checkmark")
                .font(.system(size: 7, weight: .black))
                .foregroundStyle(Color(red: 1, green: 0.949, blue: 0.808))
        }
        .frame(width: 14, height: 14)
        .accessibilityHidden(true)
    }

    private var metadataText: String {
        "\(story.donorDisplayName)  |  \(story.location.displayName)  |  \(Self.dateFormatter.string(from: story.publishedAt))"
    }

    private var storyCardBackground: Color {
        Color(red: 0.867, green: 0.918, blue: 0.953)
    }

    private var collectButtonGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.337, green: 0.651, blue: 0.867),
                Color(red: 0.145, green: 0.408, blue: 0.631)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy.MM.dd.EEE"
        return formatter
    }()
}
