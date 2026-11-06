//
//  OiServiceModels.swift
//  OiDonation
//
//  Created by 이돈혁 on 10/28/26.
//

import Foundation

struct OiSchool: Codable, Identifiable { let id: String; let name: String }
struct OiRegion: Codable, Identifiable { let id: String; let schoolId: String; let name: String }
struct OiAsset: Codable, Identifiable { let id: String; let kind: String; let name: String }

struct OiAccount: Codable, Equatable {
    let id: UUID
    let email: String?
}

struct OiSession: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: TimeInterval
    var expiresAt: TimeInterval?
    let user: OiAccount
    var appAccount: OiAccount? = nil

    var needsRefresh: Bool { (expiresAt ?? 0) < Date().timeIntervalSince1970 + 60 }
}

protocol OiSessionStorage {
    func read() throws -> OiSession?
    func write(_ session: OiSession?) throws
}

enum OiServiceFailure {
    static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }
}

struct OiProfile: Codable, Equatable, Identifiable {
    let id: UUID
    var nickname: String
    var schoolId: String?
    let farmerAsset: String
    var farmName: String? = nil
    var schoolAdmissionYear: Int? = nil
    var schoolDepartment: String? = nil
    // Only information deliberately entered for public donor search. Never inferred from evidence.
    var publicName: String? = nil
    var department: String? = nil
    var admissionYear: String? = nil
}

struct OiPublicAcademicInfo: Equatable {
    var name = ""
    var department = ""
    var admissionYear = ""

    var cleaned: Self {
        Self(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
             department: department.trimmingCharacters(in: .whitespacesAndNewlines),
             admissionYear: admissionYear.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    var isValid: Bool {
        name.count <= 50 && department.count <= 100 &&
        (admissionYear.isEmpty || admissionYear.range(of: "^[0-9]{2}([0-9]{2})?$", options: .regularExpression) != nil)
    }
}

struct OiLiveStory: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    let grantId: UUID?
    let regionId: String
    let title: String
    let body: String
    let theme: String
    let emotion: String
    let cucumberName: String
    let cucumberAsset: String
    let cardAsset: String
    let latitude: Double
    let longitude: Double
    let status: String
    let revision: Int
    let createdAt: String
    var storageOwnerId: UUID? = nil

    var createdDateLabel: String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fractional = parser.date(from: createdAt)
        parser.formatOptions = [.withInternetDateTime]
        guard let date = fractional ?? parser.date(from: createdAt) else { return "날짜 확인 중" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: date)
    }
}

struct OiCardRequest: Decodable, Identifiable, Equatable {
    enum Status: String, Decodable { case pending, accepted, rejected }

    let id: UUID
    let storyTitle: String
    let requesterName: String
    let requesterSchoolName: String?
    let createdAt: Date
    let status: Status
}

struct OiCardRequestReceipt: Decodable {
    let id: UUID
    let storyId: UUID
    let status: OiCardRequest.Status
}

struct OiEvidence: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    let status: String
    let objectPath: String?
    let reviewNote: String?
    var storageOwnerId: UUID? = nil
    var createdAt: String? = nil
    var submittedAt: String? = nil
    var reviewedAt: String? = nil
    var reviewerId: UUID? = nil
}

struct OiDonationEvidenceSummary: Decodable, Equatable {
    enum Outcome: String, Decodable, CaseIterable {
        case sufficientEvidence = "sufficient_evidence"
        case needsMoreEvidence = "needs_more_evidence"
        case manualReview = "manual_review"
        case suspectedManipulation = "suspected_manipulation"
        case duplicateEvidence = "duplicate_evidence"
        case notDonation = "not_donation"

        var label: String {
            switch self {
            case .sufficientEvidence: "증빙 충족"
            case .needsMoreEvidence: "증빙 보완 필요"
            case .manualReview: "운영자 추가 확인 필요"
            case .suspectedManipulation: "수정 흔적 확인 필요"
            case .duplicateEvidence: "중복 자료 확인 필요"
            case .notDonation: "기부 완료 근거 부족"
            }
        }
    }

    struct Check: Decodable, Equatable {
        let kind: String
        let status: String
        let detail: String
    }

    struct SourceReference: Decodable, Equatable, Identifiable {
        let id: String
        let url: String
        let title: String
        let kind: String
        let verifiedAt: String

        var safeURL: URL? {
            guard let components = URLComponents(string: url), components.scheme == "https",
                  components.user == nil, components.password == nil,
                  components.port == nil || components.port == 443,
                  let host = components.host?.lowercased(),
                  host == "postech.ac.kr" || host.hasSuffix(".postech.ac.kr") else { return nil }
            return components.url
        }
    }

    let outcome: Outcome
    let sufficientEvidence: Bool
    let title: String
    let reasons: [String]
    let checks: [Check]
    let sourceReferences: [SourceReference]

    var isConsistent: Bool {
        sufficientEvidence == (outcome == .sufficientEvidence)
            && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !reasons.isEmpty
            && reasons.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

struct OiDonationEvidenceReview: Decodable, Equatable {
    struct Assessment: Decodable, Equatable {
        enum Verdict: String, Decodable { case suspicious, noObviousSigns = "no_obvious_signs", inconclusive }
        enum Readability: String, Decodable { case readable, limited, unreadable }
        struct Finding: Decodable, Equatable {
            let category: String
            let location: String
            let observation: String
        }
        let verdict: Verdict
        let readability: Readability
        let findings: [Finding]
        let limitations: [String]
        let manualChecks: [String]

        var title: String {
            switch verdict {
            case .noObviousSigns: "눈에 띄는 수정 흔적을 찾지 못했어요"
            case .suspicious: "운영자의 추가 확인이 필요해요"
            case .inconclusive: "자료만으로 판단하기 어려워요"
            }
        }
    }
    let reviewType: String
    let evidenceId: UUID
    let submittedAt: String
    let analyzedAt: String
    let humanReviewRequired: Bool
    let authenticityVerified: Bool
    let notice: String
    let assessment: Assessment
    var summary: OiDonationEvidenceSummary? = nil
}

struct OiWritingGrant: Codable, Identifiable, Equatable {
    let id: UUID
    let storyLimit: Int
    let revokedAt: String?
}

struct OiOwnedStory: Codable, Identifiable {
    let storyId: UUID
    let createdAt: String?
    var id: UUID { storyId }
}

struct OiCollectionMetric: Decodable {
    let storyId: UUID
    let collectionCount: Int
}

struct OiMedia: Codable, Identifiable {
    let id: UUID
    let storyId: UUID
    let objectPath: String
    let position: Int
}

nonisolated struct OiFarmerOutfit: Codable, Equatable, Sendable {
    var version = 1
    var character: String
    var slots: [String: String]

    var isValid: Bool {
        guard version == 1, ["kyu", "cumber"].contains(character), slots.count <= 6 else { return false }
        let allowedSlots: Set<String> = ["top", "bottom", "shoes", "hat", "accessory", "set"]
        return slots.allSatisfy { key, value in
            guard allowedSlots.contains(key), let first = value.utf8.first,
                  (97...122).contains(first) || (48...57).contains(first), value.utf8.count <= 80 else { return false }
            return value.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
        }
    }
}

nonisolated struct OiFarmerOutfitReceipt: Decodable, Sendable {
    let accountId: UUID
    let outfit: OiFarmerOutfit?

    private enum CodingKeys: String, CodingKey { case accountId, outfit }
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.contains(.outfit) else {
            throw DecodingError.keyNotFound(CodingKeys.outfit, .init(codingPath: decoder.codingPath,
                debugDescription: "The farmer outfit receipt must contain its nullable outfit field."))
        }
        accountId = try container.decode(UUID.self, forKey: .accountId)
        outfit = try container.decodeIfPresent(OiFarmerOutfit.self, forKey: .outfit)
    }
}

struct OiAccountDeletionStatus: Decodable {
    let accountId: UUID?
    let memberIds: [UUID]?
}

struct OiAccountDeletionReceipt: Codable {
    let deleted: Bool
    let appleRevocationRequired: Bool
    let deletedMemberIds: [UUID]
}

struct OiCapabilities: Decodable {
    let `operator`: Bool
    let coinsEnabled: Bool
    let unapprovedDraftsEnabled: Bool?
    let accountId: UUID?
    let accountMergeEnabled: Bool?
    let accountMemberIds: [UUID]?
    let accountProviders: [String]?
    let schoolProfileEnabled: Bool?
    let farmerOutfitEnabled: Bool?
}

/// Content validation is separate from permission. The server remains authoritative.
enum OiWritingAccess {
    static func canWrite(grantID: UUID?, grants: [OiWritingGrant], unapprovedDraftsEnabled: Bool) -> Bool {
        if let grantID { return grants.contains { $0.id == grantID && $0.revokedAt == nil } }
        return unapprovedDraftsEnabled
    }
}

struct OiStoryDraft: Codable, Equatable {
    var id = UUID()
    var grantId: UUID?
    var revision = 0
    var regionId = "pond"
    var title = ""
    var body = ""
    var theme = ""
    var emotion = ""
    var cucumberName = ""
    var cucumberAsset = "OiCats"
    var cardAsset = "MYBasicCard"
    var latitude: Double?
    var longitude: Double?

    init() {}

    init(story: OiLiveStory) {
        id = story.id; grantId = story.grantId; revision = story.revision
        regionId = story.regionId; title = story.title; body = story.body
        theme = story.theme; emotion = story.emotion; cucumberName = story.cucumberName
        cucumberAsset = story.cucumberAsset; cardAsset = story.cardAsset
        latitude = story.latitude; longitude = story.longitude
    }

    var valid: Bool {
        latitude != nil && longitude != nil &&
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !theme.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !emotion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !cucumberName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func payload() throws -> [String: Any] {
        guard valid, let latitude, let longitude else { throw OiServiceError.invalidDraft }
        return ["id": id.uuidString, "grant_id": grantId.map { $0.uuidString as Any } ?? NSNull(), "revision": revision,
                "region_id": regionId, "title": title, "body": body, "theme": theme,
                "emotion": emotion, "cucumber_name": cucumberName, "cucumber_asset": cucumberAsset,
                "card_asset": cardAsset, "latitude": latitude, "longitude": longitude]
    }
}

nonisolated struct OiSchoolEvidenceReview: Decodable, Sendable {
    nonisolated struct Summary: Decodable, Sendable {
        let outcome: String
    }

    let reviewType: String
    let humanReviewRequired: Bool
    let affiliationVerified: Bool
    let authenticityVerified: Bool
    let summary: Summary?
}

nonisolated enum OiSchoolEvidenceOutcome: String, Codable, Sendable {
    // Keep the two legacy raw values so existing device receipts remain readable.
    case completed, rejected
    case documentNeeded = "school_document_needed"
    case retakeNeeded = "retake_needed"
    case manualReviewNeeded = "manual_review_needed"

    init?(reviewOutcome: String) {
        switch reviewOutcome {
        case "school_evidence_visible": self = .completed
        case "school_document_needed": self = .documentNeeded
        case "retake_needed": self = .retakeNeeded
        case "manual_review_needed": self = .manualReviewNeeded
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .completed: "AI 자료 확인 완료"
        case .rejected: "추가 확인 필요"
        case .documentNeeded: "학교 증빙 자료 필요"
        case .retakeNeeded: "재촬영 필요"
        case .manualReviewNeeded: "사람의 확인 필요"
        }
    }

    var guidance: String {
        switch self {
        case .completed: "자료에서 학교 관련 표기를 확인했어요."
        case .rejected: "이전에 저장한 결과에는 세부 사유가 없어요. 자료를 다시 확인해 주세요."
        case .documentNeeded: "학교명과 소속을 확인할 수 있는 자료를 첨부해 주세요."
        case .retakeNeeded: "자료의 글자가 잘 보이도록 다시 촬영해 주세요."
        case .manualReviewNeeded: "AI만으로 판단하기 어려워요. 운영팀에 확인 방법을 문의해 주세요. 자동으로 검토가 접수되지는 않아요."
        }
    }
}

nonisolated struct OiSavedSchoolEvidenceReview: Codable, Sendable {
    let outcome: OiSchoolEvidenceOutcome
    let reviewedAt: Date

    private enum CodingKeys: String, CodingKey { case outcome, reviewedAt, summary }

    init(outcome: OiSchoolEvidenceOutcome, reviewedAt: Date) {
        self.outcome = outcome
        self.reviewedAt = reviewedAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        reviewedAt = try values.decode(Date.self, forKey: .reviewedAt)
        if let outcome = try values.decodeIfPresent(OiSchoolEvidenceOutcome.self, forKey: .outcome) {
            self.outcome = outcome
        } else {
            let previous = try values.decode(OiSchoolEvidenceReview.Summary.self, forKey: .summary)
            guard let outcome = OiSchoolEvidenceOutcome(reviewOutcome: previous.outcome) else {
                throw DecodingError.dataCorruptedError(forKey: .summary, in: values,
                    debugDescription: "Unknown school evidence outcome")
            }
            self.outcome = outcome
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(outcome, forKey: .outcome)
        try values.encode(reviewedAt, forKey: .reviewedAt)
    }
}

enum OiServiceError: LocalizedError {
    case configuration, signInRequired, writingApprovalRequired, invalidDraft, invalidCallback, unavailable, accountChanged, authenticationFailed
    case server(String)
    case invalidInput, conflict
    case secureStorage(Int32)

    var errorDescription: String? {
        switch self {
        case .secureStorage(let status): "계정 저장소에 접근할 수 없습니다(코드 \(status)). 앱 서명과 키체인 권한을 확인해 주세요."
        case .configuration: "Supabase 연결 설정이 없습니다. 개발용 공개 키를 설정한 빌드를 사용해 주세요."
        case .signInRequired: "로그인이 필요합니다."
        case .authenticationFailed: "로그인을 완료하지 못했습니다. 계정과 로그인 설정을 확인한 뒤 다시 시도해 주세요."
        case .writingApprovalRequired: "서버 저장·검토 요청에는 작성 승인이 필요해요. 기존 글과 사진은 보관됩니다."
        case .invalidDraft: "모든 입력 항목과 캠퍼스의 야외 위치를 확인해 주세요."
        case .invalidCallback: "로그인 응답을 확인할 수 없습니다. 다시 로그인해 주세요."
        case .unavailable: "지금은 연결할 수 없습니다. 잠시 후 다시 시도해 주세요."
        case .accountChanged: "계정이 변경됐습니다. 다시 시도해 주세요."
        case .server(let message): message
        case .invalidInput: "입력값·첨부파일·승인 수량 또는 선택한 캠퍼스 위치를 확인해 주세요."
        case .conflict: "다른 작업으로 내용이 변경됐습니다. 새로고침 후 다시 시도해 주세요."
        }
    }
}

extension String {
    var oiStatusTitle: String {
        switch self {
        case "draft": "작성 중"
        case "pending": "운영자 검토 대기"
        case "approved": "작성 승인"
        case "rejected": "반려"
        case "changes_requested": "보완 요청"
        case "revoked": "승인 취소"
        case "published": "공개 중"
        case "hidden": "비공개"
        case "deleted": "삭제됨"
        default: "상태 확인 필요"
        }
    }
}


struct OiContentReport: Decodable, Identifiable, Sendable {
    let id: UUID
    let storyId: UUID
    let authorId: UUID
    let title: String
    let body: String
    let reason: String
    let detail: String
    let status: String
    let restricted: Bool
    let reviewNote: String?
}
struct OiContentReportReceipt: Decodable { let id: UUID; let status: String }
