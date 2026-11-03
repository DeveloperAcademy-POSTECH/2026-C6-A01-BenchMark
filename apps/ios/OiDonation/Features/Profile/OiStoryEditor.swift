// Created by 이돈혁

import ImageIO
import PhotosUI
import SwiftUI

struct OiStoryEditor: View {
    let remote: OiRemoteStore
    var onFinish: (() -> Void)?
    @State private var draft: OiStoryDraft
    @State private var owner: UUID?
    @State private var photos: [UUID] = []
    @State private var uploadedPhotos: Set<UUID> = []
    @State private var localVersion = 0
    @State private var restored = false
    @State private var submitted = false
    @State private var locationRequest: OiLocationPickerRequest?
    @State private var photoSelections: [PhotosPickerItem] = []
    @State private var step: OiCreationStep = .story
    @State private var customization = OiDraftCustomization()
    @State private var removedMediaPaths: [String] = []
    @State private var saving = false
    @State private var localError: String?
    @State private var saveLabel = "기기 저장 준비 중"
    @State private var preparingPhoto = false
    @State private var publishing = false
    @State private var showingPreview = false
    @State private var choosingExit = false
    @State private var pendingSave: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(remote: OiRemoteStore, story: OiLiveStory? = nil, localID: UUID? = nil, onFinish: (() -> Void)? = nil) {
        self.remote = remote
        self.onFinish = onFinish
        var value: OiStoryDraft
        if let story { value = OiStoryDraft(story: story) }
        else { value = OiStoryDraft() }
        if let localID { value.id = localID }
        _draft = State(initialValue: value)
    }

    var body: some View {
        presentedContent
        .task {
            guard owner == nil, let accountID = remote.account?.id else { return }
            owner = accountID
            do {
                if let record = try await remote.localDraft(id: draft.id, owner: accountID) {
                    draft = record.draft; photos = record.photos; uploadedPhotos = Set(record.uploadedPhotos)
                    localVersion = record.version; submitted = record.submitted
                    step = record.creationStep.flatMap(OiCreationStep.init(rawValue:)) ?? .story
                    customization = record.customization ?? OiDraftCustomization()
                    removedMediaPaths = record.removedMediaPaths ?? []
                }
                if let server = remote.ownStories.first(where: { $0.id == draft.id }) {
                    submitted = !OiCreationAccess.canEdit(status: server.status, submitted: submitted)
                }
                if draft.grantId == nil { draft.grantId = availableGrants.first?.id }
                restored = true; saveLabel = "이 계정의 기기 초안 자동 저장"
            } catch { localError = error.localizedDescription }
        }
        .onChange(of: draft) { _, _ in scheduleSave() }
        .onChange(of: photos) { _, _ in scheduleSave() }
        .onChange(of: uploadedPhotos) { _, _ in scheduleSave() }
        .onChange(of: step) { _, _ in scheduleSave() }
        .onChange(of: customization) { _, _ in scheduleSave() }
        .onChange(of: removedMediaPaths) { _, _ in scheduleSave() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { scheduleSave() } }
        .onDisappear { if restored { scheduleSave() } }
        .task(id: photoSelections) {
            let selections = photoSelections
            guard !selections.isEmpty, let owner else { return }
            preparingPhoto = true
            defer { preparingPhoto = false; photoSelections = [] }
            var failures = 0
            for selection in selections {
                do {
                    guard let data = try await selection.loadTransferable(type: Data.self) else { throw OiServiceError.invalidInput }
                    let jpeg = try OiPhotoProcessor.prepare(data)
                    try Task.checkCancellation()
                    let id = UUID()
                    try await remote.saveLocalPhoto(jpeg, id: id, owner: owner)
                    try Task.checkCancellation()
                    guard remote.account?.id == owner else { throw OiServiceError.accountChanged }
                    photos.append(id); localVersion += 1; _ = await persist()
                } catch is CancellationError { return }
                catch { failures += 1 }
            }
            if failures > 0 { localError = "\(failures)장의 사진을 추가하지 못했어요. 기기에서 열 수 있는 사진인지 확인한 뒤 다시 선택해 주세요." }
        }
    }

    private var presentedContent: some View {
        VStack(spacing: 0) {
            if submitted {
                completion
            } else {
                if step != .photos { OiCreationProgressHeader(step: step.progress).padding(.horizontal, 20).padding(.vertical, 8) }
                ScrollViewReader { scroll in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            Color.clear.frame(height: 1).id("creation.top")
                            editorStatus
                            stepContent
                        }.padding(.horizontal, 20).padding(.bottom, 24)
                    }.scrollDismissesKeyboard(.interactively)
                        .onChange(of: step) { _, _ in scroll.scrollTo("creation.top", anchor: .top) }
                }
                OiCreationNextButton(title: step == .card ? "미리보기·검토 요청" : "다음", enabled: canContinue) {
                    if let next = step.next { step = next } else { showingPreview = true }
                }.accessibilityIdentifier("oi.creation.next").padding(.horizontal, 20).padding(.vertical, 10)
            }
        }
        .background(step == .photos ? Color(white: 0.14) : Color(.systemBackground))
        .preferredColorScheme(step == .photos ? .dark : .light)
        .environment(\.colorScheme, step == .photos ? .dark : .light)
        .toolbarColorScheme(step == .photos ? .dark : .light, for: .navigationBar)
        .toolbarBackground(step == .photos ? Color(white: 0.14) : Color(.systemBackground), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .disabled(remote.isBusy || preparingPhoto || publishing || saving || !restored)
        .navigationTitle(submitted ? "접수 완료" : step.title).navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    if submitted { finish() }
                    else if let previous = step.previous { step = previous }
                    else { choosingExit = true }
                } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("이전 단계").disabled(remote.isBusy || preparingPhoto || publishing || saving)
            }
            ToolbarItem(placement: .topBarTrailing) {
                if !submitted { Button("나가기") { choosingExit = true }.disabled(remote.isBusy || preparingPhoto || publishing || saving) }
            }
        }
        .interactiveDismissDisabled()
        .confirmationDialog("현재 입력을 어떻게 할까요?", isPresented: $choosingExit, titleVisibility: .visible) {
            Button("기기에 보관하고 나가기") { Task { if await persist() { dismiss() } } }
            Button("기기 보관본·미저장 수정 버리기", role: .destructive) {
                Task {
                    guard let owner else { return }
                    restored = false
                    await pendingSave?.value
                    do { try await remote.discardLocalDraft(id: draft.id, owner: owner); dismiss() }
                    catch { restored = true; localError = error.localizedDescription }
                }
            }
            Button("계속 작성", role: .cancel) {}
        } message: { Text("버리기는 이 기기의 초안과 사진 복사본만 삭제합니다. 서버에 저장된 이야기는 삭제하지 않습니다.") }
        .fullScreenCover(item: $locationRequest) { request in
            OiLocationPicker(latitude: $draft.latitude, longitude: $draft.longitude, focusPlaceID: request.focusPlaceID)
        }
        .sheet(isPresented: $showingPreview) { reviewSheet }
    }

    private var reviewSheet: some View {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        MYCardArtwork(card: publicCard).frame(height: 280).frame(maxWidth: .infinity)
                        Text("공개 예정 카드 프리셋").font(.caption).foregroundStyle(.secondary)
                        Text("커스텀 색상과 의상 설정은 이 기기의 미리보기에만 보관됩니다.").font(.caption)
                        Text(draft.title).font(.title2.bold())
                        Text(draft.body)
                        Text("\(draft.theme) · \(draft.emotion) · \(draft.cucumberName)")
                        if let latitude = draft.latitude, let longitude = draft.longitude { Text("\(latitude), \(longitude)").font(.caption) }
                        ForEach(editingPhotos) { photo in reviewPhoto(photo).frame(height: 180) }
                        if let error = localError ?? remote.error { Text(error).foregroundStyle(.red) }
                        OiConnectionStatus(remote: remote)
                        Button("이 내용으로 저장 후 검토 요청") {
                            Task {
                                publishing = true
                                defer { publishing = false }
                                if let saved = await saveCurrent(), let receipt = await remote.submitStory(saved) {
                                    draft = OiStoryDraft(story: receipt); submitted = true; localVersion += 1
                                    _ = await persist(); showingPreview = false
                                }
                            }
                        }.disabled(remote.isBusy || publishing || saving || !draft.valid || !hasApproval).accessibilityIdentifier("oi.story.confirmSubmit")
                    }.padding(20)
                }.navigationTitle("공개 검토 전 확인").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("수정으로 돌아가기") { showingPreview = false }.disabled(publishing) } }
                    .interactiveDismissDisabled(publishing)
            }
    }

    @ViewBuilder private func reviewPhoto(_ photo: OiEditingPhoto) -> some View {
        switch photo {
        case .local(let id):
            if let owner { OiLocalPhoto(remote: remote, owner: owner, id: id) }
        case .uploaded(let path):
            OiStoryMediaImage(path: path) { try await remote.mediaURL(bucket: "oi-story-media", path: $0) }
        }
    }

    private var availableGrants: [OiWritingGrant] { remote.grants.filter { $0.revokedAt == nil } }
    private var hasApproval: Bool { availableGrants.contains { $0.id == draft.grantId } }
    private var canContinue: Bool { hasApproval && step.canContinue(draft: draft) }
    private var editingPhotos: [OiEditingPhoto] {
        OiEditingPhoto.ordered(local: photos, remote: remote.mediaPaths(storyID: draft.id), removed: removedMediaPaths)
    }
    private var publicCard: MYCard {
        MYCard(id: draft.id.uuidString, title: draft.cucumberName, image: draft.cucumberAsset, school: .postech, order: 0,
               body: draft.body, donor: remote.profile?.nickname ?? "농부", date: "", appearance: draft.cardAsset)
    }

    @ViewBuilder private var editorStatus: some View {
        OiConnectionStatus(remote: remote)
        if let error = localError ?? remote.error { Text(error).font(.footnote).foregroundStyle(.red) }
        Text(saveLabel).font(.caption2).foregroundStyle(.secondary).accessibilityIdentifier("oi.draft.saveState")
        if !hasApproval { Text("유효한 작성 승인이 필요해요. 계정에서 승인 상태를 확인해 주세요.").font(.footnote).foregroundStyle(.orange) }
        if let saved = remote.ownStories.first(where: { $0.id == draft.id }), saved.revision != draft.revision {
            VStack(alignment: .leading) {
                Text("서버 초안이 변경됐어요. 현재 입력은 기기에 보관합니다.").font(.footnote)
                Button("서버 초안 다시 불러오기") {
                    draft = OiStoryDraft(story: saved)
                    submitted = !OiCreationAccess.canEdit(status: saved.status, submitted: false)
                }
            }
        }
    }

    @ViewBuilder private var stepContent: some View {
        switch step {
        case .story: OiStoryWritingStep(draft: $draft, grants: availableGrants)
        case .photos:
            OiStoryPhotoStep(items: editingPhotos,
                uploadedPhotos: uploadedPhotos, selections: $photoSelections,
                edit: { id, edit in Task { await editPhoto(id, operation: edit) } }, remove: removePhoto, photo: reviewPhoto)
        case .location:
            OiStoryLocationStep(draft: $draft, regions: remote.regions.filter { $0.schoolId == "postech" }) { placeID in
                locationRequest = OiLocationPickerRequest(focusPlaceID: placeID)
            }
        case .cucumber: OiCucumberCustomizationStep(draft: $draft, customization: $customization, assets: remote.assets)
        case .card:
            OiCardCustomizationStep(draft: $draft, customization: $customization, assets: remote.assets)
            Button("초안 저장·사진 업로드") { Task { _ = await saveCurrent() } }
                .disabled(!draft.valid || !hasApproval).accessibilityIdentifier("oi.story.save")
        }
    }

    private var completion: some View {
        ScrollView {
            VStack(spacing: 22) {
                MYCardArtwork(card: publicCard).frame(height: 360)
                Text(draft.cucumberName).font(CampusStyle.semibold(28))
                Text("이야기 검토 요청이 접수됐어요").font(.headline)
                Text("운영자가 공개 승인하면 캠퍼스 지도와 현장 AR에서 볼 수 있어요.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                OiCreationNextButton(title: "이야기 목록으로 돌아가기", action: finish)
            }.padding(24)
        }.background(Color("OiLight"))
    }

    private func finish() {
        if let onFinish { onFinish() } else { dismiss() }
    }

    private func removePhoto(_ item: OiEditingPhoto) {
        switch item {
        case .local(let id):
            if uploadedPhotos.contains(id) {
                removedMediaPaths += remote.mediaPaths(storyID: draft.id).filter { $0.contains(id.uuidString.lowercased()) }
            }
            photos.removeAll { $0 == id }; uploadedPhotos.remove(id)
        case .uploaded(let path): removedMediaPaths.append(path)
        }
        scheduleSave()
    }

    private func editPhoto(_ id: UUID, operation: OiPhotoEdit) async {
        guard let owner, !uploadedPhotos.contains(id), !preparingPhoto, !saving, !publishing else { return }
        preparingPhoto = true
        defer { preparingPhoto = false }
        do {
            let data = try await remote.localPhoto(id: id, owner: owner)
            let jpeg = try OiPhotoProcessor.edit(data, operation: operation)
            let newID = UUID()
            try await remote.saveLocalPhoto(jpeg, id: newID, owner: owner)
            guard remote.account?.id == owner, let index = photos.firstIndex(of: id) else { throw OiServiceError.accountChanged }
            photos[index] = newID; localVersion += 1; _ = await persist()
        } catch { localError = error.localizedDescription }
    }

    private func record() -> OiLocalDraft {
        OiLocalDraft(draft: draft, photos: photos, uploadedPhotos: Array(uploadedPhotos), version: localVersion, submitted: submitted, creationStep: step.rawValue, customization: customization, removedMediaPaths: removedMediaPaths)
    }

    private func scheduleSave() {
        guard restored, let owner else { return }
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
        guard !saving, hasApproval, OiCreationStep.allCases.allSatisfy({ $0.canContinue(draft: draft) }) else { return nil }
        saving = true
        defer { saving = false }
        guard let owner, await persist(), var current = await remote.save(draft) else { return nil }
        draft = OiStoryDraft(story: current); localVersion += 1
        guard await persist() else { return nil }
        for id in photos where !uploadedPhotos.contains(id) {
            do {
                let data = try await remote.localPhoto(id: id, owner: owner)
                guard let updated = await remote.uploadStoryImage(data, photoID: id, story: current) else { return nil }
                current = updated; uploadedPhotos.insert(id); draft.revision = updated.revision; localVersion += 1
                guard await persist() else { return nil }
            } catch { localError = error.localizedDescription; return nil }
        }
        if !removedMediaPaths.isEmpty {
            let paths = remote.mediaPaths(storyID: draft.id).filter { !removedMediaPaths.contains($0) }
            guard let updated = await remote.setStoryMedia(paths, story: current) else { return nil }
            current = updated; draft.revision = updated.revision; removedMediaPaths = []; localVersion += 1
            guard await persist() else { return nil }
        }
        return current
    }
}

struct OiLocalPhoto: View {
    let remote: OiRemoteStore
    let owner: UUID
    let id: UUID
    @State private var image: UIImage?
    @State private var error: String?

    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else if let error { Text(error).font(.caption) } else { ProgressView() }
        }.task(id: id) {
            do {
                let data = try await remote.localPhoto(id: id, owner: owner)
                guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 512] as CFDictionary) else { throw OiServiceError.invalidInput }
                try Task.checkCancellation()
                guard remote.account?.id == owner else { throw OiServiceError.accountChanged }
                image = UIImage(cgImage: thumbnail)
            } catch { self.error = error.localizedDescription }
        }
    }
}


struct OiStoryMediaImage: View {
    let path: String
    let loadURL: (String) async throws -> URL
    @State private var url: URL?
    @State private var error: String?

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFit() }
                    else if phase.error != nil { Text("사진을 불러오지 못했어요.").font(.caption) }
                    else { ProgressView() }
                }
            } else if let error { Text(error).font(.caption).foregroundStyle(.secondary) }
            else { ProgressView() }
        }
        .accessibilityLabel("이야기에 첨부된 사진")
        .task(id: path) {
            do { url = try await loadURL(path); error = nil }
            catch { self.error = error.localizedDescription }
        }
    }
}
