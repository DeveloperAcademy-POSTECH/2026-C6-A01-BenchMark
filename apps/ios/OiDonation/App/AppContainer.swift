import Foundation

struct AppContainer {
    let homeRepository: any HomeRepository
    let benchRepository: any BenchRepository
    let participationRepository: any ParticipationRepository
    let storyRepository: any StoryRepository
    let approvedLinkHost: String?

    // Temporary Figma dashboard for device design review; other services remain unconnected.
    static let pilot = AppContainer(homeRepository: DesignDemoHomeRepository(),
        benchRepository: UnconnectedPilotRepository(), participationRepository: UnconnectedPilotRepository(),
        storyRepository: UnconnectedPilotRepository(), approvedLinkHost: nil)

    static var preview: AppContainer {
        let participation = PreviewParticipationRepository()
        return AppContainer(homeRepository: DesignDemoHomeRepository(), benchRepository: participation,
            participationRepository: participation, storyRepository: UnconnectedPilotRepository(), approvedLinkHost: nil)
    }
}
