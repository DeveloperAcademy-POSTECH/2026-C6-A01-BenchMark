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
        VStack(spacing: 0) {
            TabView(selection: $router.selectedTab) {
                NavigationStack(path: $router.storyPath) {
                    HomeView(repository: container.homeRepository) { router.selectedTab = .participation }
                        .navigationDestination(for: PublicLinkParser.Destination.self) { publicDestination($0) }
                }.tag(AppTab.home)
                NavigationStack { MyDonationsView(repository: container.participationRepository) }.tag(AppTab.myDonations)
                NavigationStack {
                    ParticipationView(benches: container.benchRepository, participation: container.participationRepository)
                }.tag(AppTab.participation)
                NavigationStack(path: $router.benchPath) {
                    BenchesView(repository: container.benchRepository)
                        .navigationDestination(for: PublicLinkParser.Destination.self) { publicDestination($0) }
                }.tag(AppTab.benches)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
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
