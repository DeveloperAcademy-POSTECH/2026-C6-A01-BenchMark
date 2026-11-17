import SwiftUI

private struct OiPlantedStoryRevealKey: EnvironmentKey {
    static let defaultValue: (@MainActor @Sendable (OiStoryPlantSelection) -> Void)? = nil
}

extension EnvironmentValues {
    var revealPlantedStory: (@MainActor @Sendable (OiStoryPlantSelection) -> Void)? {
        get { self[OiPlantedStoryRevealKey.self] }
        set { self[OiPlantedStoryRevealKey.self] = newValue }
    }
}

struct OiStoryListScreen: View {
    let remote: OiRemoteStore
    var continuation: OiStoryContinuationIntent? = nil

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
    @State private var reviewWork: ReviewWork?
    @State private var reviewFailure: (id: UUID, message: String)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.revealPlantedStory) private var revealPlantedStory
    @State private var plantSelection: OiStoryPlantSelection?
    @State private var plantingStoryID: UUID?
    @State private var publicationMessage: String?

    #if DEBUG
    struct ReviewTestActions {
        let request: (UUID) -> Void
        let status: (UUID) -> OiStoryListReviewState
        let visibleIDs: () -> [UUID]
        let message: (UUID) -> String?
        let openPlantPicker: () -> Void
        let showsPlantPicker: () -> Bool
        let selectPlantCard: (UUID) -> Void
        let selectedPlantCard: () -> UUID?
        let cancelPlantPicker: () -> Void
        let confirmPlant: () -> Void
    }

    var onReviewActionsForTest: ((ReviewTestActions) -> Void)?
    #endif

    private struct ReviewWork {
        enum Stage {
            case prepare
            case capture(owner: UUID, draft: OiLocalDraft, look: OiWardrobeLook, orientation: OiCardOrientation, key: String)
            case submit(owner: UUID, draft: OiLocalDraft, portrait: Data?)
        }

        let id = UUID()
        let storyID: UUID
        let authorizesAIReview: Bool
        let stage: Stage

        func advancing(to stage: Stage) -> Self {
            Self(storyID: storyID, authorizesAIReview: authorizesAIReview, stage: stage)
        }
    }

    private struct DeletionTarget: Identifiable {
        let id: UUID
        let owner: UUID
        let story: OiLiveStory?
    }

    private struct DraftLoadKey: Equatable {
        let owner: UUID?
        let revision: Int
        let placementRevision: Int
    }
    @State private var selectedStoryID: UUID?
    @State private var showingConsent = false

    private var list: some View {
        let currentState = state
        let offersAIReview = remote.autoStoryModeration
        let visibleState = plantSelection.map { OiStoryListState.content($0.items) } ?? currentState
        return OiStoryListView(
            state: visibleState,
            minimumVisibleSlotCount: plantSelection == nil ? OiStoryListState.draftCapacity : 0,
            onRetry: { Task { await remote.refresh(); await loadLocalDrafts() } },
            onSelectStory: handleStoryTap,
            onCreateStory: beginCreatingStory,
            onDeleteStory: requestDeletion,
            isDeleting: deletingID != nil || remote.isBusy || reviewWork != nil || plantingStoryID != nil,
            reviewState: { reviewState(for: $0) },
            onRequestReview: { requestReview($0, offersAIReview: offersAIReview) },
            reviewMessage: reviewMessage,
            onPlant: handlePlantTap,
            canPlant: remote.autoStoryModeration && canPlant(in: currentState),
            selectedPlantStoryID: plantSelection?.selectedID,
            onCancelPlant: cancelPlantAction
        )
    }

    var body: some View {
        listWithDraftManagement
            .alert(publicationMessage ?? "", isPresented: Binding(
                get: { publicationMessage != nil }, set: { if !$0 { publicationMessage = nil } }
            )) {
                Button("확인", role: .cancel) {}
            }
            .task(id: reviewWork?.id) {
                if let work = reviewWork { await performReview(work) }
            }
            .overlay(alignment: .topLeading) { reviewPortraitCapture }
            .onDisappear { reviewWork = nil }
            #if DEBUG
            .onAppear {
                onReviewActionsForTest?(.init(request: { requestReview($0, offersAIReview: remote.autoStoryModeration) }, status: reviewState,
                    visibleIDs: { state.items.map(\.id) }, message: reviewMessage,
                    openPlantPicker: selectStoryToPlant, showsPlantPicker: { plantSelection != nil },
                    selectPlantCard: selectPlantCard, selectedPlantCard: { plantSelection?.selectedID },
                    cancelPlantPicker: cancelPlantSelection, confirmPlant: confirmPlant))
            }
            #endif
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
            reviewWork = nil
            reviewFailure = nil
            plantSelection = nil
            plantingStoryID = nil
            publicationMessage = nil
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
        // Figma `6101:8056`: the same fixed wording for every cucumber, whatever the delete covers.
        .alert(
            "‘작성 중인 오이'를\n삭제하시겠습니까?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            presenting: pendingDeletion
        ) { target in
            Button("취소하기", role: .cancel) { pendingDeletion = nil }
            Button("삭제하기", role: .destructive) { Task { await delete(target) } }
        } message: { _ in
            Text("삭제된 오이는 되돌릴 수 없습니다")
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
            OiStoryCreationConsentFlow(remote: remote, continuation: continuation, onFinish: { showingConsent = false })
        }

    }

    private func requestReview(_ id: UUID, offersAIReview: Bool) {
        let status = reviewState(for: id)
        guard reviewWork == nil, !remote.isBusy, deletingID == nil,
              state.items.contains(where: { $0.id == id }),
              status == .unreviewed || status == .rejected else { return }
        guard offersAIReview else {
            reviewFailure = (id, "지금은 자동검수를 사용할 수 없어요. 초안은 보존돼 있어요. 잠시 후 다시 시도해 주세요.")
            return
        }
        reviewFailure = nil
        reviewWork = ReviewWork(storyID: id, authorizesAIReview: offersAIReview, stage: .prepare)
    }

    private func performReview(_ work: ReviewWork) async {
        guard let owner = remote.account?.id else { reviewWork = nil; return }
        do {
            switch work.stage {
            case .prepare:
                try await prepareReview(work, owner: owner)
            case .capture:
                break
            case .submit(let preparedOwner, var draft, let portrait):
                guard preparedOwner == owner else { throw OiServiceError.accountChanged }
                try await submitReview(work, owner: owner, draft: &draft, portrait: portrait)
            }
        } catch {
            guard !Task.isCancelled, reviewWork?.id == work.id, remote.account?.id == owner else { return }
            reviewFailure = (work.storyID, error.localizedDescription)
            await loadLocalDrafts()
            if reviewWork?.id == work.id { reviewWork = nil }
        }
    }

    private func prepareReview(_ work: ReviewWork, owner: UUID) async throws {
        guard remote.canStartStory else { throw OiServiceError.storyCreationUnavailable }
        guard remote.canPublishDuplexCard, remote.canPublishStoryCard else {
            throw OiServiceError.server("서버가 양면 카드 공개를 지원하면 다시 요청해 주세요.")
        }
        let story = remote.ownStories.first { $0.id == work.storyID }
        let local = try await remote.localDraft(id: work.storyID, owner: owner)
        try Task.checkCancellation()
        guard reviewWork?.id == work.id else { return }
        if work.authorizesAIReview, remote.autoStoryModeration, let story, story.status == "pending" {
            try await submitLegacyReview(work, story: story, owner: owner, originalLocal: local)
            return
        }
        guard let draft = local ?? story.map({ OiLocalDraft(draft: OiStoryDraft(story: $0)) }),
              OiCreationAccess.canEdit(status: story?.status, submitted: draft.submitted) else { throw OiServiceError.conflict }
        guard OiStoryConsentState(savedIDs: draft.agreedConsentClauseIDs ?? []).allRequiredClausesAreAgreed else {
            throw OiServiceError.server("오이를 눌러 필수 약관에 동의해 주세요.")
        }
        let photos = OiEditingPhoto.ordered(local: draft.photos, remote: remote.mediaPaths(storyID: work.storyID),
            removed: draft.removedMediaPaths ?? [], removedPhotoIDs: draft.removedPhotoIDs ?? [])
        if let issue = OiCreationStep.reviewInputIssues(draft: draft.draftWithSavedLocation, photoCount: photos.count).first {
            throw OiServiceError.server(issue.message)
        }
        if draft.customization?.portraitLook != nil && !remote.canPublishCucumberAppearance {
            throw OiServiceError.server("서버가 꾸민 오이 공개를 지원하면 다시 요청해 주세요.")
        }

        if let customization = draft.customization, let look = customization.portraitLook {
            let card = customization.card
            let orientation = card?.characterOrientation ?? OiCardOrientation()
            let key = (customization.seedSnapshot?.portraitKey ?? OiCardPortrait.key(for: look)) + "-angle-" + orientation.cacheIdentity
            if card?.portraitKey == key, let bytes = card?.portraitPNG,
               let decoded = try? OiPublishedCucumberImage.decode(bytes, part: .portrait),
               OiPortraitMatte.hasTransparentBackground(UIImage(cgImage: decoded)) {
                reviewWork = work.advancing(to: .submit(owner: owner, draft: draft, portrait: bytes))
            } else {
                reviewWork = work.advancing(to: .capture(owner: owner, draft: draft, look: look, orientation: orientation, key: key))
            }
        } else {
            reviewWork = work.advancing(to: .submit(owner: owner, draft: draft, portrait: nil))
        }
    }

    private func submitLegacyReview(_ work: ReviewWork, story: OiLiveStory, owner: UUID,
                                    originalLocal: OiLocalDraft?) async throws {
        // The manual submission already has its public photos and appearance attached.
        let card = story.cardSnapshotId == nil
            ? try await reviewCard(for: OiStoryDraft(story: story), customization: OiDraftCustomization(), portrait: nil, story: nil)
            : nil
        try Task.checkCancellation()
        guard reviewWork?.id == work.id, remote.account?.id == owner else { return }
        let receipt = await remote.submitStory(story, card: card, agreesToAIReview: work.authorizesAIReview)
        try Task.checkCancellation()
        guard reviewWork?.id == work.id, remote.account?.id == owner else { return }
        let current = receipt ?? remote.ownStories.first(where: { $0.id == story.id })
        guard let current, remote.moderationResult(for: current) != nil else {
            throw OiServiceError.server(remote.error ?? "검토 요청을 확인하지 못했어요. 다시 시도해 주세요.")
        }
        if var local = try await remote.localDraft(id: story.id, owner: owner),
           local.version == originalLocal?.version, local.contentFingerprint == originalLocal?.contentFingerprint,
           OiCreationAccess.canRebase(local.draft, to: current) {
            local.draft = OiStoryDraft(story: current)
            local.submitted = false
            local.reviewedContentFingerprint = local.contentFingerprint
            local.version += 1
            try await remote.saveLocalDraft(local, owner: owner)
        }
        await loadLocalDrafts()
        if reviewWork?.id == work.id { reviewWork = nil }
    }

    @ViewBuilder private var reviewPortraitCapture: some View {
        if let work = reviewWork, case .capture(let owner, let draft, let look, let orientation, let key) = work.stage {
            OiCardPortraitCapture(look: look, seed: draft.customization?.seedSnapshot, cacheKey: key, orientation: orientation, onCapture: { bytes, _ in
                guard reviewWork?.id == work.id else { return }
                reviewWork = work.advancing(to: .submit(owner: owner, draft: draft, portrait: bytes))
            }, onFailure: {
                guard reviewWork?.id == work.id else { return }
                reviewFailure = (work.storyID, "꾸민 오이의 이미지를 준비하지 못했어요. 다시 검토를 요청해 주세요.")
                reviewWork = nil
            })
            .frame(width: 112, height: 142)
            .opacity(0.001)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .id(work.id)
        }
    }

    private func submitReview(_ work: ReviewWork, owner: UUID, draft: inout OiLocalDraft, portrait: Data?) async throws {
        let customization = draft.customization ?? OiDraftCustomization()
        let cucumber: OiCucumberPublication?
        if let look = customization.portraitLook {
            guard let portrait else { throw OiPhotoDataError.unreadable }
            cucumber = try OiCucumberPublication(look: look, portrait: portrait, seed: customization.seedSnapshot)
        } else { cucumber = nil }
        let existing = remote.ownStories.first { $0.id == work.storyID }
        let reviewDraft = draft.draftWithSavedLocation
        let card = try await reviewCard(for: reviewDraft, customization: customization, portrait: portrait, story: existing)
        let current = try await remote.localDraft(id: work.storyID, owner: owner)
        guard current?.contentFingerprint == draft.contentFingerprint,
              current?.agreedConsentClauseIDs == draft.agreedConsentClauseIDs,
              (current?.version ?? 0) <= draft.version else { throw OiServiceError.conflict }
        draft.draft = reviewDraft
        let saved = try await remote.saveDraftForReview(&draft, owner: owner)
        if work.authorizesAIReview, let fingerprint = draft.contentFingerprint {
            draft.reviewSubmission = .init(fingerprint: fingerprint,
                appearance: cucumber?.appearance ?? saved.cucumberAppearance,
                cardID: card.id, cardFormat: card.format, coverType: card.coverType)
            draft.version += 1
            try await remote.saveLocalDraft(draft, owner: owner)
        }
        try Task.checkCancellation()
        guard reviewWork?.id == work.id, remote.account?.id == owner else { return }
        let receipt = await remote.submitStory(saved, cucumber: cucumber, card: card, agreesToAIReview: work.authorizesAIReview)
        try Task.checkCancellation()
        guard reviewWork?.id == work.id, remote.account?.id == owner else { return }
        if let receipt {
            draft.draft = OiStoryDraft(story: receipt)
            draft.submitted = receipt.status == "pending"
        } else if remote.moderationResult(for: saved)?.status != .rejected {
            throw OiServiceError.server(remote.error ?? "검토 요청을 확인하지 못했어요. 다시 시도해 주세요.")
        }
        draft.reviewedContentFingerprint = draft.submitted ? nil : draft.contentFingerprint
        draft.reviewSubmission = nil
        draft.version += 1
        try await remote.saveLocalDraft(draft, owner: owner)
        await loadLocalDrafts()
        if reviewWork?.id == work.id { reviewWork = nil }
    }

    private func reviewCard(for draft: OiStoryDraft, customization: OiDraftCustomization, portrait: Data?,
                            story: OiLiveStory?) async throws -> OiStoryCardPublication {
        let author = remote.profile?.publicName ?? ""
        if customization == OiDraftCustomization(), let story, let path = story.cardArtworkPath {
            let front = try await remote.cucumberImage(path)
            let type = story.resolvedCardCoverType ?? .png
            let cover: Data?
            if remote.canPublishStoryCardCover, story.cardSnapshotFormat == 3, let path = story.cardArtworkPaths.last {
                cover = try await remote.storyCoverData(path, type: type)
            } else { cover = nil }
            return try OiCardImageExport.publication(front: front, message: draft.body, author: author,
                academicAuthor: OiPostcardAuthor.academic(department: remote.profile?.department, year: remote.profile?.admissionYear),
                tags: [draft.emotion, draft.theme],
                cover: cover, coverType: type)
        }
        let preview = OiDraftCardPreview(draft: draft, customization: customization, donorName: author,
                                         portrait: portrait.flatMap(UIImage.init(data:)))
        return try preview.publication(colorScheme: .light, includeCover: remote.canPublishStoryCardCover,
            coverType: remote.canPublishStoryCardCoverJPEG ? .jpeg : .png)
    }

    private var state: OiStoryListState {
        guard let owner = remote.account?.id else { return .empty }
        let drafts = loadedDraftOwner == owner ? localDrafts : []
        let localIDs = Set(drafts.map(\.id))
        let storiesByID = Dictionary(uniqueKeysWithValues: remote.ownStories.map { ($0.id, $0) })
        let donorName = donorLine
        func serverItem(_ story: OiLiveStory, portrait: Data? = nil) -> OiStoryListItem? {
            guard story.status == "draft" || story.status == "pending" else { return nil }
            return OiStoryListItem(story: story, portraitPNG: portrait,
                donorDisplayName: donorName, locationDisplayName: locationDisplayName(for: story.regionId))
        }
        let localItems = drafts.compactMap { record -> OiStoryListItem? in
            let portrait = record.customization?.card?.portraitPNG
            // A server receipt updates the existing row without moving it out of its local slot.
            if let story = storiesByID[record.id] { return serverItem(story, portrait: portrait) }
            guard !record.submitted else { return nil }
            return OiStoryListItem(id: record.id, cucumberName: record.personalPlacement?.name ?? record.draft.cucumberName.nonEmpty ?? "작성 중인 오이",
                title: record.draft.title, cucumberAsset: record.draft.cucumberAsset,
                portraitPNG: portrait, donorDisplayName: donorName,
                locationDisplayName: record.personalPlacement == nil ? "이 기기에 보관한 초안" : "내 지도에 배치됨",
                tags: [record.draft.emotion, record.draft.theme].filter { !$0.isEmpty },
                dateLabel: record.personalPlacement == nil ? "작성 중" : "나만 보기")
        }
        let serverItems = remote.ownStories.compactMap { localIDs.contains($0.id) ? nil : serverItem($0) }
        var remainingDrafts = OiStoryListState.draftCapacity
        let items = (localItems + serverItems).filter { item in
            if storiesByID[item.id]?.status == "pending" { return true }
            guard remainingDrafts > 0 else { return false }
            remainingDrafts -= 1
            return true
        }
        if !items.isEmpty { return .content(items) }
        if let error = (loadedDraftOwner == owner ? localError : nil) ?? remote.loadError { return .failure(error) }
        return remote.hasLoadedRemote ? .empty : .loading
    }

    private func reviewState(for id: UUID) -> OiStoryListReviewState {
        if reviewWork?.storyID == id || remote.reviewingStoryID == id { return .reviewing }
        guard let story = remote.ownStories.first(where: { $0.id == id }) else { return .unreviewed }
        if story.status == "pending" { return .unreviewed }
        guard let review = remote.moderationResult(for: story) else {
            return remote.storyReviewLookupFailed ? .lookupFailed : .unreviewed
        }
        if loadedDraftOwner == remote.account?.id,
           let local = localDrafts.first(where: { $0.id == id }),
           !(local.draft.revision == story.revision
             ? unchangedReviewedDraftIDs.contains(id)
             : local.matchesCompletedReview(story) || matchesLegacyReview(local, story: story)) {
            return .unreviewed
        }
        return review.status == .approved ? .approved : .rejected
    }

    private func matchesLegacyReview(_ local: OiLocalDraft, story: OiLiveStory) -> Bool {
        // An older submitted draft is read-only on this device. The transaction
        // can finalize it while the app is suspended, before the local receipt is saved.
        return local.submitted && story.revision == local.draft.revision + 1
            && OiCreationAccess.canRebase(local.draft, to: story)
    }

    private func canPlant(in state: OiStoryListState) -> Bool {
        if let selection = plantSelection { return reviewState(for: selection.selectedID) == .approved }
        return state.items.contains { reviewState(for: $0.id) == .approved }
    }

    private var cancelPlantAction: (() -> Void)? {
        guard plantSelection != nil else { return nil }
        return { cancelPlantSelection() }
    }

    private func handleStoryTap(_ id: UUID) {
        if plantSelection == nil { selectStory(id: id) }
        else { selectPlantCard(id) }
    }

    private func handlePlantTap() {
        if plantSelection == nil { selectStoryToPlant() }
        else { confirmPlant() }
    }

    private func selectStoryToPlant() {
        guard remote.autoStoryModeration, plantSelection == nil, !remote.isBusy, reviewWork == nil else { return }
        let items = state.items.filter { reviewState(for: $0.id) == .approved }
        guard let first = items.first else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.1)) {
            plantSelection = OiStoryPlantSelection(items: items, selectedID: first.id)
        }
    }

    private func selectPlantCard(_ id: UUID) {
        guard plantingStoryID == nil, let selection = plantSelection, selection.selectedID != id,
              selection.items.contains(where: { $0.id == id }), reviewState(for: id) == .approved else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) {
            plantSelection?.selectedID = id
        }
    }

    private func cancelPlantSelection() {
        guard plantingStoryID == nil else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.1)) { plantSelection = nil }
    }

    private func confirmPlant() {
        guard remote.autoStoryModeration, !remote.isBusy, plantingStoryID == nil, let selection = plantSelection,
              reviewState(for: selection.selectedID) == .approved,
              let story = remote.ownStories.first(where: { $0.id == selection.selectedID }) else { return }
        plantingStoryID = story.id
        Task {
            await plant(story, selection: selection)
            if plantingStoryID == story.id { plantingStoryID = nil }
        }
    }

    private func plant(_ story: OiLiveStory, selection: OiStoryPlantSelection) async {
        guard let owner = remote.account?.id else { return }
        do {
            let current = try await remote.localDraft(id: story.id, owner: owner)
            guard owner == remote.account?.id else { return }
            if let current, !(current.draft.revision == story.revision
                             ? current.matchesReviewedContent
                             : matchesLegacyReview(current, story: story)) {
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
        if published {
            if let revealPlantedStory {
                revealPlantedStory(selection)
            } else {
                plantSelection = nil
                publicationMessage = "이야기가 등록됐어요"
            }
        } else {
            publicationMessage = remote.error ?? "현재 이야기를 다시 검토해 주세요."
        }
    }

    private func reviewMessage(_ id: UUID) -> String? {
        if reviewFailure?.id == id { return reviewFailure?.message }
        guard reviewState(for: id) == .rejected,
              let story = remote.ownStories.first(where: { $0.id == id }) else { return nil }
        return remote.moderationResult(for: story)?.rejectionMessage
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
              state.items.contains(where: { $0.id == id }) else { return }
        let story = remote.ownStories.first { $0.id == id }
        let local = loadedDraftOwner == owner ? localDrafts.first { $0.id == id && !$0.submitted } : nil
        guard story != nil || local != nil else { return }
        pendingDeletion = DeletionTarget(id: id, owner: owner, story: story)
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
