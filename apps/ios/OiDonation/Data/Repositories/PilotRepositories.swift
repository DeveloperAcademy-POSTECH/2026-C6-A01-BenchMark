import Foundation

/// Safe runtime state until the school's API contract and authentication are agreed.
struct UnconnectedPilotRepository: HomeRepository, BenchRepository, ParticipationRepository, StoryRepository {
    func fetchDashboard() async throws -> HomeDashboard? { nil }
    func fetchBenches() async throws -> [Bench] { [] }
    func fetchApplications() async throws -> [ParticipationApplication] { [] }
    func fetchPublicStory(storyID: String) async throws -> Story? { nil }
    func submit(_ draft: ParticipationDraft, idempotencyKey: UUID) async throws -> ParticipationApplication {
        throw ParticipationError.serviceUnavailable
    }
}

/// Temporary Figma values for previews and pilot design review, never school-confirmed statistics.
struct DesignDemoHomeRepository: HomeRepository {
    func fetchDashboard() async throws -> HomeDashboard? { .designExample }
}

actor PreviewParticipationRepository: BenchRepository, ParticipationRepository {
    private var submissions: [UUID: ParticipationApplication] = [:]
    func fetchBenches() async throws -> [Bench] {
        [Bench(id: "preview-bench", name: "예시 벤치", locationDescription: "디자인 확인용 장소")]
    }
    func fetchApplications() async throws -> [ParticipationApplication] { Array(submissions.values) }
    func submit(_ draft: ParticipationDraft, idempotencyKey: UUID) async throws -> ParticipationApplication {
        let validated = try draft.validated()
        if let existing = submissions[idempotencyKey] {
            guard existing.draft == validated else { throw ParticipationError.idempotencyConflict }
            return existing
        }
        let application = ParticipationApplication(id: UUID(), draft: validated,
            applicationStatus: .submitted, verificationStatus: .awaitingSchoolConfirmation, plaqueStatus: nil)
        submissions[idempotencyKey] = application
        return application
    }
}
