import SwiftUI

struct OiStoryListScreen: View {
    let remote: OiRemoteStore

    @State private var localDrafts: [OiLocalDraft] = []
    @State private var selectedLocalID: UUID?
    @State private var showingAccount = false
    @State private var localError: String?
    @State private var selectedStoryID: UUID?
    @State private var showingConsent = false
    @State private var showingApprovalNotice = false
    #if DEBUG
    @State private var showingPractice = false
    #endif

    var body: some View {
        OiStoryListView(
            state: state,
            notices: ["이야기를 누르면 작성 내용과 공개 상태를 확인할 수 있습니다", "운영자 공개 승인 후 지도에서 오이를 볼 수 있습니다"],
            guidance: "작성 승인을 받은 뒤 오이와 이야기를 심어보세요",
            onRetry: { Task { await remote.refresh(); await loadLocalDrafts() } },
            onAddTicket: { showingAccount = true },
            onSelectStory: selectStory,
            onCreateStory: beginCreatingStory,
            onUseTicket: beginCreatingStory
        )
        #if DEBUG
        .safeAreaInset(edge: .top, spacing: 0) {
            Button { showingPractice = true } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Label("증빙 없이 작성 체험", systemImage: "play.circle.fill").font(.subheadline.bold())
                    Text("개발용 · 로그인 없이 체험 · 서버 전송 없음").font(.caption)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                    .foregroundStyle(Color("OiGreen")).background(Color("OiLight"), in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 20).padding(.vertical, 8)
            }.buttonStyle(.plain).accessibilityIdentifier("oi.practice.open")
        }
        .fullScreenCover(isPresented: $showingPractice) { OiCreationPreviewHost() }
        #endif
        .task(id: remote.account?.id) { await loadLocalDrafts() }
        .onChange(of: remote.revision) { _, _ in Task { await loadLocalDrafts() } }
        .onAppear { Task { await loadLocalDrafts() } }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(remote.account == nil ? "로그인" : "작성 승인·계정", systemImage: "person.crop.circle") { showingAccount = true }
            }
        }
        .navigationDestination(isPresented: $showingAccount) { OiAccountView(remote: remote) }
        .navigationDestination(item: $selectedLocalID) { id in
            OiStoryEditor(remote: remote, localID: id, onFinish: { selectedLocalID = nil })
        }
        .navigationDestination(item: $selectedStoryID) { storyID in
            OiStoryManagement(remote: remote, storyID: storyID)
        }
        .navigationDestination(isPresented: $showingConsent) {
            OiStoryCreationConsentFlow(remote: remote, onFinish: { showingConsent = false })
        }
        .alert("작성 승인이 필요해요", isPresented: $showingApprovalNotice) {
            Button("승인 상태 확인") { showingAccount = true }
            Button("닫기", role: .cancel) {}
        } message: {
            Text("증빙 검토와 이야기 작성 승인을 받은 뒤 오이와 이야기를 만들 수 있어요.")
        }
    }

    private var state: OiStoryListState {
        guard remote.account != nil else { return .empty }
        let drafts = localDrafts.filter { record in
            !record.submitted && !remote.ownStories.contains { $0.id == record.id }
        }
        if let error = localError ?? remote.loadError, remote.ownStories.isEmpty && drafts.isEmpty { return .failure(error) }
        if !remote.hasLoadedRemote && drafts.isEmpty { return .loading }
        let donorName = remote.profile?.nickname.nonEmpty ?? "익명"
        let serverItems = remote.ownStories.map { story in
            OiStoryListItem(story: story, donorDisplayName: donorName, locationDisplayName: locationDisplayName(for: story.regionId))
        }
        let localItems = drafts.map { record in
            OiStoryListItem(id: record.id, cucumberName: record.draft.cucumberName.nonEmpty ?? "작성 중인 오이",
                cucumberAsset: record.draft.cucumberAsset, donorDisplayName: donorName,
                locationDisplayName: "이 기기에 보관한 초안", tags: [record.draft.emotion, record.draft.theme].filter { !$0.isEmpty }, dateLabel: "작성 중")
        }
        let items = localItems + serverItems
        return items.isEmpty ? .empty : .content(items)
    }

    private func loadLocalDrafts() async {
        do { localDrafts = try await remote.localDrafts(); localError = nil }
        catch { localError = error.localizedDescription }
    }

    private func selectStory(id: UUID) {
        if localDrafts.contains(where: { $0.id == id && !$0.submitted }),
           !remote.ownStories.contains(where: { $0.id == id }) {
            selectedLocalID = id; return
        }
        guard remote.ownStories.contains(where: { $0.id == id }) else { return }
        selectedStoryID = id
    }

    private func beginCreatingStory() {
        guard remote.account != nil else { showingAccount = true; return }
        if remote.grants.contains(where: { $0.revokedAt == nil }) {
            showingConsent = true
        } else {
            showingApprovalNotice = true
        }
    }

    private func locationDisplayName(for regionID: String) -> String {
        guard let region = remote.regions.first(where: { $0.id == regionID }) else {
            return "장소 확인 중"
        }
        let schoolName = remote.schools.first(where: { $0.id == region.schoolId })?.name
        return [schoolName, region.name].compactMap { $0 }.joined(separator: " ")
    }
}

private extension String {
    var nonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
