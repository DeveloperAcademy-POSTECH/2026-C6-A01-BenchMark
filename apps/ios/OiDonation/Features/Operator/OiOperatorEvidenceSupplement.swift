import Foundation
import Observation

struct OiEvidenceHistory: Decodable, Identifiable, Equatable {
    let id: UUID
    let requestId: UUID
    let status: String
    let objectPath: String
    let reviewNote: String?
    let reviewerId: UUID?
    let recordedAt: String
    var recordedDateLabel: String { OiEvidence.dateLabel(recordedAt) }
}

struct OiEvidenceAnalysis: Decodable, Equatable {
    enum Verdict: String, Decodable {
        case suspicious, noObviousSigns = "no_obvious_signs", inconclusive
        var title: String {
            switch self {
            case .suspicious: "의심 징후 관찰"
            case .noObviousSigns: "뚜렷한 징후를 찾지 못함"
            case .inconclusive: "판단 어려움"
            }
        }
    }
    enum Readability: String, Decodable {
        case readable, limited, unreadable
        var title: String { switch self { case .readable: "판독 가능"; case .limited: "일부 판독 가능"; case .unreadable: "판독 어려움" } }
    }
    struct Finding: Decodable, Equatable {
        enum Category: String, Decodable { case visualEdit = "visual_edit", inconsistency }
        let category: Category
        let location: String
        let observation: String
    }
    struct Assessment: Decodable, Equatable {
        let verdict: Verdict
        let readability: Readability
        let findings: [Finding]
        let limitations: [String]
        let manualChecks: [String]
    }
    let evidenceId: UUID
    let submittedAt: String
    let sha256: String
    let analyzedAt: String
    let model: String
    let promptVersion: String
    let humanReviewRequired: Bool
    let authenticityVerified: Bool
    let notice: String
    let assessment: Assessment

    func validate(for snapshot: OiEvidence) throws {
        guard snapshot.status == "pending", evidenceId == snapshot.id,
              let expected = Self.date(snapshot.submittedAt), Self.date(submittedAt) == expected else { throw OiServiceError.conflict }
        let assessment = assessment
        func text(_ value: String) -> Bool { !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf16.count <= 500 }
        func list(_ values: [String]) -> Bool { (1...6).contains(values.count) && values.allSatisfy(text) }
        guard humanReviewRequired, !authenticityVerified, Self.date(analyzedAt) != nil,
              !model.isEmpty, !promptVersion.isEmpty, !notice.isEmpty,
              sha256.count == 64, sha256.allSatisfy({ "0123456789abcdef".contains($0) }),
              assessment.findings.count <= 8, list(assessment.limitations), list(assessment.manualChecks),
              assessment.findings.allSatisfy({ text($0.location) && text($0.observation) }),
              assessment.verdict != .suspicious || !assessment.findings.isEmpty,
              assessment.verdict != .noObviousSigns || (assessment.readability == .readable && assessment.findings.isEmpty)
        else { throw OiEvidenceAnalysisError.invalidResult }
    }

    private static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = parser.date(from: value) { return date }
        parser.formatOptions = [.withInternetDateTime]
        return parser.date(from: value)
    }
}

enum OiEvidenceAnalysisError: LocalizedError {
    case notDeployed, notConfigured, busy, timeout, invalidResult, documentUnavailable, consentRequired, unavailable
    var errorDescription: String? {
        switch self {
        case .notDeployed: "AI 분석 함수를 찾지 못했어요. 서버 배포 상태를 확인해 주세요."
        case .notConfigured: "서버의 AI 분석 설정이 준비되지 않았어요. 원본을 직접 검토해 주세요."
        case .busy: "분석 중이거나 요청 한도에 도달했어요. 잠시 후 직접 다시 시도해 주세요."
        case .timeout: "분석 시간이 초과됐어요. 자동으로 재요청하지 않습니다."
        case .invalidResult: "유효한 분석 결과를 받지 못했어요. 원본을 직접 검토해 주세요."
        case .documentUnavailable: "이 자료의 AI 분석 결과를 만들 수 없어요. 원본을 직접 검토해 주세요."
        case .consentRequired: "이 제출본의 AI 분석 동의가 확인되지 않았어요. 원본을 직접 검토해 주세요."
        case .unavailable: "AI 분석을 완료하지 못했어요. 연결 상태를 확인하고 직접 다시 시도해 주세요."
        }
    }
}

@MainActor protocol OiOperatorEvidenceHistoryServing {
    func operatorEvidenceHistory(_ id: UUID) async throws -> [OiEvidenceHistory]
}

@MainActor protocol OiOperatorEvidenceAnalysisServing {
    func operatorEvidenceAnalysis(_ snapshot: OiEvidence) async throws -> OiEvidenceAnalysis
    func validateOperatorEvidence(_ snapshot: OiEvidence) async throws
}

@MainActor @Observable final class OiOperatorEvidenceHistoryModel {
    // Avoid the synthesized isolated deinit crash on early iOS 26 (Swift #88036).
    nonisolated deinit {}

    private(set) var rows: [OiEvidenceHistory] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var error: String?
    func load(_ id: UUID, using service: any OiOperatorEvidenceHistoryServing) async {
        guard !isLoading else { return }
        rows = []; isLoading = true; hasLoaded = false; error = nil
        defer { isLoading = false }
        do {
            let rows = try await service.operatorEvidenceHistory(id)
            try Task.checkCancellation()
            self.rows = rows; hasLoaded = true
        } catch { if !OiServiceFailure.isCancellation(error) { self.error = error.localizedDescription } }
    }
}

@MainActor @Observable final class OiOperatorEvidenceAnalysisModel {
    // Avoid the synthesized isolated deinit crash on early iOS 26 (Swift #88036).
    nonisolated deinit {}

    private(set) var result: OiEvidenceAnalysis?
    private(set) var isLoading = false
    private(set) var error: String?
    private var generation = UUID()
    func invalidate() {
        generation = UUID(); result = nil; isLoading = false; error = nil
    }
    func analyze(_ snapshot: OiEvidence, using service: any OiOperatorEvidenceAnalysisServing) async {
        guard !isLoading, snapshot.status == "pending" else { return }
        let request = UUID(); generation = request
        result = nil; error = nil; isLoading = true
        defer { if generation == request { isLoading = false } }
        do {
            let result = try await service.operatorEvidenceAnalysis(snapshot)
            try Task.checkCancellation()
            try result.validate(for: snapshot)
            guard generation == request else { return }
            self.result = result
        } catch {
            guard generation == request else { return }
            if !OiServiceFailure.isCancellation(error) { self.error = error.localizedDescription }
        }
    }
    func revalidate(_ snapshot: OiEvidence, using service: any OiOperatorEvidenceAnalysisServing) async {
        guard result != nil else { return }
        let request = generation
        do {
            try await service.validateOperatorEvidence(snapshot)
            try Task.checkCancellation()
        } catch {
            guard generation == request else { return }
            result = nil
            if !OiServiceFailure.isCancellation(error) {
                self.error = "분석 대상의 최신 상태를 확인하지 못해 결과를 숨겼어요. 증빙을 새로 불러와 주세요."
            }
        }
    }
}
