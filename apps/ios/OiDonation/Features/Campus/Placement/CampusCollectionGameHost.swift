//
//  CampusCollectionGameHost.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/3/26.
//

import SwiftUI

/// A game win opens an explicit save action; it never grants a local collection.
struct CampusCollectionGameHost: View {
    let story: CampusStory
    let remote: OiRemoteStore
    let store: CampusStoryStore
    let onClose: () -> Void
    @State private var owner: UUID?
    @State private var saveRequest: UUID?
    @State private var notice: String?

    init(story: CampusStory, remote: OiRemoteStore, store: CampusStoryStore, onClose: @escaping () -> Void) {
        self.story = story
        self.remote = remote
        self.store = store
        self.onClose = onClose
        _owner = State(initialValue: remote.account?.id)
    }

    var body: some View {
        Group {
            if remote.account == nil {
                NavigationStack {
                    OiAccountView(remote: remote)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("수집 닫기", action: onClose)
                            }
                        }
                }
            } else if owner == nil || remote.account?.id != owner || remote.needsReauthentication {
                ContentUnavailableView {
                    Label("로그인을 확인해 주세요", systemImage: "person.crop.circle")
                } description: {
                    Text("수집을 시작한 계정으로 로그인한 뒤 다시 시도해 주세요.")
                } actions: {
                    Button("닫기", action: onClose).buttonStyle(.borderedProminent)
                }
            } else if store.isExample || story.isExample || UUID(uuidString: story.id) == nil {
                ContentUnavailableView {
                    Label("예시 오이는 수집하지 않아요", systemImage: "leaf")
                } description: {
                    Text("실제 공개된 오이의 이야기 화면에서 수집할 수 있어요.")
                } actions: {
                    Button("닫기", action: onClose).buttonStyle(.borderedProminent)
                }
            } else {
                ARCollectionGameView(
                    cucumberName: story.title,
                    cucumberAssetName: story.portraitImage,
                    onBack: onClose
                ) { _ in
                    ARCollectionResultView(
                        name: story.title,
                        tags: story.tags,
                        donor: story.donor,
                        location: story.location,
                        date: story.date,
                        isCollected: isCollected,
                        isSaving: saveRequest != nil,
                        canCollect: !isCollected && !remote.isBusy && !remote.isRefreshing,
                        cancelTitle: isCollected ? "완료" : "취소",
                        accessibilityPrefix: "campus.collection",
                        notice: notice ?? (isCollected ? "이 계정의 도감에 저장했어요." : nil),
                        onCollect: requestSave,
                        onCancel: onClose
                    ) {
                        OiStoryCardArtwork(
                            name: story.title,
                            introduction: story.excerpt,
                            donor: story.donor,
                            date: story.date,
                            tags: story.tags,
                            assetName: story.portraitImage
                        )
                    }
                }
            }
        }
        .task(id: saveRequest) {
            guard let request = saveRequest else { return }
            await save(request: request)
        }
        .onChange(of: remote.account?.id) { _, account in
            saveRequest = nil
            if owner == nil { owner = account }
        }
        .onDisappear { saveRequest = nil }
        .interactiveDismissDisabled(saveRequest != nil)
        .preferredColorScheme(.light)
    }

    private var isCollected: Bool {
        guard let owner, remote.account?.id == owner, let id = UUID(uuidString: story.id) else { return false }
        return remote.collections.contains { $0.storyId == id }
    }

    private func requestSave() {
        guard saveRequest == nil, !isCollected, !remote.isBusy, !remote.isRefreshing else { return }
        notice = nil
        saveRequest = UUID()
    }

    private func save(request: UUID) async {
        defer { if saveRequest == request { saveRequest = nil } }
        guard !Task.isCancelled, let owner, remote.account?.id == owner,
              !remote.needsReauthentication, !store.isExample, !story.isExample,
              let id = UUID(uuidString: story.id), !remote.isBusy else { return }
        await remote.perform("collect", payload: ["id": id.uuidString])
        guard !Task.isCancelled, saveRequest == request, remote.account?.id == owner else { return }
        if remote.collections.contains(where: { $0.storyId == id }) {
            // Root's receipt observer updates both the account library and map button.
            notice = "이 계정의 도감에 저장했어요."
        } else {
            notice = remote.error ?? "수집 저장을 확인하지 못했어요. 다시 시도해 주세요."
        }
    }
}
