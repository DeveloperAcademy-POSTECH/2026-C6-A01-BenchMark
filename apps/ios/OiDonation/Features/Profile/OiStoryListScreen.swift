import SwiftUI

struct OiStoryListScreen: View {
    let remote: OiRemoteStore

    @State private var localDrafts: [OiLocalDraft] = []
    @State private var unchangedReviewedDraftIDs: Set<UUID> = []
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
    @State private var selectedReviewID: UUID?
    @State private var choosingStoryToPlant = false
    @State private var publicationMessage: String?

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

    private var list: some View {
        OiStoryListView(
            state: state,
            seedCount: nil,
            notices: remote.autoStoryModeration ? OiStoryListView.reviewListNotices : OiStoryListView.listNotices,
            guidance: remote.autoStoryModeration ? nil : OiStoryListView.listGuidance,
            onRetry: { Task { await remote.refresh(); await loadLocalDrafts() } },
            onAddSeed: nil,
            onSelectStory: selectStory,
            onCreateStory: beginCreatingStory,
            onUseSeed: nil,
            onDeleteStory: requestDeletion,
            isDeleting: deletingID != nil || remote.isBusy,
            showsPublicationReview: remote.autoStoryModeration,
            reviewState: { reviewState(for: $0) },
            onRequestReview: { selectedReviewID = $0 },
            onShowReviewFailure: showReviewFailure,
            onPlant: { selectStoryToPlant() },
            canPlant: !plantableStories.isEmpty
        )
    }

    var body: some View {
        listWithDraftManagement
            .confirmationDialog("심을 오이를 선택하세요", isPresented: $choosingStoryToPlant, titleVisibility: .visible) {
                ForEach(plantableStories) { story in
                    Button(story.cucumberName) { Task { await plant(story) } }
                }
                Button("취소", role: .cancel) {}
            }
            .alert(publicationMessage ?? "", isPresented: Binding(
                get: { publicationMessage != nil }, set: { if !$0 { publicationMessage = nil } }
            )) {
                Button("확인", role: .cancel) {}
            }
            .navigationDestination(item: $selectedReviewID) { id in reviewEditor(for: id) }
    }

    private var listWithDraftManagement: some View {
        list
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
            selectedReviewID = nil; choosingStoryToPlant = false; publicationMessage = nil
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

    private func reviewEditor(for id: UUID) -> some View {
        let story = remote.ownStories.first { $0.id == id }
        return OiStoryEditor(remote: remote, story: story, localID: id,
                             opensReview: true, onFinish: { selectedReviewID = nil })
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
            let local = loadedDraftOwner == remote.account?.id ? localDrafts.first { $0.id == story.id } : nil
            return OiStoryListItem(story: story, portraitPNG: local?.customization?.card?.portraitPNG,
                donorDisplayName: donorName, locationDisplayName: locationDisplayName(for: story.regionId))
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

    private func reviewState(for id: UUID) -> OiStoryListReviewState {
        if remote.reviewingStoryID == id { return .reviewing }
        guard let story = remote.ownStories.first(where: { $0.id == id }),
              let review = remote.moderationResult(for: story) else { return .unreviewed }
        if loadedDraftOwner == remote.account?.id,
           let local = localDrafts.first(where: { $0.id == id }),
           local.draft.revision != story.revision || !unchangedReviewedDraftIDs.contains(id) {
            return .unreviewed
        }
        return review.status == .approved ? .approved : .rejected
    }

    private var plantableStories: [OiLiveStory] {
        let eligible = Set(state.items.filter { reviewState(for: $0.id) == .approved }.map(\.id))
        return remote.ownStories.filter { eligible.contains($0.id) }
    }

    private func selectStoryToPlant() {
        if plantableStories.count == 1, let story = plantableStories.first {
            Task { await plant(story) }
        } else if !plantableStories.isEmpty {
            choosingStoryToPlant = true
        }
    }

    private func plant(_ story: OiLiveStory) async {
        guard let owner = remote.account?.id else { return }
        do {
            let current = try await remote.localDraft(id: story.id, owner: owner)
            guard owner == remote.account?.id else { return }
            if let current, current.draft.revision != story.revision || !current.matchesReviewedContent {
                publicationMessage = "내용이 바뀌었어요. 다시 검토해 주세요."
                await loadLocalDrafts()
                return
            }
        } catch {
            publicationMessage = error.localizedDescription
            return
        }
        let published = await remote.plantStory(story)
        guard owner == remote.account?.id else { return }
        publicationMessage = published ? "이야기가 등록됐어요" : remote.error ?? "현재 이야기를 다시 검토해 주세요."
    }

    private func showReviewFailure(_ id: UUID) {
        guard let story = remote.ownStories.first(where: { $0.id == id }) else { return }
        publicationMessage = remote.moderationResult(for: story)?.rejectionMessage
    }

    private func loadLocalDrafts() async {
        let attempt = UUID()
        draftLoadAttempt = attempt
        guard let owner = remote.account?.id else {
            loadedDraftOwner = nil
            localDrafts = []
            unchangedReviewedDraftIDs = []
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
            unchangedReviewedDraftIDs = Set(listing.drafts.filter(\.matchesReviewedContent).map(\.id))
            unreadableDraftCount = listing.unreadableFiles.count
            pendingDiscardCount = listing.pendingDiscardCount
            localError = nil
        } catch {
            guard !Task.isCancelled, draftLoadAttempt == attempt, remote.account?.id == owner else { return }
            if loadedDraftOwner != owner {
                localDrafts = []
                unchangedReviewedDraftIDs = []
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
    private var donorLine: String {
        let profile = remote.profile
        let name = profile?.publicName?.nonEmpty
        let year = (profile?.admissionYear?.nonEmpty).map { "\($0.suffix(2))학번" }
        let line = [year, profile?.department?.nonEmpty, name].compactMap { $0 }.joined(separator: " ")
        return name == nil ? (profile?.nickname.nonEmpty ?? "익명") : line
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
