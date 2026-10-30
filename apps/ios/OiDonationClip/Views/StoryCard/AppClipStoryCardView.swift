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
                VStack(spacing: 34) {
                    StoryCardImage(url: experience.storyCard.imageURL)
                        .aspectRatio(320 / 444, contentMode: .fit)
                        .frame(width: min(320, geometry.size.width - 32))
                        .shadow(color: .black.opacity(0.25), radius: 3.5, x: 3, y: 6)

                    summaryCard
                        .frame(width: min(362, geometry.size.width - 40), height: 216)
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
            HStack(alignment: .center, spacing: 6) {
                Text(story.title)
                    .font(.custom("PearToucan-Regular", size: 28, relativeTo: .title).weight(.bold))
                    .tracking(1.12)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)

                Spacer(minLength: 0)

                tags
            }

            metadata

            HStack(spacing: 16) {
                Button(action: onCollect) {
                    HStack(spacing: 5) {
                        if isCollected {
                            Image(systemName: "checkmark")
                        }
                        Text(isCollected ? "도감 저장 완료" : "도감 저장하기")
                    }
                        .font(.custom("Paperlogy-6SemiBold", size: 14, relativeTo: .callout))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
                        .background(collectButtonColor, in: RoundedRectangle(cornerRadius: 20))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: 239)
                .accessibilityIdentifier("appclip.storyCard.collect")

                Button("삭제", action: onCancel)
                    .buttonStyle(.plain)
                    .font(.custom("Paperlogy-6SemiBold", size: 14, relativeTo: .callout))
                    .foregroundStyle(.white)
                    .frame(width: 67, height: 44)
                    .background(Color(red: 0.867, green: 0.867, blue: 0.867), in: Capsule())
                    .accessibilityIdentifier("appclip.storyCard.cancel")
            }
        }
        .foregroundStyle(.black)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white, in: RoundedRectangle(cornerRadius: 30))
        .shadow(color: Color(red: 0.18, green: 0.31, blue: 0.09).opacity(0.4), radius: 5)
    }

    private var tags: some View {
        HStack(spacing: 6) {
            ForEach(story.tags.prefix(2), id: \.self) { tag in
                Text(tag)
                    .font(.custom("Paperlogy-4Regular", size: 16, relativeTo: .caption))
                    .tracking(0.32)
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .frame(height: 30)
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
        HStack(spacing: 5) {
            Text(label)
            Text("|")
            Text(value)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
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

private struct StoryCardImage: View {
    let url: URL

    var body: some View {
        Group {
            if url.isFileURL, let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { phase in
                    switch phase {
                    case .empty:
                        ProgressView("카드를 불러오는 중이에요")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(.secondarySystemBackground))
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        ContentUnavailableView(
                            "카드를 불러오지 못했어요",
                            systemImage: "photo",
                            description: Text("잠시 후 다시 확인해 주세요")
                        )
                        .background(Color(.secondarySystemBackground))
                    @unknown default:
                        Color(.secondarySystemBackground)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .accessibilityLabel("스토리 카드")
    }
}
