//
//  OiStoryEditor.swift
//  OiDonation
//
//  Created by 이돈혁 on 10/28/26.
//

import ImageIO
import PhotosUI
import SwiftUI

struct OiStoryEditor: View {
    private enum SupplementaryScreen: String, Identifiable {
        case completion
        var id: String { rawValue }
    }

    let remote: OiRemoteStore
    var onFinish: (() -> Void)?
    @State private var draft: OiStoryDraft
    @State private var owner: UUID?
    @State private var photos: [UUID] = []
    @State private var photoOrder: [String]?
    @State private var uploadedPhotos: Set<UUID> = []
    @State private var localVersion = 0
    @State private var restored = false
    @State private var isRestoring = false
    @State private var restorationError: String?
    @State private var restorationAttempt = 0
    @State private var isDiscarding = false
    @State private var discardCleanupError: String?
    @State private var submitted = false
    @State private var photoCheckpoint: PhotoCheckpoint?
    private struct PhotoCheckpoint: Identifiable {
        let id = UUID()
        let photos: [UUID]
        let order: [String]?
        let uploaded: Set<UUID>
        let removedPaths: [String]
        let removedIDs: Set<UUID>
    }
    @State private var photoSelections: [PhotosPickerItem] = []
    @State private var step: OiCreationStep = .story
    @FocusState private var focusedStoryField: OiStoryWritingStep.Field?
    @State private var customization = OiDraftCustomization()
    @State private var personalPlacement: OiPersonalPlacement?
    @State private var removedMediaPaths: [String] = []
    @State private var removedPhotoIDs: Set<UUID> = []
    @State private var saving = false
    @State private var placing = false
    @State private var localError: String?
    @State private var saveLabel = "기기 저장 준비 중"
    @State private var preparingPhoto = false
    @State private var publishing = false
    @State private var showingPreview = false
    @State private var openingPhotosAfterReview = false
    @State private var consentState = OiStoryConsentState()
    @State private var supplementaryScreen: SupplementaryScreen?
    @State private var choosingExit = false
    @State private var customizationReady = false
    @State private var wardrobePhotoEditing = false
    @State private var cardSizeEditing = false
    private var fillsCardEditor: Bool { step == .card && cardSizeEditing && !customizationReady }
    @State private var serverRevisionToReplace: Int?
    @State private var replacingServerDraft = false
    @State private var pendingSave: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss
    @Environment(CampusStoryStore.self) private var campusStore: CampusStoryStore?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(remote: OiRemoteStore, story: OiLiveStory? = nil, localID: UUID? = nil,
         initialStep: OiCreationStep = .story, onFinish: (() -> Void)? = nil) {
        self.remote = remote
        self.onFinish = onFinish
        var value: OiStoryDraft
        if let story { value = OiStoryDraft(story: story) }
        else { value = OiStoryDraft() }
        if let localID { value.id = localID }
        _draft = State(initialValue: value)
        _step = State(initialValue: initialStep)
    }

    #if DEBUG
    // Hosted tests can drive the mounted editor without depending on SwiftUI's UIKit accessibility tree.
    struct PhotoEditingTestActions {
        let items: @MainActor () -> [OiEditingPhoto]
        let open: @MainActor () -> Void
        let move: @MainActor (OiEditingPhoto, Int) -> Void
        let cancel: @MainActor () -> Void
        let done: @MainActor () -> Void
        let edit: @MainActor (UUID, OiPhotoEdit) async -> Bool
        let remove: @MainActor (OiEditingPhoto) -> Void
    }

    private var onPhotoEditingReady: ((PhotoEditingTestActions) -> Void)?

    func observePhotoEditingForTest(_ observe: @escaping (PhotoEditingTestActions) -> Void) -> Self {
        var view = self
        view.onPhotoEditingReady = observe
        return view
    }
    #endif

    var body: some View {
        if let owner, remote.account?.id != owner {
            ContentUnavailableView {
                Label("계정이 변경됐어요", systemImage: "person.crop.circle")
            } description: {
                Text("초안은 작성한 계정의 기기에 보관돼요.")
            } actions: {
                Button("나가기") { dismiss() }.buttonStyle(.borderedProminent)
            }
        } else {
            editorContent
        }
    }

    private var editorContent: some View {
        presentedContent
        .task(id: restorationAttempt) { await restoreDraft() }
        .onChange(of: draft) { _, _ in scheduleSave() }
        .onChange(of: photos) { _, _ in scheduleSave() }
        .onChange(of: uploadedPhotos) { _, _ in scheduleSave() }
        .onChange(of: step) { _, _ in
            focusedStoryField = nil
            scheduleSave()
        }
        .onChange(of: customization) { _, _ in scheduleSave() }
        .onChange(of: consentState) { _, _ in scheduleSave() }
        .onChange(of: removedMediaPaths) { _, _ in scheduleSave() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { scheduleSave() } }
        .onDisappear { if restored { scheduleSave() } }
        #if DEBUG
        .onAppear {
            onPhotoEditingReady?(PhotoEditingTestActions(
                items: { editingPhotos }, open: openPhotoEditor, move: movePhoto,
                cancel: cancelPhotoEditing, done: saveAndClosePhotoEditor, edit: editPhoto, remove: removePhoto
            ))
        }
        #endif
    }

    private var presentedContent: some View {
        VStack(spacing: 0) {
            if !restored {
                restorationStatus
            } else if submitted {
                completion
            } else if step == .location {
                OiLocationPicker(latitude: $draft.latitude, longitude: $draft.longitude,
                                 regionID: $draft.regionId,
                                 onFinish: { navigate(to: .story) })
            } else if step == .card && customizationReady {
                OiDraftPlacementPreview(draft: draft, wardrobe: customization.wardrobe, isShowingReview: showingPreview,
                    savedPlacement: personalPlacement, error: localError,
                    onEdit: { customizationReady = false },
                    onEditLocation: { navigate(to: .location) },
                    onPlace: { placement in Task { await placeOnMyMap(placement) } },
                    onReview: advance,
                    onPlacementChange: savePlacementPreview)
            } else {
                OiCreationProgressHeader(step: step.progress, onSelect: selectProgressStage,
                    canSelectStage: canSelectProgressStage)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    .background(Color(.systemBackground))
                    .environment(\.colorScheme, .light)

                Group {
                    if step == .consent {
                        OiStoryConsentView(clauses: OiStoryConsentClause.writingClauses,
                            continueTitle: "공개 약관에 동의하고 계속",
                            onContinue: advance, onExit: { choosingExit = true },
                            showsHeader: false, state: $consentState)
                    } else if step == .cucumber || step == .card {
                        VStack(spacing: 0) {
                            editorStatus.padding(.horizontal, 20)
                            stepContent
                            if !wardrobePhotoEditing && !fillsCardEditor {
                                Text(saveLabel).font(.caption2).foregroundStyle(.secondary)
                                    .accessibilityIdentifier("oi.draft.saveState")
                                if !customizationReady {
                                    Button("기기에 보관하거나 나가기") { choosingExit = true }
                                        .font(.footnote).padding(.vertical, 8)
                                }
                            }
                        }
                        .ignoresSafeArea(.container, edges: fillsCardEditor ? .bottom : [])
                    } else {
                        ScrollViewReader { scroll in
                            ScrollView { editorScrollContent }
                                .scrollDismissesKeyboard(.interactively)
                                .onChange(of: step) { _, _ in scroll.scrollTo("creation.top", anchor: .top) }
                                .onChange(of: wardrobePhotoEditing) { _, editing in
                                    if editing { scroll.scrollTo("creation.top", anchor: .top) }
                                }
                                .scrollDisabled(wardrobePhotoEditing)
                        }
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if step != .consent && (step == .story ? focusedStoryField == nil : customizationReady) {
                        OiCreationNavigationBar(canContinue: canLeaveCurrentStep,
                            onPrevious: reviewPreviousStep,
                            onNext: advance,
                            onSaveAndExit: { Task { if await persist() { dismiss() } } })
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
        }
        .background(Color(.systemBackground))
        .preferredColorScheme(.light)
        .environment(\.colorScheme, .light)
        .toolbarColorScheme(.light, for: .navigationBar)
        .toolbarBackground(Color(.systemBackground), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar(usesNavigationBar ? .visible : .hidden, for: .navigationBar)
        .disabled(remote.isBusy || preparingPhoto || publishing || saving || placing || replacingServerDraft || isDiscarding)
        .navigationTitle(submitted ? "접수 완료" : step.title).navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if step == .location {
                    Button("취소") { navigate(to: .story) }.accessibilityIdentifier("oi.location.cancel3D")
                } else {
                    Button(action: goBack) { Image(systemName: "chevron.left") }
                        .accessibilityLabel("이전 단계")
                        .disabled(remote.isBusy || preparingPhoto || publishing || saving || isDiscarding)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if !submitted && step != .location {
                    Button("나가기") { if restored { choosingExit = true } else { dismiss() } }
                        .disabled(remote.isBusy || preparingPhoto || publishing || saving || isDiscarding)
                }
            }
        }
        .interactiveDismissDisabled()
        .confirmationDialog("현재 입력을 어떻게 할까요?", isPresented: $choosingExit, titleVisibility: .visible) {
            Button("임시저장 후 나가기") { Task { if await persist() { dismiss() } } }
            Button(personalPlacement == nil ? "기기 초안 삭제" : "내 지도 배치와 기기 초안 삭제", role: .destructive) {
                Task { await discardDraft() }
            }
            Button("계속 작성", role: .cancel) {}
        } message: { Text("기기 초안과 사진 복사본을 삭제해요. 공개 요청을 보낸 이야기는 내 이야기에서 관리할 수 있어요.") }
        .alert("서버 버전으로 바꿀까요?", isPresented: Binding(
            get: { serverRevisionToReplace != nil },
            set: { if !$0 { serverRevisionToReplace = nil } }
        ), presenting: serverRevisionToReplace) { revision in
            Button("계속 편집", role: .cancel) {}
            Button("서버 버전으로 바꾸기", role: .destructive) {
                Task { await replaceWithServerDraft(revision: revision) }
            }
        } message: { _ in
            Text("제목, 본문, 위치를 서버 버전으로 바꿉니다. 추가한 사진과 기기에서 꾸민 오이·카드는 보관합니다.")
        }
        .fullScreenCover(item: $photoCheckpoint) { _ in photoEditorContent }
        .sheet(isPresented: $showingPreview, onDismiss: {
            guard openingPhotosAfterReview else { return }
            openingPhotosAfterReview = false
            openPhotoEditor()
        }) { reviewSheet }
        .sheet(item: $supplementaryScreen) { screen in
            NavigationStack {
                Group {
                    switch screen {
                    case .completion: completionContent(isPreview: true)
                    }
                }
                .toolbar { ToolbarItem(placement: .cancellationAction) {
                    Button("작성으로 돌아가기") { supplementaryScreen = nil }
                } }
            }
        }
    }

    private var usesNavigationBar: Bool { !restored }

    private var photoEditorContent: some View {
        VStack(spacing: 0) {
            photoEditorHeader
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 16) {
                        storyPhotos(previewWidth: min(296, max(0, geometry.size.width - 40)),
                                    previewHeight: min(400, max(180, geometry.size.height - 318)))
                        if let localError { Text(localError).font(.footnote).foregroundStyle(.red) }
                    }
                    .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 12)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .background { Color(white: 38 / 255).ignoresSafeArea() }
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
        .interactiveDismissDisabled()
        .disabled(remote.isBusy || preparingPhoto || saving || !photoSelections.isEmpty)
        .task(id: photoSelections) { await importSelectedPhotos() }
    }

    private var photoEditorHeader: some View {
        let cancel = Button(action: cancelPhotoEditing) {
            Text("취소").font(.custom("Paperlogy-3Light", size: 20, relativeTo: .body))
                .fixedSize()
                .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }.accessibilityIdentifier("oi.photos.cancel")
        let title = Text("이미지 선택")
            .font(.custom("Paperlogy-5Medium", size: 20, relativeTo: .body))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .accessibilityAddTraits(.isHeader)
        let done = Button(action: saveAndClosePhotoEditor) {
            Text("완료").font(.custom("Paperlogy-5Medium", size: 20, relativeTo: .body))
                .fixedSize()
                .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                .contentShape(Rectangle())
        }.accessibilityIdentifier("oi.creation.photosDone")

        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                cancel
                title.fixedSize().frame(maxWidth: .infinity)
                done
            }
            VStack(spacing: 4) {
                title
                HStack {
                    cancel
                    Spacer(minLength: 8)
                    done
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(white: 108 / 255))
        .tracking(0.4)
        .padding(.horizontal, 20)
        .frame(minHeight: 60)
    }

    private func storyPhotos(previewWidth: CGFloat, previewHeight: CGFloat) -> some View {
        OiStoryPhotoStep(items: editingPhotos, uploadedPhotos: attachedPhotoIDs, selections: $photoSelections,
            loadPhoto: { id in
                guard let owner, remote.account?.id == owner else { throw OiServiceError.accountChanged }
                return try await remote.localPhoto(id: id, owner: owner)
            }, edit: { id, operation in await editPhoto(id, operation: operation) }, remove: removePhoto,
            move: movePhoto,
            photo: { reviewPhoto($0, contentMode: .fill) }, thumbnail: { reviewPhoto($0, allowsRetry: false, contentMode: .fill) },
            previewWidth: previewWidth, previewHeight: previewHeight)
    }

    private func openPhotoEditor() {
        guard restored, !submitted, photoCheckpoint == nil else { return }
        focusedStoryField = nil
        photoCheckpoint = PhotoCheckpoint(photos: photos, order: photoOrder, uploaded: uploadedPhotos,
            removedPaths: removedMediaPaths, removedIDs: removedPhotoIDs)
    }

    private func cancelPhotoEditing() {
        guard !preparingPhoto, !saving, photoSelections.isEmpty, let checkpoint = photoCheckpoint else { return }
        photos = checkpoint.photos; photoOrder = checkpoint.order; uploadedPhotos = checkpoint.uploaded
        removedMediaPaths = checkpoint.removedPaths; removedPhotoIDs = checkpoint.removedIDs
        localVersion += 1
        saveAndClosePhotoEditor()
    }

    private func saveAndClosePhotoEditor() {
        guard !preparingPhoto, !saving, photoSelections.isEmpty, photoCheckpoint != nil else { return }
        saving = true
        Task {
            defer { saving = false }
            if await persist() { photoCheckpoint = nil }
        }
    }

    private func importSelectedPhotos() async {
        let selections = photoSelections
        guard !selections.isEmpty, let owner else { return }
        preparingPhoto = true
        defer { preparingPhoto = false; photoSelections = [] }
        var failures = 0
        for selection in selections {
            guard editingPhotos.count < OiCreationStep.storyPhotoLimit else { break }
            do {
                guard let data = try await selection.loadTransferable(type: Data.self) else { throw OiServiceError.invalidInput }
                let jpeg = try OiPhotoProcessor.prepare(data)
                try Task.checkCancellation()
                let id = UUID()
                try await remote.saveLocalPhoto(jpeg, id: id, owner: owner)
                try Task.checkCancellation()
                guard remote.account?.id == owner else { throw OiServiceError.accountChanged }
                guard editingPhotos.count < OiCreationStep.storyPhotoLimit else { break }
                photos.append(id); localVersion += 1; _ = await persist()
            } catch is CancellationError { return }
            catch { failures += 1 }
        }
        if failures > 0 { localError = "\(failures)장의 사진을 추가하지 못했어요. 기기에서 열 수 있는 사진인지 확인한 뒤 다시 선택해 주세요." }
    }

    private var editorScrollContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            editorStatus
            stepContent.id("creation.top")
            if step != .story {
                Text(saveLabel).font(.caption2).foregroundStyle(.secondary).accessibilityIdentifier("oi.draft.saveState")
            }
            if step == .cucumber || step == .card, !customizationReady && !wardrobePhotoEditing {
                Button("기기에 보관하거나 나가기") { choosingExit = true }.font(.footnote)
            }
        }.padding(.horizontal, 20).padding(.bottom, 24)
            .background {
                if step == .story && focusedStoryField != nil {
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { focusedStoryField = nil }
                        .accessibilityHidden(true)
                }
            }
    }

    private func reviewPreviousStep() {
        goBack()
    }

    private func selectProgressStage(_ stage: Int) {
        guard canSelectProgressStage(stage), let destination = OiCreationStep.stage(stage) else { return }
        navigate(to: destination)
    }

    private func canSelectProgressStage(_ stage: Int) -> Bool {
        guard !wardrobePhotoEditing, canLeaveCurrentStep else { return false }
        if stage <= step.progress { return true }
        return stage <= OiCreationStep.story.progress || OiCreationStep.location.canContinue(draft: draft)
    }

    private func navigate(to destination: OiCreationStep) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
            if step != destination { customizationReady = false }
            step = destination
        }
    }

    private func toggleCustomizationReady() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
            customizationReady.toggle()
        }
    }

    private func savePlacementPreview(_ placement: CampusPlacement, region: CampusRegion?) {
        var updated = draft
        updated.latitude = placement.latitude
        updated.longitude = placement.longitude
        updated.heightMeters = placement.heightMeters
        updated.headingDegrees = placement.headingDegrees
        if let region { updated.regionId = region.id }
        draft = updated
    }

    private func goBack() {
        if !restored { dismiss() }
        else if submitted { finish() }
        else if let previous = step.previous { navigate(to: previous) }
        else { choosingExit = true }
    }

    private var canLeaveCurrentStep: Bool {
        step != .consent || consentState.allRequiredClausesAreAgreed
    }

    private func advance() {
        guard canLeaveCurrentStep else { return }
        if step == .story, !OiCreationStep.location.canContinue(draft: draft) {
            navigate(to: .location)
            return
        }
        if let next = step.next { navigate(to: next) } else { showingPreview = true }
    }

    private func placeOnMyMap(_ placement: CampusPlacement) async {
        guard restored, !placing, !saving, !publishing, let owner, remote.account?.id == owner else { return }
        placing = true
        defer { placing = false }
        await pendingSave?.value
        let name = draft.cucumberName.trimmingCharacters(in: .whitespacesAndNewlines)
        let saved = OiPersonalPlacement(regionID: draft.regionId, name: name.isEmpty ? "내 오이" : name,
            latitude: placement.latitude, longitude: placement.longitude,
            heightMeters: placement.heightMeters, headingDegrees: placement.headingDegrees)
        localVersion += 1
        var snapshot = record()
        snapshot.personalPlacement = saved
        do {
            try await remote.savePersonalPlacement(snapshot, owner: owner)
            personalPlacement = saved
            saveLabel = "내 지도에 저장됨"
            localError = nil
            campusStore?.showAuthoredPlacementAction?(snapshot.id)
        } catch {
            localError = "내 지도에 배치하지 못했어요. \(error.localizedDescription)"
        }
    }

    private var restorationStatus: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isDiscarding || discardCleanupError != nil {
                Text("기기 초안 정리").font(.headline)
                if isDiscarding {
                    ProgressView().accessibilityLabel("기기 초안을 정리하고 있어요")
                } else if let discardCleanupError {
                    Text(discardCleanupError).font(.footnote).foregroundStyle(.red)
                    Button("첨부 파일 정리 다시 시도") { Task { await discardDraft() } }
                    Button("나가기") { dismiss() }
                }
            } else {
                Text("기기 초안 복원").font(.headline)
                if isRestoring { ProgressView().accessibilityLabel("기기 초안을 확인하고 있어요") }
                if let restorationError {
                    Text("초안을 복원하지 못했습니다. 원본을 덮어쓰지 않고 보관했습니다. \(restorationError)")
                        .font(.footnote).foregroundStyle(.red).accessibilityIdentifier("oi.draft.restoreError")
                    Button("초안 복원 다시 시도") { restorationAttempt += 1 }
                        .disabled(isRestoring).accessibilityIdentifier("oi.draft.restoreRetry")
                }
                Button("원본 보관하고 나가기") { dismiss() }.accessibilityIdentifier("oi.draft.preserveAndExit")
            }
        }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func discardDraft() async {
        guard let owner, !isDiscarding else { return }
        isDiscarding = true
        defer { isDiscarding = false }
        let wasRestored = restored
        restored = false
        await pendingSave?.value
        do {
            try await remote.discardLocalDraft(id: draft.id, owner: owner)
            dismiss()
        } catch let error as OiDraftDiscardCleanupError {
            discardCleanupError = error.localizedDescription
        } catch {
            if wasRestored { restored = true; localError = error.localizedDescription }
            else { discardCleanupError = error.localizedDescription }
        }
    }

    private func restoreDraft() async {
        guard !restored, !isDiscarding, discardCleanupError == nil else { return }
        guard let accountID = remote.account?.id else {
            restorationError = OiServiceError.signInRequired.localizedDescription; return
        }
        guard owner == nil || owner == accountID else {
            restorationError = OiServiceError.accountChanged.localizedDescription; return
        }
        owner = accountID; isRestoring = true; restorationError = nil
        defer { if !Task.isCancelled { isRestoring = false } }
        do {
            let record = try await remote.localDraft(id: draft.id, owner: accountID)
            try Task.checkCancellation()
            guard remote.account?.id == accountID else { throw OiServiceError.accountChanged }
            if let record {
                draft = record.draft; photos = record.photos; uploadedPhotos = Set(record.uploadedPhotos)
                localVersion = record.version; submitted = record.submitted
                step = record.creationStep.flatMap(OiCreationStep.init(rawValue:)) ?? .story
                customization = record.customization ?? OiDraftCustomization()
                personalPlacement = record.personalPlacement
                customizationReady = personalPlacement != nil && step == .card
                consentState = OiStoryConsentState(savedIDs: record.agreedConsentClauseIDs ?? [])
                removedMediaPaths = record.removedMediaPaths ?? []
                removedPhotoIDs = record.removedPhotoIDs ?? []
                photoOrder = record.photoOrder
            }
            if let server = remote.ownStories.first(where: { $0.id == draft.id }) {
                if draft.heightMeters == nil { draft.heightMeters = server.heightMeters }
                if draft.headingDegrees == nil { draft.headingDegrees = server.headingDegrees }
                submitted = !OiCreationAccess.canEdit(status: server.status, submitted: submitted)
            }
            restored = true; localError = nil; saveLabel = "이 계정의 기기 초안 자동 저장"
            if step == .photos {
                // Older drafts stored the photo editor as a step. Resume over the writing form.
                step = .story
                openPhotoEditor()
            }
        } catch let error as OiDraftDiscardCleanupError {
            discardCleanupError = error.localizedDescription
        } catch is CancellationError {
        } catch {
            restorationError = error.localizedDescription; saveLabel = "기기 초안 복원 미완료"
        }
    }

    private var reviewSheet: some View {
        OiStoryReview(draft: draft, customization: customization, savedCardPath: reusedCardPath,
            savedPortraitPath: customization.wardrobe == nil ? currentStory?.cucumberArtwork?.path(.portrait) : nil,
            donorName: remote.profile?.publicName ?? "",
            location: OiCreationStep.location.canContinue(draft: draft) ? completionLocation : nil,
            photos: editingPhotos, remote: remote, issues: reviewIssues,
            error: localError ?? remote.error ?? publicationAvailabilityMessage,
            canSubmit: canSubmit && publicationAvailabilityMessage == nil && !remote.isBusy && !saving, isSubmitting: publishing,
            onClose: { showingPreview = false },
            onEdit: { destination in
                openingPhotosAfterReview = destination == .photos
                showingPreview = false
                customizationReady = false
                navigate(to: destination == .photos ? .story : destination)
            }, onSubmit: { portrait, card in
                let reviewedCardPath = reusedCardPath
                Task { await submitReview(portrait: portrait, card: card, reviewedCardPath: reviewedCardPath) }
            }) { photo, thumbnail in
                reviewPhoto(photo, allowsRetry: !thumbnail, contentMode: thumbnail ? .fill : .fit,
                            maximumPixelSize: thumbnail ? 512 : 1600)
            }
            .id(reusedCardPath)
    }

    private var reviewIssues: [OiStoryReviewIssue] {
        var issues: [OiStoryReviewIssue] = []
        if !consentState.allRequiredClausesAreAgreed {
            issues.append(.init(step: .consent, message: "공개하려면 이야기와 게시물 조치 규정에 동의해 주세요."))
        }
        if !OiCreationStep.story.canContinue(draft: draft) {
            issues.append(.init(step: .story, message: "테마와 감정을 선택하고 제목과 이야기를 각각 \(OiCreationStep.storyTextLimit)자 이내로 입력해 주세요."))
        }
        if !OiCreationStep.location.canContinue(draft: draft) {
            issues.append(.init(step: .location, message: "캠퍼스 위치를 선택해 주세요."))
        }
        if !hasValidStoryPhotoCount {
            issues.append(.init(step: .photos, message: "이야기 사진을 1~\(OiCreationStep.storyPhotoLimit)장 선택해 주세요."))
        }
        if draft.cucumberName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.cucumberName.count > 50 {
            issues.append(.init(step: .card, message: "오이 이름을 1~50자로 입력해 주세요."))
        }
        return issues
    }

    private var publicationAvailabilityMessage: String? {
        if !canWrite { return OiWritingGuidance.unavailable }
        if !remote.canPublishStoryCard {
            return "서버가 꾸민 카드의 공개를 지원할 때 다시 요청해 주세요. 내 카드와 초안은 저장돼 있어요."
        }
        if customization.wardrobe != nil && !remote.canPublishCucumberAppearance {
            return "서버가 꾸민 오이의 공개를 지원할 때 다시 요청해 주세요. 내 지도와 초안은 저장돼 있어요."
        }
        return nil
    }

    private func submitReview(portrait: Data?, card: OiStoryCardPublication?, reviewedCardPath: String?) async {
        guard !publishing, !remote.isBusy, !saving, canSubmit, publicationAvailabilityMessage == nil else { return }
        publishing = true
        localError = nil
        defer { publishing = false }
        let publication: OiCucumberPublication?
        do {
            if let look = customization.wardrobe {
                guard let portrait else { throw OiPhotoDataError.unreadable }
                publication = try OiCucumberPublication(look: look, portrait: portrait)
            } else { publication = nil }
        } catch {
            localError = "꾸민 오이의 공개 이미지를 준비하지 못했어요. 의상과 사진을 확인해 주세요."
            return
        }
        guard let saved = await saveCurrent() else { return }
        guard card != nil || (reviewedCardPath != nil && reviewedCardPath == saved.cardArtworkPath) else {
            localError = "저장된 카드가 바뀌었어요. 카드를 다시 확인하고 검토를 요청해 주세요."
            return
        }
        if let receipt = await remote.submitStory(saved, cucumber: publication, card: card) {
            draft = OiStoryDraft(story: receipt); submitted = true; localVersion += 1
            _ = await persist()
            showingPreview = false
        }
    }

    @ViewBuilder private func reviewPhoto(_ photo: OiEditingPhoto, allowsRetry: Bool = true,
                                          contentMode: ContentMode = .fit, maximumPixelSize: Int = 512) -> some View {
        switch photo {
        case .local(let id):
            if let owner {
                OiLocalPhoto(remote: remote, owner: owner, id: id, contentMode: contentMode, maximumPixelSize: maximumPixelSize)
            }
        case .uploaded(let path):
            OiStoryMediaImage(path: path, allowsRetry: allowsRetry, contentMode: contentMode) { try await remote.mediaURL(bucket: "oi-story-media", path: $0) }
        }
    }

    private var canWrite: Bool { remote.canStartStory }
    private var hasValidStoryPhotoCount: Bool {
        (1...OiCreationStep.storyPhotoLimit).contains(editingPhotos.count)
    }
    private var canSubmit: Bool {
        canWrite && consentState.allRequiredClausesAreAgreed && hasValidStoryPhotoCount &&
        OiCreationStep.allCases.allSatisfy { $0.canContinue(draft: draft) }
    }
    private var serverMediaPaths: [String] { remote.mediaPaths(storyID: draft.id) }
    private var attachedPhotoIDs: Set<UUID> {
        uploadedPhotos.union(serverMediaPaths.compactMap(OiEditingPhoto.localPhotoID(for:)))
    }
    private var editingPhotos: [OiEditingPhoto] {
        let items = OiEditingPhoto.ordered(local: photos, remote: serverMediaPaths,
            removed: removedMediaPaths, removedPhotoIDs: removedPhotoIDs)
        guard let photoOrder else { return items }
        return OiEditingPhoto.applyingOrder(photoOrder, to: items, key: \.orderKey)
    }
    private var currentStory: OiLiveStory? { remote.ownStories.first { $0.id == draft.id } }
    // On a second device, preserve the last reviewed design until the author customizes it here.
    private var reusedCardPath: String? { customization == OiDraftCustomization() ? currentStory?.cardArtworkPath : nil }

    @ViewBuilder private var editorStatus: some View {
        OiConnectionStatus(remote: remote)
        if let error = localError ?? remote.error { Text(error).font(.footnote).foregroundStyle(.red) }
        if !canWrite {
            Text(OiWritingGuidance.unavailable)
                .font(.footnote).foregroundStyle(.orange)
            Button("공개 가능 상태 다시 확인") {
                Task { await remote.refresh() }
            }
        }

        if let saved = remote.ownStories.first(where: { $0.id == draft.id }),
           saved.revision != draft.revision, !OiCreationAccess.canRebase(draft, to: saved) {
            VStack(alignment: .leading) {
                Text("서버에서 이야기가 변경됐어요. 서버 버전을 적용하기 전까지 현재 입력은 바뀌지 않아요.").font(.footnote)
                Button("서버 초안 다시 불러오기") {
                    serverRevisionToReplace = saved.revision
                }
            }
        }
    }

    private func replaceWithServerDraft(revision: Int) async {
        guard let owner, remote.account?.id == owner, restored,
              !replacingServerDraft, !saving, !publishing, !preparingPhoto else { return }
        replacingServerDraft = true
        defer { replacingServerDraft = false }
        await pendingSave?.value
        guard remote.account?.id == owner,
              let latest = remote.ownStories.first(where: { $0.id == draft.id }), latest.revision == revision else {
            localError = "서버에서 이야기가 다시 변경됐어요. 최신 내용을 확인해 주세요."
            return
        }
        var replacement = record()
        replacement.version += 1
        replacement.draft = OiStoryDraft(story: latest)
        replacement.submitted = !OiCreationAccess.canEdit(status: latest.status, submitted: false)
        do {
            try await remote.saveLocalDraft(replacement, owner: owner)
            guard try await remote.localDraft(id: replacement.id, owner: owner) == replacement else {
                throw OiServiceError.conflict
            }
        } catch {
            localError = "서버 버전을 기기에 저장했는지 확인하지 못했어요. 현재 편집 내용을 유지합니다. \(error.localizedDescription)"
            return
        }
        draft = replacement.draft
        submitted = replacement.submitted
        localVersion = replacement.version
        saveLabel = "기기에 저장됨"
        localError = nil
    }

    @ViewBuilder private var stepContent: some View {
        switch step {
        case .consent, .photos, .location: EmptyView() // Presented separately above.
        case .story:
            VStack(alignment: .leading, spacing: 50) {
                Text("내 지도에 오이를 배치하려면 위치를 골라 주세요. 이야기와 사진은 공개할 때 필요해요.")
                    .font(CampusStyle.body(14)).foregroundStyle(.secondary)
                OiStoryWritingStep(draft: $draft, focusedField: $focusedStoryField)
                OiStoryAttachmentSections(photoCount: editingPhotos.count,
                    latitude: draft.latitude, longitude: draft.longitude,
                    onPhotos: openPhotoEditor, onLocation: { navigate(to: .location) })
            }
        case .cucumber:
            OiCucumberCustomizationStep(customization: $customization,
                canContinue: true, isFinished: customizationReady, onContinue: toggleCustomizationReady,
                onPhotoEditingChanged: { wardrobePhotoEditing = $0 })
        case .card:
            OiCardCustomizationStep(draft: $draft, customization: $customization,
                donorName: remote.profile?.publicName ?? "",
                onContinue: { customizationReady = true },
                onSizeEditingChanged: { cardSizeEditing = $0 })

        }
    }

    private var completion: some View {
        completionContent(isPreview: false)
    }

    private func completionContent(isPreview: Bool) -> some View {
        ScrollView {
            VStack(spacing: 34) {
                if isPreview {
                    Label("화면 미리보기 · 실제로 접수되지 않았어요", systemImage: "eye")
                        .font(.subheadline).foregroundStyle(Color("OiDark"))
                        .accessibilityIdentifier("oi.creation.completionPreview")
                }
                Group {
                    if let path = isPreview ? reusedCardPath : currentStory?.cardArtworkPath {
                        OiCucumberPortraitImage(path: path, label: "내가 꾸민 카드", load: { try await remote.cucumberImage($0) })
                            .aspectRatio(362 / 502, contentMode: .fit)
                    } else {
                        OiDraftCardPreview(draft: draft, customization: customization, donorName: remote.profile?.publicName ?? "")
                    }
                }.frame(maxWidth: 320).shadow(color: .black.opacity(0.25), radius: 7, x: 3, y: 6)
                VStack(alignment: .leading, spacing: 16) {
                    Text(draft.cucumberName.isEmpty ? "나의 오이" : draft.cucumberName).font(CampusStyle.characterTitle(28)).tracking(1.12)
                    Text([draft.emotion, draft.theme].filter { !$0.isEmpty }.map { "#" + $0 }.joined(separator: " "))
                        .font(CampusStyle.body(16)).foregroundStyle(Color("OiGreen"))
                    VStack(alignment: .leading, spacing: 6) {
                        completionMetadata("작성자", value: remote.profile?.nickname ?? "농부")
                        completionMetadata("위치", value: completionLocation)
                        if let date = currentStory?.createdDateLabel { completionMetadata("날짜", value: date) }
                    }
                    Text(isPreview ? "접수 후에는 이렇게 보여요" : "공개 검토 요청이 접수됐어요").font(CampusStyle.semibold(16))
                    Text("승인되면 이야기와 사진, 꾸민 오이와 카드를 다른 사람도 볼 수 있어요.")
                        .font(CampusStyle.body(14)).foregroundStyle(.secondary)
                    if !isPreview, let owner, owner == remote.account?.id, !remote.needsReauthentication,
                       let registered = remote.ownStories.first(where: { $0.id == draft.id && $0.userId == owner && $0.isRegisteredOnCampus }),
                       let showPlacement = campusStore?.showAuthoredPlacementAction {
                        if registered.status == "pending" {
                            Text("검토 중에도 내 지도에서 꾸민 오이와 카드를 확인할 수 있어요.")
                                .font(CampusStyle.body(14)).foregroundStyle(.secondary)
                        }
                        OiCreationNextButton(title: "지도에서 내 오이 보기") { showPlacement(draft.id) }
                            .accessibilityIdentifier("oi.creation.showAuthoredPlacement")
                    }
                    OiCreationNextButton(title: isPreview ? "작성으로 돌아가기" : "이야기 목록으로 돌아가기") {
                        if isPreview { supplementaryScreen = nil } else { finish() }
                    }
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 30))
                    .shadow(color: Color("OiDark").opacity(0.4), radius: 5)
            }.padding(.horizontal, 20).padding(.top, 42).padding(.bottom, 24)
        }.background(Color("OiLight"))
    }

    private var completionLocation: String {
        guard let region = remote.regions.first(where: { $0.id == draft.regionId }) else { return "선택한 캠퍼스 위치" }
        let school = remote.schools.first(where: { $0.id == region.schoolId })?.name
        return [school, region.name].compactMap { $0 }.joined(separator: " ")
    }

    private func completionMetadata(_ title: String, value: String) -> some View {
        Text("\(title) | \(value)").font(.custom("Paperlogy-2ExtraLight", size: 15, relativeTo: .subheadline))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func finish() {
        if let onFinish { onFinish() } else { dismiss() }
    }

    private func removePhoto(_ item: OiEditingPhoto) {
        switch item {
        case .local(let id):
            // The server might already have attached this UUID even if its receipt was lost.
            removedPhotoIDs.insert(id)
            photos.removeAll { $0 == id }; uploadedPhotos.remove(id)
        case .uploaded(let path): removedMediaPaths.append(path)
        }
        photoOrder?.removeAll { $0 == item.orderKey }
        scheduleSave()
    }

    private func movePhoto(_ item: OiEditingPhoto, by offset: Int) {
        var items = editingPhotos
        guard let from = items.firstIndex(of: item) else { return }
        let destination = min(max(0, from + offset), items.count - 1)
        guard from != destination else { return }
        items.remove(at: from)
        items.insert(item, at: destination)
        photoOrder = items.map(\.orderKey)
        scheduleSave()
    }

    private func editPhoto(_ id: UUID, operation: OiPhotoEdit) async -> Bool {
        guard let owner, !attachedPhotoIDs.contains(id), !preparingPhoto, !saving, !publishing else { return false }
        preparingPhoto = true
        defer { preparingPhoto = false }
        do {
            let data = try await remote.localPhoto(id: id, owner: owner)
            let jpeg = try OiPhotoProcessor.edit(data, operation: operation)
            let newID = UUID()
            try await remote.saveLocalPhoto(jpeg, id: newID, owner: owner)
            guard remote.account?.id == owner else { throw OiServiceError.accountChanged }
            guard !attachedPhotoIDs.contains(id), let index = photos.firstIndex(of: id) else { throw OiServiceError.conflict }
            if let orderIndex = photoOrder?.firstIndex(of: id.uuidString) {
                photoOrder?[orderIndex] = newID.uuidString
            }
            photos[index] = newID; localVersion += 1
            return await persist()
        } catch { localError = error.localizedDescription; return false }
    }

    private func record() -> OiLocalDraft {
        OiLocalDraft(draft: draft, photos: photos, uploadedPhotos: Array(uploadedPhotos), version: localVersion, submitted: submitted, creationStep: step.rawValue, customization: customization, removedMediaPaths: removedMediaPaths, removedPhotoIDs: removedPhotoIDs, agreedConsentClauseIDs: consentState.savedIDs, personalPlacement: personalPlacement, photoOrder: photoOrder)
    }

    private func scheduleSave() {
        guard restored, !placing, !replacingServerDraft, let owner else { return }
        localVersion += 1
        let snapshot = record()
        let previous = pendingSave
        pendingSave = Task { await previous?.value; _ = await persist(snapshot, owner: owner) }
    }

    private func persist() async -> Bool {
        guard restored, let owner else { return false }
        return await persist(record(), owner: owner)
    }

    private func persist(_ snapshot: OiLocalDraft, owner: UUID) async -> Bool {
        do {
            try await remote.saveLocalDraft(snapshot, owner: owner)
            if localVersion == snapshot.version { saveLabel = "기기에 저장됨"; localError = nil }
            return true
        } catch { localError = "기기 저장에 실패했습니다. 나가기 전에 재시도해 주세요. \(error.localizedDescription)"; return false }
    }

    private func saveCurrent() async -> OiLiveStory? {
        guard !saving, canSubmit else { return nil }
        saving = true
        defer { saving = false }
        if let latest = remote.ownStories.first(where: { $0.id == draft.id }), latest.revision != draft.revision,
           OiCreationAccess.canRebase(draft, to: latest) {
            draft.revision = latest.revision
            localVersion += 1
        }
        guard let owner, await persist(), remote.account?.id == owner else { return nil }
        let saved: OiLiveStory?
        if let existing = currentStory, OiCreationAccess.canRebase(draft, to: existing) { saved = existing }
        else { saved = await remote.save(draft) }
        guard var current = saved, remote.account?.id == owner else { return nil }
        draft = OiStoryDraft(story: current); localVersion += 1
        guard await persist() else { return nil }
        let alreadyAttached = attachedPhotoIDs
        for id in photos where !alreadyAttached.contains(id) && !removedPhotoIDs.contains(id) {
            do {
                let data = try await remote.localPhoto(id: id, owner: owner)
                guard let updated = await remote.uploadStoryImage(data, photoID: id, story: current) else { return nil }
                current = updated; uploadedPhotos.insert(id); draft.revision = updated.revision; localVersion += 1
                guard await persist() else { return nil }
            } catch { localError = error.localizedDescription; return nil }
        }
        if !removedMediaPaths.isEmpty || !removedPhotoIDs.isEmpty {
            guard let updated = await remote.removeStoryMedia(
                paths: Set(removedMediaPaths), photoIDs: removedPhotoIDs, story: current
            ) else { return nil }
            current = updated; draft.revision = updated.revision
            removedMediaPaths = []; removedPhotoIDs = []; localVersion += 1
            guard await persist() else { return nil }
        }
        if let photoOrder {
            // Uses the existing attach_media call to keep the server's attachment order equal to the draft.
            guard let updated = await remote.reorderStoryMedia(photoOrder, story: current) else { return nil }
            if updated.revision != current.revision {
                draft.revision = updated.revision; localVersion += 1
                guard await persist() else { return nil }
            }
            current = updated
        }
        return current
    }
}

struct OiLocalPhoto: View {
    let remote: OiRemoteStore
    let owner: UUID
    let id: UUID
    var contentMode: ContentMode = .fit
    var maximumPixelSize = 512
    @State private var image: UIImage?
    @State private var error: String?

    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode) }
            else if let error { Text(error).font(.caption) } else { ProgressView() }
        }.task(id: id) {
            do {
                let data = try await remote.localPhoto(id: id, owner: owner)
                guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize] as CFDictionary) else { throw OiServiceError.invalidInput }
                try Task.checkCancellation()
                guard remote.account?.id == owner else { throw OiServiceError.accountChanged }
                image = UIImage(cgImage: thumbnail)
            } catch { self.error = error.localizedDescription }
        }
    }
}


struct OiStoryMediaImage: View {
    let path: String
    var allowsRetry = true
    var contentMode: ContentMode = .fit
    let loadURL: (String) async throws -> URL
    @State private var retryCount = 0
    @State private var resolution: Resolution?

    private struct Request: Hashable {
        let path: String
        let attempt: Int
    }

    private enum Resolution {
        case success(Request, URL)
        case failure(Request, String)
    }

    var body: some View {
        let request = Request(path: path, attempt: retryCount)
        Group {
            if case .success(let resolved, let url) = resolution, resolved == request {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: contentMode).accessibilityLabel("이야기에 첨부된 사진")
                    } else if phase.error != nil { failure("사진을 불러오지 못했어요.") }
                    else { ProgressView().accessibilityLabel("사진 불러오는 중") }
                }
                .id(request)
            } else if case .failure(let resolved, let message) = resolution, resolved == request {
                failure(message)
            } else { ProgressView().accessibilityLabel("사진 불러오는 중") }
        }
        .task(id: request) {
            do {
                let url = try await loadURL(request.path)
                try Task.checkCancellation()
                resolution = .success(request, url)
            } catch {
                guard !Task.isCancelled else { return }
                resolution = .failure(request, error.localizedDescription)
            }
        }
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 4) {
            Text(message).font(.caption).foregroundStyle(.secondary)
            if allowsRetry {
                Button { retryCount += 1 } label: {
                    Text("사진 다시 불러오기").font(.caption).frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("oi.story.media.retry")
            }
        }
    }
}
