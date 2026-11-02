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
                    StoryCardImage(url: experience.storyCard.imageURL)
                        .aspectRatio(320 / 444, contentMode: .fit)
                        .frame(width: min(320, geometry.size.width - 32))
                        .compositingGroup()
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
                Text(story.cucumberName)
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
                    .accessibilityHint("이 기기에 보관한 카드를 삭제하고 수집 시작 화면으로 돌아갑니다")
            }
        }
        .foregroundStyle(.black)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: usesAccessibilityLayout ? nil : .infinity)
        .background(.white, in: RoundedRectangle(cornerRadius: 30))
        .compositingGroup()
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
        .font(.custom("Paperlogy-2ExtraLight", size: 15, relativeTo: .caption))
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

    private var usesAccessibilityLayout: Bool { dynamicTypeSize > .large }

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
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "yyyy년 M월 d일 EEEE"
        return formatter
    }()
}

private struct StoryCardImage: View {
    let url: URL?
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
                            ProgressView("카드를 불러오는 중이에요")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                ContentUnavailableView(
                    "카드 이미지가 없어요",
                    systemImage: "photo",
                    description: Text("이 이야기의 카드 이미지가 제공되지 않았어요.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 234 / 255, green: 238 / 255, blue: 226 / 255))
        .environment(\.colorScheme, .light)
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("스토리 카드")
    }

    private func unavailableImage(canRetry: Bool) -> some View {
        VStack(spacing: 12) {
            ContentUnavailableView(
                "카드를 불러오지 못했어요",
                systemImage: "photo",
                description: Text("잠시 후 다시 확인해 주세요.")
            )
            if canRetry {
                Button("다시 불러오기") { reloadID += 1 }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
