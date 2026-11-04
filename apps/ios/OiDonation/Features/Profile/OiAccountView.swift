// Created by 이돈혁

import SwiftUI

struct OiAccountView: View {
    let remote: OiRemoteStore
    @State private var appleAuthentication = OiAppleAuthentication()
    @State private var nickname = ""
    @State private var localDrafts: [OiLocalDraft] = []
    @State private var unreadableDraftCount = 0
    @State private var draftLoadError: String?
    @State private var isLoadingDrafts = false
    @State private var draftLoadID = UUID()
    @State private var displayedDraftOwner: UUID?

    private var hasWritingGrant: Bool { remote.grants.contains { $0.revokedAt == nil } }

    var body: some View {
        List {
            OiConnectionStatus(remote: remote)
            if let error = remote.error {
                Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("oi.account.error"); Button("다시 불러오기") { Task { await remote.refresh() } } }
            }
            if let account = remote.account {
                Section("내 계정") {
                    Text(account.email ?? "로그인 계정")
                    Text("계정 ID: \(account.id.uuidString)").font(.caption).textSelection(.enabled)
                    TextField("농부 닉네임", text: $nickname).textInputAutocapitalization(.never)
                        .onAppear { nickname = remote.profile?.nickname ?? "농부" }
                    Button("닉네임 저장") { Task { await remote.updateProfile(nickname: nickname) } }
                        .disabled(nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || nickname.count > 30)
                    Button("로그아웃", role: .destructive) { Task { await remote.signOut() } }
                }
                Section("로그인 방법과 계정") {
                    if !remote.accountProviders.isEmpty {
                        Text("사용 가능한 로그인: " + remote.accountProviders.map { $0 == "apple" ? "Apple" : "Google" }.joined(separator: " · "))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    NavigationLink("로그인 방법 추가") { OiAccountMergeView(remote: remote, mode: .addLoginMethod).environment(\.isEnabled, true) }
                        .disabled(!remote.isAccountMergeAvailable || remote.isOperator)
                        .accessibilityIdentifier("oi.identity.add")
                    NavigationLink("기존 계정 통합") { OiAccountMergeView(remote: remote).environment(\.isEnabled, true) }
                        .disabled(!remote.isAccountMergeAvailable || remote.isOperator)
                        .accessibilityIdentifier("oi.account.merge")
                    if remote.isOperator {
                        Text("운영자 계정은 자동 통합 대상에서 제외됩니다.").font(.footnote).foregroundStyle(.secondary)
                    } else if !remote.isAccountMergeAvailable {
                        Text("계정 통합은 서버 설정이 완료된 후 사용할 수 있습니다.").font(.footnote).foregroundStyle(.secondary)
                    }
                    if remote.localRecoveryWarning != nil {
                        Text("일부 기기 기록을 복원하지 못했어요. 원본은 기기에 보관했습니다.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("이야기 작성 승인") {
                    if remote.hasLoadedRemote {
                        Text(hasWritingGrant ? "작성 승인 기록이 있어요." : "아직 작성 승인이 없어요.")
                    } else {
                        Text(remote.isRefreshing ? "작성 승인 상태를 확인 중이에요." : "작성 승인 상태를 확인할 수 없어요.")
                    }
                }
                Section("이 계정의 기기 초안·보관본") {
                    if isLoadingDrafts { ProgressView("기기 초안 확인 중") }
                    if unreadableDraftCount > 0 {
                        Text("기기 초안 \(unreadableDraftCount)개를 읽지 못했습니다. 원본은 보관하고 읽을 수 있는 초안만 표시합니다.")
                            .font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("oi.drafts.recoveryWarning")
                    }
                    if let draftLoadError { Text(draftLoadError).font(.footnote).foregroundStyle(.red) }
                    if unreadableDraftCount > 0 || draftLoadError != nil {
                        Button("기기 초안 다시 확인") { Task { await loadLocalDrafts() } }
                            .disabled(isLoadingDrafts).accessibilityIdentifier("oi.drafts.retry")
                    }
                    ForEach(localDrafts) { record in
                        NavigationLink { OiStoryEditor(remote: remote, localID: record.id) } label: {
                            VStack(alignment: .leading) {
                                Text(record.draft.title.isEmpty ? "제목 없는 초안" : record.draft.title)
                                Text(record.submitted ? "검토 요청 완료 · 기기 보관본" : "미완료 초안 · 사진 \(record.photos.count)장").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("내 이야기와 오이") {
                    NavigationLink("이야기 리스트") {
                        OiStoryListScreen(remote: remote)
                    }
                    .accessibilityIdentifier("oi.story.list")
                    if hasWritingGrant {
                        NavigationLink("오이 만들기") { OiStoryCreationConsentFlow(remote: remote) }
                            .accessibilityIdentifier("oi.story.create")
                    } else {
                        Text("이야기를 만들려면 작성 승인이 필요해요.").foregroundStyle(.secondary)
                    }
                    if remote.ownStories.isEmpty { Text("등록한 이야기가 없어요.").foregroundStyle(.secondary) }
                    ForEach(remote.ownStories) { story in
                        NavigationLink { OiStoryManagement(remote: remote, storyID: story.id) } label: {
                            VStack(alignment: .leading) { Text(story.title); Text(story.status.oiStatusTitle).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    Text("피클코인 구매·적립·사용은 비활성화돼 있어요.").font(.footnote).foregroundStyle(.secondary)
                }
                if remote.isOperator {
                    Section("운영자") { NavigationLink("이야기 공개 검토") { OiOperatorView(remote: remote) } }
                }
            } else {
                Section {
                    Text("로그인하면 수집한 오이와 즐겨찾기, 내 이야기가 계정에 저장됩니다.")
                    Button("Google로 로그인") { Task { await remote.signIn() } }
                        .disabled(!remote.isConfigured).accessibilityIdentifier("oi.auth.google")
                    OiAppleSignInButton { Task { await remote.signIn(using: appleAuthentication) } }
                        .frame(minHeight: 44)
                        .disabled(!remote.isConfigured || remote.isBusy)
                    if !remote.isConfigured { Text(OiServiceError.configuration.localizedDescription).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            Section("아직 준비 중인 부분") {
                Text("옷·모자·하의의 개별 꾸미기, 성장·보상, 물리적 방문 인증과 AR 수집 게임 규칙은 미정입니다. 준비된 오이·카드 프리셋만 선택할 수 있어요.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("계정과 내 이야기").navigationBarTitleDisplayMode(.inline)
        .onChange(of: remote.profile?.nickname) { _, value in if let value { nickname = value } }
        .disabled(remote.isBusy)
        .overlay { if remote.isBusy { ProgressView().padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
        .refreshable { await remote.refresh() }
        .task(id: remote.account?.id) { await loadLocalDrafts() }
    }

    private func loadLocalDrafts() async {
        let owner = remote.account?.id
        let attempt = UUID()
        draftLoadID = attempt
        if displayedDraftOwner != owner { localDrafts = []; displayedDraftOwner = owner }
        unreadableDraftCount = 0; draftLoadError = nil; isLoadingDrafts = true
        defer { if draftLoadID == attempt { isLoadingDrafts = false } }
        do {
            let listing = try await remote.localDraftListing()
            try Task.checkCancellation()
            guard draftLoadID == attempt, remote.account?.id == owner else { return }
            localDrafts = listing.drafts; unreadableDraftCount = listing.unreadableFiles.count
        } catch is CancellationError {
        } catch {
            guard draftLoadID == attempt, remote.account?.id == owner else { return }
            draftLoadError = "기기 초안을 불러오지 못했습니다. 원본은 보관했습니다. \(error.localizedDescription)"
        }
    }
}

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

private struct OiOperatorView: View {
    let remote: OiRemoteStore

    var body: some View {
        List {
            if let error = remote.error { Text(error).foregroundStyle(.red) }
            Section("이야기 공개 검토") {
                ForEach(remote.reviewStories) { story in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(story.title).font(.headline)
                        Text(story.body)
                        Text(story.status.oiStatusTitle).font(.caption)
                        Text("\(story.latitude), \(story.longitude)").font(.caption)
                        ForEach(remote.media.filter { $0.storyId == story.id }) { media in
                            OiStoryMediaImage(path: media.objectPath) { path in try await remote.mediaURL(bucket: "oi-story-media", path: path) }
                                .frame(height: 140)
                        }
                        Button(story.status == "published" ? "비공개로 변경" : "공개 승인") {
                            Task { await remote.perform("review_story", payload: ["id":story.id.uuidString,"revision":story.revision,"status":story.status == "published" ? "hidden" : "published"]) }
                        }
                    }
                }
            }
        }.navigationTitle("운영자 검토").disabled(remote.isBusy).refreshable { await remote.refresh() }
    }
}
