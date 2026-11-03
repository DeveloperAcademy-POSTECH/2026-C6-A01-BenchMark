import SwiftUI

/// The home is now the immersive campus explorer; existing account flows live in its menu.
struct HomeView: View {
    let container: AppContainer
    let store: CampusStoryStore
    let myDemo: MYLibraryStore
    let isCameraCoverActive: Bool
    let onCamera: () -> Void
    let onOpenProfile: () -> Void
    let onOpenStory: (String) -> Void
    var remote: OiRemoteStore? = nil
    var onAccount: (() -> Void)? = nil
    @Environment(\.scenePhase) private var scenePhase
    @State private var scene = CampusExploreScene()
    @State private var region: CampusRegion?
    @State private var sort = CampusStorySort.latest
    @State private var distances: [String: Float] = [:]
    @State private var expanded = false
    @State private var showingSchools = false
    @State private var searchResults: Set<String>?
    @State private var isOnScreen = false
    @State private var showingSearchChoice = false
    @State private var pendingSearchMode: CampusSearchMode?
    @State private var searchMode: CampusSearchMode?
    @State private var pendingStoryID: String?
    @State private var showingRequests = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                CampusMapSurface(scene: scene).ignoresSafeArea()
                VStack {
                    HStack {
                        if region != nil {
                            Button { region = nil; expanded = false; scene.showOverview() } label: { Image(systemName: "chevron.left") }
                                .buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.large)
                                .accessibilityLabel("캠퍼스 전체 지도").accessibilityIdentifier("campus.overview")
                            Spacer()
                            Button { searchVisibleArea() } label: { Label("이 지역 재검색", systemImage: "arrow.clockwise") }
                                .font(CampusStyle.body(15)).buttonStyle(.glass).buttonBorderShape(.capsule)
                            Spacer()
                            Color.clear.frame(width: 50, height: 1)
                        } else {
                            Button { showingSchools = true } label: { Label("POSTECH", systemImage: "chevron.backward").font(.system(size: 18, weight: .semibold)) }
                                .buttonStyle(.glass).buttonBorderShape(.capsule).controlSize(.large)
                            Spacer()
                            if let remote {
                                Button(action: { onAccount?() }) { Text(remote.account == nil ? "로그인" : "계정") }
                                    .buttonStyle(.glass).accessibilityIdentifier("oi.account")
                            } else {
                                Text("연결 확인 필요").font(.caption2).padding(7).background(.thinMaterial, in: Capsule())
                            }
                        }
                    }.padding(.horizontal, 20).padding(.top, 6)
                    Spacer()
                    if region == nil {
                        if let remote, remote.isRefreshing || remote.loadError != nil || remote.syncWarning != nil || remote.needsReauthentication {
                            OiConnectionStatus(remote: remote).padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)).padding(.horizontal, 20)
                        }
                        homeActions.padding(.horizontal, 20).padding(.bottom, 14)
                    }
                }
                if let remote, let error = remote.error {
                    VStack(spacing: 8) {
                        Text(error).font(.footnote)
                        Button("연결 확인") { onAccount?() }
                    }.padding(14).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
                if scene.isLoading { ProgressView("POSTECH 캠퍼스 불러오는 중").padding(22).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20)) }
                if let error = scene.error {
                    ContentUnavailableView { Label("지도를 불러올 수 없어요", systemImage: "map") } description: { Text(error) } actions: {
                        Button("다시 시도") { Task { await scene.load() } }
                    }.background(.regularMaterial)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let region { regionPanel(region, maxHeight: geometry.size.height * 0.72) }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(CampusStyle.lightGreen)
        .navigationDestination(for: MYDestination.self) { destination in
            switch destination {
            case .workshop:
                MYWorkshopView(container: container, store: store, demo: myDemo, onCamera: openCamera, remote: remote)
            case .farm: MYFarmView(remote: remote, nickname: myDemo.nickname)
            case .collection: MYCollectionView(demo: myDemo, storyRepository: container.storyRepository, remote: remote)
            case .school(let school): MYCollectionView(demo: myDemo, school: school, storyRepository: container.storyRepository, remote: remote)
            }
        }
        .sheet(isPresented: $showingSchools) {
            CampusSchoolSearchView {
                showingSchools = false; region = nil; expanded = false; searchResults = nil
                scene.showOverview()
            }
        }
        .sheet(isPresented: $showingSearchChoice, onDismiss: {
            searchMode = pendingSearchMode; pendingSearchMode = nil
        }) {
            CampusSearchChoiceSheet { pendingSearchMode = $0; showingSearchChoice = false }
        }
        .fullScreenCover(item: $searchMode, onDismiss: {
            // Push only after the search cover has gone, so it cannot cover the destination.
            if let id = pendingStoryID { pendingStoryID = nil; onOpenStory(id) }
        }) { mode in
            CampusSearchView(mode: mode, entries: searchEntries, isExample: false) {
                pendingStoryID = $0.id; searchMode = nil
            }
        }
        .sheet(isPresented: $showingRequests) {
            NavigationStack {
                ContentUnavailableView("카드 요청 준비 중", systemImage: "envelope",
                    description: Text("카드 요청은 아직 지원하지 않아요. 공개된 오이는 이야기 화면에서 수집할 수 있어요."))
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { showingRequests = false } } }
            }
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
            if remote != nil { scene.setRegionCounts(Dictionary(grouping: store.stories, by: \.regionID).mapValues(\.count)) }
            await scene.load()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-campus-renderer-check") { await scene.checkRendererRestoration() }
            if ProcessInfo.processInfo.arguments.contains("-campus-placement-check") {
                await scene.preparePlacements(); scene.checkPrecisePlacement()
            }
            if ProcessInfo.processInfo.arguments.contains("-campus-schools-preview") { showingSchools = true }
            if ProcessInfo.processInfo.arguments.contains("-campus-region-preview"), let first = CampusRegion.campus.first { scene.onRegion?(first) }
            #endif
        }
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
        .onChange(of: store.stories) { _, _ in
            if remote != nil { scene.setRegionCounts(Dictionary(grouping: store.stories, by: \.regionID).mapValues(\.count)) }
            if let region { scene.showStoriesInCurrentArea(region, stories: store.stories(in: region.id, sortedBy: sort)) }
        }
    }

    private var homeActions: some View {
        HStack(alignment: .top) {
            Button(action: onOpenProfile) {
                VStack(spacing: 7) {
                    Image("OiFarmer").resizable().scaledToFill().frame(width: 100, height: 100, alignment: .top)
                        .background(Color(red: 0.96, green: 1, blue: 0.84)).clipShape(Circle())
                        .overlay(Circle().stroke(CampusStyle.green, lineWidth: 2))
                    Text(myDemo.nickname).font(CampusStyle.body(14)).frame(width: 104, height: 25)
                        .background(Color(.systemBackground), in: Capsule()).shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                }
            }.buttonStyle(.plain).accessibilityLabel("\(myDemo.nickname)의 MY 작업실").accessibilityIdentifier("campus.profile")
            Spacer()
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    mapAction("envelope", label: "카드 요청", id: "campus.requests") { showingRequests = true }
                    mapAction("magnifyingglass", label: "오이 검색", id: "campus.search") { showingSearchChoice = true }
                    mapAction("plus", label: "오이 심기 · 작성 승인과 내 이야기", id: "placement.begin") { onAccount?() }
                }
                Button(action: openCamera) { Image(systemName: "camera.fill").font(.system(size: 34)).frame(width: 78, height: 78) }
                    .buttonStyle(.glassProminent).buttonBorderShape(.circle).tint(Color(red: 0.40, green: 0.31, blue: 0.12))
                    .accessibilityLabel("AR 카메라 열기").accessibilityIdentifier("campus.camera")
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }.frame(maxWidth: 190)

        }
    }

    private func mapAction(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 24)).foregroundStyle(.white)
                .frame(width: 52, height: 52).background(CampusStyle.green.opacity(0.8), in: Circle())
        }.buttonStyle(.plain).accessibilityLabel(label).accessibilityIdentifier(id)
    }

    private var searchEntries: [CampusSearchEntry] {
        store.stories.map { story in
            let live = remote?.stories.first { $0.id.uuidString == story.id }
            let schoolID = remote?.regions.first { $0.id == story.regionID }?.schoolId
            let school = remote?.schools.first { $0.id == schoolID }?.name ?? "POSTECH"
            let nickname = remote?.profiles.first { $0.id == live?.userId }?.nickname ?? ""
            return CampusSearchEntry(story: story, publicID: UUID(uuidString: story.id), cucumberName: story.title,
                code: story.id, school: school + (schoolID == "postech" ? " 포스텍 포항공과대학교" : ""), donorName: nickname)
        }
    }

    private func searchVisibleArea() {
        guard let closest = scene.nearestRegion() else { return }
        region = closest; expanded = false
        scene.showStoriesInCurrentArea(closest, stories: store.stories(in: closest.id, sortedBy: sort))
        distances = scene.distances(); searchResults = scene.visibleStoryIDs()
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
                    ForEach([CampusStorySort.latest, .oldest], id: \.self) { item in
                        Button { sort = item; distances = scene.distances() } label: {
                            Text(item.rawValue).font(.system(size: 16)).padding(.horizontal, 12).padding(.vertical, 5)
                                .foregroundStyle(sort == item ? .white : .black)
                                .background(sort == item ? CampusStyle.lightGreen : Color(.systemGray5), in: Capsule())
                        }.buttonStyle(.plain).accessibilityAddTraits(sort == item ? .isSelected : [])
                    }
                    Menu {
                        Button("거리순") { sort = .distance; distances = scene.distances() }
                        Button("인기순") { sort = .popular }
                    } label: { Image(systemName: "ellipsis").frame(width: 32, height: 32) }.accessibilityLabel("다른 정렬")
                    Spacer(minLength: 0)
                    Text("\(items.count)개").font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white).padding(.horizontal, 16).padding(.vertical, 5).background(CampusStyle.green, in: Capsule())
                }
                if sort == .distance { Text("지도 중심에서 가까운 순서").font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
                if let remote { OiConnectionStatus(remote: remote) }
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if items.isEmpty, remote == nil || remote?.hasLoadedRemote == true { Text("이 화면에는 오이가 없어요. 지도를 움직여 다시 검색해 주세요.").font(.subheadline).foregroundStyle(.secondary).padding() }
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
