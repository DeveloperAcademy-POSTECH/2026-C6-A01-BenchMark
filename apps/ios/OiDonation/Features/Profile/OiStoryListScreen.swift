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
    @State private var pendingDeletion: DeletionTarget?
    @State private var deletingID: UUID?
    @State private var deletionError: String?

    private struct DeletionTarget: Identifiable {
        let id: UUID
        let owner: UUID
        let name: String
        let story: OiLiveStory?
        let hasPersonalPlacement: Bool

        var message: String {
            if story != nil { return "이야기가 비공개·삭제 상태로 바뀌어요. 이 기기의 같은 초안과 내 지도 배치도 삭제돼요." }
            if hasPersonalPlacement { return "기기 초안과 첨부 사진, 내 지도에 배치한 오이가 삭제돼요. 되돌릴 수 없어요." }
            return "기기 초안과 첨부 사진이 삭제돼요. 되돌릴 수 없어요."
        }
    }

    private struct DraftLoadKey: Equatable {
        let owner: UUID?
        let revision: Int
        let placementRevision: Int
    }
    @State private var selectedStoryID: UUID?
    @State private var showingConsent = false

    var body: some View {
        OiStoryListView(
            state: state,
            seedCount: nil,
            notices: OiStoryListView.listNotices,
            guidance: OiStoryListView.listGuidance,
            onRetry: { Task { await remote.refresh(); await loadLocalDrafts() } },
            onAddSeed: nil,
            onSelectStory: selectStory,
            onCreateStory: beginCreatingStory,
            onUseSeed: nil,
            onDeleteStory: requestDeletion,
            isDeleting: deletingID != nil || remote.isBusy
        )
        .task(id: DraftLoadKey(owner: remote.account?.id, revision: remote.revision,
                               placementRevision: remote.localPlacementRevision)) {
            await loadLocalDrafts()
        }
        .onChange(of: remote.account?.id) { _, _ in
            selectedLocalID = nil
            selectedStoryID = nil
            showingConsent = false
            pendingDeletion = nil
            deletionError = nil
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
        .confirmationDialog(
            pendingDeletion.map { "‘\($0.name)’ 삭제할까요?" } ?? "오이를 삭제할까요?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { target in
            Button("삭제", role: .destructive) { Task { await delete(target) } }
            Button("취소", role: .cancel) { pendingDeletion = nil }
        } message: { target in
            Text(target.message)
        }
        .alert("삭제하지 못했어요", isPresented: Binding(
            get: { deletionError != nil }, set: { if !$0 { deletionError = nil } }
        )) {
            Button("확인", role: .cancel) { deletionError = nil }
        } message: {
            Text(deletionError ?? "잠시 후 다시 시도해 주세요.")
        }
        .navigationDestination(isPresented: $showingSettings) { MYSettingsView(remote: remote) }
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

    private var state: OiStoryListState {
        guard remote.account != nil else { return .empty }
        let drafts = (loadedDraftOwner == remote.account?.id ? localDrafts : []).filter { record in
            !record.submitted && !remote.ownStories.contains { $0.id == record.id }
        }
        if let error = (loadedDraftOwner == remote.account?.id ? localError : nil) ?? remote.loadError,
           !remote.ownStories.contains(where: { $0.status == "draft" }) && drafts.isEmpty { return .failure(error) }
        if !remote.hasLoadedRemote && drafts.isEmpty { return .loading }
        let donorName = donorLine
        // Only saved drafts belong here; stories sent for review or published are not listed (#368).
        let serverItems = remote.ownStories.filter { $0.status == "draft" }.map { story in
            OiStoryListItem(story: story, donorDisplayName: donorName,
                locationDisplayName: locationDisplayName(for: story.regionId))
        }
        let localItems = drafts.map { record in
            OiStoryListItem(id: record.id, cucumberName: record.personalPlacement?.name ?? record.draft.cucumberName.nonEmpty ?? "작성 중인 오이",
                title: record.draft.title, cucumberAsset: record.draft.cucumberAsset,
                portraitPNG: record.customization?.card?.portraitPNG, donorDisplayName: donorName,
                locationDisplayName: record.personalPlacement == nil ? "이 기기에 보관한 초안" : "내 지도에 배치됨",
                tags: [record.draft.emotion, record.draft.theme].filter { !$0.isEmpty },
                dateLabel: record.personalPlacement == nil ? "작성 중" : "나만 보기")
        }
        let items = Array((localItems + serverItems).prefix(OiStoryListState.draftCapacity))
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

    private func requestDeletion(id: UUID) {
        guard deletingID == nil, !remote.isBusy, let owner = remote.account?.id,
              let item = state.items.first(where: { $0.id == id }) else { return }
        let story = remote.ownStories.first { $0.id == id }
        let local = loadedDraftOwner == owner ? localDrafts.first { $0.id == id && !$0.submitted } : nil
        guard story != nil || local != nil else { return }
        pendingDeletion = DeletionTarget(id: id, owner: owner, name: item.cucumberName,
            story: story, hasPersonalPlacement: local?.personalPlacement != nil)
    }

    private func delete(_ target: DeletionTarget) async {
        pendingDeletion = nil
        guard deletingID == nil, !remote.isBusy, remote.account?.id == target.owner else { return }
        deletingID = target.id
        defer { deletingID = nil }
        if let story = target.story {
            let deleted = await remote.deleteStory(story)
            guard remote.account?.id == target.owner else { return }
            if !deleted {
                deletionError = remote.error ?? "이야기를 삭제하지 못했어요. 최신 상태를 확인한 후 다시 시도해 주세요."
            } else {
                do {
                    try await remote.discardLocalDraft(id: target.id, owner: target.owner)
                } catch {
                    if remote.account?.id == target.owner {
                        deletionError = "이야기는 삭제했지만 기기 초안 정리를 마치지 못했어요. \(error.localizedDescription)"
                    }
                }
            }
        } else {
            do {
                try await remote.discardLocalDraft(id: target.id, owner: target.owner)
            } catch {
                if remote.account?.id == target.owner { deletionError = error.localizedDescription }
            }
        }
        guard remote.account?.id == target.owner else { return }
        await loadLocalDrafts()
    }

    private func beginCreatingStory() {
        guard !state.isFull else { return }
        guard remote.canPlaceOi else { showingSettings = true; return }
        showingConsent = true
    }

    /// "24학번 반도체공학과 서수리" when the donor search details are set, otherwise the nickname (Figma `5441:17267`).
    private var donorLine: String { remote.profile?.publicDonorLine ?? "익명" }

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
