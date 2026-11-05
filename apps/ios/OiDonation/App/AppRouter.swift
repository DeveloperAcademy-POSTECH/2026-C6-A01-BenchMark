import Foundation
import Observation

@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .home
    var isARPresented = false
    var benchPath: [PublicLinkParser.Destination] = []
    var storyPath: [PublicLinkParser.Destination] = []
    private let parser: PublicLinkParser?
    init(approvedLinkHost: String? = nil) {
        parser = approvedLinkHost.map { PublicLinkParser(allowedHost: $0) }
    }
    func open(_ url: URL) {
        if AppClipLink.matches(url) {
            selectedTab = .home
            storyPath = []
            isARPresented = false
            return
        }
        guard let destination = parser?.parse(url) else { return }
        switch destination {
        case .bench:
            selectedTab = .benches
            benchPath = [destination]
        case .story:
            selectedTab = .home
            storyPath = [destination]
        }
    }
}

enum AppTab: Int, CaseIterable, Identifiable {
    case home, myDonations, participation, benches
    var id: Int { rawValue }
    var title: String {
        switch self { case .home: "홈"; case .myDonations: "내 기부"; case .participation: "후원"; case .benches: "벤치지도" }
    }
    var symbol: String {
        switch self { case .home: "house.fill"; case .myDonations: "heart.fill"; case .participation: "hand.palm.facing.fill"; case .benches: "map.fill" }
    }
}
