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
    var cancelTitle = "삭제"
    var notice: String? = nil
    let onCollect: () -> Void
    let onCancel: () -> Void
    var reloadCard: (() async throws -> StoryCard)? = nil

    private var story: Story { experience.story }

    var body: some View {
        ARCollectionResultView(
            name: story.cucumberName,
            tags: story.tags,
            donor: story.donorDisplayName,
            location: story.location.displayName,
            date: Self.dateFormatter.string(from: story.publishedAt),
            isCollected: isCollected,
            collectTitle: "이 기기에 보관하기",
            collectedTitle: "이 기기에 보관됨",
            cancelTitle: cancelTitle,
            accessibilityPrefix: "appclip.storyCard",
            notice: notice,
            onCollect: onCollect,
            onCancel: onCancel
        ) {
            AppClipCardPreview(card: experience.storyCard, story: story, reloadCard: reloadCard)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "yyyy년 M월 d일 EEEE"
        return formatter
    }()
}

struct AppClipCardPreview: View {
    let card: StoryCard
    let story: Story
    var reloadCard: (() async throws -> StoryCard)? = nil
    @State private var refreshed: StoryCard?
    @State private var showingBack = false
    @State private var refreshing = false
    @State private var refreshError: String?
    private var current: StoryCard { refreshed ?? card }
    private var url: URL? {
        showingBack ? current.backPreviewURL ?? current.backImageURL : current.frontPreviewURL ?? current.imageURL
    }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reloadID = 0

    var body: some View {
        Group {
            if let url {
                if url.isFileURL {
                    if let image = UIImage(contentsOfFile: url.path) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                    } else {
                        unavailableImage(canRetry: false)
                    }
                } else {
                    AsyncImage(url: url, transaction: Transaction(animation: reduceMotion ? nil : .easeInOut(duration: 0.2))) { phase in
                        switch phase {
                        case .empty:
                            placeholder {
                                ProgressView().accessibilityLabel("카드를 불러오는 중이에요")
                            }
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                        case .failure:
                            unavailableImage(canRetry: true)
                        @unknown default:
                            unavailableImage(canRetry: true)
                        }
                    }
                    .id(reloadID)
                }
            } else {
                OiStoryCardArtwork(
                    name: story.cucumberName,
                    introduction: story.content,
                    donor: story.donorDisplayName,
                    date: Self.dateLabel(story.publishedAt),
                    tags: story.tags,
                    imageURL: story.cucumberImageURL,
                    expectsPortrait: story.hasCustomCucumberImage
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, .light)
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("스토리 카드 \(showingBack ? "뒷면" : "앞면")")
        .accessibilityHint(current.backImageURL == nil ? "" : "탭하여 앞·뒷면 뒤집기")
        .onTapGesture { if current.backImageURL != nil { showingBack.toggle() } }
        .accessibilityAction(named: "카드 뒤집기") { if current.backImageURL != nil { showingBack.toggle() } }
        .onChange(of: card.imageURL) { _, _ in refreshed = nil; showingBack = false }
    }

    private static func dateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "yyyy년 M월 d일"
        return formatter.string(from: date)
    }

    private func unavailableImage(canRetry: Bool) -> some View {
        placeholder {
            VStack(spacing: 12) {
                ContentUnavailableView(
                    "카드를 불러오지 못했어요",
                    systemImage: "photo",
                    description: Text("잠시 후 다시 확인해 주세요.")
                )
                if canRetry {
                    Button("다시 불러오기") {
                        Task {
                            refreshing = true; refreshError = nil
                            defer { refreshing = false }
                            do {
                                if let reloadCard { refreshed = try await reloadCard() }
                                try Task.checkCancellation()
                                reloadID += 1
                            } catch { if !Task.isCancelled { refreshError = "공개 카드 상태를 확인하지 못했어요. 다시 시도해 주세요." } }
                        }
                    }.disabled(refreshing)
                        .buttonStyle(.borderedProminent)
                    if let refreshError { Text(refreshError).font(.footnote) }
                }
            }
        }
    }

    private func placeholder<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 234 / 255, green: 238 / 255, blue: 226 / 255),
                        in: RoundedRectangle(cornerRadius: 13))
    }
}
