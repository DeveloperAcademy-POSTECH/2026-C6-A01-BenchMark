import AuthenticationServices
import SwiftUI

struct RootTabView: View {
    let container: AppContainer
    @State private var path = NavigationPath()
    @State private var store = CampusStoryStore()
    @State private var myDemo = MYLibraryStore()
    @State private var isARPresented = false
    @State private var isCameraCoverActive = false
    @State private var remote: OiRemoteStore
    @State private var showingStoryList = false
    @State private var authoredPlacementToReveal: UUID?
    @State private var photoSubject: ARCameraSubject?
    @State private var pendingStoryList = false
    /// 수집하기 pressed over the AR camera: the scratch screen opens once the camera closes.
    @State private var pendingScratchStoryID: String?
    @State private var plantedSelectionCover: OiStoryPlantSelection?
    @State private var plantedSelectionOpacity = 1.0
    @State private var showingPlantConfirmation = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(container: AppContainer = .pilot, remote: OiRemoteStore? = nil) {
        self.container = container
        _remote = State(initialValue: remote ?? OiRemoteStore())
    }

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(
                container: container,
                store: store,
                myDemo: myDemo,
                isCameraCoverActive: isCameraCoverActive,
                onOpenProfile: { path.append(MYDestination.workshop) },
                onOpenStory: { path.append(CampusDestination.summary($0)) },
                remote: remote,
                onCreateStory: { showingStoryList = true },
                authoredPlacementToReveal: $authoredPlacementToReveal
            )
            .navigationDestination(isPresented: $showingStoryList) {
                OiStoryListScreen(remote: remote)
            }
            .navigationDestination(for: CampusDestination.self) { destination in
                switch destination {
                case .summary(let id):
                    if let story = store.story(id) {
                        summaryView(story)
                    } else {
                        ContentUnavailableView("이야기를 볼 수 없어요", systemImage: "doc")
                    }
                case .story(let id):
                    if let story = store.story(id) {
                        CampusCucumberStoryView(story: story, store: store)
                    } else {
                        ContentUnavailableView("이야기를 볼 수 없어요", systemImage: "doc")
                    }
                case .scratch(let id):
                    if let story = store.story(id) {
                        CampusScratchScreen(story: story, repository: container.storyRepository, remote: remote,
                                            onDonate: {
                                                let continuation = OiStoryContinuationIntent(story: story, requestedBy: remote.account?.id)
                                                path.append(CampusDestination.storyList(continuation: continuation))
                                            },
                                            onSaved: {
                                                // 앨범에 저장하기 → MY 수집한 기부.
                                                var next = NavigationPath()
                                                next.append(MYDestination.collectedWorkshop)
                                                path = next
                                            })
                    } else {
                        ContentUnavailableView("이야기를 볼 수 없어요", systemImage: "doc")
                    }
                case .storyList(let continuation):
                    OiStoryListScreen(remote: remote, continuation: continuation)
                }
            }
            .navigationDestination(for: PublicLinkParser.Destination.self) { publicDestination($0) }
            .navigationDestination(for: CampusNFCPostcardRoute.self) { route in
                CampusNFCPostcardView(route: route, repository: container.storyRepository, store: store, remote: remote) {
                    summaryView($0)
                }
            }
        }
        .tint(.black)
        .environment(\.exploreCampusForCoins, {
            showingStoryList = false
            path = NavigationPath()
        })
        .overlay(alignment: .top) { OiCoinAwardOverlay(remote: remote) }
        .overlay { plantedSelectionOverlay }
        .alert("이야기가 등록됐어요", isPresented: $showingPlantConfirmation) {
            Button("확인", role: .cancel) {}
        }
        .onChange(of: OiContentSafetyStore.shared.authors) { _, _ in
            synchronizeRemote()
            if let photoSubject, let author = store.story(photoSubject.id.uuidString)?.authorID,
               OiContentSafetyStore.shared.isBlocked(author) { isARPresented = false }
        }
        .onChange(of: remote.revision) { _, _ in synchronizeRemote() }
        // The App Clip may have collected cards since MY was last built; the records are read again on each screen change.
        .onChange(of: path.count) { _, _ in synchronizeRemote() }
        .onChange(of: myDemo.clipCollection.cards) { _, _ in synchronizeRemote() }
        .onChange(of: remote.account?.id) { _, _ in
            authoredPlacementToReveal = nil
            plantedSelectionCover = nil
            showingPlantConfirmation = false
            myDemo.resetFilters()
            synchronizeRemote()
        }
        .onReceive(NotificationCenter.default.publisher(for: ASAuthorizationAppleIDProvider.credentialRevokedNotification)) { _ in
            guard remote.accountProviders.contains("apple") else { return }
            Task { await remote.signOut() }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            OiContentSafetyStore.shared.reload()
            store.collectAction = { story in
                if isARPresented {
                    pendingScratchStoryID = story.id
                    isARPresented = false
                } else { path.append(CampusDestination.scratch(story.id)) }
            }
            store.createStoryAction = {
                if isARPresented {
                    pendingStoryList = true
                    isARPresented = false
                } else { showingStoryList = true }
            }
            store.showAuthoredPlacementAction = { id in
                // Home resolves this navigation intent against the current account's placements.
                guard remote.canPlaceOi else { return }
                revealPlacement(id)
            }
            store.mediaURL = { path in try await remote.mediaURL(bucket: "oi-story-media", path: path) }
            myDemo.campusStore = store
            myDemo.favoriteAction = { card in
                guard let id = UUID(uuidString: card.id) else { return }
                Task { await remote.perform("favorite", payload: ["id": card.id, "enabled": !remote.favorites.contains(id)]) }
            }
            if remote.isConfigured { await remote.refresh() } else { await remote.start() }
            // A Clip write does not change the remote revision. Always re-read it on foreground return.
            synchronizeRemote()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                await remote.refresh(reuseCatalog: true)
            }
        }
        .preferredColorScheme(.light)
        .fullScreenCover(isPresented: $isARPresented, onDismiss: {
            // Restore the map only after the camera's dismissal has finished.
            isCameraCoverActive = false
            photoSubject = nil
            if pendingStoryList { pendingStoryList = false; showingStoryList = true }
            if let id = pendingScratchStoryID { pendingScratchStoryID = nil; path.append(CampusDestination.scratch(id)) }
        }) {
            if let photoSubject {
                ARCameraScreen(subject: photoSubject).id(photoSubject.id)
            }
        }
        .onOpenURL { handlePublicLink($0) }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            if let url = activity.webpageURL { handlePublicLink(url) }
        }
        .environment(remote)
        .environment(store)
        .environment(\.revealPlantedStory, revealPlantedPlacement)
        .environment(\.campusCucumberPortraitLoader, { try await remote.cucumberImage($0) })
    }

    private func revealPlacement(_ id: UUID) {
        authoredPlacementToReveal = id
        showingStoryList = false
        path = NavigationPath()
    }

    private func revealPlantedPlacement(_ selection: OiStoryPlantSelection) {
        guard remote.canPlaceOi else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            plantedSelectionOpacity = 1
            plantedSelectionCover = reduceMotion ? nil : selection
            revealPlacement(selection.selectedID)
        }
        if reduceMotion { showingPlantConfirmation = true }
    }

    @ViewBuilder private var plantedSelectionOverlay: some View {
        if let selection = plantedSelectionCover {
            NavigationStack {
                OiStoryListView(state: .content(selection.items), minimumVisibleSlotCount: 0,
                    reviewState: { _ in .approved }, onPlant: {}, canPlant: true,
                    selectedPlantStoryID: selection.selectedID, onCancelPlant: {},
                    portraitAccountID: remote.account?.id,
                    loadPortrait: { try await remote.cucumberImage($0) })
            }
            .opacity(plantedSelectionOpacity)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
            .task(id: selection.selectedID) {
                await Task.yield()
                guard !Task.isCancelled else { return }
                // Figma 6101:9395 dissolves to the map over 300 ms after a successful planting.
                withAnimation(.easeInOut(duration: 0.3), completionCriteria: .removed) {
                    plantedSelectionOpacity = 0
                } completion: {
                    guard plantedSelectionCover?.selectedID == selection.selectedID else { return }
                    plantedSelectionCover = nil
                    showingPlantConfirmation = true
                }
            }
        }
    }

    private func synchronizeRemote() {
        let mapped = remote.stories.enumerated().map { index, item in
            remote.campusStory(item, order: index)
        }
        store.synchronize(stories: mapped, collected: Set(remote.collections.map { $0.storyId.uuidString }))
        if let photoSubject {
            let current = store.story(photoSubject.id.uuidString).flatMap {
                CampusCucumberCameraSubject.make(story: $0, remote: remote)
            }
            if current == nil || current?.placement != photoSubject.placement { isARPresented = false }
        }
        myDemo.synchronizeCollectedCards(from: remote)
    }

    /// The map's cucumber summary (Figma 5400:5071), also opened by NFC postcard tags (#324).
    private func summaryView(_ story: CampusStory) -> some View {
        CampusSummaryView(story: story, store: store, isCameraCoverActive: isCameraCoverActive)
            .toolbar {
                if UUID(uuidString: story.id) != nil && !story.isExample && story.latitude != nil && story.longitude != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("3D", systemImage: "arkit") {
                            guard let subject = CampusCucumberCameraSubject.make(story: story, remote: remote) else { return }
                            photoSubject = subject
                            isCameraCoverActive = true
                            isARPresented = true
                        }
                        .accessibilityLabel("선택한 오이로 AR 촬영")
                        .accessibilityIdentifier("campus.summary.arCamera")
                    }
                }
            }
    }

    private func handlePublicLink(_ url: URL) {
        // An NFC postcard tag opens the linked story's summary instead of the App Clip story list.
        if let tag = AppClipLink.postcardID(in: url) {
            path = NavigationPath()
            pendingStoryList = false
            isARPresented = false
            path.append(CampusNFCPostcardRoute(tagID: tag))
            return
        }
        // The default and `story=` App Clip links open the map home; the old story list is gone (#351).
        if AppClipLink.matches(url) {
            path = NavigationPath()
            pendingStoryList = false
            isARPresented = false
            return
        }
        if let host = container.approvedLinkHost,
                  let destination = PublicLinkParser(allowedHost: host).parse(url) {
            path = NavigationPath()
            path.append(destination)
        }
    }

    private func publicDestination(_ destination: PublicLinkParser.Destination) -> some View {
        PublicDestinationView(destination: destination, benches: container.benchRepository, stories: container.storyRepository)
    }
}

#Preview { RootTabView(container: .preview) }
