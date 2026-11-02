import SwiftUI

struct RootTabView: View {
    let container: AppContainer
    @State private var path = NavigationPath()
    @State private var store = CampusStoryStore()
    @State private var myDemo = MYDemoStore()
    @State private var isARPresented = false
    @State private var isCameraCoverActive = false
    @State private var remote = OiRemoteStore()
    @State private var showingAccount = false
    @State private var geoPlacement: CampusPlacement?
    @Environment(\.scenePhase) private var scenePhase

    init(container: AppContainer = .pilot) {
        self.container = container
        _store = State(initialValue: CampusStoryStore(loadExamples: container.showsDesignExamples))
        _myDemo = State(initialValue: MYDemoStore(loadExamples: container.showsDesignExamples))
    }

    var body: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-story-list-preview") {
            OiStoryListPreviewHost(state: storyListPreviewState)
        } else {
            appContent
        }
        #else
        appContent
        #endif
    }

    #if DEBUG
    private var storyListPreviewState: OiStoryListState {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-story-list-preview-loading") { return .loading }
        if arguments.contains("-story-list-preview-empty") { return .empty }
        if arguments.contains("-story-list-preview-error") {
            return .failure("네트워크 연결을 확인한 뒤 다시 시도해 주세요.")
        }
        if arguments.contains("-story-list-preview-long") { return .layoutStressPreview }
        return .preview
    }
    #endif

    private var appContent: some View {
        NavigationStack(path: $path) {
            HomeView(
                container: container,
                store: store,
                myDemo: myDemo,
                isCameraCoverActive: isCameraCoverActive,
                onCamera: { geoPlacement = nil; path = NavigationPath(); isCameraCoverActive = true; isARPresented = true },
                onOpenProfile: { path.append(MYDestination.workshop) },
                onOpenStory: { path.append(CampusDestination.summary($0)) },
                remote: container.showsDesignExamples ? nil : remote,
                onAccount: { showingAccount = true }
            )
            .navigationDestination(for: CampusDestination.self) { destination in
                switch destination {
                case .summary(let id):
                    if let story = store.story(id) {
                        CampusSummaryView(story: story, store: store)
                            .toolbar {
                                if story.latitude != nil && story.longitude != nil {
                                    ToolbarItem(placement: .topBarTrailing) {
                                        Button("현장 AR", systemImage: "arkit") { openGeoStory(story) }
                                    }
                                }
                            }
                    }
                case .story(let id):
                    if let story = store.story(id) { CampusStoryDetailView(story: story, store: store) }
                }
            }
            .navigationDestination(for: PublicLinkParser.Destination.self) { publicDestination($0) }
        }
        .tint(.black)
        .sheet(isPresented: $showingAccount) { NavigationStack { OiAccountView(remote: remote) }.id(remote.account?.id) }
        .onChange(of: remote.revision) { _, _ in synchronizeRemote() }
        .onChange(of: remote.account?.id) { _, _ in path = NavigationPath(); myDemo.collectionFilter = .all }
        .task(id: scenePhase) {
            guard !container.showsDesignExamples, scenePhase == .active else { return }
            store.collectAction = { story in
                Task { await remote.perform("collect", payload: ["id": story.id]) }
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
                await remote.refresh()
            }
        }
        .preferredColorScheme(.light)
        .fullScreenCover(isPresented: $isARPresented, onDismiss: {
            // Restore the map only after the camera's dismissal has finished.
            isCameraCoverActive = false
        }) {
            if let geoPlacement {
                CampusGeoARScreen(placement: geoPlacement, stories: store, remote: remote)
            } else { ARView() }
        }
        .onOpenURL { handlePublicLink($0) }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            if let url = activity.webpageURL { handlePublicLink(url) }
        }
    }

    private func openGeoStory(_ story: CampusStory) {
        guard let id = UUID(uuidString: story.id), let latitude = story.latitude, let longitude = story.longitude else { return }
        geoPlacement = CampusPlacement(id: id, storyID: story.id, latitude: latitude, longitude: longitude)
        isCameraCoverActive = true
        isARPresented = true
    }

    private func synchronizeRemote() {
        guard !container.showsDesignExamples else { return }
        let mapped = remote.stories.enumerated().map { index, item in
            var story = CampusStory(id: item.id.uuidString, regionID: item.regionId, title: item.cucumberName,
                image: item.cucumberAsset, tags: [item.theme,item.emotion],
                donor: remote.profiles.first(where: { $0.id == item.userId })?.nickname ?? "작성자 정보 확인 중",
                location: CampusRegion.examples.first(where: { $0.id == item.regionId })?.title ?? "POSTECH",
                date: item.createdDateLabel, order: index, popularity: remote.collectionCounts[item.id] ?? 0, palette: 0)
            story.remoteBody = item.body
            story.remoteMediaPaths = remote.mediaPaths(storyID: item.id)
            story.latitude = item.latitude; story.longitude = item.longitude
            return story
        }
        store.synchronize(stories: mapped, collected: Set(remote.collections.map { $0.storyId.uuidString }))
        let cards = remote.collections.enumerated().compactMap { index, collection -> MYDemoCard? in
            guard let story = remote.stories.first(where: { $0.id == collection.storyId }) else { return nil }
            return MYDemoCard(id: story.id.uuidString, title: story.cucumberName, image: story.cardAsset,
                school: .postech, order: index, distance: 0, popularity: 0, storyID: story.id.uuidString)
        }
        myDemo.synchronize(nickname: remote.profile?.nickname ?? "농부", cards: cards,
            favorites: Set(remote.favorites.map(\.uuidString)))
    }

    private func handlePublicLink(_ url: URL) {
        if AppClipLink.matches(url) {
            path = NavigationPath()
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

#if DEBUG
private struct OiStoryListPreviewHost: View {
    let state: OiStoryListState
    @State private var notice: PreviewNotice?

    var body: some View {
        NavigationStack {
            OiStoryListView(
                state: state,
                ticketCountText: "3pc",
                notices: OiStoryListView.figmaPreviewNotices,
                onRetry: { show("다시 시도", "실제 앱에서는 서버의 이야기 목록을 다시 불러옵니다.") },
                onAddTicket: { show("티켓 추가", "티켓 추가 정책이 확정되면 실제 흐름에 연결됩니다.") },
                onSelectStory: { _ in show("이야기 선택", "실제 앱에서는 기존 이야기 관리 화면으로 이동합니다.") },
                onCreateStory: { show("오이 만들기", "실제 앱에서는 작성 승인을 확인한 뒤 이야기 에디터로 이동합니다.") },
                onUseTicket: { show("티켓 사용", "티켓 사용 정책이 확정되면 실제 흐름에 연결됩니다.") }
            )
        }
        .alert(item: $notice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("확인"))
            )
        }
    }

    private func show(_ title: String, _ message: String) {
        notice = PreviewNotice(title: title, message: message)
    }
}

private struct PreviewNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
#endif

#Preview { RootTabView(container: .preview) }
