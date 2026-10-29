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

    private var story: Story { experience.story }

    var body: some View {
        GeometryReader { geometry in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 38) {
                    StoryCardImage(url: experience.storyCard.imageURL)
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
                        Text(isCollected ? "도감 저장 완료" : "도감 저장하기")
                    }
                        .font(.custom("Paperlogy-6SemiBold", size: 14, relativeTo: .callout))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(collectButtonGradient, in: RoundedRectangle(cornerRadius: 20))
                }
                .buttonStyle(.plain)
                .disabled(isCollected)
                .accessibilityIdentifier("appclip.storyCard.collect")

                Text("삭제")
                    .font(.custom("Paperlogy-6SemiBold", size: 14, relativeTo: .callout))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 44)
                    .background(Color(red: 0.867, green: 0.867, blue: 0.867), in: Capsule())
                    .accessibilityLabel("삭제 기능 준비 중")
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
