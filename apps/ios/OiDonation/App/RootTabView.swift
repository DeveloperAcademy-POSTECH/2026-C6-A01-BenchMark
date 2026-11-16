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
    @State private var collectionStory: CampusStory?
    @State private var collectionReturnsToAR = false
    @State private var pendingStoryList = false
    @Environment(\.scenePhase) private var scenePhase
    /// Cards collected in the App Clip, shown with the account's saved cards in MY `수집한 기부` (#409).
    @State private var clipCollection = StoryCollectionStore()

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
                        CampusStoryDetailView(story: story, store: store)
                    } else {
                        ContentUnavailableView("이야기를 볼 수 없어요", systemImage: "doc")
                    }
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
        .onChange(of: OiContentSafetyStore.shared.authors) { _, _ in
            synchronizeRemote()
            if let author = collectionStory?.authorID, OiContentSafetyStore.shared.isBlocked(author) {
                isARPresented = false
            }
            if let photoSubject, let author = store.story(photoSubject.id.uuidString)?.authorID,
               OiContentSafetyStore.shared.isBlocked(author) { isARPresented = false }
        }
        .onChange(of: remote.revision) { _, _ in synchronizeRemote() }
        // The App Clip may have collected cards since MY was last built; the records are read again on each screen change.
        .onChange(of: path.count) { _, _ in synchronizeRemote() }
        .onChange(of: remote.account?.id) { _, _ in
            authoredPlacementToReveal = nil
            myDemo.resetFilters()
        }
        .onReceive(NotificationCenter.default.publisher(for: ASAuthorizationAppleIDProvider.credentialRevokedNotification)) { _ in
            guard remote.accountProviders.contains("apple") else { return }
            Task { await remote.signOut() }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            OiContentSafetyStore.shared.reload()
            store.collectAction = { story in
                guard collectionStory == nil else { return }
                collectionReturnsToAR = isARPresented
                collectionStory = story
                isCameraCoverActive = true
                isARPresented = true
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
                authoredPlacementToReveal = id
                showingStoryList = false
                path = NavigationPath()
            }
            store.mediaURL = { path in try await remote.mediaURL(bucket: "oi-story-media", path: path) }
            myDemo.campusStore = store
            myDemo.favoriteAction = { card in
                guard let id = UUID(uuidString: card.id) else { return }
                Task { await remote.perform("favorite", payload: ["id": card.id, "enabled": !remote.favorites.contains(id)]) }
            }
            if remote.isConfigured { await remote.refresh() } else { await remote.start() }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                await remote.refresh(reuseCatalog: true)
            }
        }
        .preferredColorScheme(.light)
        .fullScreenCover(isPresented: $isARPresented, onDismiss: {
            // Restore the map only after the camera's dismissal has finished.
            isCameraCoverActive = false
            collectionStory = nil
            photoSubject = nil
            if pendingStoryList { pendingStoryList = false; showingStoryList = true }
        }) {
            if let collectionStory {
                CampusCollectionGameHost(story: collectionStory, remote: remote, store: store) {
                    if collectionReturnsToAR { self.collectionStory = nil }
                    else { isARPresented = false }
                }
            } else if let photoSubject {
                ARCameraScreen(subject: photoSubject).id(photoSubject.id)
            }
        }
        .onOpenURL { handlePublicLink($0) }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            if let url = activity.webpageURL { handlePublicLink(url) }
        }
        .environment(remote)
        .environment(store)
        .environment(\.campusCucumberPortraitLoader, { try await remote.cucumberImage($0) })
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
        func entry(for story: OiLiveStory, collectedAt: Date?) -> MYCollectedCardEntry? {
            guard let region = remote.regions.first(where: { $0.id == story.regionId }),
                  let school = remote.schools.first(where: { $0.id == region.schoolId }) else { return nil }
            let card = MYCard(id: story.id.uuidString, title: story.cucumberName, image: story.cucumberAsset,
                school: MYSchool(id: school.id, name: school.name), order: 0,
                body: story.body, donor: remote.profiles.first(where: { $0.id == story.userId })?.nickname ?? "농부",
                date: story.createdDateLabel, storyID: story.id.uuidString, appearance: story.cardAsset,
                cucumberPortraitPath: story.cucumberArtwork?.path(.portrait), cardArtworkPath: story.cardArtworkPath)
            return MYCollectedCardEntry(card: card, collectedAt: collectedAt)
        }
        clipCollection.reload()
        let accountEntries = remote.collections.compactMap { collection -> MYCollectedCardEntry? in
            guard let story = remote.stories.first(where: { $0.id == collection.storyId }) else { return nil }
            return entry(for: story, collectedAt: MYCollectedCards.date(from: collection.createdAt))
        }
        // A private, deleted or blocked story is skipped here; its record stays on the device.
        let clipEntries = clipCollection.cards.compactMap { record -> MYCollectedCardEntry? in
            guard let id = UUID(uuidString: record.storyID),
                  let story = remote.stories.first(where: { $0.id == id }) else { return nil }
            return entry(for: story, collectedAt: record.collectedAt)
        }
        let cards = MYCollectedCards.merged(account: accountEntries, clip: clipEntries)
        myDemo.synchronize(nickname: remote.profile?.nickname ?? "농부", cards: cards,
            favorites: Set(remote.favorites.map(\.uuidString)))
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
