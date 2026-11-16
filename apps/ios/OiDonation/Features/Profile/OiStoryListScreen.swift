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
    @State private var reviewWork: ReviewWork?
    @State private var reviewConsentID: UUID?
    @State private var reviewFailure: (id: UUID, message: String)?
    @State private var choosingStoryToPlant = false
    @State private var publicationMessage: String?

    #if DEBUG
    struct ReviewTestActions {
        let request: (UUID) -> Void
        let grantConsent: (UUID) -> Void
        let status: (UUID) -> OiStoryListReviewState
        let needsConsent: (UUID) -> Bool
        let message: (UUID) -> String?
    }

    var onReviewActionsForTest: ((ReviewTestActions) -> Void)?
    #endif

    private struct ReviewWork {
        enum Stage {
            case prepare(consentGranted: Bool)
            case capture(owner: UUID, draft: OiLocalDraft, look: OiWardrobeLook, orientation: OiCardOrientation, key: String)
            case submit(owner: UUID, draft: OiLocalDraft, portrait: Data?)
        }

        let id = UUID()
        let storyID: UUID
        let stage: Stage
    }

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
        let plantAction: (() -> Void)? = remote.autoStoryModeration ? { selectStoryToPlant() } : nil
        return OiStoryListView(
            state: state,
            onRetry: { Task { await remote.refresh(); await loadLocalDrafts() } },
            onSelectStory: selectStory,
            onCreateStory: beginCreatingStory,
            onDeleteStory: requestDeletion,
            isDeleting: deletingID != nil || remote.isBusy || reviewWork != nil,
            reviewState: { reviewState(for: $0) },
            onRequestReview: requestReview,
            needsReviewConsent: { reviewConsentID == $0 },
            onGrantReviewConsent: { requestReview($0, consentGranted: true) },
            reviewMessage: reviewMessage,
            onPlant: plantAction,
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
            .task(id: reviewWork?.id) {
                if let work = reviewWork { await performReview(work) }
            }
            .overlay(alignment: .topLeading) { reviewPortraitCapture }
            .onDisappear { reviewWork = nil }
            #if DEBUG
            .onAppear {
                onReviewActionsForTest?(.init(request: requestReview,
                    grantConsent: { requestReview($0, consentGranted: true) }, status: reviewState,
                    needsConsent: { reviewConsentID == $0 }, message: reviewMessage))
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
            reviewConsentID = nil
            reviewFailure = nil
            choosingStoryToPlant = false
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

    private func requestReview(_ id: UUID) {
        requestReview(id, consentGranted: false)
    }

    private func requestReview(_ id: UUID, consentGranted: Bool) {
        guard reviewWork == nil, !remote.isBusy, deletingID == nil,
              state.items.contains(where: { $0.id == id }),
              reviewState(for: id) != .approved else { return }
        reviewFailure = nil
        reviewConsentID = nil
        reviewWork = ReviewWork(storyID: id, stage: .prepare(consentGranted: consentGranted))
    }

    private func performReview(_ work: ReviewWork) async {
        guard let owner = remote.account?.id else { reviewWork = nil; return }
        do {
            switch work.stage {
            case .prepare(let consentGranted):
                try await prepareReview(work, owner: owner, consentGranted: consentGranted)
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

    private func prepareReview(_ work: ReviewWork, owner: UUID, consentGranted: Bool) async throws {
        guard remote.canStartStory else { throw OiServiceError.storyCreationUnavailable }
        guard remote.canPublishDuplexCard, remote.canPublishStoryCard else {
            throw OiServiceError.server("서버가 양면 카드 공개를 지원하면 다시 요청해 주세요.")
        }
        let story = remote.ownStories.first { $0.id == work.storyID }
        let local = try await remote.localDraft(id: work.storyID, owner: owner)
        try Task.checkCancellation()
        guard reviewWork?.id == work.id else { return }
        guard var draft = local ?? story.map({ OiLocalDraft(draft: OiStoryDraft(story: $0)) }),
              OiCreationAccess.canEdit(status: story?.status, submitted: draft.submitted) else { throw OiServiceError.conflict }
        var consent = OiStoryConsentState(savedIDs: draft.agreedConsentClauseIDs ?? [])
        guard consent.allRequiredClausesAreAgreed else {
            throw OiServiceError.server("오이를 눌러 필수 약관에 동의해 주세요.")
        }
        guard OiCreationStep.allCases.allSatisfy({ $0.canContinue(draft: draft.draft) }) else {
            throw OiServiceError.invalidDraft
        }
        let photos = OiEditingPhoto.ordered(local: draft.photos, remote: remote.mediaPaths(storyID: work.storyID),
            removed: draft.removedMediaPaths ?? [], removedPhotoIDs: draft.removedPhotoIDs ?? [])
        guard (1...OiCreationStep.storyPhotoLimit).contains(photos.count) else {
            throw OiServiceError.server("이야기에 대표 사진을 한 장 넣어 주세요.")
        }
        if draft.customization?.wardrobe != nil && !remote.canPublishCucumberAppearance {
            throw OiServiceError.server("서버가 꾸민 오이 공개를 지원하면 다시 요청해 주세요.")
        }
        if remote.autoStoryModeration && !consent.isAgreed(to: .aiReviewV1) {
            guard consentGranted else { reviewConsentID = work.storyID; reviewWork = nil; return }
            consent.setAgreed(true, to: .aiReviewV1)
            draft.agreedConsentClauseIDs = consent.savedIDs
            draft.version += 1
        }

        if let look = draft.customization?.wardrobe {
            let card = draft.customization?.card
            let orientation = card?.characterOrientation ?? OiCardOrientation()
            let key = OiCardPortrait.key(for: look) + "-angle-" + orientation.cacheIdentity
            if card?.portraitKey == key, let bytes = card?.portraitPNG,
               let decoded = try? OiPublishedCucumberImage.decode(bytes, part: .portrait),
               OiPortraitMatte.hasTransparentBackground(UIImage(cgImage: decoded)) {
                reviewWork = ReviewWork(storyID: work.storyID, stage: .submit(owner: owner, draft: draft, portrait: bytes))
            } else {
                reviewWork = ReviewWork(storyID: work.storyID,
                    stage: .capture(owner: owner, draft: draft, look: look, orientation: orientation, key: key))
            }
        } else {
            reviewWork = ReviewWork(storyID: work.storyID, stage: .submit(owner: owner, draft: draft, portrait: nil))
        }
    }

    @ViewBuilder private var reviewPortraitCapture: some View {
        if let work = reviewWork, case .capture(let owner, let draft, let look, let orientation, let key) = work.stage {
            OiCardPortraitCapture(look: look, cacheKey: key, orientation: orientation, onCapture: { bytes, _ in
                guard reviewWork?.id == work.id else { return }
                reviewWork = ReviewWork(storyID: work.storyID, stage: .submit(owner: owner, draft: draft, portrait: bytes))
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
        if let look = customization.wardrobe {
            guard let portrait else { throw OiPhotoDataError.unreadable }
            cucumber = try OiCucumberPublication(look: look, portrait: portrait)
        } else { cucumber = nil }
        let existing = remote.ownStories.first { $0.id == work.storyID }
        let card = try await reviewCard(for: draft.draft, customization: customization, portrait: portrait, story: existing)
        let current = try await remote.localDraft(id: work.storyID, owner: owner)
        guard current?.contentFingerprint == draft.contentFingerprint,
              (current?.version ?? 0) <= draft.version else { throw OiServiceError.conflict }
        let saved = try await remote.saveDraftForReview(&draft, owner: owner)
        try Task.checkCancellation()
        guard reviewWork?.id == work.id, remote.account?.id == owner else { return }
        let agrees = draft.agreedConsentClauseIDs?.contains(OiStoryConsentClause.ID.aiReviewV1.rawValue) == true
        let receipt = await remote.submitStory(saved, cucumber: cucumber, card: card, agreesToAIReview: agrees)
        try Task.checkCancellation()
        guard reviewWork?.id == work.id, remote.account?.id == owner else { return }
        if let receipt {
            draft.draft = OiStoryDraft(story: receipt)
            draft.submitted = receipt.status == "pending"
        } else if remote.moderationResult(for: saved)?.status != .rejected {
            throw OiServiceError.server(remote.error ?? "검토 요청을 확인하지 못했어요. 다시 시도해 주세요.")
        }
        draft.reviewedContentFingerprint = draft.submitted ? nil : draft.contentFingerprint
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
                cover: cover, coverType: type)
        }
        let preview = OiDraftCardPreview(draft: draft, customization: customization, donorName: author,
                                         portrait: portrait.flatMap(UIImage.init(data:)))
        return try preview.publication(colorScheme: .light, includeCover: remote.canPublishStoryCardCover,
            coverType: remote.canPublishStoryCardCoverJPEG ? .jpeg : .png)
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
        if reviewWork?.storyID == id || remote.reviewingStoryID == id { return .reviewing }
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
