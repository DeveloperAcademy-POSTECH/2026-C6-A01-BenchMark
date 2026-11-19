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
    private let onReopen: (() -> Void)?
    private let onDeleteSubmittedStory: (() -> Void)?
    private let continuation: OiStoryContinuationIntent?
    private var cucumberPreviewMode: OiCucumberCustomizationStep.PreviewMode = .seed
    @State private var draft: OiStoryDraft
    @State private var owner: UUID?
    @State private var photos: [UUID] = []
    @State private var photoOrder: [String]?
    @State private var uploadedPhotos: Set<UUID> = []
    @State private var localVersion = 0
    @State private var reviewedContentFingerprint: String?
    @State private var restored = false
    @State private var isRestoring = false
    @State private var restorationError: String?
    @State private var restorationAttempt = 0
    @State private var isDiscarding = false
    @State private var discardCleanupError: String?
    @State private var submitted = false
    @State private var photoCheckpoint: PhotoCheckpoint?
    /// Step the location picker was opened from; the story form stays mounted underneath so its scroll position survives.
    @State private var locationOrigin: OiCreationStep?
    private struct PhotoCheckpoint: Identifiable {
        let id = UUID()
        let photos: [UUID]
        let order: [String]?
        let uploaded: Set<UUID>
        let removedPaths: [String]
        let removedIDs: Set<UUID>
    }
    @State private var photoSelections: [PhotosPickerItem] = []
    /// 사진 추가하기 on an empty story opens the system picker directly instead of the photo editor (#430).
    @State private var showingStoryPhotoPicker = false
    /// 사진 다시 선택하기: the new picks replace the current photos once the first one is ready.
    @State private var replacingStoryPhotos = false
    @State private var step: OiCreationStep = .story
    @State private var focusedStoryField: OiStoryWritingStep.Field?
    /// STEP 2 shows missing items under the buttons only after Next is tapped (#373).
    @State private var showingStoryMissing = false
    @State private var completionFigure: UIImage?
    /// STEP 4 완료 is saving the draft; the screen must not dim while it does (#386).
    @State private var completingCard = false
    /// The card portrait rendered in the background once STEP 3 is finished (#386).
    @State private var portraitPrefetch: (look: OiWardrobeLook, seed: OiSeedCucumberSnapshot?, key: String, orientation: OiCardOrientation)?
    @State private var showingDonorPicker = false
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
    @State private var consentState = OiStoryConsentState.acceptedForStoryCreation
    @State private var supplementaryScreen: SupplementaryScreen?
    @State private var choosingExit = false
    /// STEP 1 exit alert, Figma `5400:8313` (#370).
    @State private var confirmingConsentExit = false
    @State private var customizationReady = false
    @State private var wardrobePhotoEditing = false
    @State private var bottomSafeAreaInset: CGFloat = 0
    @State private var cardPlacementReady = false
    /// Figma `5887:10243`: STEP 4 `완료` saves on this device and shows this summary (#377).
    @State private var showingCardCompletion = false
    /// The navigation controller holding the pushed completion screen, used to leave in a single animation.
    @State private var completionNavigation = OiNavigationHolder()
    @State private var serverRevisionToReplace: Int?
    @State private var replacingServerDraft = false
    @State private var pendingSave: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss
    @Environment(CampusStoryStore.self) private var campusStore: CampusStoryStore?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(remote: OiRemoteStore, story: OiLiveStory? = nil, localID: UUID? = nil,
         initialStep: OiCreationStep = .story, continuation: OiStoryContinuationIntent? = nil,
         onReopen: (() -> Void)? = nil, onDeleteSubmittedStory: (() -> Void)? = nil,
         onFinish: (() -> Void)? = nil) {
        self.remote = remote
        self.onReopen = onReopen
        self.onDeleteSubmittedStory = onDeleteSubmittedStory
        self.onFinish = onFinish
        self.continuation = continuation
        var value: OiStoryDraft
        if let story { value = OiStoryDraft(story: story) }
        else { value = OiStoryDraft() }
        if let localID { value.id = localID }
        _draft = State(initialValue: value)
        _step = State(initialValue: initialStep == .consent ? .story : initialStep)
    }

    #if DEBUG
    func useWardrobeEditorForTest() -> Self {
        var view = self
        view.cucumberPreviewMode = .wardrobe
        return view
    }

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

    struct NavigationTestActions {
        let finish: @MainActor () -> Void
        let next: @MainActor () -> Void
        let exit: @MainActor () async -> Bool
        let editFromReview: @MainActor (OiCreationStep) -> Void
        let isPlacementPreview: @MainActor () -> Bool
        let currentStep: @MainActor () -> OiCreationStep
        let shownMissingItems: @MainActor () -> [String]
        let isCompletion: @MainActor () -> Bool
        let completionDone: @MainActor () -> Void
    }
    private var onNavigationVisibilityForTest: ((Bool) -> Void)?
    private var onNavigationActionsForTest: ((NavigationTestActions) -> Void)?

    func observeNavigationForTest(_ observe: @escaping (Bool) -> Void,
                                  actions: ((NavigationTestActions) -> Void)? = nil) -> Self {
        var view = self
        view.onNavigationVisibilityForTest = observe
        view.onNavigationActionsForTest = actions
        return view
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
        .task(id: step == .story) {
            // Prepare only the selected source while the user fills in STEP 2.
            guard step == .story, ProcessInfo.processInfo.thermalState.rawValue < ProcessInfo.ThermalState.serious.rawValue else { return }
            let look = customization.wardrobe ?? OiWardrobeLook()
            if let url = try? OiWardrobeAsset.url(look.modelName, folder: "Wardrobe") {
                _ = try? await OiWardrobeModelCache.shared.clone(from: url)
            }
        }
        .onChange(of: draft) { _, _ in scheduleSave() }
        .onChange(of: photos) { _, _ in scheduleSave() }
        .onChange(of: uploadedPhotos) { _, _ in scheduleSave() }
        .onChange(of: step) { _, _ in
            endStoryEditing()
            showingStoryMissing = false
            scheduleSave()
        }
        .onChange(of: customization) { _, _ in scheduleSave() }
        .onChange(of: consentState) { _, _ in scheduleSave() }
        .onChange(of: removedMediaPaths) { _, _ in scheduleSave() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { scheduleSave() } }
        .onDisappear { if restored { scheduleSave() } }
        #if DEBUG
        .onChange(of: showsNavigationPanel) { _, visible in onNavigationVisibilityForTest?(visible) }
        .onAppear {
            onNavigationActionsForTest?(NavigationTestActions(
                finish: { if step == .card { Task { await completeCard() } } else { toggleCustomizationReady() } },
                next: { if step == .card { cardPlacementReady = true } else if step == .story { storyNext() } else { advance() } },
                exit: saveAndExit, editFromReview: editFromReview,
                isPlacementPreview: { step == .card && cardPlacementReady },
                currentStep: { step }, shownMissingItems: { showingStoryMissing ? missingStoryItems : [] },
                isCompletion: { showingCardCompletion }, completionDone: finish))
            onPhotoEditingReady?(PhotoEditingTestActions(
                items: { editingPhotos }, open: openPhotoEditor, move: movePhoto,
                cancel: cancelPhotoEditing, done: saveAndClosePhotoEditor, edit: editPhoto, remove: removePhoto
            ))
        }
        #endif
    }

    private var cardCompletion: some View {
        OiStoryCompletionView(draft: draft, customization: customization,
            donorName: remote.profile?.publicName ?? "", location: completionLocation,
            onDone: { finish() }, initialFigure: completionFigure)
    }

    private var placementPreview: some View {
        OiDraftPlacementPreview(draft: draft, wardrobe: customization.portraitLook, seed: customization.seedSnapshot, isShowingReview: showingPreview,
            savedPlacement: personalPlacement, error: localError, autoStoryModeration: remote.autoStoryModeration,
            onEdit: { cardPlacementReady = false; customizationReady = false },
            onEditLocation: { navigate(to: .location) },
            onPlace: { placement in Task { await placeOnMyMap(placement) } },
            onReview: advance,
            onPlacementChange: savePlacementPreview)
    }

    private var editorLayout: some View {
        VStack(spacing: 0) {
            if !restored {
                restorationStatus
            } else if submitted {
                completion
            } else if step == .location && !locationOverStory {
                locationPicker
            } else if step == .card && cardPlacementReady {
                placementPreview
            } else {
                OiCreationProgressHeader(step: step.progress, onSelect: selectProgressStage,
                    canSelectStage: canSelectProgressStage)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    .background(Color(.systemBackground))
                    .environment(\.colorScheme, .light)

                Group {
                    if step == .consent {
                        VStack(spacing: 0) {
                            if let localError {
                                Text(localError).font(.footnote).foregroundStyle(.red).padding(.horizontal, 20)
                                    .accessibilityIdentifier("oi.consent.saveError")
                            }
                            OiStoryConsentView(clauses: OiStoryConsentClause.writingClauses,
                                onContinue: advance, onExit: requestExit,
                                showsHeader: false, state: $consentState)
                        }
                        .task { prewarmStoryStep() }
                    } else if step == .cucumber || step == .card {
                        VStack(spacing: 0) {
                            editorStatus.padding(.horizontal, 20)
                            stepContent
                        }
                        .environment(\.oiCustomizationBottomInset, customizationReady ? 0 : bottomSafeAreaInset)
                        .ignoresSafeArea(.container, edges:
                            !customizationReady && !wardrobePhotoEditing ? .bottom : [])
                        // STEP 3 follows the keyboard itself to scale the cucumber smoothly (#377).
                        .ignoresSafeArea(.keyboard, edges: step == .cucumber ? .bottom : [])
                    } else {
                        ScrollViewReader { scroll in
                            ScrollView { editorScrollContent }
                                .modifier(OiCustomizationScrollEdge())
                                .accessibilityIdentifier("oi.creation.storyScroll")
                                .scrollDismissesKeyboard(.interactively)
                                                                .onChange(of: step) { old, new in
                                    // Coming back from the location picker keeps the earlier scroll position.
                                    guard old != .location, new != .location else { return }
                                    scroll.scrollTo("creation.top", anchor: .top)
                                }
                                .onChange(of: wardrobePhotoEditing) { _, editing in
                                    if editing { scroll.scrollTo("creation.top", anchor: .top) }
                                }
                                .onChange(of: showingStoryMissing) { _, showing in
                                    // The message sits under the buttons; bring it into view.
                                    guard showing else { return }
                                    withAnimation(reduceMotion ? nil : OiCreationMotion.screen) {
                                        scroll.scrollTo("creation.storyButtons", anchor: .bottom)
                                    }
                                }
                                .scrollDisabled(wardrobePhotoEditing)
                        }
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if (step == .cucumber || step == .card) && customizationReady {
                        OiCreationNavigationBar(canContinue: canLeaveCurrentStep,
                            onPrevious: reviewPreviousStep,
                            onNext: {
                                if step == .card { cardPlacementReady = true }
                                else { advance() }
                            },
                            onSaveAndExit: { Task { if await persist() { dismiss() } } })
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { bottomSafeAreaInset = $0 }
        .background(Color(.systemBackground))
        .preferredColorScheme(.light)
        .environment(\.colorScheme, .light)
        .toolbarColorScheme(.light, for: .navigationBar)
        .toolbarBackground(Color(.systemBackground), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar(usesNavigationBar ? .visible : .hidden, for: .navigationBar)
        // Saving for STEP 4 완료 blocks other actions through `saving` but must not grey the whole screen out first.
        .disabled(remote.isBusy || preparingPhoto || publishing || (saving && !completingCard) || placing || replacingServerDraft || isDiscarding)
        .navigationTitle(navigationTitle).navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if step == .location {
                    Button("취소") { navigate(to: .story) }.accessibilityIdentifier("oi.location.cancel3D")
                } else {
                    Button(action: goBack) { Image(systemName: "chevron.left") }
                        .accessibilityLabel("이전 단계")
                        .disabled(remote.isBusy || preparingPhoto || publishing || (saving && !completingCard) || isDiscarding)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if !submitted && step != .location {
                    Button("나가기", action: requestExit)
                        .disabled(remote.isBusy || preparingPhoto || publishing || (saving && !completingCard) || isDiscarding)
                }
            }
        }
        .interactiveDismissDisabled()
        // From the story form the picker is a native push: slides in from the right and swipes back (#430).
        // 접수 완료 is a native push too, so it slides in and swipes back exactly like the location picker (#386).
        .navigationDestination(isPresented: $showingCardCompletion) {
            cardCompletion
                .toolbar(.hidden, for: .navigationBar)
                .navigationBarBackButtonHidden()
                .oiSwipeBackEnabled()
                .oiCaptureNavigation(into: completionNavigation)
        }
        .navigationDestination(isPresented: Binding(
            get: { locationOverStory },
            set: { if !$0, step == .location { navigate(to: .story) } }
        )) {
            locationPicker
                .background(Color(.systemBackground))
                .preferredColorScheme(.light)
                .toolbar(.hidden, for: .navigationBar)
                .navigationBarBackButtonHidden()
                .oiSwipeBackEnabled()
        }
    }

    private var presentedContent: some View {
        editorLayout
            .background(alignment: .topLeading) { portraitPrefetchSurface }
            .onChange(of: step) { _, _ in updatePortraitPrefetch() }
            .onChange(of: customization.wardrobe) { _, _ in portraitPrefetch = nil }
            .onChange(of: customization.seedSnapshot) { _, _ in portraitPrefetch = nil }
            .confirmationDialog("현재 입력을 어떻게 할까요?", isPresented: $choosingExit, titleVisibility: .visible) {
                Button("임시저장 후 나가기") { Task { if await persist() { dismiss() } } }
                Button(personalPlacement == nil ? "기기 초안 삭제" : "내 지도 배치와 기기 초안 삭제", role: .destructive) {
                    Task { await discardDraft() }
                }
                Button("계속 작성", role: .cancel) {}
            } message: { Text("기기 초안과 사진 복사본을 삭제해요. 공개 요청을 보낸 이야기는 MY에서 확인할 수 있어요.") }
            .alert("현재 진행 상황을\n저장하고 나가시겠습니까?", isPresented: $confirmingConsentExit) {
                Button("저장하고 나가기") { Task { _ = await saveAndExit() } }
                    .accessibilityIdentifier("oi.consent.exit.save")
                Button("삭제하기", role: .destructive) { Task { await discardDraft() } }
                    .accessibilityIdentifier("oi.consent.exit.discard")
            } message: {
                Text("작성하신 내용들은 삭제되지 않고\n기기에 로컬로 임시 저장됩니다")
            }
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
            .photosPicker(isPresented: $showingStoryPhotoPicker, selection: $photoSelections,
                          maxSelectionCount: replacingStoryPhotos ? OiCreationStep.storyPhotoLimit : max(1, OiCreationStep.storyPhotoLimit - editingPhotos.count),
                          matching: .images)
            .onChange(of: showingStoryPhotoPicker) { _, showing in
                if !showing && photoSelections.isEmpty { replacingStoryPhotos = false }
            }
            .task(id: photoSelections) {
                // The photo editor imports its own selections while it is open.
                guard photoCheckpoint == nil else { return }
                await importSelectedPhotos()
            }
            .fullScreenCover(isPresented: $showingDonorPicker) {
                OiConnectedDonationPicker(
                    stories: recentDonationStories,
                    onCancel: { showingDonorPicker = false },
                    onDone: { customization.connectedStoryID = $0; customization.connectedStorySelectionEdited = true; showingDonorPicker = false })
            }
            .sheet(isPresented: $showingPreview, onDismiss: {
                guard openingPhotosAfterReview else { return }
                openingPhotosAfterReview = false
                openStoryPhotos()
            }) { reviewSheet }
            .sheet(item: $supplementaryScreen) { supplementaryContent($0) }
    }

    private var showsNavigationPanel: Bool {
        if step == .story { return false } // STEP 2 keeps its buttons at the end of the scroll (#373).
        return (step == .cucumber || step == .card) && customizationReady && !cardPlacementReady
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

    /// The story fields are UIKit text views; resign them synchronously so no keyboard survives a screen change.
    private func endStoryEditing() {
        focusedStoryField = nil
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func openStoryPhotos() {
        guard restored, !submitted, photoCheckpoint == nil else { return }
        endStoryEditing()
        replacingStoryPhotos = !editingPhotos.isEmpty
        showingStoryPhotoPicker = true
    }

    private func openPhotoEditor() {
        guard restored, !submitted, photoCheckpoint == nil else { return }
        // Resign before presenting; otherwise UIKit keeps (and later restores) the story keyboard over the photo editor.
        endStoryEditing()
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
        localVersion += 1
        Task {
            defer { saving = false }
            await pendingSave?.value
            if await persist() { photoCheckpoint = nil }
        }
    }

    private func importSelectedPhotos() async {
        let selections = photoSelections
        guard !selections.isEmpty, let owner else { return }
        preparingPhoto = true
        defer { preparingPhoto = false; photoSelections = []; replacingStoryPhotos = false }
        var failures = 0
        // When replacing, the current photos go only after a new one is ready, so a failed pick keeps them.
        var pendingRemoval: [OiEditingPhoto]? = replacingStoryPhotos ? editingPhotos : nil
        for selection in selections {
            guard (pendingRemoval == nil ? editingPhotos.count : 0) < OiCreationStep.storyPhotoLimit else { break }
            do {
                guard let data = try await selection.loadTransferable(type: Data.self) else { throw OiServiceError.invalidInput }
                let jpeg = try OiPhotoProcessor.prepare(data)
                try Task.checkCancellation()
                let id = UUID()
                try await remote.saveLocalPhoto(jpeg, id: id, owner: owner)
                try Task.checkCancellation()
                guard remote.account?.id == owner else { throw OiServiceError.accountChanged }
                guard (pendingRemoval == nil ? editingPhotos.count : 0) < OiCreationStep.storyPhotoLimit else { break }
                if let old = pendingRemoval { old.forEach(removePhoto); pendingRemoval = nil }
                photos.append(id)
                if photoCheckpoint == nil {
                    localVersion += 1
                    _ = await persist()
                }
            } catch is CancellationError { return }
            catch { failures += 1 }
        }
        if failures > 0 { localError = "\(failures)장의 사진을 추가하지 못했어요. 기기에서 열 수 있는 사진인지 확인한 뒤 다시 선택해 주세요." }
    }

    private var editorScrollContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            editorStatus
            stepContent.id("creation.top")
            if contentStep == .story {
                // Figma `5400:7726`: the buttons follow the last section instead of floating over it.
                OiCreationNavigationBar(inline: true, missingItems: showingStoryMissing ? missingStoryItems : [],
                    onPrevious: reviewPreviousStep, onNext: storyNext,
                    onSaveAndExit: { Task { if await persist() { dismiss() } } })
                    .padding(.top, 30)
                    .id("creation.storyButtons")
            }
            if contentStep != .story {
                Text(saveLabel).font(.caption2).foregroundStyle(.secondary).accessibilityIdentifier("oi.draft.saveState")
            }
        }.padding(.horizontal, 20).padding(.bottom, 24)
            .background {
                if step == .story && focusedStoryField != nil {
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { endStoryEditing() }
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
        guard stage > OiCreationStep.consent.progress, !wardrobePhotoEditing else { return false }
        if step == .consent, stage == OiCreationStep.cucumber.progress,
           ProcessInfo.processInfo.arguments.contains("-oi-test-step3") {
            return true
        }
        if stage <= step.progress { return step != .consent || consentState.allRequiredClausesAreAgreed }
        guard canLeaveCurrentStep else { return false }
        return stage <= OiCreationStep.story.progress || storyInputIsComplete
    }

    /// The first STEP 2 draw caches TextKit and the Korean glyphs of its fonts; prepare them while STEP 1
    /// is idle so switching to STEP 2 shows without a hitch. The rendered image is discarded.
    private func prewarmStoryStep() {
        OiStoryTextView.prewarm()
        let renderer = ImageRenderer(content: VStack(alignment: .leading, spacing: 50) {
            OiStoryWritingStep(draft: .constant(draft), focusedField: .constant(nil))
            OiCreationNavigationBar(inline: true, onPrevious: {}, onNext: {}, onSaveAndExit: {})
        }.frame(width: 362).environment(\.colorScheme, .light))
        renderer.scale = 3
        _ = renderer.cgImage
    }

    private var locationOverStory: Bool { step == .location && locationOrigin == .story }
    /// Content shown in the scroll view; the story form stays while the picker covers it.
    private var contentStep: OiCreationStep { locationOverStory ? .story : step }

    private var locationPicker: some View {
        OiLocationPicker(latitude: $draft.latitude, longitude: $draft.longitude,
                         regionID: $draft.regionId,
                         heightMeters: $draft.heightMeters, headingDegrees: $draft.headingDegrees,
                         onFinish: { navigate(to: .story) })
    }

    private func navigate(to destination: OiCreationStep) {
        let destination: OiCreationStep = destination == .consent ? .story : destination
        if destination == .location { locationOrigin = step }
        // STEP 1 ↔ STEP 2 switch at once, without a slide or fade (#373); other steps keep the short fade.
        let switchesAtOnce = Set([step, destination]) == [.consent, .story]
            || (Set([step, destination]).contains(.location) && (destination == .location ? step : locationOrigin) == .story)
        withAnimation(reduceMotion || switchesAtOnce ? nil : OiCreationMotion.screen) {
            if step != destination { customizationReady = false; cardPlacementReady = false }
            step = destination
        }
    }

    /// Save the draft on this device before showing the completion summary; keep editing on failure.
    private func completeCard() async {
        guard restored, step == .card, !saving, !placing, !publishing, !isDiscarding else { return }
        saving = true; completingCard = true
        defer { saving = false; completingCard = false }
        await pendingSave?.value
        guard !Task.isCancelled, let owner, remote.account?.id == owner else { return }
        var design = customization.card ?? OiCardDesign()
        if design.postcardDate == nil {
            design.postcardDate = .now
            customization.card = design
        }
        guard await persist(), !Task.isCancelled, remote.account?.id == owner else { return }
        // Prepare the trimmed cucumber first and fade the summary in, so it neither pops in nor cuts in (#386).
        completionFigure = await OiStoryCompletionView.figureImage(draft: draft, customization: customization)
        showingCardCompletion = true
    }

    private func toggleCustomizationReady() {
        withAnimation(reduceMotion ? nil : OiCreationMotion.screen) {
            customizationReady.toggle()
        }
        updatePortraitPrefetch()
    }

    /// Once STEP 3 is finished the card portrait is rendered behind the screen, so STEP 4 opens with it ready.
    private func updatePortraitPrefetch() {
        guard step == .cucumber, customizationReady, let look = customization.portraitLook else { portraitPrefetch = nil; return }
        let orientation = (customization.card?.characterOrientation ?? OiCardOrientation()).normalized
        let seed = customization.seedSnapshot
        let key = (seed?.portraitKey ?? OiCardPortrait.key(for: look)) + "-angle-" + orientation.cacheIdentity
        portraitPrefetch = customization.card?.portraitKey == key ? nil : (look, seed, key, orientation)
    }

    @ViewBuilder private var portraitPrefetchSurface: some View {
        if step == .cucumber, let prefetch = portraitPrefetch {
            // Same size as STEP 4's capture surface; invisible and never touchable.
            OiCardPortraitCapture(look: prefetch.look, seed: prefetch.seed, cacheKey: prefetch.key, orientation: prefetch.orientation,
                                  onCapture: { _, _ in portraitPrefetch = nil })
                .id(prefetch.key).frame(width: 217, height: 308)
                .opacity(0.001).allowsHitTesting(false).accessibilityHidden(true)
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
        else { requestExit() }
    }

    private func requestExit() {
        guard restored else { dismiss(); return }
        if step == .consent { confirmingConsentExit = true }
        else { choosingExit = true }
    }

    private func saveAndExit() async -> Bool {
        guard restored, !saving, !placing, !publishing, !isDiscarding else { return false }
        saving = true
        defer { saving = false }
        await pendingSave?.value
        guard await persist() else { return false }
        dismiss()
        return true
    }

    private var canLeaveCurrentStep: Bool {
        switch step {
        case .consent: consentState.allRequiredClausesAreAgreed
        case .story: storyInputIsComplete
        default: true
        }
    }

    /// Next stays enabled on STEP 2; missing input shows what to fill instead of moving on.
    private func storyNext() {
        endStoryEditing()
        guard storyInputIsComplete else {
            showingStoryMissing = true
            AccessibilityNotification.Announcement(missingStoryItems.joined(separator: ", ")).post()
            return
        }
        showingStoryMissing = false
        advance()
    }

    /// Figma `5400:7726` order: theme, emotion, title, story, photo, location (#373).
    private var missingStoryItems: [String] {
        func blank(_ value: String) -> Bool { value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var items: [String] = []
        if blank(draft.theme) { items.append("테마가 선택되지 않았습니다") }
        if blank(draft.emotion) { items.append("감정이 선택되지 않았습니다") }
        if blank(draft.title) { items.append("제목이 입력되지 않았습니다") }
        else if OiCreationStep.storyBytes(draft.title) > OiCreationStep.storyTitleByteLimit { items.append("제목을 \(OiCreationStep.storyTitleByteLimit)byte 이내로 줄여주세요") }
        if blank(draft.body) { items.append("이야기가 입력되지 않았습니다") }
        else if OiCreationStep.storyBytes(draft.body) > OiCreationStep.storyBodyByteLimit { items.append("이야기를 \(OiCreationStep.storyBodyByteLimit)byte 이내로 줄여주세요") }
        if editingPhotos.isEmpty { items.append("사진은 1장 이상 추가해주세요 (대표이미지)") }
        else if editingPhotos.count > OiCreationStep.storyPhotoLimit { items.append("사진은 \(OiCreationStep.storyPhotoLimit)장만 선택할 수 있습니다") }
        if !OiCreationStep.location.canContinue(draft: draft) { items.append("오이 위치가 설정되지 않았습니다") }
        return items
    }

    /// Theme, emotion, title, story, one photo and a campus location are all required before the cucumber step.
    private var storyInputIsComplete: Bool {
        OiCreationStep.story.canContinue(draft: draft) && hasValidStoryPhotoCount
            && OiCreationStep.location.canContinue(draft: draft)
    }

    private func advance() {
        if step == .cucumber { endStoryEditing() }
        guard canLeaveCurrentStep else { return }
        if let next = step.next { navigate(to: next) } else { showingPreview = true }
    }

    private func placeOnMyMap(_ placement: CampusPlacement) async {
        guard restored, !placing, !saving, !publishing, let owner, remote.account?.id == owner else { return }
        placing = true
        defer { placing = false }
        await pendingSave?.value
        savePlacementPreview(placement, region: nil)
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
                draft = record.draftWithSavedLocation; photos = record.photos; uploadedPhotos = Set(record.uploadedPhotos)
                localVersion = record.version; submitted = record.submitted
                reviewedContentFingerprint = record.reviewedContentFingerprint
                let savedStep = record.creationStep.flatMap(OiCreationStep.init(rawValue:)) ?? .story
                step = savedStep == .consent ? .story : savedStep
                customization = record.customization ?? OiDraftCustomization()
                if customization.connectedStorySelectionEdited != true, customization.connectedStoryID == nil {
                    customization.connectedStoryID = currentStory?.continuedFromStoryId?.uuidString
                }
                personalPlacement = record.personalPlacement
                customizationReady = personalPlacement != nil && step == .card
                cardPlacementReady = customizationReady
                consentState = .acceptedForStoryCreation
                removedMediaPaths = record.removedMediaPaths ?? []
                removedPhotoIDs = record.removedPhotoIDs ?? []
                photoOrder = record.photoOrder
            }
            if let server = remote.ownStories.first(where: { $0.id == draft.id }) {
                if record?.submitted == true, OiCreationAccess.canRebase(draft, to: server) {
                    draft.revision = server.revision
                }
                if draft.heightMeters == nil { draft.heightMeters = server.heightMeters }
                if draft.headingDegrees == nil { draft.headingDegrees = server.headingDegrees }
                if customization.connectedStorySelectionEdited != true, customization.connectedStoryID == nil {
                    customization.connectedStoryID = server.continuedFromStoryId?.uuidString
                }
                submitted = !OiCreationAccess.canEdit(status: server.status, submitted: submitted)
            } else if record == nil, let parent = continuation?.availableParent(in: campusStore, for: accountID) {
                customization.connectedStoryID = parent
                customization.connectedStorySelectionEdited = true
                OiRecentStories.record(parent, owner: accountID)
            }
            restored = true; localError = nil; saveLabel = "이 계정의 기기 초안 자동 저장"
            if step == .photos {
                // Older drafts stored the photo editor as a step. Resume over the writing form.
                step = .story
            }
            if record == nil || record?.creationStep == OiCreationStep.consent.rawValue
                || record?.agreedConsentClauseIDs != consentState.savedIDs {
                scheduleSave()
            }
        } catch let error as OiDraftDiscardCleanupError {
            discardCleanupError = error.localizedDescription
        } catch is CancellationError {
        } catch {
            restorationError = error.localizedDescription; saveLabel = "기기 초안 복원 미완료"
        }
    }

    private func editFromReview(_ destination: OiCreationStep) {
        openingPhotosAfterReview = destination == .photos
        showingPreview = false
        customizationReady = false
        cardPlacementReady = false
        navigate(to: destination == .photos ? .story : destination)
    }

    private var reviewSheet: some View {
        let offersAIReview = remote.autoStoryModeration
        return OiStoryReview(draft: draft, customization: customization, savedCardPath: reusedCardPath,
            savedPortraitPath: customization.wardrobe == nil ? currentStory?.cucumberArtwork?.path(.portrait) : nil,
            donorName: remote.profile?.publicName ?? "",
            location: OiCreationStep.location.canContinue(draft: draft) ? completionLocation : nil,
            photos: editingPhotos, remote: remote, issues: reviewIssues,
            error: localError ?? remote.error ?? publicationAvailabilityMessage,
            canSubmit: canSubmit && publicationAvailabilityMessage == nil && !remote.isBusy && !saving, isSubmitting: publishing,
            offersAIReview: offersAIReview,
            onClose: { showingPreview = false },
            onEdit: editFromReview, onSubmit: { portrait, card in
                let reviewedCardPath = reusedCardPath
                Task {
                    await submitReview(portrait: portrait, card: card, reviewedCardPath: reviewedCardPath,
                                       authorizesAIReview: offersAIReview)
                }
            }) { photo, thumbnail in
                reviewPhoto(photo, allowsRetry: !thumbnail, contentMode: thumbnail ? .fill : .fit,
                            maximumPixelSize: thumbnail ? 512 : 1600)
            }
            .id(reusedCardPath)
    }

    private var reviewIssues: [OiStoryReviewIssue] {
        let inputIssues = OiCreationStep.reviewInputIssues(draft: draft, photoCount: editingPhotos.count)
        guard consentState.allRequiredClausesAreAgreed else {
            return [.init(step: .consent, message: "공개하려면 필수 약관에 모두 동의해 주세요.")] + inputIssues
        }
        return inputIssues
    }

    private var publicationAvailabilityMessage: String? {
        if !canWrite { return OiWritingGuidance.unavailable }
        if !remote.autoStoryModeration { return "지금은 자동검수를 사용할 수 없어요. 초안은 보존돼 있어요." }
        if !remote.canPublishDuplexCard {
            return "서버의 카드 양면 저장 업데이트가 필요해요. 내 카드와 초안은 보존돼 있어요."
        }
        if !remote.canPublishStoryCard {
            return "서버가 꾸민 카드의 공개를 지원할 때 다시 요청해 주세요. 내 카드와 초안은 저장돼 있어요."
        }
        if customization.wardrobe != nil && !remote.canPublishCucumberAppearance {
            return "서버가 꾸민 오이의 공개를 지원할 때 다시 요청해 주세요. 내 지도와 초안은 저장돼 있어요."
        }
        return nil
    }

    private func submitReview(portrait: Data?, card: OiStoryCardPublication?, reviewedCardPath: String?,
                              authorizesAIReview: Bool) async {
        guard !publishing, !remote.isBusy, !saving, canSubmit, publicationAvailabilityMessage == nil else { return }
        publishing = true
        localError = nil
        defer { publishing = false }
        let publication: OiCucumberPublication?
        do {
            if let look = customization.portraitLook {
                guard let portrait else { throw OiPhotoDataError.unreadable }
                publication = try OiCucumberPublication(look: look, portrait: portrait, seed: customization.seedSnapshot)
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
        let usesAIReview = remote.autoStoryModeration
        let receipt = await remote.submitStory(saved, cucumber: publication, card: card,
                                               agreesToAIReview: authorizesAIReview)
        if let receipt {
            draft = OiStoryDraft(story: receipt); localVersion += 1
            if usesAIReview {
                reviewedContentFingerprint = record().contentFingerprint
                guard await persist() else { return }
                showingPreview = false
                finish()
            } else {
                submitted = true
                _ = await persist()
                showingPreview = false
            }
        } else if usesAIReview, remote.moderationResult(for: saved)?.status == .rejected {
            reviewedContentFingerprint = record().contentFingerprint
            localVersion += 1
            _ = await persist()
        }
    }

    /// The chosen photos in a row above 사진 추가하기, in attachment order (first = cover).
    private var storyPhotoStrip: some View {
        HStack(spacing: 10) {
            ForEach(editingPhotos, id: \.orderKey) { photo in
                Color(white: 244 / 255)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay { reviewPhoto(photo, allowsRetry: false, contentMode: .fill) }
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                    .accessibilityLabel("선택한 사진")
            }
            ForEach(0..<max(0, OiCreationStep.storyPhotoLimit - editingPhotos.count), id: \.self) { _ in
                Color.clear.aspectRatio(1, contentMode: .fit)
            }
        }
        .accessibilityIdentifier("oi.story.photoStrip")
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
        canWrite && reviewIssues.isEmpty
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
    // Preserve the last reviewed card until the author edits its artwork.
    private var reusedCardPath: String? {
        var cardCustomization = customization
        cardCustomization.seedAppearance = nil
        cardCustomization.selectedSeedTop = nil
        cardCustomization.selectedSeedBottom = nil
        cardCustomization.seedSneakers = nil
        cardCustomization.selectedSeedSet = nil
        return cardCustomization == OiDraftCustomization() ? currentStory?.cardArtworkPath : nil
    }

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
        switch contentStep {
        case .consent, .photos, .location: EmptyView() // Presented separately above.
        case .story:
            VStack(alignment: .leading, spacing: 50) {
                OiStoryWritingStep(draft: $draft, focusedField: $focusedStoryField)
                OiStoryAttachmentSections(photoCount: editingPhotos.count,
                    latitude: draft.latitude, longitude: draft.longitude,
                    onPhotos: openStoryPhotos, onLocation: { endStoryEditing(); navigate(to: .location) },
                    connectedStory: connectedStory, onSelectDonor: selectDonor,
                    // A restored cloud draft may hide a non-public parent's ID. Keep
                    // an explicit clear action available without revealing that ID.
                    onClearDonor: customization.connectedStoryID != nil || (remote.supportsStoryContinuations && currentStory != nil) ? {
                        customization.connectedStoryID = nil; customization.connectedStorySelectionEdited = true
                    } : nil,
                    photoStrip: AnyView(storyPhotoStrip))
            }
        case .cucumber:
            OiCucumberCustomizationStep(customization: $customization, cucumberName: $draft.cucumberName,
                previewMode: cucumberPreviewMode,
                // Figma: 완료 goes straight to STEP 4 card customization (`5919:12077`, #377).
                canContinue: true, isFinished: false, onContinue: advance,
                onPhotoEditingChanged: { wardrobePhotoEditing = $0 })
        case .card:
            OiCardCustomizationStep(draft: $draft, customization: $customization,
                donorName: remote.profile?.publicName ?? "",
                academicAuthor: OiPostcardAuthor.academic(department: remote.profile?.department, year: remote.profile?.admissionYear),
                storyPhotos: editingPhotos, loadStoryPhoto: cardStoryPhoto,
                isFinished: false, isCompleting: completingCard, onContinue: { Task { await completeCard() } })

        }
    }

    private var recentDonationStories: [CampusStory] {
        guard let owner = remote.account?.id, let campusStore else { return [] }
        return OiRecentStories.pickerStories(owner: owner) { id in
            guard let story = campusStore.story(id),
                  !(story.authorID.map { OiContentSafetyStore.shared.isBlocked($0) } ?? false) else { return nil }
            return story
        }
    }

    /// The story this donation continues from, while it is still public.
    private var connectedStory: CampusStory? {
        guard let id = customization.connectedStoryID, let story = campusStore?.story(id),
              !(story.authorID.map { OiContentSafetyStore.shared.isBlocked($0) } ?? false) else { return nil }
        return story
    }

    /// Keep the saved selection until a new choice is confirmed; cancel must preserve it.
    private func selectDonor() {
        endStoryEditing()
        showingDonorPicker = true
    }

    private func cardStoryPhoto(_ photo: OiEditingPhoto) async throws -> Data {
        guard let owner, remote.account?.id == owner else { throw OiServiceError.accountChanged }
        let data: Data
        switch photo {
        case .local(let id): data = try await remote.localPhoto(id: id, owner: owner)
        case .uploaded(let path): data = try await remote.storyPhotoData(path)
        }
        try Task.checkCancellation()
        guard remote.account?.id == owner else { throw OiServiceError.accountChanged }
        return try OiPhotoProcessor.prepare(data)
    }

    private func supplementaryContent(_ screen: SupplementaryScreen) -> some View {
        NavigationStack {
            switch screen {
            case .completion:
                completionContent(isPreview: true)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("작성으로 돌아가기") { supplementaryScreen = nil }
                        }
                    }
            }
        }
    }

    @ViewBuilder private var completion: some View {
        if currentStory?.status == "published" {
            VStack(spacing: 20) {
                Text("이야기가 등록됐어요").font(CampusStyle.semibold(20)).accessibilityAddTraits(.isHeader)
                OiCreationNextButton(title: "확인", action: finish)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color("OiLight"))
        } else {
            completionContent(isPreview: false)
        }
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
                    if !isPreview, let story = currentStory, story.status != "pending" {
                        Text(story.status.oiStatusTitle).font(CampusStyle.semibold(16))
                    } else {
                        Text(isPreview ? "접수 후에는 이렇게 보여요" : "공개 검토 요청이 접수됐어요").font(CampusStyle.semibold(16))
                        Text("승인되면 이야기와 사진, 꾸민 오이와 카드를 다른 사람도 볼 수 있어요.")
                            .font(CampusStyle.body(14)).foregroundStyle(.secondary)
                    }
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
                    if !isPreview {
                        if let onReopen {
                            Button(currentStory?.status == "pending" ? "초안으로 되돌리기" : "수정 시작", action: onReopen)
                                .accessibilityIdentifier("oi.creation.reopen")
                        }
                        if let onDeleteSubmittedStory {
                            Button("이야기 삭제", role: .destructive, action: onDeleteSubmittedStory)
                        }
                    }
                    OiCreationNextButton(title: isPreview ? "작성으로 돌아가기" : onReopen == nil ? "이야기 목록으로 돌아가기" : "돌아가기") {
                        if isPreview { supplementaryScreen = nil } else { finish() }
                    }
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 30))
                    .shadow(color: Color("OiDark").opacity(0.4), radius: 5)
            }.padding(.horizontal, 20).padding(.top, 42).padding(.bottom, 24)
        }.background(Color("OiLight"))
    }

    private var navigationTitle: String {
        if submitted { return currentStory?.status == "published" ? "" : "접수 완료" }
        return step.title
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
        let close = { if let onFinish { onFinish() } else { dismiss() } }
        guard showingCardCompletion else { close(); return }
        // The completion screen sits on top of this editor. Pop both in one animation back to the screen that
        // opened the editor, then let that screen update its own state (#473).
        if let navigation = completionNavigation.navigation, navigation.viewControllers.count >= 3 {
            let target = navigation.viewControllers[navigation.viewControllers.count - 3]
            // The system pop takes about 0.35s; run it a little slower (about 0.47s) for this long leave.
            let slowed = !reduceMotion
            if slowed { navigation.view.layer.speed = 0.75 }
            navigation.popToViewController(target, animated: !reduceMotion)
            if slowed {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { [weak navigation] in navigation?.view.layer.speed = 1 }
            }
            if let onFinish {
                if let coordinator = navigation.transitionCoordinator {
                    coordinator.animate(alongsideTransition: nil) { _ in onFinish() }
                } else { onFinish() }
            }
            return
        }
        // Fallback: drop the completion screen first, then close the editor.
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) { showingCardCompletion = false }
        DispatchQueue.main.async(execute: close)
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
            photos[index] = newID
            if photoCheckpoint != nil { return true }
            localVersion += 1
            return await persist()
        } catch { localError = error.localizedDescription; return false }
    }

    private func record() -> OiLocalDraft {
        OiLocalDraft(draft: draft, photos: photos, uploadedPhotos: Array(uploadedPhotos), version: localVersion, submitted: submitted, creationStep: step.rawValue, customization: customization, removedMediaPaths: removedMediaPaths, removedPhotoIDs: removedPhotoIDs, agreedConsentClauseIDs: consentState.savedIDs, personalPlacement: personalPlacement, photoOrder: photoOrder, reviewedContentFingerprint: reviewedContentFingerprint)
    }

    private func scheduleSave() {
        guard restored, !submitted, photoCheckpoint == nil, !preparingPhoto, !placing, !publishing, !replacingServerDraft,
              let owner else { return }
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
        guard !saving, canSubmit, let owner else { return nil }
        saving = true
        defer { saving = false }
        await pendingSave?.value
        var snapshot = record()
        defer {
            if remote.account?.id == owner {
                draft = snapshot.draft
                localVersion = snapshot.version
                uploadedPhotos = Set(snapshot.uploadedPhotos)
                removedMediaPaths = snapshot.removedMediaPaths ?? []
                removedPhotoIDs = snapshot.removedPhotoIDs ?? []
            }
        }
        do {
            return try await remote.saveDraftForReview(&snapshot, owner: owner)
        } catch {
            localError = error.localizedDescription
            return nil
        }
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
    var onPhotoLoaded: (() -> Void)? = nil
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
                            .onAppear { if Request(path: path, attempt: retryCount) == request { onPhotoLoaded?() } }
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
