//
//  OiOperatorNFCTagsView.swift
//  OiDonation
//
//  Created by jiwon hong on 11/13/26.
//

import SwiftUI
import UIKit

/// Operator list of NFC postcard tags (#310): which story each campus tag opens, and whether it opens at all.
struct OiOperatorNFCTagsView: View {
    let remote: OiRemoteStore
    @State private var tags: [OiNFCTag] = []
    @State private var loaded = false
    @State private var busy = false
    @State private var error: String?
    @State private var editing: OiNFCTagEditTarget?
    @State private var requestID = UUID()
    @AppStorage("operator.nfc.showRetired") private var showRetired = false

    private var visibleTags: [OiNFCTag] { showRetired ? tags : tags.filter(\.active) }
    private var retiredCount: Int { tags.filter { !$0.active }.count }

    var body: some View {
        List {
            Section {
                Text("태그에는 태그 ID만 기록합니다. 여기서 연결한 공개 이야기가 App Clip 스크래치 엽서로 열려요. 변경 내용은 운영 감사 기록에 남습니다.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    Button("다시 시도") { Task { await load() } }
                }
            }
            if busy && !loaded {
                Section { ProgressView("태그 목록을 불러오는 중") }
            } else if loaded && tags.isEmpty && error == nil {
                Section { Text("등록된 태그가 없어요. 오른쪽 위 + 버튼으로 추가해 주세요.").foregroundStyle(.secondary) }
            }
            if !tags.isEmpty {
                Section {
                    ForEach(visibleTags) { tag in
                        Button { editing = .existing(tag) } label: { row(tag) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("operator.nfc.tag.\(tag.tagId)")
                    }
                    if visibleTags.isEmpty { Text("사용 중인 태그가 없어요.").foregroundStyle(.secondary) }
                } header: {
                    Text("사용 \(tags.count - retiredCount)개 · 열림 \(tags.filter(\.opensPostcard).count)개 · 중지 \(retiredCount)개")
                } footer: {
                    if retiredCount > 0 {
                        Toggle("중지된 태그 \(retiredCount)개 보기", isOn: $showRetired)
                            .font(.footnote)
                            .accessibilityIdentifier("operator.nfc.showRetired")
                    }
                }
            }
        }
        .navigationTitle("NFC 태그")
        .privacySensitive()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editing = .new } label: { Label("태그 추가", systemImage: "plus") }
                    .disabled(!loaded)
                    .accessibilityIdentifier("operator.nfc.add")
            }
        }
        .task(id: remote.account?.id) { await load() }
        .refreshable { await load() }
        .onDisappear { requestID = UUID() }
        .sheet(item: $editing) { target in
            OiOperatorNFCTagEditor(remote: remote, target: target, existingIDs: Set(tags.map(\.tagId))) {
                Task { await load() }
            }
        }
    }

    private func row(_ tag: OiNFCTag) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(tag.tagId).font(.headline.monospaced())
                Spacer()
                Label(tag.statusText, systemImage: tag.opensPostcard ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(tag.opensPostcard ? .green : .orange)
                    .labelStyle(.titleAndIcon)
            }
            Text(tag.storyTitle ?? "연결된 이야기 없음")
                .font(.subheadline).lineLimit(1)
            if !tag.note.isEmpty {
                Text(tag.note).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func load() async {
        guard let owner = remote.account?.id, remote.isOperator else { tags = []; return }
        let request = UUID(); requestID = request
        busy = true; error = nil
        defer { if request == requestID { busy = false } }
        do {
            let page = try await remote.operatorNFCTags()
            guard !Task.isCancelled, requestID == request, owner == remote.account?.id else { return }
            tags = page; loaded = true
        } catch {
            guard !Task.isCancelled, requestID == request, owner == remote.account?.id else { return }
            self.error = (error as? LocalizedError)?.errorDescription ?? "태그 목록을 읽지 못했어요. 운영자 권한과 연결 상태를 확인해 주세요."
        }
    }
}

enum OiNFCTagEditTarget: Identifiable {
    case new
    case existing(OiNFCTag)
    var id: String {
        switch self { case .new: "new"; case .existing(let tag): tag.tagId }
    }
}

/// Create or change one tag. Saving asks for confirmation because a locked tag on campus changes immediately.
struct OiOperatorNFCTagEditor: View {
    let remote: OiRemoteStore
    let target: OiNFCTagEditTarget
    let existingIDs: Set<String>
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var tagID = ""
    @State private var story: OiNFCStoryChoice?
    @State private var active = true
    @State private var note = ""
    @State private var stories: [OiLiveStory] = []
    @State private var storiesError: String?
    @State private var confirming = false
    @State private var busy = false
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    @State private var copied = false

    private var isNew: Bool { if case .new = target { true } else { false } }
    private var trimmedNote: String { note.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var tagIssue: String? {
        guard isNew else { return nil }
        if tagID.isEmpty { return nil }
        if !AppClipLink.isValidPostcardTag(tagID) { return OiNFCTagError.invalidTag.errorDescription }
        if existingIDs.contains(tagID) { return "이미 등록된 태그 ID예요. 목록에서 해당 태그를 선택해 수정해 주세요." }
        return nil
    }
    private var canSave: Bool {
        !busy && AppClipLink.isValidPostcardTag(tagID) && tagIssue == nil && trimmedNote.count <= OiNFCTagError.noteLimit
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if isNew {
                        HStack {
                            TextField("예: oi-k7m2q9", text: $tagID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.body.monospaced())
                            .accessibilityIdentifier("operator.nfc.tagID")
                            Button {
                                tagID = OiNFCTagID.suggestion(avoiding: existingIDs)
                            } label: { Image(systemName: "arrow.clockwise") }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("새 태그 ID 만들기")
                        }
                        if let tagIssue { Text(tagIssue).font(.footnote).foregroundStyle(.red) }
                    } else {
                        LabeledContent("태그 ID") { Text(tagID).font(.body.monospaced()) }
                    }
                } header: { Text("태그 ID") } footer: {
                    Text(isNew ? "자동으로 만든 ID를 그대로 써도 돼요. 직접 바꾸려면 영어 소문자·숫자·하이픈(-), 1~40자로 입력해 주세요. 태그에 기록한 뒤에는 바꿀 수 없어요."
                         : "태그에 기록한 뒤에는 바꿀 수 없어요.")
                }

                Section("연결할 이야기") {
                    NavigationLink {
                        OiNFCStoryPicker(stories: stories, error: storiesError, selection: $story)
                    } label: {
                        LabeledContent("이야기") {
                            Text(story?.title ?? "선택 안 함").lineLimit(1)
                        }
                    }
                    .accessibilityIdentifier("operator.nfc.story")
                    if let story, story.status != "published" {
                        Text("공개 승인 전 이야기예요. 승인되기 전까지 태그를 대도 엽서가 열리지 않아요.")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                    if story != nil {
                        Button("연결 해제", role: .destructive) { self.story = nil }
                    }
                }

                Section {
                    Toggle("태그 사용", isOn: $active).accessibilityIdentifier("operator.nfc.active")
                } footer: {
                    Text("끄면 태그를 대도 엽서가 열리지 않아요. 훼손·분실된 태그는 끄고 새 태그를 등록해 주세요.")
                }

                Section {
                    TextField("설치 위치 메모 (운영자만 보임)", text: $note, axis: .vertical)
                        .accessibilityIdentifier("operator.nfc.note")
                    if trimmedNote.count > OiNFCTagError.noteLimit {
                        Text("메모는 \(OiNFCTagError.noteLimit)자까지 입력할 수 있어요.").font(.footnote).foregroundStyle(.red)
                    }
                } header: { Text("메모") }

                if AppClipLink.isValidPostcardTag(tagID) {
                    Section {
                        let url = AppClipLink.postcardURL(tagID).absoluteString
                        Text(url).font(.footnote.monospaced()).textSelection(.enabled)
                        Button(copied ? "복사했어요" : "태그 URL 복사") {
                            UIPasteboard.general.string = url
                            copied = true
                        }
                    } header: { Text("태그에 기록할 URL") } footer: {
                        Text("NFC 기록 앱으로 이 URL을 기록하고, 실제 iPhone으로 열리는지 확인한 뒤 잠가 주세요.")
                    }
                }

                if let error {
                    Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                }
            }
            .disabled(busy)
            .navigationTitle(isNew ? "태그 추가" : "태그 수정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if busy { ProgressView() } else {
                        Button("저장") { confirming = true }
                            .disabled(!canSave)
                            .accessibilityIdentifier("operator.nfc.save")
                    }
                }
            }
            .confirmationDialog("이 내용으로 저장할까요?", isPresented: $confirming, titleVisibility: .visible) {
                Button("저장") { save() }
                Button("취소", role: .cancel) {}
            } message: {
                Text(confirmationMessage)
            }
            .privacySensitive()
            .interactiveDismissDisabled(busy)
            .task { await prepare() }
            .onChange(of: tagID) { _, _ in copied = false }
            .onDisappear { task?.cancel() }
        }
    }

    private var confirmationMessage: String {
        let storyText = story.map { "‘\($0.title)’" } ?? "연결 없음"
        return "\(tagID) → \(storyText), \(active ? "사용" : "중지"). 이미 붙인 태그에는 바로 반영돼요."
    }

    private func prepare() async {
        if case .new = target, tagID.isEmpty {
            tagID = OiNFCTagID.suggestion(avoiding: existingIDs)
        }
        if case .existing(let tag) = target, tagID.isEmpty {
            tagID = tag.tagId; active = tag.active; note = tag.note
            if let id = tag.storyId {
                story = OiNFCStoryChoice(id: id, title: tag.storyTitle ?? "제목 없음", status: tag.storyStatus ?? "")
            }
        }
        do {
            let rows = try await remote.operatorStories()
            guard !Task.isCancelled else { return }
            // Only stories that are, or can become, public are useful on a tag.
            stories = rows.filter { $0.status == "published" || $0.status == "pending" }
            storiesError = nil
        } catch {
            guard !Task.isCancelled else { return }
            storiesError = "이야기 목록을 불러오지 못했어요. 뒤로 갔다가 다시 열어 주세요."
        }
    }

    private func save() {
        guard canSave, let owner = remote.account?.id else { return }
        busy = true; error = nil
        let tag = tagID, storyID = story?.id, isActive = active, memo = trimmedNote, creating = isNew
        task = Task {
            defer { busy = false }
            do {
                if creating {
                    // The server upserts by tag ID, so confirm no one else registered it since the list loaded.
                    let latest = try await remote.operatorNFCTags()
                    if latest.contains(where: { $0.tagId == tag }) { throw OiNFCTagError.duplicateTag }
                }
                _ = try await remote.setNFCTag(tag, story: storyID, active: isActive, note: memo)
                guard !Task.isCancelled, owner == remote.account?.id else { return }
                onSaved()
                dismiss()
            } catch {
                guard !Task.isCancelled, owner == remote.account?.id else { return }
                self.error = (error as? LocalizedError)?.errorDescription
                    ?? "저장하지 못했어요. 목록을 새로고침해 상태를 확인한 뒤 다시 시도해 주세요."
            }
        }
    }
}

struct OiNFCStoryChoice: Equatable {
    let id: UUID
    let title: String
    let status: String
}

/// Searchable list of published and pending stories to link to a tag.
private struct OiNFCStoryPicker: View {
    let stories: [OiLiveStory]
    let error: String?
    @Binding var selection: OiNFCStoryChoice?
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [OiLiveStory] {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return stories }
        return stories.filter {
            $0.title.localizedCaseInsensitiveContains(text) || $0.cucumberName.localizedCaseInsensitiveContains(text)
                || $0.id.uuidString.lowercased().hasPrefix(text.lowercased())
        }
    }

    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.orange) }
            else if stories.isEmpty { Text("연결할 수 있는 공개·검토 대기 이야기가 없어요.").foregroundStyle(.secondary) }
            ForEach(filtered, id: \.id) { story in
                Button {
                    selection = OiNFCStoryChoice(id: story.id, title: story.title, status: story.status)
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(story.title).font(.headline).lineLimit(1)
                            Text("\(story.cucumberName) · \(story.status == "published" ? "공개" : "검토 대기")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selection?.id == story.id { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .searchable(text: $query, prompt: "제목·오이 이름·ID 검색")
        .navigationTitle("이야기 선택")
    }
}
