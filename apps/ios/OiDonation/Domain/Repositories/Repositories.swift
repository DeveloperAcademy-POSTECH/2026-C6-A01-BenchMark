import Foundation

protocol HomeRepository: Sendable {
    /// nil means no confirmed dashboard is available; it must not become fake zero counts.
    func fetchDashboard() async throws -> HomeDashboard?
}

protocol BenchRepository: Sendable {
    func fetchBenches() async throws -> [Bench]
}

protocol ParticipationRepository: Sendable {
    func fetchApplications() async throws -> [ParticipationApplication]
    /// Retries of the same application must reuse the same key.
    func submit(_ draft: ParticipationDraft, idempotencyKey: UUID) async throws -> ParticipationApplication
}

protocol StoryRepository: Sendable {
    func fetchPublicStory(plaqueID: String) async throws -> Story?
}
