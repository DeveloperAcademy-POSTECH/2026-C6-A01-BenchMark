//
//  OiSampleExperienceView.swift
//  OiDonation / OiDonationClip
//
//  Created by Codex on 11/7/26.
//

import SwiftUI

/// The same public, offline example in both apps. Collection lives only in this view.
/// No remote store, account, App Group storage or donation approval is involved.
struct OiSampleExperienceView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var path: [CampusDestination] = []
    @State private var isPlaying = false
    @State private var isCollected = false

    var body: some View {
        NavigationStack(path: $path) {
            OiSampleMapView()
                .modifier(OiSampleNoticeModifier())
                .navigationTitle("체험 지도")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("닫기") { dismiss() }.accessibilityIdentifier("sample.close")
                    }
                }
                .navigationDestination(for: CampusDestination.self) { destination in
                    switch destination {
                    case .summary(let id):
                        if let story = CampusStoryExamples.stories.first(where: { $0.id == id }) {
                            OiSampleSummaryView(story: story, onCollect: { isPlaying = true })
                                .modifier(OiSampleNoticeModifier())
                        }
                    case .story(let id):
                        if let story = CampusStoryExamples.stories.first(where: { $0.id == id }) {
                            OiSampleStoryDetailView(story: story, onCollect: { isPlaying = true })
                                .modifier(OiSampleNoticeModifier())
                        }
                    }
                }
        }
        .fullScreenCover(isPresented: $isPlaying) {
            // The AR stage draws to the screen edges; keep the notice outside its layout.
            VStack(spacing: 0) {
                Text("체험용 · 실제 도감에는 저장되지 않아요")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(.regularMaterial, ignoresSafeAreaEdges: .top)
                ARCollectionGameView(cucumberName: OiSampleStory.name,
                    cucumberAssetName: "OiStoryCardCats", onBack: { isPlaying = false }) { _ in
                    OiSampleCollectionResult(isCollected: isCollected,
                        onCollect: { isCollected = true }, onClose: { isPlaying = false })
                }
            }
            .preferredColorScheme(.light)
        }
        .tint(Color(red: 90 / 255, green: 112 / 255, blue: 51 / 255))
        .preferredColorScheme(.light)
    }
}

struct OiSampleCollectionResult: View {
    let isCollected: Bool
    let onCollect: () -> Void
    let onClose: () -> Void

    var body: some View {
        ARCollectionResultView(name: OiSampleStory.name, tags: ["즐거움", "우정"],
            donor: "체험용 예시", location: "예시 장소 · POSTECH 연못길", date: "예시 이야기",
            isCollected: isCollected, canCollect: !isCollected,
            collectTitle: "체험 카드 모으기", collectedTitle: "체험 수집 완료", cancelTitle: "완료",
            accessibilityPrefix: "sample.collection",
            notice: isCollected ? "체험 카드를 모았어요. 실제 도감에는 저장되지 않으며, 체험을 닫으면 초기화됩니다." : OiSampleStory.notice,
            onCollect: onCollect, onCancel: onClose) {
                OiSampleCardArtwork()
            }
    }
}

private struct OiSampleCardArtwork: View {
    var body: some View {
        OiStoryCardArtwork(name: OiSampleStory.name, introduction: OiSampleStory.introduction,
            donor: "체험용 예시", date: "예시 이야기", tags: ["즐거움", "우정"], assetName: "OiStoryCardCats")
    }
}

/// Place the persistent disclosure in navigation chrome so it cannot cover a screen's actions.
struct OiSampleNoticeModifier: ViewModifier {
    @State private var showsNotice = false
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showsNotice = true } label: {
                    Text("체험용").font(.caption)
                }.accessibilityIdentifier("sample.notice")
            }
        }
        .alert("이야기·AR 체험", isPresented: $showsNotice) {
            Button("확인", role: .cancel) {}
        } message: { Text(OiSampleStory.notice) }
    }
}
