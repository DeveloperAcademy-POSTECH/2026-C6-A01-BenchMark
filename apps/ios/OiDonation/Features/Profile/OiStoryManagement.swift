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

    var body: some View {
        Group {
            if let story = remote.ownStories.first(where: { $0.id == storyID }) {
                List {
                    Text(story.title).font(.headline)
                    Text(story.status.oiStatusTitle)
                    Text(story.body)
                    if let error = remote.error { Text(error).foregroundStyle(.red) }
                    if story.status == "draft" {
                        NavigationLink("초안 수정·미리보기·검토 요청") { OiStoryEditor(remote: remote, story: story) }
                    } else {
                        Text("수정을 시작하면 공개가 해제되고 다시 검토를 요청해야 합니다.").font(.footnote)
                        Button("수정 시작") { Task { await remote.perform("reopen_story", payload: ["id":story.id.uuidString,"revision":story.revision]) } }
                    }
                    Button("이야기 삭제", role: .destructive) { confirmingDelete = true }
                    Text("삭제해도 작성 승인 수량이 자동으로 복구되지는 않습니다.").font(.footnote).foregroundStyle(.secondary)
                }
                .confirmationDialog("이야기를 비공개·삭제 상태로 바꿀까요?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                    Button("삭제", role: .destructive) { Task { await remote.perform("delete_story", payload: ["id":story.id.uuidString,"revision":story.revision]) } }
                }
            } else { ContentUnavailableView("이야기를 볼 수 없어요", systemImage: "doc") }
        }.navigationTitle("내 이야기").navigationBarTitleDisplayMode(.inline).disabled(remote.isBusy)
    }
}
