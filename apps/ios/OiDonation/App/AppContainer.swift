import Foundation

struct AppContainer {
    let homeRepository: any HomeRepository
    let benchRepository: any BenchRepository
    let participationRepository: any ParticipationRepository
    let storyRepository: any StoryRepository
    let approvedLinkHost: String?

    static let pilot = AppContainer(homeRepository: UnconnectedPilotRepository(),
        benchRepository: UnconnectedPilotRepository(), participationRepository: UnconnectedPilotRepository(),
        storyRepository: UnconnectedPilotRepository(), approvedLinkHost: nil)

    static var preview: AppContainer {
        let participation = PreviewParticipationRepository()
        return AppContainer(homeRepository: PreviewHomeRepository(), benchRepository: participation,
            participationRepository: participation, storyRepository: UnconnectedPilotRepository(), approvedLinkHost: nil)
    }
}
