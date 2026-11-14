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
    @State private var geoPlacement: CampusPlacement?
    @State private var collectionStory: CampusStory?
    @State private var collectionReturnsToAR = false
    @State private var pendingStoryList = false
    @Environment(\.scenePhase) private var scenePhase

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
            .navigationDestination(for: AppClipInvocation.self) { invocation in
                AppClipExperienceView(storyRepository: container.storyRepository, invocation: invocation) { story, id in
                    OiStorySafetyButton(storyID: id, authorID: story.donorID, authorName: story.donorDisplayName)
                }
                .navigationTitle("이야기·AR")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .tint(.black)
        .onChange(of: OiContentSafetyStore.shared.authors) { _, _ in
            synchronizeRemote()
            if let author = collectionStory?.authorID, OiContentSafetyStore.shared.isBlocked(author) {
                isARPresented = false
            }
        }
        .onChange(of: remote.revision) { _, _ in synchronizeRemote() }
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
            geoPlacement = nil
            if pendingStoryList { pendingStoryList = false; showingStoryList = true }
        }) {
            if let collectionStory {
                CampusCollectionGameHost(story: collectionStory, remote: remote, store: store) {
                    if collectionReturnsToAR { self.collectionStory = nil }
                    else { isARPresented = false }
                }
            } else if let geoPlacement {
                CampusGeoARScreen(placement: geoPlacement, stories: store, remote: remote)
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

    private func openGeoStory(_ story: CampusStory) {
        guard let id = UUID(uuidString: story.id), let latitude = story.latitude, let longitude = story.longitude else { return }
        geoPlacement = CampusPlacement(id: id, storyID: story.id, latitude: latitude, longitude: longitude)
        isCameraCoverActive = true
        isARPresented = true
    }

    private func synchronizeRemote() {
        let mapped = remote.stories.enumerated().map { index, item in
            remote.campusStory(item, order: index)
        }
        store.synchronize(stories: mapped, collected: Set(remote.collections.map { $0.storyId.uuidString }))
        let cards = remote.collections.enumerated().compactMap { index, collection -> MYCard? in
            guard let story = remote.stories.first(where: { $0.id == collection.storyId }) else { return nil }
            guard let region = remote.regions.first(where: { $0.id == story.regionId }),
                  let school = remote.schools.first(where: { $0.id == region.schoolId }) else { return nil }
            return MYCard(id: story.id.uuidString, title: story.cucumberName, image: story.cucumberAsset,
                school: MYSchool(id: school.id, name: school.name), order: index,
                body: story.body, donor: remote.profiles.first(where: { $0.id == story.userId })?.nickname ?? "농부",
                date: story.createdDateLabel, storyID: story.id.uuidString, appearance: story.cardAsset,
                cucumberPortraitPath: story.cucumberArtwork?.path(.portrait), cardArtworkPath: story.cardArtworkPath)
        }
        myDemo.synchronize(nickname: remote.profile?.nickname ?? "농부", cards: cards,
            favorites: Set(remote.favorites.map(\.uuidString)))
    }

    /// The map's cucumber summary (Figma 5400:5071), also opened by NFC postcard tags (#324).
    private func summaryView(_ story: CampusStory) -> some View {
        CampusSummaryView(story: story, store: store, isCameraCoverActive: isCameraCoverActive)
            .toolbar {
                if story.latitude != nil && story.longitude != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("현장 AR", systemImage: "arkit") { openGeoStory(story) }
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
        if AppClipLink.matches(url) {
            path = NavigationPath()
            pendingStoryList = false
            isARPresented = false
            path.append(AppClipInvocation(url: url))
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
