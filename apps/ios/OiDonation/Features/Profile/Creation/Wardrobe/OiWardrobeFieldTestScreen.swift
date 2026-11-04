import SwiftUI

/// Independent local map: no published-story IDs, account approval or server writes.
struct OiWardrobeFieldTestScreen: View {
    var initialLook: OiWardrobeLook? = nil
    var initialName = "나의 오이"
    @State private var scene = CampusExploreScene()
    @State private var look: OiWardrobeLook?
    @State private var name = "나의 오이"
    @State private var heading = 0.0
    @State private var saved: OiWardrobeFieldTrial?
    @State private var error: String?
    @State private var preparing = true
    @State private var onScreen = false
    @State private var showPlaces = false
    @State private var showDelete = false
    @State private var showReplace = false
    @State private var arTrial: OiWardrobeFieldTrial?
    @Environment(\.scenePhase) private var phase
    private let repository = OiWardrobeFieldTrialRepository()

    private var matchesSaved: Bool {
        guard let saved, let point = scene.draftPoint, let data = scene.data else { return false }
        let coordinate = data.coordinate(point)
        return saved.look == look && saved.name == name && saved.heading == heading &&
            abs(saved.latitude - coordinate.latitude) < 0.0000001 && abs(saved.longitude - coordinate.longitude) < 0.0000001
    }
    var body: some View {
        VStack(spacing: 0) {
            if look != nil && arTrial == nil {
                CampusMapSurface(scene: scene).frame(minHeight: 220)
                    .accessibilityIdentifier("wardrobe.field.map")
            } else {
                ContentUnavailableView("저장한 테스트가 없어요", systemImage: "mappin.and.ellipse",
                    description: Text("오이 커스텀에서 ‘캠퍼스에 테스트 배치’를 눌러 시작하세요."))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("이 iPhone 전용 · 150cm · 공개되지 않아요").font(.caption).foregroundStyle(.secondary)
                    if preparing { ProgressView("캠퍼스와 의상 준비 중") }
                    if let message = error ?? scene.error ?? scene.placementError {
                        Text(message).foregroundStyle(.red).font(.footnote)
                        Button("다시 시도") { Task { await prepare() } }
                    }
                    if look != nil {
                        HStack {
                            Text(name).font(.headline)
                            Spacer()
                            Button("오이 보기") { scene.inspectWardrobePlacement() }
                                .disabled(scene.draftPoint == nil)
                                .accessibilityIdentifier("wardrobe.field.inspect")
                            Button("장소 찾기", systemImage: "magnifyingglass") { showPlaces = true }
                                .disabled(!scene.placementReady)
                        }
                        Text(scene.placementMessage).font(.caption).monospacedDigit()
                        CampusPlacementTools(scene: scene)
                        HStack {
                            Text("방향 \(Int(heading))°").font(.caption).frame(width: 70)
                            Slider(value: $heading, in: 0...359, step: 1).accessibilityLabel("테스트 오이 방향")
                        }.disabled(!scene.placementReady)
                        HStack {
                            Button(saved == nil ? "테스트 배치 저장" : "이 배치로 저장") {
                                if saved != nil && !matchesSaved { showReplace = true } else { save() }
                            }.buttonStyle(.borderedProminent).disabled(scene.draftPoint == nil || preparing || error != nil)
                                .accessibilityIdentifier("wardrobe.field.save")
                            Button("현장 AR로 보기") { if matchesSaved { arTrial = saved } }
                                .buttonStyle(.bordered).disabled(!matchesSaved || preparing || error != nil)
                                .accessibilityIdentifier("wardrobe.field.ar")
                        }
                        Text(matchesSaved ? "저장됨 · 현장에서 이 화면을 다시 열어 AR로 확인하세요." : "위치와 방향을 정한 뒤 저장해 주세요.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("테스트 한 개와 사진 디자인을 이 기기에 보관합니다. 새 배치는 이전 테스트를 교체하며, 다른 기기나 공개 지도에는 표시되지 않아요.")
                        .font(.caption2).foregroundStyle(.secondary)
                    Button("저장한 테스트 삭제", role: .destructive) { showDelete = true }
                        .font(.footnote).accessibilityIdentifier("wardrobe.field.delete")
                }.padding()
            }.frame(maxHeight: 340).background(.regularMaterial)
        }
        .navigationTitle("커스텀 오이 현장 테스트").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar).tint(Color("OiGreen"))
        .task { if !scene.placementReady { await prepare() } }
        .onAppear { onScreen = true; scene.setVisible(phase == .active && arTrial == nil) }
        .onDisappear { onScreen = false; scene.suspendForARCamera() }
        .onChange(of: phase) { _, value in scene.setVisible(onScreen && value == .active && arTrial == nil) }
        .onChange(of: heading) { _, value in scene.updateDraft(height: 1.5, heading: value) }
        .onChange(of: arTrial != nil) { _, presented in
            if presented { scene.suspendForARCamera() }
            else { scene.setVisible(onScreen && phase == .active) }
        }
        .navigationDestination(item: $arTrial) { trial in OiWardrobeFieldARScreen(trial: trial) }
        .sheet(isPresented: $showPlaces) {
            NavigationStack {
                List((scene.data?.pois ?? []).sorted { $0.name < $1.name }) { place in
                    Button(place.name) { scene.focusPlaceForPlacement(place.id); showPlaces = false }
                }.navigationTitle("POSTECH 장소")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { showPlaces = false } } }
            }
        }
        .alert("이전 테스트를 교체할까요?", isPresented: $showReplace) {
            Button("취소", role: .cancel) { }
            Button("교체하여 저장") { save() }
        } message: { Text("이 기기에 보관된 이전 배치와 사진 디자인을 현재 디자인으로 교체합니다. 커스텀 초안은 유지됩니다.") }
        .alert("저장한 테스트를 삭제할까요?", isPresented: $showDelete) {
            Button("취소", role: .cancel) { }
            Button("삭제", role: .destructive) {
                do {
                    try repository.remove(); saved = nil; error = nil
                    scene.endPlacement()
                    if initialLook != nil { scene.beginPlacement(); scene.updateDraft(height: 1.5, heading: heading) }
                    else { look = nil; scene.suspendForARCamera() }
                } catch { self.error = error.localizedDescription }
            }
        } message: { Text("기기에 보관된 테스트 배치와 사진 사본만 삭제합니다. 기존 오이 커스텀 초안은 유지됩니다.") }
    }
    private func prepare() async {
        preparing = true; error = nil
        defer { preparing = false }
        do {
            saved = try repository.load()
            look = initialLook ?? saved?.look
            name = initialLook == nil ? (saved?.name ?? initialName) : String(initialName.prefix(60))
            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { name = "나의 오이" }
            guard let look else { return }
            heading = saved?.heading ?? 0
            await scene.load()
            try Task.checkCancellation()
            guard let data = scene.data else { return }
            if let saved, data.placementError(at: data.world(latitude: saved.latitude, longitude: saved.longitude)) != nil {
                throw CampusPlacementError.outside
            }
            await scene.preparePlacements(wardrobe: look)
            try Task.checkCancellation()
            scene.beginPlacement(editing: saved?.placement)
            scene.updateDraft(height: 1.5, heading: heading)
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-wardrobe-field-check"), saved == nil {
                await OiWardrobeFieldChecks.verifyAssets()
                scene.checkWardrobePlacement()
            }
            #endif
        } catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }
    private func save() {
        guard let look, let point = scene.draftPoint, let data = scene.data, data.placementError(at: point) == nil else { return }
        let coordinate = data.coordinate(point)
        do {
            let trial = OiWardrobeFieldTrial(name: name, latitude: coordinate.latitude,
                longitude: coordinate.longitude, heading: heading, look: look)
            try repository.save(trial); saved = trial; error = nil
        } catch { self.error = error.localizedDescription }
    }
}

extension OiWardrobeFieldTrial {
    /// Coordinate carrier only; the local AR screen explicitly supplies its wardrobe model.
    var placement: CampusPlacement {
        CampusPlacement(id: id, storyID: "local-wardrobe-test", latitude: latitude,
                        longitude: longitude, heightMeters: Self.heightMeters, headingDegrees: heading)
    }
}
