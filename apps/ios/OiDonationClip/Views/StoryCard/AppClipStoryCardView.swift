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
