import SwiftUI

struct RootTabView: View {
    let container: AppContainer
    @State private var router: AppRouter

    init(container: AppContainer = .pilot) {
        self.container = container
        _router = State(initialValue: AppRouter(approvedLinkHost: container.approvedLinkHost))
    }

    var body: some View {
        @Bindable var router = router
        ZStack(alignment: .bottom) {
            Group {
                switch router.selectedTab {
                case .home:
                NavigationStack(path: $router.storyPath) {
                    HomeView(repository: container.homeRepository) { router.selectedTab = .participation }
                        .navigationDestination(for: PublicLinkParser.Destination.self) { publicDestination($0) }
                }
                case .myDonations:
                NavigationStack { MyDonationsView(repository: container.participationRepository, showDesignExamples: container.showsDesignExamples) { router.selectedTab = .participation } }
                case .participation:
                NavigationStack {
                    SponsorshipView(benches: container.benchRepository, participation: container.participationRepository) { router.selectedTab = .home }
                }
                case .benches:
                NavigationStack(path: $router.benchPath) {
                    BenchesView(repository: container.benchRepository)
                        .navigationDestination(for: PublicLinkParser.Destination.self) { publicDestination($0) }
                }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.container, edges: .bottom)
            .contentMargins(.bottom, 86, for: .scrollContent)
            OiTabBar(selectedTab: $router.selectedTab) { router.isARPresented = true }
        }
        .background(Color.white).tint(Color("OiGreen"))
        .fullScreenCover(isPresented: $router.isARPresented) { ARView() }
        .onOpenURL { router.open($0) }
    }

    private func publicDestination(_ destination: PublicLinkParser.Destination) -> some View {
        PublicDestinationView(destination: destination, benches: container.benchRepository, stories: container.storyRepository)
    }
}

#Preview { RootTabView(container: .preview) }
