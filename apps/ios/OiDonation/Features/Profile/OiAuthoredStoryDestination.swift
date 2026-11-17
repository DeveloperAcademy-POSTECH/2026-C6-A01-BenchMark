//
//  OiAuthoredStoryDestination.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/17/26.
//

import SwiftUI

struct OiAuthoredStoryDestination: View {
    let remote: OiRemoteStore
    let storyID: UUID

    @Environment(CampusStoryStore.self) private var campus: CampusStoryStore?
    @Environment(\.dismiss) private var dismiss
    @State private var pendingAction: Action?
    @State private var editorIdentity = UUID()
    @State private var actionError: String?

    private enum Action {
        case reopen(OiLiveStory)
        case delete(OiLiveStory)

        var title: String {
            switch self {
            case .reopen(let story):
                story.status == "published" ? "수정을 시작하면 공개가 해제돼요." : "오이를 초안으로 되돌릴까요?"
            case .delete:
                "이야기를 비공개·삭제 상태로 바꿀까요?"
            }
        }
    }

    var body: some View {
        Group {
            if let owner = remote.account?.id, !remote.needsReauthentication,
               let story = remote.ownStories.first(where: { $0.id == storyID && $0.userId == owner }) {
                if story.status == "published", let campus {
                    CampusCucumberStoryView(story: remote.campusStory(story), store: campus)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Menu("오이 관리", systemImage: "ellipsis.circle") {
                                    if let showPlacement = campus.showAuthoredPlacementAction {
                                        Button("내 지도에서 오이 보기") { showPlacement(story.id) }
                                    }
                                    Button("수정 시작") { pendingAction = .reopen(story) }
                                    Button("이야기 삭제", role: .destructive) { pendingAction = .delete(story) }
                                }
                                .disabled(remote.isBusy)
                            }
                        }
                } else {
                    OiStoryEditor(remote: remote, story: story, onReopen: { pendingAction = .reopen(story) },
                                  onDeleteSubmittedStory: { pendingAction = .delete(story) })
                        .id(editorIdentity)
                }
            } else {
                ContentUnavailableView("이야기를 볼 수 없어요", systemImage: "doc")
                    .toolbar(.visible, for: .navigationBar)
            }
        }
        .confirmationDialog(pendingAction?.title ?? "", isPresented: Binding(
            get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }
        ), titleVisibility: .visible, presenting: pendingAction) { action in
            switch action {
            case .reopen(let story):
                Button(story.status == "pending" ? "초안으로 되돌리기" : "수정 시작") {
                    Task { await reopen(story) }
                }
            case .delete(let story):
                Button("삭제", role: .destructive) { Task { await delete(story) } }
            }
        }
        .alert("작업을 완료하지 못했어요", isPresented: Binding(
            get: { actionError != nil }, set: { if !$0 { actionError = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    private func reopen(_ story: OiLiveStory) async {
        guard remote.account?.id == story.userId, !remote.needsReauthentication, !remote.isBusy else { return }
        await remote.perform("reopen_story", payload: ["id": story.id.uuidString, "revision": story.revision])
        guard remote.account?.id == story.userId else { return }
        guard remote.ownStories.contains(where: { $0.id == story.id && $0.status == "draft" && $0.revision > story.revision }) else {
            actionError = remote.error ?? "초안으로 되돌리지 못했어요. 다시 시도해 주세요."
            return
        }
        if story.status != "published" { editorIdentity = UUID() }
    }

    private func delete(_ story: OiLiveStory) async {
        guard remote.account?.id == story.userId, !remote.needsReauthentication, !remote.isBusy else { return }
        let deleted = await remote.deleteStory(story)
        guard remote.account?.id == story.userId else { return }
        if deleted {
            dismiss()
        } else {
            actionError = remote.error ?? "이야기를 삭제하지 못했어요. 다시 시도해 주세요."
        }
    }
}
