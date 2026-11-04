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
    var onCreateStory: (() -> Void)? = nil
    var onOpenExamples: (() -> Void)? = nil
    var onCloseExamples: (() -> Void)? = nil
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    @State private var listIsAtTop = true
    @State private var showingWardrobeTest = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                CampusMapSurface(scene: scene).ignoresSafeArea().accessibilityHidden(expanded)
                VStack {
                    mapHeader.padding(.horizontal, 20).padding(.top, region == nil ? 9 : 4)
                    Spacer()
                    if region == nil {
                        if let remote, (remote.isRefreshing && !remote.hasLoadedRemote) || remote.loadError != nil || remote.syncWarning != nil || remote.needsReauthentication {
                            OiConnectionStatus(remote: remote).padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)).padding(.horizontal, 20)
                        }
                        homeActions.padding(.leading, 22).padding(.trailing, 20).padding(.bottom, 0)
                    }
                }
                if let remote, let error = remote.error {
                    VStack(spacing: 8) {
                        Text(error).font(.footnote)
                        Button("확인") { remote.error = nil }
                            .accessibilityLabel("안내 닫기")
                    }.padding(14).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
                if scene.isLoading { ProgressView("POSTECH 캠퍼스 불러오는 중").padding(22).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20)) }
                if let error = scene.error {
                    ContentUnavailableView { Label("지도를 불러올 수 없어요", systemImage: "map") } description: { Text(error) } actions: {
                        Button("다시 시도") { Task { await scene.load() } }
                    }.background(.regularMaterial)
                }
            }
            // Keep the RealityKit viewport fixed while the list changes height.
            .overlay(alignment: .bottom) {
                if let region { regionPanel(region, availableHeight: geometry.size.height, bottomInset: geometry.safeAreaInsets.bottom) }
            }
            .onAppear { configureMapLabels(geometry) }
            .onChange(of: geometry.size) { _, _ in configureMapLabels(geometry) }
            .onChange(of: geometry.safeAreaInsets) { _, _ in configureMapLabels(geometry) }
            .onChange(of: region?.id) { _, _ in configureMapLabels(geometry) }
            .onChange(of: expanded) { _, _ in configureMapLabels(geometry) }
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
        .navigationDestination(isPresented: $showingWardrobeTest) { OiWardrobeFieldTestScreen() }
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
            if let id = pendingStoryID { pendingStoryID = nil; openStory(id) }
        }) { mode in
            CampusSearchView(mode: mode, entries: searchEntries, isExample: store.isExample) {
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
            configureSceneCallbacks()
            scene.setRegionCounts(Dictionary(grouping: store.stories, by: \.regionID).mapValues(\.count))
            await scene.load()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-campus-map-browsing-check") { scene.checkMapBrowsing() }
            if ProcessInfo.processInfo.arguments.contains("-campus-map-label-check") { await scene.checkMapLabels() }
            if ProcessInfo.processInfo.arguments.contains("-campus-renderer-check") { await scene.checkRendererRestoration() }
            if ProcessInfo.processInfo.arguments.contains("-campus-placement-check") {
                await scene.preparePlacements(); scene.checkPrecisePlacement()
            }
            if ProcessInfo.processInfo.arguments.contains("-campus-schools-preview") { showingSchools = true }
            if ProcessInfo.processInfo.arguments.contains("-campus-region-preview"), let first = CampusRegion.campus.first {
                scene.onRegion?(first)
                if ProcessInfo.processInfo.arguments.contains("-campus-expanded-preview") { expanded = true }
                if ProcessInfo.processInfo.arguments.contains("-campus-list-motion-preview") {
                    do {
                        try await Task.sleep(for: .seconds(2))
                        setListExpanded(true)
                        try await Task.sleep(for: .seconds(2))
                        setListExpanded(false)
                    } catch is CancellationError {
                        return
                    } catch {
                        assertionFailure("Unexpected preview clock failure: \(error)")
                    }
                }
            }
            #endif
        }
        .onAppear { isOnScreen = true; scene.setVisible(!isCameraCoverActive && scenePhase == .active) }
        .onDisappear { isOnScreen = false; scene.suspendForARCamera() }
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
            scene.setRegionCounts(Dictionary(grouping: store.stories, by: \.regionID).mapValues(\.count))
            if let region {
                scene.showStoriesInCurrentArea(region, stories: searchResults == nil ? store.stories(in: region.id, sortedBy: sort) : store.stories)
                if searchResults != nil { searchResults = scene.visibleStoryIDs() }
            }
        }
        .onChange(of: store.isExample) { _, example in
            configureSceneCallbacks()
            // Keep the current ARView/scene graph alive when changing the data source.
            sort = .latest; expanded = false; searchResults = nil
            if example, let first = CampusRegion.campus.first {
                region = first
                scene.focus(first, stories: store.stories(in: first.id, sortedBy: .latest))
                distances = scene.distances()
            } else { region = nil; scene.showOverview() }
        }
    }

    private func configureSceneCallbacks() {
        scene.onRegion = { selected in
            region = selected; sort = .latest; expanded = false; searchResults = nil
            scene.focus(selected, stories: store.stories(in: selected.id, sortedBy: .latest))
            distances = scene.distances()
        }
        scene.onStory = { id in
            guard store.story(id) != nil else { return }
            // Use the same value-based path as list links and the summary's detail link.
            openStory(id)
        }
    }

    private func configureMapLabels(_ geometry: GeometryProxy) {
        let bottom = region == nil ? 8 : regionPanelHeight(geometry.size.height) + 58
        let bottomY = geometry.size.height + geometry.safeAreaInsets.top
        let controls = region == nil ? [
            CGRect(x: 24, y: bottomY - 140, width: 112, height: 144),
            CGRect(x: geometry.size.width - 84, y: bottomY - 204, width: 68, height: 208)
        ] : []
        scene.setMapLabelPresentation(enabled: !expanded,
            topInset: geometry.safeAreaInsets.top + 64,
            bottomInset: geometry.safeAreaInsets.bottom + bottom, controls: controls)
    }

    private func regionPanelHeight(_ availableHeight: CGFloat) -> CGFloat {
        expanded ? max(200, availableHeight - 68) : max(220, availableHeight * 0.416)
    }

    private var homeActions: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Button(action: onOpenProfile) {
                    HStack(spacing: -12) {
                        MYFarmerArtwork(ownerID: remote?.account?.id)
                            .frame(width: 38, height: 38).background(CampusStyle.secondaryAction, in: Circle())
                            .clipShape(Circle()).overlay(Circle().stroke(CampusStyle.green, lineWidth: 1.5))
                            .zIndex(1)
                        Text(myDemo.nickname).font(CampusStyle.medium(14)).tracking(0.28)
                            .lineLimit(1).padding(.leading, 24).padding(.trailing, 15).padding(.vertical, 2)
                            .background(.white, in: Capsule())
                    }.shadow(color: CampusStyle.mapAction.opacity(0.4), radius: 7, y: 3)
                        .frame(minHeight: 44)
                }.buttonStyle(.plain).accessibilityLabel("\(myDemo.nickname)의 농부 프로필")
                    .accessibilityIdentifier("campus.profile")
                Button(action: onOpenProfile) {
                    Circle()
                        .fill(Color(red: 1, green: 247 / 255, blue: 219 / 255))
                        .frame(width: 100, height: 100)
                        .overlay {
                            Image("CampusMyHouse").resizable().scaledToFit()
                                .frame(width: 80, height: 80).offset(y: -3)
                        }
                        .clipShape(Circle())
                        .overlay {
                            Circle().strokeBorder(Color(red: 128 / 255, green: 99 / 255, blue: 33 / 255), lineWidth: 2)
                                .frame(width: 104, height: 104)
                        }
                        .shadow(color: Color(red: 120 / 255, green: 77 / 255, blue: 25 / 255), radius: 7.5)
                        .contentShape(Circle())
                }.buttonStyle(.plain).accessibilityLabel("MY 작업실 열기").accessibilityIdentifier("campus.workshop")
            }.disabled(store.isExample)
            Spacer()
            VStack(spacing: 10) {
                mapAction("envelope", label: "카드 요청", id: "campus.requests") { showingRequests = true }
                mapAction("magnifyingglass", label: "오이 검색", id: "campus.search",
                    background: "CampusMapSearchBackground") { showingSearchChoice = true }
                Button { onCreateStory?() } label: {
                    Image("CampusAddOi").renderingMode(.original).frame(width: 60, height: 60)
                        .contentShape(Circle())
                }.buttonStyle(.plain).accessibilityLabel("오이 심기 · 작성 승인과 내 이야기")
                    .accessibilityIdentifier("placement.begin")
                    .disabled(store.isExample).opacity(store.isExample ? 0.45 : 1)
            }
        }
    }

    private func mapAction(_ symbol: String, label: String, id: String,
                           background: String = "CampusMapActionBackground", rotation: Angle = .zero,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 24, weight: .medium)).foregroundStyle(.white)
                .rotationEffect(rotation)
                .frame(width: 60, height: 60)
                .background { Image(background).renderingMode(.original).accessibilityHidden(true) }
                .contentShape(Circle())
        }.buttonStyle(.plain).accessibilityLabel(label).accessibilityIdentifier(id)
    }

    private var searchEntries: [CampusSearchEntry] {
        store.stories.map { story in
            let live = remote?.stories.first { $0.id.uuidString == story.id }
            let schoolID = remote?.regions.first { $0.id == story.regionID }?.schoolId
            let school = remote?.schools.first { $0.id == schoolID }?.name ?? "POSTECH"
            let nickname = remote?.profiles.first { $0.id == live?.userId }?.nickname ?? (story.isExample ? story.donor : "")
            return CampusSearchEntry(story: story, publicID: UUID(uuidString: story.id), cucumberName: story.title,
                code: story.id, school: school + (schoolID == "postech" || story.isExample ? " 포스텍 포항공과대학교" : ""), donorName: nickname)
        }
    }

    private func searchVisibleArea() {
        guard let closest = scene.nearestRegion() else { return }
        region = closest; expanded = false
        scene.showStoriesInCurrentArea(closest, stories: store.stories)
        distances = scene.distances(); searchResults = scene.visibleStoryIDs()
    }

    private func openCamera() {
        scene.suspendForARCamera()
        onCamera()
    }

    private func openStory(_ id: String) {
        // The summary uses its own non-AR renderer. Release this one before the push,
        // just as for AR, then rebuild it with the saved camera values on return.
        scene.suspendForARCamera()
        onOpenStory(id)
    }

    private var mapHeader: some View {
        HStack(alignment: .top) {
            if region != nil {
                Button {
                    region = nil; expanded = false; searchResults = nil; scene.showOverview()
                } label: {
                    // A plain SF Symbol button needs an explicit hit area for its glass circle.
                    Image(systemName: "chevron.left").font(.system(size: 19, weight: .semibold)).frame(width: 50, height: 50)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain).glassEffect(.regular.interactive(), in: Circle())
                .accessibilityLabel("캠퍼스 전체 지도").accessibilityIdentifier("campus.overview")
                Spacer()
                if let onCloseExamples {
                    Button("예시 닫기", action: onCloseExamples)
                        .font(.caption).buttonStyle(.glass).accessibilityIdentifier("campus.examples.close")
                } else { Color.clear.frame(width: 50, height: 1) }
            } else {
                Button { showingSchools = true } label: {
                    HStack(spacing: 8) {
                        Image("CampusSchoolIcon").renderingMode(.original).frame(width: 16, height: 16)
                        Text("POSTECH 농장").font(CampusStyle.semibold(18)).lineLimit(1).minimumScaleFactor(0.7)
                    }.frame(width: 195, height: 42)
                }
                .buttonStyle(.plain).glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 20))
                .accessibilityLabel("캠퍼스 선택").accessibilityIdentifier("campus.school")
                .contextMenu {
                    if let onAccount {
                        Button(remote?.account == nil ? "로그인" : "계정", systemImage: "person.crop.circle", action: onAccount)
                    }
                    if let onOpenExamples {
                        Button("예시 오이 둘러보기", systemImage: "leaf", action: onOpenExamples)
                    }
                    Button("내 오이 현장 테스트", systemImage: "mappin.and.ellipse") {
                        showingWardrobeTest = true
                    }.accessibilityIdentifier("campus.wardrobeTest.open")
                }
                Spacer()
                if let onCloseExamples {
                    Button("예시 닫기", action: onCloseExamples)
                        .buttonStyle(.glass).accessibilityIdentifier("campus.examples.close")
                }
            }
        }
        .overlay(alignment: .top) {
            if region != nil && !expanded {
                searchAreaButton.alignmentGuide(.top) { ($0.height - 34) / 2 }.transition(.opacity)
            }
        }
    }

    private var searchAreaButton: some View {
        Button { searchVisibleArea() } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.clockwise").font(.system(size: 13))
                Text("이 지역 재검색").font(CampusStyle.body(15))
            }.padding(.horizontal, 16).frame(height: 34)
                .background(.white.opacity(0.7), in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Capsule())
        }.buttonStyle(.plain).accessibilityIdentifier("campus.searchArea")
    }

    private func regionPanel(_ region: CampusRegion, availableHeight: CGFloat, bottomInset: CGFloat) -> some View {
        let items = store.stories(in: searchResults == nil ? region.id : nil,
                                  matching: searchResults, sortedBy: sort, distances: distances)
        // Figma: sheet starts at y=516 (collapsed) or y=130 (expanded) in an 874pt screen.
        let height = regionPanelHeight(availableHeight)
        return VStack(spacing: 9.5) {
            Button { setListExpanded(!expanded) } label: {
                HStack(spacing: 8) {
                    Image(systemName: expanded ? "xmark" : "list.star").font(.system(size: 16))
                    Text(expanded ? "목록닫기" : "목록보기").font(CampusStyle.body(16))
                }.padding(.horizontal, 20).frame(height: 35)
                    .background(.white, in: Capsule()).frame(minHeight: 44)
                    .contentShape(Capsule())
            }.buttonStyle(.plain).accessibilityIdentifier("campus.list.toggle")
            VStack(spacing: 20) {
                HStack(spacing: 7) {
                    ForEach([CampusStorySort.latest, .oldest], id: \.self) { item in
                        Button { sort = item; distances = scene.distances() } label: {
                            Text(item.rawValue).font(CampusStyle.body(16)).tracking(0.32)
                                .padding(.horizontal, 12).frame(height: 29)
                                .foregroundStyle(sort == item ? Color(red: 247/255, green: 1, blue: 233/255) : .black)
                                .background(sort == item ? CampusStyle.lightGreen : .white, in: Capsule())
                                .frame(minHeight: 44).contentShape(Capsule())
                        }.buttonStyle(.plain).accessibilityAddTraits(sort == item ? .isSelected : [])
                    }
                    Spacer(minLength: 0)
                    // Secondary sort choices stay available without adding an extra icon to the design.
                    Menu {
                        Button("거리순") { sort = .distance; distances = scene.distances() }
                        Button("인기순") { sort = .popular }
                    } label: {
                        Text("\(items.count)개").font(CampusStyle.medium(16)).tracking(0.32)
                            .foregroundStyle(Color(red: 112 / 255, green: 140 / 255, blue: 64 / 255))
                            .padding(.horizontal, 16).frame(minWidth: 68).frame(height: 29)
                            .background(CampusStyle.secondaryAction, in: Capsule())
                            .frame(minHeight: 44).contentShape(Capsule())
                    }.accessibilityLabel("오이 \(items.count)개, 다른 정렬")
                }.padding(.vertical, -7.5)
                if sort == .distance || sort == .popular {
                    Text(sort == .distance ? "지도 중심에서 가까운 순서" : "인기순")
                        .font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }
                if let remote { OiConnectionStatus(remote: remote) }
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if items.isEmpty, remote == nil || remote?.hasLoadedRemote == true {
                            Text("이 화면에는 오이가 없어요. 지도를 움직여 다시 검색해 주세요.")
                                .font(CampusStyle.body(14)).foregroundStyle(.secondary).padding()
                        }
                        ForEach(items) { story in
                            Button { openStory(story.id) } label: { CampusStoryRow(story: story) }
                                .buttonStyle(.plain).accessibilityIdentifier("campus.row.\(story.id)")
                        }
                    }.padding(.bottom, 12)
                }.scrollIndicators(.hidden)
                    .onScrollGeometryChange(for: Bool.self) { geometry in
                        geometry.contentOffset.y + geometry.contentInsets.top <= 1
                    } action: { _, isAtTop in listIsAtTop = isAtTop }
            }
            .padding(.horizontal, 20).padding(.top, 20).frame(height: height)
            .background {
                UnevenRoundedRectangle(topLeadingRadius: 35, topTrailingRadius: 35)
                    .fill(Color(white: 244/255).opacity(0.85))
                    .padding(.bottom, -bottomInset)
                    .shadow(color: .black.opacity(0.25), radius: 20)
            }
            .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { gesture in
                guard abs(gesture.translation.height) > abs(gesture.translation.width) else { return }
                if gesture.translation.height < -50 { setListExpanded(true) }
                else if gesture.translation.height > 50 && listIsAtTop { setListExpanded(false) }
            })
        }
    }

    private func setListExpanded(_ value: Bool) {
        guard expanded != value else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.4)) {
            expanded = value
        }
    }

}
