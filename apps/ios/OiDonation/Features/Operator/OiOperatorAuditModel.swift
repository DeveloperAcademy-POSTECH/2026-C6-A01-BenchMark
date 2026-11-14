import Foundation
import Observation

enum OiAuditCategory: String, CaseIterable, Identifiable {
    case all, evidence, stories, accounts
    var id: String { rawValue }
    var title: String { switch self { case .all: "전체"; case .evidence: "과거 증빙 검토"; case .stories: "이야기 처리"; case .accounts: "계정 통합" } }
}

struct OiAuditQuery: Equatable {
    let from: Date
    let until: Date
    let category: OiAuditCategory
    static let pageSize = 50
    init(from: Date, until: Date, category: OiAuditCategory) throws {
        guard from.timeIntervalSince1970.isFinite, until.timeIntervalSince1970.isFinite,
              from < until, until.timeIntervalSince(from) <= 31 * 86400 else { throw OiAuditError.invalidQuery }
        self.from = from; self.until = until; self.category = category
    }
}

struct OiAuditCursor: Codable, Equatable {
    let createdAt: String
    let id: String
}

struct OiAuditRecord: Decodable, Identifiable, Equatable {
    let id: String
    let actorId: UUID
    let action: String
    let targetId: UUID
    let createdAt: String
    var title: String {
        switch action {
        case "review_evidence:approved": "기부 자료 검토 완료"
        case "review_evidence:changes_requested": "증빙 보완 요청"
        case "review_evidence:rejected": "증빙 반려"
        case "review_evidence:revoked": "증빙 승인 철회"
        case "save_story": "이야기 저장"
        case "save_campus_story": "캠퍼스 이야기 저장"
        case "attach_media": "이야기 사진 변경"
        case "submit_story": "이야기 공개 검토 요청"
        case "reopen_story": "이야기 작성 재개"
        case "delete_story": "이야기 삭제"
        case "review_story": "이야기 공개 상태 검토"
        case "merge_accounts": "계정 통합"
        case "nfc_tag:link": "NFC 태그 연결"
        case "nfc_tag:unlink": "NFC 태그 연결 해제·중지"
        default: "기타 처리 (\(action))"
        }
    }
    var targetLabel: String {
        if action.hasPrefix("review_evidence:") { return "증빙 ID" }
        if action == "merge_accounts" { return "통합된 원본 계정 ID" }
        if action.hasPrefix("nfc_tag:") { return "이야기 ID" }
        if ["save_story", "save_campus_story", "attach_media", "submit_story", "reopen_story", "delete_story", "review_story"].contains(action) { return "이야기 ID" }
        return "대상 ID"
    }

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

struct OiAuditPage: Decodable {
    let records: [OiAuditRecord]
    let nextCursor: OiAuditCursor?
    func validate(query: OiAuditQuery, after cursor: OiAuditCursor?) throws {
        let parser = ISO8601DateFormatter()
        func date(_ text: String) -> Date? {
            parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let value = parser.date(from: text) { return value }
            parser.formatOptions = [.withInternetDateTime]
            return parser.date(from: text)
        }
        guard records.count <= OiAuditQuery.pageSize, Set(records.map(\.id)).count == records.count,
              records.allSatisfy({ row in
                  guard let id = Int64(row.id), id > 0, let created = date(row.createdAt) else { return false }
                  return created >= query.from && created < query.until
              }) else { throw OiAuditError.invalidPage }
        if let nextCursor {
            guard records.count == OiAuditQuery.pageSize, let last = records.last,
                  nextCursor.id == last.id, nextCursor.createdAt == last.createdAt, nextCursor != cursor
            else { throw OiAuditError.invalidPage }
        }
    }
}

enum OiAuditError: LocalizedError {
    case invalidQuery, invalidPage, notDeployed
    var errorDescription: String? {
        switch self {
        case .invalidQuery: "조회 기간은 시작일부터 종료일까지 최대 31일로 선택해 주세요."
        case .invalidPage: "감사 기록 응답을 확인하지 못했어요. 처음부터 다시 조회해 주세요."
        case .notDeployed: "서버의 감사 기록 조회 기능이 아직 준비되지 않았어요. 배포 상태를 확인해 주세요."
        }
    }
}

@MainActor protocol OiOperatorAuditServing {
    func operatorAudit(_ query: OiAuditQuery, after cursor: OiAuditCursor?) async throws -> OiAuditPage
}

@MainActor @Observable final class OiOperatorAuditModel {
    // Avoid the synthesized isolated deinit crash on early iOS 26 (Swift #88036).
    nonisolated deinit {}

    private(set) var records: [OiAuditRecord] = []
    private(set) var query: OiAuditQuery?
    private(set) var nextCursor: OiAuditCursor?
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var error: String?
    private var generation = UUID()

    func invalidate() {
        generation = UUID(); records = []; query = nil; nextCursor = nil
        isLoading = false; hasLoaded = false; error = nil
    }
    func reload(_ query: OiAuditQuery, using service: any OiOperatorAuditServing) async {
        invalidate(); self.query = query
        await load(after: nil, using: service)
    }
    func loadMore(using service: any OiOperatorAuditServing) async {
        guard !isLoading, let nextCursor else { return }
        await load(after: nextCursor, using: service)
    }
    private func load(after cursor: OiAuditCursor?, using service: any OiOperatorAuditServing) async {
        guard let query else { return }
        let request = generation
        isLoading = true; error = nil
        defer { if generation == request { isLoading = false } }
        do {
            let page = try await service.operatorAudit(query, after: cursor)
            try Task.checkCancellation()
            try page.validate(query: query, after: cursor)
            guard generation == request else { return }
            let seen = Set(records.map(\.id))
            records += page.records.filter { !seen.contains($0.id) }
            nextCursor = page.nextCursor; hasLoaded = true
        } catch {
            guard generation == request else { return }
            if case OiServiceError.signInRequired = error { records = []; nextCursor = nil; hasLoaded = false }
            if case OiServiceError.accountChanged = error { records = []; nextCursor = nil; hasLoaded = false }
            if case OiOperatorStoryError.accessDenied = error { records = []; nextCursor = nil; hasLoaded = false }
            if !OiServiceFailure.isCancellation(error) { self.error = error.localizedDescription }
        }
    }
}
