import Foundation

/// Safe runtime state until the school's API contract and authentication are agreed.
struct UnconnectedPilotRepository: HomeRepository, BenchRepository, ParticipationRepository, StoryRepository {
    func fetchDashboard() async throws -> HomeDashboard? { nil }
    func fetchBenches() async throws -> [Bench] { [] }
    func fetchApplications() async throws -> [ParticipationApplication] { [] }
    func fetchPublicStory(storyID: String) async throws -> Story? { nil }
    func fetchPublicStoryCard(storyID: String) async throws -> StoryCard? { nil }
    func submit(_ draft: ParticipationDraft, idempotencyKey: UUID) async throws -> ParticipationApplication {
        throw ParticipationError.serviceUnavailable
    }
}
