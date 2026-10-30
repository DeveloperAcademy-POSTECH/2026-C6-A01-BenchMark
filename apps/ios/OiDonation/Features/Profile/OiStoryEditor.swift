// Created by 이돈혁

import ImageIO
import PhotosUI
import SwiftUI

struct OiStoryEditor: View {
    let remote: OiRemoteStore
    @State private var draft: OiStoryDraft
    @State private var owner: UUID?
    @State private var photos: [UUID] = []
    @State private var uploadedPhotos: Set<UUID> = []
    @State private var localVersion = 0
    @State private var restored = false
    @State private var submitted = false
    @State private var selectingLocation = false
    @State private var photo: PhotosPickerItem?
    @State private var localError: String?
    @State private var saveLabel = "기기 저장 준비 중"
    @State private var preparingPhoto = false
    @State private var publishing = false
    @State private var showingPreview = false
    @State private var choosingExit = false
    @State private var pendingSave: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(remote: OiRemoteStore, story: OiLiveStory? = nil, localID: UUID? = nil) {
        self.remote = remote
        var value: OiStoryDraft
        if let story { value = OiStoryDraft(story: story) }
        else { value = OiStoryDraft() }
        if let localID { value.id = localID }
        _draft = State(initialValue: value)
    }

    var body: some View {
        Form {
            OiConnectionStatus(remote: remote)
            if let error = localError ?? remote.error { Text(error).foregroundStyle(.red) }
            Text(saveLabel).font(.caption).accessibilityIdentifier("oi.draft.saveState")
            if let saved = remote.ownStories.first(where: { $0.id == draft.id }), saved.revision != draft.revision {
                Section("서버의 초안이 변경됐어요") {
                    Text("현재 입력은 기기에 보관합니다. 서버 초안을 대신 불러오려면 아래 버튼을 눌러주세요.").font(.footnote)
                    Button("서버 초안 다시 불러오기") { draft = OiStoryDraft(story: saved); submitted = false }
                }
            }
            Section("작성 승인") {
                Picker("사용할 승인", selection: $draft.grantId) {
                    Text("선택해 주세요").tag(Optional<UUID>.none)
                    ForEach(remote.grants.filter { $0.revokedAt == nil }) { permission in
                        Text("승인 \(permission.id.uuidString.prefix(8)) · 최대 \(permission.storyLimit)개").tag(Optional(permission.id))
                    }
                }.disabled(draft.revision > 0)
            }
            Section("테마 선택 · 감정 선택") {
                TextField("테마", text: $draft.theme)
                TextField("감정", text: $draft.emotion)
                Text("추천 목록은 준비 중입니다. 지금은 직접 입력해 주세요.").font(.caption).foregroundStyle(.secondary)
            }
            Section("제목 입력 · 내용 입력") {
                TextField("이야기 제목", text: $draft.title).accessibilityIdentifier("oi.draft.title")
                TextEditor(text: $draft.body).frame(minHeight: 150).accessibilityLabel("이야기 내용")
            }
            Section("오이 커스텀") {
                TextField("오이 이름 입력", text: $draft.cucumberName)
                Image(draft.cucumberAsset).resizable().scaledToFit().frame(height: 180).frame(maxWidth: .infinity)
                Picker("준비된 오이 프리셋", selection: $draft.cucumberAsset) {
                    ForEach(remote.assets.filter { $0.kind == "cucumber" }) { asset in
                        Text(asset.name).tag(asset.id)
                    }
                }
                Text("포즈·상의·하의·모자별 교체는 자산 규격이 확정되면 연결합니다.").font(.caption).foregroundStyle(.secondary)
            }
            Section("카드 커스텀") {
                MYCardArtwork(card: MYCard(id: draft.id.uuidString, title: draft.cucumberName, image: draft.cucumberAsset, school: .postech, order: 0, body: draft.body, donor: remote.profile?.nickname ?? "농부", date: "", appearance: draft.cardAsset)).frame(height: 220)
                Picker("준비된 카드 프리셋", selection: $draft.cardAsset) {
                    ForEach(remote.assets.filter { $0.kind == "card" }) { asset in Text(asset.name).tag(asset.id) }
                }
                Text("개별 패턴·테두리·크기 편집은 준비 중입니다. 카드에는 현재 작성한 이야기 내용이 표시됩니다.").font(.caption).foregroundStyle(.secondary)
            }
            Section("위치 설정") {
                Picker("캠퍼스 구역", selection: $draft.regionId) {
                    ForEach(remote.regions) { region in Text(region.name).tag(region.id) }
                }
                Button("캠퍼스 지도에서 위치 선택") { selectingLocation = true }
                if let latitude = draft.latitude, let longitude = draft.longitude {
                    Text("\(latitude.formatted(.number.precision(.fractionLength(6)))), \(longitude.formatted(.number.precision(.fractionLength(6))))").font(.caption)
                }
                Text("건물 안과 캠퍼스 밖의 위치는 서버에서 거절합니다. 지도 좌표는 실제 현장 AR 정밀도를 보장하지 않습니다.").font(.caption).foregroundStyle(.secondary)
            }
            Section("사진 선택 · 기기에 보관") {
                PhotosPicker("사진 추가", selection: $photo, matching: .images)
                if let owner {
                    ForEach(photos, id: \.self) { id in
                        VStack {
                            OiLocalPhoto(remote: remote, owner: owner, id: id).frame(height: 140)
                            Text(uploadedPhotos.contains(id) ? "서버 첨부 확인됨" : "기기에 보관 · 업로드 대기").font(.caption)
                        }
                    }
                }
                ForEach(remote.mediaPaths(storyID: draft.id), id: \.self) { path in
                    OiStoryMediaImage(path: path) { path in try await remote.mediaURL(bucket: "oi-story-media", path: path) }.frame(height: 180)
                }
            }
            Section {
                Button("초안 저장·사진 업로드") { Task { _ = await saveCurrent() } }.disabled(!draft.valid || submitted)
                    .accessibilityIdentifier("oi.story.save")
                Button("현재 내용 미리보기·검토 요청") { showingPreview = true }.disabled(!draft.valid || submitted)
                    .accessibilityIdentifier("oi.story.submit")
                if submitted { Text("공개 검토 요청이 접수됐습니다. 기기의 보관본도 유지합니다.").foregroundStyle(.secondary) }
            }
            Section {
                Text("내부 검증용입니다. 최종 약관·증빙 운영 정책과 개별 꾸미기 자산은 아직 미정이며, 코인 기능은 사용하지 않습니다.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .disabled(remote.isBusy || preparingPhoto || publishing || !restored)
        .navigationTitle("이야기와 오이 만들기").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("뒤로") { choosingExit = true }.disabled(remote.isBusy || preparingPhoto || publishing)
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
        .sheet(isPresented: $selectingLocation) { OiLocationPicker(latitude: $draft.latitude, longitude: $draft.longitude) }
        .sheet(isPresented: $showingPreview) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(draft.title).font(.title2.bold())
                        Text(draft.body)
                        Text("\(draft.theme) · \(draft.emotion) · \(draft.cucumberName)")
                        if let latitude = draft.latitude, let longitude = draft.longitude { Text("\(latitude), \(longitude)").font(.caption) }
                        if let owner { ForEach(photos, id: \.self) { OiLocalPhoto(remote: remote, owner: owner, id: $0).frame(height: 180) } }
                        ForEach(remote.mediaPaths(storyID: draft.id).filter { path in
                            !photos.contains { path.contains($0.uuidString.lowercased()) }
                        }, id: \.self) { path in
                            OiStoryMediaImage(path: path) { path in try await remote.mediaURL(bucket: "oi-story-media", path: path) }.frame(height: 180)
                        }
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
                        }.disabled(remote.isBusy || publishing).accessibilityIdentifier("oi.story.confirmSubmit")
                    }.padding(20)
                }.navigationTitle("공개 검토 전 확인").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("수정으로 돌아가기") { showingPreview = false }.disabled(publishing) } }
                    .interactiveDismissDisabled(publishing)
            }
        }
        .task {
            guard owner == nil, let accountID = remote.account?.id else { return }
            owner = accountID
            do {
                if let record = try await remote.localDraft(id: draft.id, owner: accountID) {
                    draft = record.draft; photos = record.photos; uploadedPhotos = Set(record.uploadedPhotos)
                    localVersion = record.version; submitted = record.submitted
                }
                restored = true; saveLabel = "이 계정의 기기 초안 자동 저장"
            } catch { localError = error.localizedDescription }
        }
        .onChange(of: draft) { _, _ in scheduleSave() }
        .onChange(of: photos) { _, _ in scheduleSave() }
        .onChange(of: uploadedPhotos) { _, _ in scheduleSave() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { scheduleSave() } }
        .onDisappear { if restored { scheduleSave() } }
        .task(id: photo) {
            guard let photo, let owner else { return }
            preparingPhoto = true
            defer { preparingPhoto = false }
            do {
                guard let data = try await photo.loadTransferable(type: Data.self), data.count <= 40_000_000,
                      let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 2048] as CFDictionary),
                      let jpeg = UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.85) else { throw OiServiceError.invalidInput }
                let id = UUID()
                try await remote.saveLocalPhoto(jpeg, id: id, owner: owner)
                try Task.checkCancellation()
                guard remote.account?.id == owner else { throw OiServiceError.accountChanged }
                photos.append(id); localVersion += 1; _ = await persist()
            } catch { localError = error.localizedDescription }
        }
    }

    private func record() -> OiLocalDraft {
        OiLocalDraft(draft: draft, photos: photos, uploadedPhotos: Array(uploadedPhotos), version: localVersion, submitted: submitted)
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
        return current
    }
}

private struct OiLocalPhoto: View {
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

private struct OiLocationPicker: View {
    @Binding var latitude: Double?
    @Binding var longitude: Double?
    @State private var scene = CampusExploreScene()
    @State private var isOnScreen = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            CampusMapSurface(scene: scene)
                .ignoresSafeArea(.container, edges: .top)
                .safeAreaInset(edge: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        if let error = scene.error ?? scene.placementError {
                            Text(error).foregroundStyle(.red)
                            Button("다시 시도") { Task { await prepare() } }
                        } else if scene.isLoading || scene.placementLoading {
                            ProgressView("캠퍼스 지도 준비 중")
                        }
                        Text(scene.placementMessage).font(.footnote)
                        CampusPlacementTools(scene: scene)
                    }.padding().background(.regularMaterial)
                }
                .navigationTitle("위치 설정").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("선택 완료") {
                            guard let point = scene.draftPoint, let data = scene.data,
                                  data.placementError(at: point) == nil else { return }
                            let coordinate = data.coordinate(point)
                            latitude = coordinate.latitude; longitude = coordinate.longitude
                            dismiss()
                        }.disabled(scene.draftPoint == nil || !scene.placementReady)
                    }
                }
        }
        .task { await prepare() }
        .onAppear { isOnScreen = true; scene.setVisible(scenePhase == .active) }
        .onDisappear { isOnScreen = false; scene.endPlacement(); scene.setVisible(false) }
        .onChange(of: scenePhase) { _, phase in scene.setVisible(isOnScreen && phase == .active) }
    }

    private func prepare() async {
        await scene.load()
        guard !Task.isCancelled else { return }
        await scene.preparePlacements()
        guard !Task.isCancelled, scene.placementReady else { return }
        let existing: CampusPlacement?
        if let latitude, let longitude {
            existing = CampusPlacement(storyID: "draft-location", latitude: latitude, longitude: longitude)
        } else { existing = nil }
        scene.beginPlacement(editing: existing)
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
