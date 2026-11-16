//
//  OiStoryManagement.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/4/26.
//

import SwiftUI

struct OiStoryManagement: View {
    let remote: OiRemoteStore
    let storyID: UUID
    @State private var confirmingDelete = false
    @Environment(CampusStoryStore.self) private var campusStore: CampusStoryStore?

    var body: some View {
        Group {
            if let story = remote.ownStories.first(where: { $0.id == storyID }) {
                List {
                    Text(story.title).font(.headline)
                    Text(story.status == "pending"
                         ? (remote.autoStoryModeration ? "미등록" : "공개 검토 중 · 나만 보기")
                         : story.status.oiStatusTitle)
                    Text(story.body)
                    if story.status != "draft" {
                        CampusStoryCardArtwork(story: remote.campusStory(story))
                            .frame(maxWidth: 240).frame(maxWidth: .infinity)
                    }
                    if let error = remote.error { Text(error).foregroundStyle(.red) }
                    if story.isRegisteredOnCampus, !remote.needsReauthentication,
                       let showPlacement = campusStore?.showAuthoredPlacementAction {
                        Button("내 지도에서 오이 보기") { showPlacement(story.id) }
                    }
                    if story.status == "draft" {
                        NavigationLink(remote.autoStoryModeration ? "초안 열기" : "초안 수정·배치·공개 검토 요청") { OiStoryEditor(remote: remote, story: story) }
                    } else {
                        if story.status == "published" {
                            Text(remote.autoStoryModeration ? "수정을 시작하면 공개가 해제돼요."
                                 : "수정을 시작하면 공개가 해제되고 다시 검토를 요청해야 합니다.").font(.footnote)
                        }
                        Button(remote.autoStoryModeration && story.status == "pending" ? "초안으로 되돌리기" : "수정 시작") { Task { await remote.perform("reopen_story", payload: ["id":story.id.uuidString,"revision":story.revision]) } }
                    }
                    Button("이야기 삭제", role: .destructive) { confirmingDelete = true }
                }
                .confirmationDialog("이야기를 비공개·삭제 상태로 바꿀까요?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                    Button("삭제", role: .destructive) { Task { await remote.perform("delete_story", payload: ["id":story.id.uuidString,"revision":story.revision]) } }
                }
            } else { ContentUnavailableView("이야기를 볼 수 없어요", systemImage: "doc") }
        }.navigationTitle("내 이야기").navigationBarTitleDisplayMode(.inline).disabled(remote.isBusy)
    }
}
