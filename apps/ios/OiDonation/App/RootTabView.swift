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
        TabView(selection: $router.selectedTab) {
            Tab(AppTab.home.title, systemImage: AppTab.home.symbol, value: .home) {
                NavigationStack(path: $router.storyPath) {
                    HomeView(repository: container.homeRepository) { router.selectedTab = .participation }
                        .navigationDestination(for: PublicLinkParser.Destination.self) { publicDestination($0) }
                }
            }
            Tab(AppTab.myDonations.title, systemImage: AppTab.myDonations.symbol, value: .myDonations) {
                NavigationStack {
                    MyDonationsView(repository: container.participationRepository,
                                    showDesignExamples: container.showsDesignExamples) {
                        router.selectedTab = .participation
                    }
                }
            }
            Tab(AppTab.participation.title, systemImage: AppTab.participation.symbol, value: .participation) {
                NavigationStack {
                    SponsorshipView(benches: container.benchRepository,
                                    participation: container.participationRepository) {
                        router.selectedTab = .home
                    }
                }
            }
            Tab(AppTab.benches.title, systemImage: AppTab.benches.symbol, value: .benches) {
                NavigationStack(path: $router.benchPath) {
                    BenchesView(repository: container.benchRepository)
                        .navigationDestination(for: PublicLinkParser.Destination.self) { publicDestination($0) }
                }
            }
        }
        .background {
            OiNativeTabBarCameraPlacement { router.isARPresented = true }
        }
        .tint(Color("OiGreen"))
        .fullScreenCover(isPresented: $router.isARPresented) { ARView() }
        .onOpenURL { router.open($0) }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            if let url = activity.webpageURL { router.open(url) }
        }
    }

    private func publicDestination(_ destination: PublicLinkParser.Destination) -> some View {
        PublicDestinationView(destination: destination, benches: container.benchRepository, stories: container.storyRepository)
    }
}

#Preview { RootTabView(container: .preview) }
