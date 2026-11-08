import SwiftUI

struct OiStoryListScreen: View {
    let remote: OiRemoteStore

    @State private var localDrafts: [OiLocalDraft] = []
    @State private var selectedLocalID: UUID?
    @State private var showingSettings = false
    @State private var localError: String?
    @State private var unreadableDraftCount = 0
    @State private var pendingDiscardCount = 0
    @State private var loadedDraftOwner: UUID?
    @State private var draftLoadAttempt = UUID()

    private struct DraftLoadKey: Equatable {
        let owner: UUID?
        let revision: Int
    }
    @State private var selectedStoryID: UUID?
    @State private var showingConsent = false
    @State private var showingCreationUnavailable = false

    var body: some View {
        OiStoryListView(
            state: state,
            seedCount: nil,
            notices: OiStoryListView.listNotices,
            guidance: writingGuidance,
            onRetry: { Task { await remote.refresh(); await loadLocalDrafts() } },
            onAddSeed: nil,
            onSelectStory: selectStory,
            onCreateStory: beginCreatingStory,
            onUseSeed: nil
        )
        .task(id: DraftLoadKey(owner: remote.account?.id, revision: remote.revision)) {
            await loadLocalDrafts()
        }
        .onChange(of: remote.account?.id) { _, _ in
            selectedLocalID = nil
            selectedStoryID = nil
            showingConsent = false
            showingCreationUnavailable = false
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let owner = remote.account?.id, loadedDraftOwner == owner, unreadableDraftCount > 0 || pendingDiscardCount > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    if unreadableDraftCount > 0 {
                        Text("기기 초안 \(unreadableDraftCount)개를 읽지 못했어요. 원본은 기기에 보관했습니다.")
                            .font(.footnote).accessibilityIdentifier("oi.drafts.recoveryWarning")
                    }
                    if pendingDiscardCount > 0 {
                        Text("삭제한 초안 \(pendingDiscardCount)개의 첨부 파일 정리가 남아 있어요.")
                            .font(.footnote).accessibilityIdentifier("oi.drafts.pendingDiscard")
                    }
                    Button("다시 확인") { Task { await loadLocalDrafts() } }
                        .frame(minHeight: 44).accessibilityIdentifier("oi.drafts.retry")
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial)
            }
        }
        .navigationDestination(isPresented: $showingSettings) { MYSettingsView(remote: remote) }
        .alert("오이 만들기를 시작할 수 없어요", isPresented: $showingCreationUnavailable) {
            Button("다시 확인") { Task { await remote.refresh() } }
            Button("닫기", role: .cancel) {}
        } message: {
            Text(OiWritingGuidance.unavailable)
        }
        .navigationDestination(item: $selectedLocalID) { id in
            OiStoryEditor(remote: remote, localID: id, onFinish: { selectedLocalID = nil })
        }
        .navigationDestination(item: $selectedStoryID) { storyID in
            OiStoryManagement(remote: remote, storyID: storyID)
        }
        .navigationDestination(isPresented: $showingConsent) {
            OiStoryCreationConsentFlow(remote: remote, onFinish: { showingConsent = false })
        }

    }

    private var writingGuidance: String {
        guard remote.account != nil, !remote.needsReauthentication else {
            return OiWritingGuidance.available
        }
        guard remote.hasLoadedRemote, remote.loadError == nil else {
            return OiStoryListView.listGuidance
        }
        return remote.canStartStory ? OiWritingGuidance.available : OiWritingGuidance.unavailable
    }

    private var state: OiStoryListState {
        guard remote.account != nil else { return .empty }
        let drafts = (loadedDraftOwner == remote.account?.id ? localDrafts : []).filter { record in
            !record.submitted && !remote.ownStories.contains { $0.id == record.id }
        }
        if let error = (loadedDraftOwner == remote.account?.id ? localError : nil) ?? remote.loadError, remote.ownStories.isEmpty && drafts.isEmpty { return .failure(error) }
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
        let attempt = UUID()
        draftLoadAttempt = attempt
        guard let owner = remote.account?.id else {
            loadedDraftOwner = nil
            localDrafts = []
            unreadableDraftCount = 0
            pendingDiscardCount = 0
            localError = nil
            return
        }
        do {
            let listing = try await remote.localDraftListing()
            guard !Task.isCancelled, draftLoadAttempt == attempt, remote.account?.id == owner else { return }
            loadedDraftOwner = owner
            localDrafts = listing.drafts
            unreadableDraftCount = listing.unreadableFiles.count
            pendingDiscardCount = listing.pendingDiscardCount
            localError = nil
        } catch {
            guard !Task.isCancelled, draftLoadAttempt == attempt, remote.account?.id == owner else { return }
            if loadedDraftOwner != owner {
                localDrafts = []
                unreadableDraftCount = 0
                pendingDiscardCount = 0
            }
            loadedDraftOwner = owner
            localError = error.localizedDescription
        }
    }

    private func selectStory(id: UUID) {
        if loadedDraftOwner == remote.account?.id, localDrafts.contains(where: { $0.id == id && !$0.submitted }),
           !remote.ownStories.contains(where: { $0.id == id }) {
            selectedLocalID = id; return
        }
        guard remote.ownStories.contains(where: { $0.id == id }) else { return }
        selectedStoryID = id
    }

    private func beginCreatingStory() {
        guard remote.account != nil, !remote.needsReauthentication else { showingSettings = true; return }
        if remote.canStartStory {
            showingConsent = true
        } else {
            showingCreationUnavailable = true
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
