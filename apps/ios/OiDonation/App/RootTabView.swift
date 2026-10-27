import SwiftUI

struct RootTabView: View {
    let container: AppContainer
    @State private var path = NavigationPath()
    @State private var store = CampusStoryStore()
    @State private var isARPresented = false
    @State private var isCameraCoverActive = false

    init(container: AppContainer = .pilot) {
        self.container = container
    }

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(
                container: container,
                store: store,
                isCameraCoverActive: isCameraCoverActive,
                onCamera: { isCameraCoverActive = true; isARPresented = true },
                onOpenStory: { path.append(CampusDestination.summary($0)) }
            )
            .navigationDestination(for: CampusDestination.self) { destination in
                switch destination {
                case .summary(let id):
                    if let story = store.story(id) { CampusSummaryView(story: story, store: store) }
                case .story(let id):
                    if let story = store.story(id) { CampusStoryDetailView(story: story, store: store) }
                }
            }
            .navigationDestination(for: PublicLinkParser.Destination.self) { publicDestination($0) }
        }
        .tint(.black)
        .preferredColorScheme(.light)
        .fullScreenCover(isPresented: $isARPresented, onDismiss: {
            // Restore the map only after the camera's dismissal has finished.
            isCameraCoverActive = false
        }) { ARView() }
        .onOpenURL { handlePublicLink($0) }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            if let url = activity.webpageURL { handlePublicLink(url) }
        }
    }

    private func handlePublicLink(_ url: URL) {
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
