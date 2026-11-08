import Foundation
import Observation

enum OiEvidenceDecision: String, CaseIterable, Identifiable {
    case approved, changesRequested = "changes_requested", rejected, revoked
    var id: String { rawValue }
    var title: String {
        switch self { case .approved: "검토 완료"; case .changesRequested: "보완 요청"; case .rejected: "반려"; case .revoked: "검토 결과 철회" }
    }
    func allows(_ evidence: OiEvidence) -> Bool {
        self == .revoked ? evidence.status == "approved" : evidence.status == "pending"
    }
}

enum OiEvidenceFilter: String, CaseIterable, Identifiable {
    case pending, approved, changesRequested = "changes_requested", rejected, revoked, all
    var id: String { rawValue }
    var title: String { self == .all ? "전체" : rawValue.oiStatusTitle }
}

struct OiOperatorEvidenceDetail {
    let evidence: OiEvidence
    let grants: [OiWritingGrant]
}

struct OiEvidenceReview {
    let snapshot: OiEvidence
    let decision: OiEvidenceDecision
    let note: String
    init(snapshot: OiEvidence, decision: OiEvidenceDecision, note: String) throws {
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard decision.allows(snapshot), snapshot.objectPath != nil, snapshot.submittedAt != nil,
              note.unicodeScalars.count <= 2000, decision == .approved || !note.isEmpty else { throw OiEvidenceReviewError.invalidDecision }
        self.snapshot = snapshot; self.decision = decision; self.note = note
    }
}

enum OiEvidenceReviewError: LocalizedError {
    case invalidDecision, missing, invalidDocument, documentTooLarge, serverNotReady
    var errorDescription: String? {
        switch self {
        case .invalidDecision: "현재 상태와 검토 의견을 확인해 주세요. 보완 요청·반려·검토 결과 철회에는 의견이 필요하고, 의견은 2,000자 이내로 입력해 주세요."
        case .missing: "증빙이 없거나 제출 정보가 바뀌었어요. 목록을 다시 불러와 주세요."
        case .invalidDocument: "확인할 수 없는 파일이에요. JPEG·PNG 이미지 또는 암호가 없는 PDF가 필요합니다."
        case .documentTooLarge: "원본 파일이 열람 가능한 크기(10MiB)를 초과했어요."
        case .serverNotReady: "서버의 안전한 증빙 검토 기능이 아직 준비되지 않았어요. 운영 담당자에게 확인해 주세요."
        }
    }
}

struct OiEvidenceDocument {
    enum Kind { case image, pdf }
    let data: Data
    let kind: Kind
    static let maximumBytes = 10 * 1024 * 1024
    init(data: Data) throws {
        guard data.count <= Self.maximumBytes else { throw OiEvidenceReviewError.documentTooLarge }
        if data.starts(with: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]) || data.starts(with: [0xff, 0xd8, 0xff]) {
            kind = .image
        } else if data.starts(with: Array("%PDF-".utf8)) { kind = .pdf }
        else { throw OiEvidenceReviewError.invalidDocument }
        self.data = data
    }
}

struct OiEvidenceReviewResult { let evidence: OiEvidence; let warning: String? }

extension OiEvidence {
    var submittedDateLabel: String { Self.dateLabel(submittedAt) }
    var reviewedDateLabel: String { Self.dateLabel(reviewedAt) }
    static func dateLabel(_ value: String?) -> String {
        guard let value else { return "정보 없음" }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fractional = parser.date(from: value)
        parser.formatOptions = [.withInternetDateTime]
        guard let date = fractional ?? parser.date(from: value) else { return "날짜 확인 필요" }
        return date.formatted(.dateTime.year().month().day().hour().minute().locale(Locale(identifier: "ko_KR")))
    }
}

@MainActor protocol OiOperatorEvidenceServing {
    func operatorEvidenceList() async throws -> [OiEvidence]
    func operatorEvidence(_ id: UUID) async throws -> OiOperatorEvidenceDetail
    func operatorEvidenceDocument(_ snapshot: OiEvidence) async throws -> OiEvidenceDocument
    func reviewOperatorEvidence(_ review: OiEvidenceReview) async throws -> OiEvidenceReviewResult
}

@MainActor @Observable final class OiOperatorEvidenceListModel {
    // Avoid the synthesized isolated deinit crash on early iOS 26 (Swift #88036).
    nonisolated deinit {}

    var filter: OiEvidenceFilter = .pending
    private(set) var rows: [OiEvidence] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var error: String?
    private var generation = UUID()
    var filtered: [OiEvidence] { rows.filter { filter == .all || $0.status == filter.rawValue } }
    func load(using service: any OiOperatorEvidenceServing) async {
        guard !isLoading else { return }
        let request = UUID(); generation = request
        isLoading = true; error = nil
        defer { if generation == request { isLoading = false } }
        do {
            let rows = try await service.operatorEvidenceList()
            try Task.checkCancellation()
            guard generation == request else { return }
            self.rows = rows; hasLoaded = true
        } catch {
            guard generation == request else { return }
            rows = []; hasLoaded = false
            if !OiServiceFailure.isCancellation(error) { self.error = error.localizedDescription }
        }
    }
    func apply(_ evidence: OiEvidence) {
        generation = UUID(); isLoading = false
        rows.removeAll { $0.id == evidence.id }
        if evidence.status != "draft" { rows.insert(evidence, at: 0) }
        rows.sort { ($0.submittedAt ?? "", $0.id.uuidString) > ($1.submittedAt ?? "", $1.id.uuidString) }
    }
}

@MainActor @Observable final class OiOperatorEvidenceModel {
    // Avoid the synthesized isolated deinit crash on early iOS 26 (Swift #88036).
    nonisolated deinit {}

    private(set) var detail: OiOperatorEvidenceDetail?
    private(set) var isLoading = false
    private(set) var isProcessing = false
    private(set) var error: String?
    private(set) var notice: String?
    private(set) var warning: String?
    private(set) var requiresReload = true
    var canReview: Bool { detail != nil && !isLoading && !isProcessing && !requiresReload }

    func load(_ id: UUID, using service: any OiOperatorEvidenceServing) async {
        guard !isLoading, !isProcessing else { return }
        isLoading = true; detail = nil; error = nil; notice = nil; warning = nil; requiresReload = true
        defer { isLoading = false }
        do {
            let detail = try await service.operatorEvidence(id)
            try Task.checkCancellation()
            self.detail = detail; requiresReload = false
        } catch { if !OiServiceFailure.isCancellation(error) { self.error = error.localizedDescription } }
    }

    func review(_ review: OiEvidenceReview, using service: any OiOperatorEvidenceServing) async -> OiEvidence? {
        guard canReview else { return nil }
        guard detail?.evidence == review.snapshot else {
            requiresReload = true; error = "제출 정보가 바뀌었어요. 최신 원본과 상태를 다시 확인해 주세요."; return nil
        }
        isProcessing = true; error = nil; notice = nil; warning = nil
        defer { isProcessing = false }
        do {
            let result = try await service.reviewOperatorEvidence(review)
            detail = OiOperatorEvidenceDetail(evidence: result.evidence, grants: [])
            notice = "\(review.decision.title) 처리를 완료했어요."
            warning = result.warning; requiresReload = true
            return result.evidence
        } catch {
            requiresReload = true
            switch error {
            case OiServiceError.conflict: self.error = "증빙이 재제출되었거나 다른 운영자가 처리했어요. 최신 원본과 상태를 다시 확인해 주세요."
            case OiServiceError.signInRequired, OiServiceError.accountChanged, OiOperatorStoryError.accessDenied:
                detail = nil; self.error = error.localizedDescription
            case OiEvidenceReviewError.serverNotReady, OiEvidenceReviewError.invalidDecision:
                self.error = error.localizedDescription
            default: self.error = "처리 결과를 확인하지 못했어요. 중복 처리하지 말고 최신 상태를 다시 불러와 주세요."
            }
            return nil
        }
    }
}
