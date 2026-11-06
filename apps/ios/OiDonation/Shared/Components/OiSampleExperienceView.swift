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
    @State private var isPlaying = false
    @State private var isCollected = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(OiSampleStory.notice).font(.callout)
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                    OiSampleCardArtwork().frame(maxWidth: 320).frame(maxWidth: .infinity)
                    Text("6냥이").font(.custom("Paperlogy-7Bold", size: 28, relativeTo: .title))
                    Text("#즐거움  #우정 · 체험용 이야기")
                        .font(.subheadline).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 20) {
                        Text(OiSampleStory.introduction)
                            .font(.custom("Paperlogy-6SemiBold", size: 18, relativeTo: .headline))
                        Text(OiSampleStory.body)
                            .font(.custom("Paperlogy-4Regular", size: 16, relativeTo: .body))
                            .lineSpacing(6).textSelection(.enabled)
                    }.padding(20).background(Color(white: 0.96), in: RoundedRectangle(cornerRadius: 20))
                    Text("카메라로 주변을 비추며 오이 3개를 찾은 뒤 체험 카드를 모아 보세요. 캠퍼스 방문이나 위치 권한 없이 체험할 수 있어요.")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("Figma 예시 이야기를 사용한 체험 콘텐츠입니다.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(20)
            }
            .navigationTitle("이야기·AR 체험")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }.accessibilityIdentifier("sample.close")
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button { isPlaying = true } label: {
                    Label(isCollected ? "AR 다시 체험하기" : "AR 체험 시작", systemImage: "arkit")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.borderedProminent).padding().background(.regularMaterial)
                    .accessibilityIdentifier("sample.startAR")
            }
        }
        .fullScreenCover(isPresented: $isPlaying) {
            ARCollectionGameView(cucumberName: OiSampleStory.name,
                cucumberAssetName: "OiStoryCardCats", onBack: { isPlaying = false }) { _ in
                OiSampleCollectionResult(isCollected: isCollected,
                    onCollect: { isCollected = true }, onClose: { isPlaying = false })
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Text("체험용 · 실제 도감에는 저장되지 않아요")
                    .font(.caption).frame(maxWidth: .infinity).padding(8)
                    .background(.regularMaterial)
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
