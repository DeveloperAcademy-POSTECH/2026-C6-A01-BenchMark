import SwiftUI

struct HomeView: View {
    let container: AppContainer
    let store: CampusStoryStore
    let myDemo: MYLibraryStore
    let isCameraCoverActive: Bool
    let onOpenProfile: () -> Void
    let onOpenStory: (String) -> Void
    var remote: OiRemoteStore? = nil
    var onCreateStory: (() -> Void)? = nil
    var authoredPlacementToReveal: Binding<UUID?> = .constant(nil)
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scene = CampusExploreScene(stillFrameDelay: .seconds(2))
    @State private var region: CampusRegion?
    @State private var sort = CampusStorySort.latest
    @State private var distances: [String: Float] = [:]
    @State private var expanded = false
    @State private var showingSchools = false
    @State private var searchResults: Set<String>?
    @State private var isOnScreen = false
    @State private var showingSearchChoice = false
    @State private var isSearchCoverActive = false
    @State private var searchMode: CampusSearchMode?
    @State private var pendingStoryID: String?
    @State private var showingNotifications = false
    @State private var listIsAtTop = true
    /// Live vertical drag of the region list: negative grows it, positive pulls it down (#395).
    @State private var listDrag: CGFloat = 0
    @State private var showingEducationDistrict = false
    @State private var loadedAuthoredSource: AuthoredPlacementSource?
    @State private var selectedAuthoredDestination: AuthoredDestination?

    private enum AuthoredDestination: Hashable {
        case personal(UUID)
        case story(UUID)
    }

    private struct AuthoredPlacementSource: Equatable {
        let owner: UUID?
        let stories: [OiLiveStory]
        let localRevision: Int
        let hasLoadedRemote: Bool
    }

    private var authoredPlacementSource: AuthoredPlacementSource {
        guard let remote, let owner = remote.account?.id, remote.canPlaceOi else {
            return AuthoredPlacementSource(owner: nil, stories: [], localRevision: 0, hasLoadedRemote: false)
        }
        return AuthoredPlacementSource(owner: owner, stories: remote.ownStories.filter { $0.userId == owner },
            localRevision: remote.localPlacementRevision, hasLoadedRemote: remote.hasLoadedRemote)
    }

    private var isLoadingStories: Bool {
        guard let remote else { return false }
        return remote.isRefreshing && !remote.hasLoadedRemote
    }

    var body: some View {
        let authoredSource = authoredPlacementSource
        GeometryReader { geometry in
            ZStack {
                CampusMapSurface(scene: scene).ignoresSafeArea().accessibilityHidden(expanded)
                VStack {
                    mapHeader.padding(.horizontal, 20).padding(.top, region == nil ? 9 : 4)
                    Spacer()
                    if region == nil {
                        if let remote, remote.loadError != nil || remote.syncWarning != nil || remote.needsReauthentication {
                            OiConnectionStatus(remote: remote, showsInitialProgress: false)
                                .padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)).padding(.horizontal, 20)
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
                if scene.error == nil && (scene.isLoading || (region == nil && isLoadingStories)) {
                    ProgressView()
                        .accessibilityLabel(scene.isLoading ? "캠퍼스 지도 불러오는 중" : "이야기 불러오는 중")
                }
                if let error = scene.error {
                    ContentUnavailableView { Label("지도를 불러올 수 없어요", systemImage: "map") } description: { Text(error) } actions: {
                        Button("다시 시도") { Task { await scene.load() } }
                    }.background(.regularMaterial)
                }
            }
            // Keep the RealityKit viewport fixed while the list changes height.
            .overlay(alignment: .bottom) {
                if let region {
                    regionPanel(region, availableHeight: geometry.size.height, bottomInset: geometry.safeAreaInsets.bottom)
                        .transition(.move(edge: .bottom))
                }
            }
            // The list slides up when a bubble opens it and back down when it closes (#395).
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: region == nil)
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
                MYWorkshopView(demo: myDemo, remote: remote)
            case .cucumberCustomization:
                OiSeedCucumberCustomizationView()
                    .toolbar(.visible, for: .navigationBar)
            case .farm: MYFarmView(remote: remote).id(remote?.account?.id)
            case .collection: MYCollectionView(demo: myDemo, storyRepository: container.storyRepository, remote: remote).id(remote?.account?.id)
            case .school(let school): MYCollectionView(demo: myDemo, school: school, storyRepository: container.storyRepository, remote: remote).id(remote?.account?.id)
            }
        }
        .sheet(isPresented: $showingEducationDistrict, onDismiss: { scene.finishEducationDistrict() }) {
            CampusEducationDistrictView { covered in
                if covered { scene.suspendRendering() }
                else { scene.setVisible(isOnScreen && !isCameraCoverActive && scenePhase == .active) }
            }
        }
        .navigationDestination(item: $selectedAuthoredDestination) { destination in
            if let remote, remote.canPlaceOi {
                switch destination {
                case .personal(let id): OiStoryEditor(remote: remote, localID: id)
                case .story(let id): OiStoryManagement(remote: remote, storyID: id)
                }
            }
        }
        .sheet(isPresented: $showingSchools) {
            CampusSchoolSearchView {
                showingSchools = false; region = nil; expanded = false; searchResults = nil
                scene.showOverview()
            }
        }
        .accessibilityHidden(showingSearchChoice)
        .overlay {
            if showingSearchChoice {
                CampusSearchChoiceSheet(choose: { mode in
                    showingSearchChoice = false
                    isSearchCoverActive = true
                    scene.suspendRendering()
                    searchMode = mode
                }, dismiss: { showingSearchChoice = false })
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: showingSearchChoice)
        .fullScreenCover(item: $searchMode, onDismiss: {
            // Push only after the search cover has gone, so it cannot cover the destination.
            isSearchCoverActive = false
            if let id = pendingStoryID { pendingStoryID = nil; openStory(id) }
            else { updateMapVisibility() }
        }) { mode in
            CampusSearchView(mode: mode, entries: searchEntries, isExample: store.isExample, remote: remote) {
                pendingStoryID = $0.id; searchMode = nil
            }
        }
        .sheet(isPresented: $showingNotifications) {
            if let remote { CampusNotificationSheet(remote: remote).id(remote.account?.id) }
        }
        .task {
            configureSceneCallbacks()
            scene.setOverviewStories(store.stories)
            await scene.load()
        }
        .task(id: authoredSource) { await loadAuthoredPlacements(authoredSource) }
        .task(id: region?.id) {
            guard let region, let remote else { return }
            do {
                try await Task.sleep(for: .milliseconds(2500))
                guard !ProcessInfo.processInfo.isLowPowerModeEnabled,
                      ProcessInfo.processInfo.thermalState == .nominal else { return }
                for story in store.stories(in: region.id, sortedBy: .latest).prefix(1) {
                    try Task.checkCancellation()
                    if let path = story.cardArtworkPath { _ = try? await remote.postcardImage(path) }
                    else if let path = story.remoteMediaPaths.first, let resolver = store.mediaURL {
                        _ = try? await remote.postcardPhotoImage(path, loadURL: resolver)
                    }
                }
            } catch { }
        }
        .onAppear {
            pruneAuthoredPlacements(authoredSource)
            isOnScreen = true
            updateMapVisibility()
            revealAuthoredPlacement()
        }
        .onChange(of: authoredSource) { _, source in
            pruneAuthoredPlacements(source)
            revealAuthoredPlacement()
        }
        .onChange(of: scene.ready) { _, _ in revealAuthoredPlacement() }
        .onChange(of: authoredPlacementToReveal.wrappedValue) { _, id in
            if id != nil { selectedAuthoredDestination = nil }
            revealAuthoredPlacement()
        }
        .onDisappear { isOnScreen = false; scene.suspendRendering() }
        .onChange(of: scenePhase) { _, _ in updateMapVisibility() }
        .onChange(of: isCameraCoverActive) { _, _ in updateMapVisibility() }
        .onChange(of: store.stories) { _, stories in
            scene.setOverviewStories(stories)
            if let region {
                scene.showStoriesInCurrentArea(region, stories: searchResults == nil ? store.stories(in: region.id, sortedBy: sort) : stories)
                if searchResults != nil { searchResults = scene.visibleStoryIDs() }
            }
        }
    }

    private func updateMapVisibility() {
        if !isOnScreen || isCameraCoverActive || isSearchCoverActive || scenePhase == .background {
            scene.suspendRendering()
        } else {
            scene.setVisible(scenePhase == .active)
        }
    }

    private func configureSceneCallbacks() {
        scene.onEducationDistrict = { showingEducationDistrict = true }
        if let remote {
            scene.loadCucumberPortrait = { try await remote.cucumberImage($0) }
            scene.loadCucumberModel = { try await remote.cucumberModel($0) }
            scene.loadPublicCucumberModel = { story in
                guard let published = remote.stories.first(where: { $0.id.uuidString == story.id }),
                      let artwork = published.cucumberArtwork,
                      artwork.path(.portrait) == story.cucumberPortraitPath else { throw OiServiceError.unavailable }
                return try await remote.cucumberModel(artwork)
            }
        }
        scene.onRegion = { selected in
            region = selected; sort = .latest; expanded = false; searchResults = nil
            scene.focus(selected, stories: store.stories(in: selected.id, sortedBy: .latest), animated: true)
            distances = scene.distances()
        }
        // Tapping the map outside the list closes it, as the removed back button did (#395).
        scene.onEmptyMapTap = { if region != nil { closeRegionList() } }
        scene.onStory = { id in
            guard store.story(id) != nil else { return }
            // Use the same value-based path as list links and the summary's detail link.
            openStory(id)
        }
        scene.onAuthoredPlacement = { id in
            let source = authoredPlacementSource
            guard let owner = source.owner, loadedAuthoredSource?.owner == owner,
                  let item = scene.authoredPlacement(id: id) else { return }
            if item.visibility == .published, store.story(id.uuidString) != nil {
                openStory(id.uuidString)
            } else {
                scene.suspendRendering()
                selectedAuthoredDestination = source.stories.contains(where: { $0.id == id }) ? .story(id) : .personal(id)
            }
        }
    }

    private func pruneAuthoredPlacements(_ source: AuthoredPlacementSource) {
        guard loadedAuthoredSource?.owner != source.owner else { return }
        loadedAuthoredSource = nil
        selectedAuthoredDestination = nil
        scene.setAuthoredPlacements([])
    }

    private func loadAuthoredPlacements(_ source: AuthoredPlacementSource) async {
        guard let remote, let owner = source.owner else { return }
        let drafts = (try? await remote.localDraftListing())?.drafts ?? []
        guard !Task.isCancelled, authoredPlacementSource == source else { return }

        let stories = source.stories.reduce(into: [UUID: OiLiveStory]()) { $0[$1.id] = $1 }
        let records = drafts.reduce(into: [UUID: OiLocalDraft]()) { $0[$1.id] = $1 }
        var placements = source.stories.compactMap { story in
            CampusAuthoredPlacement(story: story, owner: owner, localDraft: records[story.id])
        }
        let personal = records.values.compactMap { record -> CampusAuthoredPlacement? in
            let story = stories[record.id]
            // A successfully submitted story that disappeared after sync was deleted.
            guard !record.submitted || !source.hasLoadedRemote || story != nil else { return nil }
            return CampusAuthoredPlacement(personal: record, story: story)
        }
        placements.append(contentsOf: personal) // A confirmed device position takes precedence on the owner's map.
        pruneAuthoredPlacements(source)
        scene.setAuthoredPlacements(placements)
        loadedAuthoredSource = source
        revealAuthoredPlacement()
        await scene.loadAuthoredModels()
    }

    private func revealAuthoredPlacement() {
        let source = authoredPlacementSource
        guard isOnScreen, scene.ready, loadedAuthoredSource == source,
              let id = authoredPlacementToReveal.wrappedValue else { return }
        let item = scene.authoredPlacement(id: id)
        let story = source.stories.first { $0.id == id && $0.isRegisteredOnCampus }
        guard let placement = item?.placement ?? story?.campusPlacement,
              let selectedRegion = CampusRegion.campus.first(where: { $0.id == (item?.regionID ?? story?.regionId) }) ?? scene.nearestRegion()
        else { return }
        region = selectedRegion; expanded = false; sort = .latest; searchResults = nil
        scene.focus(selectedRegion, stories: store.stories(in: selectedRegion.id, sortedBy: .latest), placement: placement)
        distances = scene.distances()
        authoredPlacementToReveal.wrappedValue = nil
    }

    private func configureMapLabels(_ geometry: GeometryProxy) {
        let bottom = region == nil ? 8 : regionPanelHeight(geometry.size.height) + 58
        let bottomY = geometry.size.height + geometry.safeAreaInsets.top
        let controls = region == nil ? [
            CGRect(x: 22, y: bottomY - 108, width: 108, height: 112),
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
                    CampusMyHouseButtonArtwork()
                }.buttonStyle(CampusMyHouseButtonStyle())
                    .accessibilityLabel("MY 작업실 열기").accessibilityIdentifier("campus.workshop")
            }.disabled(store.isExample)
            Spacer()
            VStack(spacing: 10) {
                if remote != nil {
                    mapAction("envelope", label: "알림", id: "campus.notifications") { showingNotifications = true }
                }
                mapAction("magnifyingglass", label: "오이 검색", id: "campus.search",
                    background: "CampusMapSearchBackground") { showingSearchChoice = true }
                Button { onCreateStory?() } label: {
                    Image("CampusAddOi").renderingMode(.original).frame(width: 60, height: 60)
                        .contentShape(Circle())
                }.buttonStyle(.plain).accessibilityLabel("오이 심기 · 이야기 목록")
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
            if story.isExample { return CampusSearchEntry.example(story) }
            let author = remote?.profiles.first { $0.id == live?.userId }
            // Search the donor's declared school, not the campus where the cucumber was placed.
            let schoolID = author?.schoolId
            let school = remote?.schools.first { $0.id == schoolID }?.name ?? ""
            return CampusSearchEntry(story: story, publicID: UUID(uuidString: story.id), cucumberName: story.title,
                code: story.id, school: school + (schoolID == "postech" ? " 포스텍 포항공과대학교" : ""),
                department: author?.department ?? "", year: author?.admissionYear ?? "", donorName: author?.publicName ?? "")
        }
    }

    private func searchVisibleArea() {
        guard let closest = scene.nearestRegion() else { return }
        region = closest; expanded = false
        scene.showStoriesInCurrentArea(closest, stories: store.stories)
        distances = scene.distances(); searchResults = scene.visibleStoryIDs()
    }

    private func openStory(_ id: String) {
        // The summary uses its own non-AR renderer. Release this one before the push,
        // just as for AR, then rebuild it with the saved camera values on return.
        scene.suspendRendering()
        onOpenStory(id)
    }

    private var mapHeader: some View {
        HStack(alignment: .top) {
            if region != nil {
                // No back button (#395): tap the map outside the list or swipe the list down to close it.
                Spacer().frame(height: 50)
            } else {
                Button { showingSchools = true } label: {
                    HStack(spacing: 8) {
                        Image("CampusSchoolIcon").renderingMode(.original).frame(width: 16, height: 16)
                        Text("POSTECH 농장").font(CampusStyle.semibold(18)).lineLimit(1).minimumScaleFactor(0.7)
                    }.padding(.horizontal, 14).frame(height: 42)
                }
                .buttonStyle(.plain).glassEffect(.clear.interactive(), in: Capsule())
                .accessibilityLabel("캠퍼스 선택").accessibilityIdentifier("campus.school")
                Spacer()
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
        let restingHeight = regionPanelHeight(availableHeight)
        let tallest = max(200, availableHeight - 68)
        // The list follows the finger: pulling up grows it toward the tall height, pulling down slides it.
        let height = listDrag < 0 ? min(tallest, restingHeight - listDrag) : restingHeight
        return VStack(spacing: 9.5) {
            VStack(spacing: 20) {
                HStack(spacing: 7) {
                    ForEach([CampusStorySort.latest, .oldest], id: \.self) { item in
                        Button { sort = item; distances = scene.distances() } label: {
                            Text(item.rawValue).font(CampusStyle.body(16)).tracking(0.32)
                                .padding(.horizontal, 12).frame(height: 29)
                                .foregroundStyle(sort == item ? .white : .black)
                                .background(sort == item ? CampusStyle.sectionGreen : .white, in: Capsule())
                                .frame(minHeight: 44).contentShape(Capsule())
                        }.buttonStyle(.plain).accessibilityAddTraits(sort == item ? .isSelected : [])
                    }
                    Spacer(minLength: 0)
                    // Secondary sort choices stay available without adding an extra icon to the design.
                    Menu {
                        Button("거리순") { sort = .distance; distances = scene.distances() }
                        Button("인기순") { sort = .popular }
                    } label: {
                        Text("공개 \(items.count)개").font(CampusStyle.medium(16)).tracking(0.32)
                            .foregroundStyle(.black)
                            .padding(.horizontal, 16).frame(minWidth: 68).frame(height: 29)
                            .background(CampusStyle.secondaryAction, in: Capsule())
                            .frame(minHeight: 44).contentShape(Capsule())
                    }.accessibilityLabel("공개 오이 \(items.count)개, 다른 정렬")
                }.padding(.vertical, -7.5)
                if sort == .distance || sort == .popular {
                    Text(sort == .distance ? "지도 중심에서 가까운 순서" : "인기순")
                        .font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }
                if let remote { OiConnectionStatus(remote: remote) }
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if items.isEmpty, remote == nil || remote?.hasLoadedRemote == true {
                            Text("이 화면에는 공개된 오이가 없어요. 지도를 움직여 다시 검색해 주세요.")
                                .font(CampusStyle.body(14)).foregroundStyle(.secondary).padding()
                        }
                        ForEach(items) { story in
                            Button { openStory(story.id) } label: { CampusStoryRow(story: story) }
                                .buttonStyle(.plain).accessibilityIdentifier("campus.row.\(story.id)")
                        }
                    }.padding(.bottom, 12)
                }.scrollIndicators(.hidden)
                    // At the default height a drag moves the list itself instead of scrolling its rows.
                    .scrollDisabled(!expanded)
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
            .offset(y: max(0, listDrag))
            .simultaneousGesture(DragGesture(minimumDistance: 8)
                .onChanged { gesture in
                    let dy = gesture.translation.height
                    guard abs(dy) > abs(gesture.translation.width) else { return }
                    // A tall list scrolls its rows upward; it only follows a downward pull from the top.
                    if dy < 0 { listDrag = expanded ? 0 : dy }
                    else { listDrag = listIsAtTop ? dy : 0 }
                }
                .onEnded { gesture in
                    // Decide from where the flick would land so a quick swipe responds at once.
                    let landing = gesture.predictedEndTranslation.height
                    let pulled = listDrag
                    if pulled < 0, landing < -60 {
                        setListExpanded(true)
                    } else if pulled > 0, landing > 60 {
                        // Down steps back: a tall list first returns to its default height, then closes (#395).
                        if expanded { setListExpanded(false) } else { closeRegionList(); return }
                    }
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.25)) { listDrag = 0 }
                })
            .accessibilityAction(named: "목록 닫기") { closeRegionList() }
            .accessibilityAction(named: expanded ? "목록 줄이기" : "목록 크게 보기") { setListExpanded(!expanded) }
        }
    }

    /// Closes the region list and keeps the map exactly where it was (#395).
    private func closeRegionList() {
        region = nil; expanded = false; searchResults = nil
        scene.showOverview(keepingCamera: true)
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { listDrag = 0 }
    }

    private func setListExpanded(_ value: Bool) {
        guard expanded != value else { return }
        withAnimation(reduceMotion ? nil : .spring(duration: 0.3)) {
            expanded = value
            listDrag = 0
        }
    }

}

struct CampusMyHouseButtonArtwork: View {
    var body: some View {
        // Figma 5934:4877 includes the 100pt circle, house, border and 17pt shadow margin.
        Image("CampusMyHouseButton").resizable().renderingMode(.original).scaledToFit()
            .frame(width: 134, height: 134)
            .frame(width: 100, height: 100)
            .contentShape(Circle())
    }
}

struct CampusMyHouseButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        makeBody(label: configuration.label, isPressed: configuration.isPressed, isEnabled: isEnabled)
    }

    func makeBody<Label: View>(label: Label, isPressed: Bool, isEnabled: Bool = true) -> some View {
        let pressedOpacity = isPressed ? 0.8 : 1.0
        return label.opacity(isEnabled ? pressedOpacity : 0.45)
    }
}
