import SwiftUI

/// The home is now the immersive campus explorer; existing account flows live in its menu.
struct HomeView: View {
    let container: AppContainer
    let store: CampusStoryStore
    let shared: CampusSharedStore
    let onSharedAR: (CampusSharedOi) -> Void
    let isCameraCoverActive: Bool
    let onCamera: () -> Void
    let onGeoCamera: (CampusPlacement) -> Void
    let onOpenStory: (String) -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var scene = CampusExploreScene()
    @State private var region: CampusRegion?
    @State private var sort = CampusStorySort.latest
    @State private var distances: [String: Float] = [:]
    @State private var expanded = false
    @State private var showingProfile = false
    @State private var showingSchools = false
    @State private var searchResults: Set<String>?
    @State private var isOnScreen = false
    @State private var placements = CampusPlacementStore()
    @State private var showingPlacements = false
    @State private var selectedPlacement: CampusPlacement?
    @State private var editingPlacement: CampusPlacement?
    @State private var pendingPlacementAction: PlacementAction?
    @State private var sharedMode = true
    @State private var showingWriter = false
    @State private var showingShared = false
    @State private var selectedShared: CampusSharedOi?
    @State private var pendingSharedAR: CampusSharedOi?
    @State private var pendingEdit: CampusSharedOi?
    @State private var editingShared: CampusSharedOi?
    private enum PlacementAction {
        case edit(CampusPlacement), ar(CampusPlacement), story(String)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                CampusMapSurface(scene: scene)
                    .ignoresSafeArea(.container, edges: scene.editingPlacement ? .top : .all)
                VStack {
                    HStack {
                        if region != nil {
                            Button { region = nil; expanded = false; scene.showOverview() } label: { Image(systemName: "chevron.left") }
                                .buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.large)
                                .accessibilityLabel("캠퍼스 전체 지도").accessibilityIdentifier("campus.overview")
                            Spacer()
                            Button { distances = scene.distances(); searchResults = scene.visibleStoryIDs() } label: { Label("이 지역 재검색", systemImage: "arrow.clockwise") }
                                .font(CampusStyle.body(15)).buttonStyle(.glass).buttonBorderShape(.capsule)
                            Spacer()
                            Color.clear.frame(width: 50, height: 1)
                        } else {
                            Button { showingSchools = true } label: { Label("POSTECH", systemImage: "chevron.backward").font(.system(size: 18, weight: .semibold)) }
                                .buttonStyle(.glass).buttonBorderShape(.capsule).controlSize(.large)
                                .disabled(scene.editingPlacement)
                            Spacer()
                            Menu {
                                Button("공유 캠퍼스") { sharedMode = true }
                                Button("기기 예시 테스트") { sharedMode = false }
                            } label: {
                                Text(sharedMode ? "공유 캠퍼스" : "기기 예시").font(.caption).padding(7).background(.thinMaterial, in: Capsule())
                            }.disabled(scene.editingPlacement)
                        }
                    }.padding(.horizontal, 20).padding(.top, 6)
                    if !scene.editingPlacement {
                        if sharedMode {
                            HStack {
                                Button(shared.authorized ? "오이 심기" : "작성 코드 등록", systemImage: "plus.viewfinder") {
                                    if shared.authorized { editingShared = nil; scene.beginPlacement() }
                                    else { showingWriter = true }
                                }.disabled(!shared.configured || !scene.placementReady)
                                Spacer()
                                Button("오이 목록 \(shared.items.count)", systemImage: "leaf") { showingShared = true }
                            }.font(.subheadline).buttonStyle(.glass).padding(.horizontal, 20)
                            if !shared.configured {
                                Text("공유 서버 연결 대기 · 메뉴에서 기기 예시를 볼 수 있어요.").font(.caption).padding(8).background(.regularMaterial, in: Capsule())
                            } else if let error = shared.error {
                                Button(error) { Task { await shared.refresh() } }.font(.caption).padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                            } else if shared.refreshing { ProgressView("공개 오이 확인 중").font(.caption) }
                        } else {
                            HStack {
                                Button("예시 오이 배치", systemImage: "plus.viewfinder") { editingPlacement = nil; scene.beginPlacement() }
                                    .disabled(!scene.placementReady || !placements.ready)
                                    .accessibilityIdentifier("placement.begin")
                                Spacer()
                                Button("기기 저장 \(placements.placements.count)", systemImage: "leaf") { showingPlacements = true }
                            }.font(.subheadline).buttonStyle(.glass).padding(.horizontal, 20)
                        }
                        if let error = scene.placementError {
                            Button(error) { Task { await scene.preparePlacements() } }
                                .font(.caption).padding(8).background(.regularMaterial, in: Capsule())
                        } else if scene.placementLoading {
                            ProgressView("오이 준비 중").font(.caption)
                        }
                    }
                    Spacer()
                    if !scene.editingPlacement && region == nil { homeActions.padding(.horizontal, 20).padding(.bottom, 14) }
                }
                if scene.isLoading { ProgressView("POSTECH 캠퍼스 불러오는 중").padding(22).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20)) }
                if let error = scene.error {
                    ContentUnavailableView { Label("지도를 불러올 수 없어요", systemImage: "map") } description: { Text(error) } actions: {
                        Button("다시 시도") { Task { await loadCampus() } }
                    }.background(.regularMaterial)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if scene.editingPlacement {
                    if sharedMode {
                        CampusSharedEditor(scene: scene, store: shared, editing: editingShared)
                    } else {
                        CampusPlacementEditor(scene: scene, placements: placements, stories: store.stories, editing: editingPlacement)
                            .id(editingPlacement?.id)
                    }
                } else if let region { regionPanel(region, maxHeight: geometry.size.height * 0.72) }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(CampusStyle.lightGreen)
        .sheet(isPresented: $showingWriter) { CampusWriterRegistration(store: shared) }
        .sheet(isPresented: $showingShared, onDismiss: completeSharedSelection) {
            CampusSharedList(store: shared, onAR: { item in pendingSharedAR = item; showingShared = false },
                             onEdit: { item in pendingEdit = item; showingShared = false })
        }
        .sheet(item: $selectedShared, onDismiss: completeSharedSelection) { item in
            NavigationStack {
                CampusSharedStoryView(id: item.id, store: shared,
                    onAR: { target in pendingSharedAR = target; selectedShared = nil },
                    onEdit: { target in pendingEdit = target; selectedShared = nil })
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { selectedShared = nil } } }
            }
        }
        .sheet(isPresented: $showingProfile) { CampusProfileMenu(container: container, store: store, onCamera: openCamera) }
        .sheet(isPresented: $showingPlacements, onDismiss: completePlacementSelection) {
            CampusPlacementList(placements: placements, stories: store,
                onAR: { queuePlacementAction(.ar($0)) }, onEdit: { queuePlacementAction(.edit($0)) })
        }
        .sheet(item: $selectedPlacement, onDismiss: completePlacementSelection) { placement in
            CampusPlacementDetail(placement: placement, placements: placements, stories: store,
                onEdit: { queuePlacementAction(.edit(placement)) },
                onAR: { queuePlacementAction(.ar(placement)) },
                onStory: { queuePlacementAction(.story(placement.storyID)) })
        }
        .sheet(isPresented: $showingSchools) {
            NavigationStack {
                List {
                    Button { showingSchools = false; region = nil; scene.showOverview() } label: {
                        Label("POSTECH · 포항공과대학교", systemImage: "building.2.fill")
                    }
                    Text("현재는 POSTECH 캠퍼스를 탐색할 수 있어요.").font(.footnote).foregroundStyle(.secondary)
                }.navigationTitle("학교 선택").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { showingSchools = false } } }
            }.presentationDetents([.medium])
        }
        .task {
            scene.onRegion = { selected in
                region = selected; sort = .latest; expanded = false; searchResults = nil
                scene.focus(selected, stories: store.stories(in: selected.id, sortedBy: .latest))
                distances = scene.distances()
            }
            scene.onStory = { id in
                guard store.story(id) != nil else { return }
                // Use the same value-based path as list links and the summary's detail link.
                onOpenStory(id)
            }
            scene.onPlacement = { id in
                if sharedMode { selectedShared = shared.items.first { $0.id == id } }
                else { selectedPlacement = placements.placements.first { $0.id == id } }
            }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-campus-placement-check") { sharedMode = false }
            #endif
            await loadCampus()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-campus-placement-check") { scene.checkPrecisePlacement() }
            if ProcessInfo.processInfo.arguments.contains("-campus-renderer-check") { await scene.checkRendererRestoration() }
            if ProcessInfo.processInfo.arguments.contains("-campus-region-preview"), let first = CampusRegion.examples.first { scene.onRegion?(first) }
            #endif
        }
        .task(id: sharedMode && isOnScreen && !isCameraCoverActive && scenePhase == .active) {
            guard sharedMode, isOnScreen, !isCameraCoverActive, scenePhase == .active, shared.configured else { return }
            repeat {
                await shared.refresh()
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            } while !Task.isCancelled
        }
        .onChange(of: placements.placements) { _, _ in syncMap() }
        .onChange(of: shared.items) { _, _ in syncMap() }
        .onChange(of: sharedMode) { _, _ in
            region = nil; scene.endPlacement(); scene.setSharedMap(sharedMode); syncMap()
        }
        .alert("위치 저장 확인", isPresented: Binding(get: { placements.error != nil && !showingPlacements && selectedPlacement == nil }, set: { if !$0 { placements.error = nil } })) {
            Button("확인", role: .cancel) { placements.error = nil }
        } message: { Text(placements.error ?? "") }
        .onAppear { isOnScreen = true; scene.setVisible(!isCameraCoverActive && scenePhase == .active) }
        .onDisappear { isOnScreen = false; scene.setVisible(false) }
        .onChange(of: scenePhase) { _, phase in scene.setVisible(isOnScreen && !isCameraCoverActive && phase == .active) }
        .onChange(of: isCameraCoverActive) { _, active in
            // Full-screen presentation doesn't always trigger this nested view's onAppear again.
            if active {
                scene.suspendForARCamera()
            } else {
                isOnScreen = true
                scene.setVisible(scenePhase == .active)
            }
        }
    }

    private func loadCampus() async {
        scene.setSharedMap(sharedMode)
        await scene.load()
        guard let data = scene.data else { return }
        placements.load(map: data, storyIDs: Set(store.stories.map(\.id)))
        await scene.preparePlacements()
        syncMap()
    }

    private func syncMap() {
        let records = sharedMode ? shared.items.map(\.placement) : placements.placements
        // Check the bundled map too; never render an unexpected server coordinate.
        scene.syncPlacements(records: records.filter { record in
            guard let data = scene.data else { return false }
            return data.placementError(at: data.world(latitude: record.latitude, longitude: record.longitude)) == nil
        })
    }

    private func completeSharedSelection() {
        if let item = pendingSharedAR {
            pendingSharedAR = nil; scene.suspendForARCamera(); onSharedAR(item)
        } else if let item = pendingEdit {
            pendingEdit = nil; editingShared = item; region = nil; expanded = false
            scene.beginPlacement(editing: item.placement)
        }
    }

    private func queuePlacementAction(_ action: PlacementAction) {
        pendingPlacementAction = action
        selectedPlacement = nil; showingPlacements = false
    }

    private func completePlacementSelection() {
        guard let action = pendingPlacementAction else { return }
        pendingPlacementAction = nil
        // Wait until the sheet is gone before editing the map or presenting AR/navigation.
        switch action {
        case .edit(let placement):
            editingPlacement = placement; region = nil; expanded = false
            scene.beginPlacement(editing: placement)
        case .ar(let placement):
            scene.suspendForARCamera(); onGeoCamera(placement)
        case .story(let id): onOpenStory(id)
        }
    }

    private var homeActions: some View {
        HStack(alignment: .top) {
            Button { showingProfile = true } label: {
                VStack(spacing: 7) {
                    Image("OiFarmer").resizable().scaledToFill().frame(width: 100, height: 100, alignment: .top)
                        .background(Color(red: 0.96, green: 1, blue: 0.84)).clipShape(Circle())
                        .overlay(Circle().stroke(CampusStyle.green, lineWidth: 2))
                    Text("신서임당").font(CampusStyle.body(14)).frame(width: 104, height: 25)
                        .background(Color(.systemBackground), in: Capsule()).shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                }
            }.buttonStyle(.plain).accessibilityLabel("내 프로필과 수집한 오이").accessibilityIdentifier("campus.profile")
            Spacer()
            Button(action: openCamera) { Image(systemName: "camera.fill").font(.system(size: 34)).frame(width: 78, height: 78) }
                .buttonStyle(.glassProminent).buttonBorderShape(.circle).tint(Color(red: 0.40, green: 0.31, blue: 0.12))
                .accessibilityLabel("AR 카메라 열기").accessibilityIdentifier("campus.camera")
        }
    }

    private func openCamera() {
        scene.suspendForARCamera()
        onCamera()
    }

    private func regionPanel(_ region: CampusRegion, maxHeight: CGFloat) -> some View {
        let items = store.stories(in: region.id, sortedBy: sort, distances: distances)
            .filter { searchResults?.contains($0.id) ?? true }
        return VStack(spacing: 8) {
            Button { withAnimation(.snappy) { expanded.toggle() } } label: {
                Label(expanded ? "지도보기" : "목록보기", systemImage: "list.star")
                    .font(CampusStyle.body(16)).padding(.horizontal, 20).padding(.vertical, 8)
                    .background(Color(.systemBackground), in: Capsule())
            }.buttonStyle(.plain).accessibilityIdentifier("campus.list.toggle")
            VStack(spacing: 12) {
                Capsule().fill(Color(.systemGray4)).frame(width: 52, height: 5).padding(.top, 5)
                    .padding(.horizontal, 100).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 20).onEnded { value in withAnimation(.snappy) { expanded = value.translation.height < 0 } })
                HStack(spacing: 7) {
                    ForEach(CampusStorySort.allCases, id: \.self) { item in
                        Button { sort = item; distances = scene.distances() } label: {
                            Text(item.rawValue).font(.system(size: 16)).padding(.horizontal, 12).padding(.vertical, 5)
                                .foregroundStyle(sort == item ? .white : .black)
                                .background(sort == item ? CampusStyle.lightGreen : Color(.systemGray5), in: Capsule())
                        }.buttonStyle(.plain).accessibilityAddTraits(sort == item ? .isSelected : [])
                    }
                    Spacer(minLength: 0)
                    Text("\(items.count)개").font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white).padding(.horizontal, 16).padding(.vertical, 5).background(CampusStyle.green, in: Capsule())
                }
                if sort == .distance { Text("지도 중심에서 가까운 순서").font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if items.isEmpty { Text("이 화면에는 오이가 없어요. 지도를 움직여 다시 검색해 주세요.").font(.subheadline).foregroundStyle(.secondary).padding() }
                        ForEach(items) { story in
                            NavigationLink(value: CampusDestination.summary(story.id)) { CampusStoryRow(story: story) }
                                .buttonStyle(.plain).accessibilityIdentifier("campus.row.\(story.id)")
                        }
                    }.padding(.bottom, 12)
                }.scrollIndicators(.hidden)
            }
            .padding(.horizontal, 12).frame(height: expanded ? maxHeight : 230)
            .background {
                UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30)
                    .fill(Color(.systemBackground)).ignoresSafeArea(edges: .bottom)
            }
        }.padding(.horizontal, 11)
    }
}
