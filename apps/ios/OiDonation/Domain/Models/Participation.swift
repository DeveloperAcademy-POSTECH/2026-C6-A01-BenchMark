import Foundation

nonisolated struct Bench: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let locationDescription: String
    let plaquePreview: BenchPlaquePreview?

    init(id: String, name: String, locationDescription: String, plaquePreview: BenchPlaquePreview? = nil) {
        self.id = id
        self.name = name
        self.locationDescription = locationDescription
        self.plaquePreview = plaquePreview
    }
}

enum ApplicationStatus: String, Sendable {
    case draft, submitted, underReview, approved, revisionRequested, cancelled
}

enum DonationVerificationStatus: String, Sendable {
    case awaitingSchoolConfirmation, confirmedBySchool
}

enum PlaqueStatus: String, Sendable {
    case awaitingProduction, inProduction, attached
}

struct ParticipationDraft: Sendable, Equatable {
    var benchID: String
    var message: String
    var story: String

    func validated() throws -> Self {
        let cleaned = Self(benchID: benchID.trimmingCharacters(in: .whitespacesAndNewlines),
                           message: message.trimmingCharacters(in: .whitespacesAndNewlines),
                           story: story.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !cleaned.benchID.isEmpty else { throw ParticipationError.missingBench }
        guard !cleaned.message.isEmpty else { throw ParticipationError.missingMessage }
        return cleaned
    }
}

struct ParticipationApplication: Identifiable, Sendable {
    let id: UUID
    let draft: ParticipationDraft
    let applicationStatus: ApplicationStatus
    let verificationStatus: DonationVerificationStatus
    let plaqueStatus: PlaqueStatus?
}

struct DonationRecord: Identifiable, Sendable {
    let id: UUID
    let applicationID: UUID
    let amount: Int
    let schoolConfirmedAt: Date
}

struct Plaque: Identifiable, Sendable {
    let id: String
    let applicationID: UUID
    let benchID: String
    let approvedMessage: String
    let status: PlaqueStatus
}

enum ParticipationError: Error, LocalizedError, Sendable {
    case missingBench, missingMessage, serviceUnavailable, idempotencyConflict
    var errorDescription: String? {
        switch self {
        case .missingBench: "벤치를 선택해 주세요."
        case .missingMessage: "명패에 남길 문구를 입력해 주세요."
        case .idempotencyConflict: "신청 내용이 변경되었습니다. 새로운 신청으로 다시 시도해 주세요."
        case .serviceUnavailable: "참여 신청을 준비 중입니다. 학교와의 운영 절차가 연결되면 안내드릴게요."
        }
    }
}
