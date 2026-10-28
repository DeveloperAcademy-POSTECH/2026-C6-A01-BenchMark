// Created by 이돈혁

import Foundation

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

    var needsRefresh: Bool { (expiresAt ?? 0) < Date().timeIntervalSince1970 + 60 }
}

protocol OiSessionStorage {
    func read() throws -> OiSession?
    func write(_ session: OiSession?) throws
}

struct OiProfile: Codable, Equatable, Identifiable {
    let id: UUID
    var nickname: String
    var schoolId: String?
    let farmerAsset: String
}

struct OiLiveStory: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    let grantId: UUID
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

struct OiEvidence: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    let status: String
    let objectPath: String?
    let reviewNote: String?
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

struct OiCapabilities: Decodable {
    let `operator`: Bool
    let coinsEnabled: Bool
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
        grantId != nil && latitude != nil && longitude != nil &&
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !theme.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !emotion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !cucumberName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func payload() throws -> [String: Any] {
        guard valid, let grantId, let latitude, let longitude else { throw OiServiceError.invalidDraft }
        return ["id": id.uuidString, "grant_id": grantId.uuidString, "revision": revision,
                "region_id": regionId, "title": title, "body": body, "theme": theme,
                "emotion": emotion, "cucumber_name": cucumberName, "cucumber_asset": cucumberAsset,
                "card_asset": cardAsset, "latitude": latitude, "longitude": longitude]
    }
}

enum OiServiceError: LocalizedError {
    case configuration, signInRequired, invalidDraft, invalidCallback, unavailable, accountChanged
    case server(String)
    case invalidInput, conflict

    var errorDescription: String? {
        switch self {
        case .configuration: "Supabase 연결 설정이 없습니다. 개발용 공개 키를 설정한 빌드를 사용해 주세요."
        case .signInRequired: "로그인이 필요합니다."
        case .invalidDraft: "작성 승인과 모든 입력 항목, 캠퍼스 바깥 공간의 위치를 확인해 주세요."
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
