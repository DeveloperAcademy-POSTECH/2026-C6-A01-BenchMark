import Foundation

struct AppContainer {
    let homeRepository: any HomeRepository
    let benchRepository: any BenchRepository
    let participationRepository: any ParticipationRepository
    let storyRepository: any StoryRepository
    let approvedLinkHost: String?

    static let pilot = AppContainer(homeRepository: UnconnectedPilotRepository(),
        benchRepository: UnconnectedPilotRepository(), participationRepository: UnconnectedPilotRepository(),
        storyRepository: RealStoryRepository(), approvedLinkHost: nil)

    static var preview: AppContainer { pilot }
}
