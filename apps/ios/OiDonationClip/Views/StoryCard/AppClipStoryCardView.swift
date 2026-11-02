//
//  AppClipStoryCardView.swift
//  OiDonationClip
//
//  Created by jiwon hong on 10/28/26.
//

import SwiftUI
import UIKit

struct AppClipStoryCardView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title) private var titleLineSpacing = 8

    let experience: AppClipExperience
    let isCollected: Bool
    let onCollect: () -> Void
    let onCancel: () -> Void

    private var story: Story { experience.story }

    var body: some View {
        GeometryReader { geometry in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 34) {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(story.cucumberName).font(.title.bold())
                        Text(story.content).font(.body)
                        Text(story.donorDisplayName).font(.caption)
                    }
                    .padding(24)
                    .frame(minHeight: 300)
                    .background(.background, in: RoundedRectangle(cornerRadius: 20))
                        .aspectRatio(320 / 444, contentMode: .fit)
                        .frame(width: min(320, geometry.size.width - 32))
                        .shadow(color: .black.opacity(0.25), radius: 3.5, x: 3, y: 6)

                    summaryCard
                        .frame(width: min(362, geometry.size.width - 40), height: usesAccessibilityLayout ? nil : 216)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 42)
                .padding(.bottom, max(34, geometry.safeAreaInsets.bottom + 8))
            }
        }
        .background(storyCardBackground.ignoresSafeArea())
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerLayout {
                Text(story.title)
                    .font(.custom("PearToucan-Regular", size: 28, relativeTo: .title).weight(.bold))
                    .tracking(1.12)
                    .lineSpacing(usesAccessibilityLayout ? titleLineSpacing : 0)
                    .lineLimit(usesAccessibilityLayout ? nil : 1)
                    .minimumScaleFactor(0.65)
                    .fixedSize(horizontal: false, vertical: usesAccessibilityLayout)

                if !usesAccessibilityLayout {
                    Spacer(minLength: 0)
                }

                tags
            }

            metadata

            actionsLayout {
                Button(action: onCollect) {
                    HStack(spacing: 5) {
                        if isCollected {
                            Image(systemName: "checkmark")
                        }
                        Text(isCollected ? "이 기기에 보관됨" : "이 기기에 보관하기")
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: usesAccessibilityLayout)
                    }
                        .font(.custom("Paperlogy-6SemiBold", size: 14, relativeTo: .callout))
                        .foregroundStyle(.white)
                        .padding(.horizontal, usesAccessibilityLayout ? 12 : 0)
                        .padding(.vertical, usesAccessibilityLayout ? 12 : 0)
                        .frame(maxWidth: .infinity, minHeight: 44, maxHeight: usesAccessibilityLayout ? nil : 44)
                        .background(collectButtonColor, in: RoundedRectangle(cornerRadius: 20))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: usesAccessibilityLayout ? .infinity : 239)
                .accessibilityIdentifier("appclip.storyCard.collect")

                Button("삭제", action: onCancel)
                    .buttonStyle(.plain)
                    .font(.custom("Paperlogy-6SemiBold", size: 14, relativeTo: .callout))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: usesAccessibilityLayout)
                    .padding(.vertical, usesAccessibilityLayout ? 12 : 0)
                    .frame(maxWidth: usesAccessibilityLayout ? .infinity : nil, minHeight: 44)
                    .frame(width: usesAccessibilityLayout ? nil : 67)
                    .background(Color(red: 0.867, green: 0.867, blue: 0.867), in: Capsule())
                    .accessibilityIdentifier("appclip.storyCard.cancel")
            }
        }
        .foregroundStyle(.black)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: usesAccessibilityLayout ? nil : .infinity)
        .background(.white, in: RoundedRectangle(cornerRadius: 30))
        .shadow(color: Color(red: 0.18, green: 0.31, blue: 0.09).opacity(0.4), radius: 5)
    }

    private var tags: some View {
        tagsLayout {
            ForEach(story.tags.prefix(2), id: \.self) { tag in
                Text(tag)
                    .font(.custom("Paperlogy-4Regular", size: 16, relativeTo: .caption))
                    .tracking(0.32)
                    .lineLimit(usesAccessibilityLayout ? nil : 1)
                    .fixedSize(horizontal: false, vertical: usesAccessibilityLayout)
                    .padding(.horizontal, 14)
                    .padding(.vertical, usesAccessibilityLayout ? 8 : 0)
                    .frame(height: usesAccessibilityLayout ? nil : 30)
                    .background(Color(red: 0.812, green: 0.812, blue: 0.812), in: Capsule())
            }
        }
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 6) {
            metadataRow(label: "기부자", value: story.donorDisplayName)
            metadataRow(label: "위치", value: story.location.displayName)
            metadataRow(label: "날짜", value: Self.dateFormatter.string(from: story.publishedAt))
        }
        .font(.custom("Paperlogy-4Regular", size: 15, relativeTo: .caption))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metadataRow(label: String, value: String) -> some View {
        metadataLayout {
            Text(label)
            if !usesAccessibilityLayout {
                Text("|")
            }
            Text(value)
                .lineLimit(usesAccessibilityLayout ? nil : 1)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: usesAccessibilityLayout)
        }
    }

    private var usesAccessibilityLayout: Bool { dynamicTypeSize.isAccessibilitySize }

    private var headerLayout: AnyLayout {
        usesAccessibilityLayout
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 6))
    }

    private var actionsLayout: AnyLayout {
        usesAccessibilityLayout
            ? AnyLayout(VStackLayout(spacing: 16))
            : AnyLayout(HStackLayout(spacing: 16))
    }

    private var tagsLayout: AnyLayout {
        usesAccessibilityLayout
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: 6))
    }

    private var metadataLayout: AnyLayout {
        usesAccessibilityLayout
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 5))
            : AnyLayout(HStackLayout(spacing: 5))
    }

    private var storyCardBackground: Color {
        Color(red: 0.953, green: 0.969, blue: 0.902)
    }

    private var collectButtonColor: Color {
        Color(red: 0.439, green: 0.549, blue: 0.251)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy년 M월 d일 EEEE"
        return formatter
    }()
}
