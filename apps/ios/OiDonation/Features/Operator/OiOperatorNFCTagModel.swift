//
//  OiOperatorNFCTagModel.swift
//  OiDonation
//
//  Created by jiwon hong on 11/13/26.
//

import Foundation

/// One NFC postcard tag as returned by `oi_operator_nfc_tags` (#310).
struct OiNFCTag: Decodable, Identifiable, Equatable, Sendable {
    let tagId: String
    let storyId: UUID?
    let active: Bool
    let note: String
    let updatedAt: String?
    let storyTitle: String?
    let storyStatus: String?

    var id: String { tagId }
    var url: URL { AppClipLink.postcardURL(tagId) }

    /// Mirrors `oi_nfc_postcard`: the App Clip shows a postcard only for an active tag on a published story.
    /// Author restrictions are not visible here, so a tag marked open can still be withheld by moderation.
    var opensPostcard: Bool { active && storyId != nil && storyStatus == "published" }

    var statusText: String {
        if !active { return "중지됨" }
        guard storyId != nil else { return "연결된 이야기 없음" }
        switch storyStatus {
        case "published": return "엽서 열림"
        case "pending": return "이야기 검토 대기 · 아직 열리지 않음"
        case "hidden": return "이야기 비공개 · 열리지 않음"
        case "deleted", nil: return "이야기 삭제됨 · 열리지 않음"
        default: return "이야기 공개 전 · 열리지 않음"
        }
    }
}

enum OiNFCTagID {
    /// Lowercase letters and digits without look-alikes (0/o, 1/l/i) so an ID read off a label is unambiguous.
    static let alphabet = Array("abcdefghjkmnpqrstuvwxyz23456789")

    /// Suggests `oi-` plus six random characters, avoiding IDs already in `existing`.
    static func suggestion(avoiding existing: Set<String>) -> String {
        var generator = SystemRandomNumberGenerator()
        while true {
            let id = "oi-" + String((0..<6).map { _ in alphabet.randomElement(using: &generator)! })
            if !existing.contains(id) { return id }
        }
    }
}

struct OiNFCTagReceipt: Decodable, Equatable, Sendable {
    let tagId: String
    let storyId: UUID?
    let active: Bool
    let note: String
}

enum OiNFCTagError: LocalizedError {
    case notDeployed, invalidTag, mismatchedReceipt, duplicateTag

    static let rpcPaths: Set<String> = ["rest/v1/rpc/oi_operator_nfc_tags", "rest/v1/rpc/oi_operator_set_nfc_tag"]
    static let noteLimit = 200

    var errorDescription: String? {
        switch self {
        case .notDeployed: "서버의 NFC 태그 기능이 아직 준비되지 않았어요. 마이그레이션 적용 상태를 확인해 주세요."
        case .invalidTag: "태그 ID는 영어 소문자·숫자·하이픈(-)으로 1~40자까지 입력해 주세요."
        case .mismatchedReceipt: "저장 결과를 확인하지 못했어요. 목록을 새로고침해 상태를 확인해 주세요."
        case .duplicateTag: "방금 다른 운영자가 같은 태그 ID를 등록했어요. 새 ID로 다시 저장해 주세요."
        }
    }
}

extension OiServiceAPI {
    private static let nfcDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    func operatorNFCTags(token: String) async throws -> [OiNFCTag] {
        let data = try await request("rest/v1/rpc/oi_operator_nfc_tags", method: "POST", token: token, body: Data("{}".utf8))
        return try Self.nfcDecoder.decode([OiNFCTag].self, from: data)
    }

    func setNFCTag(_ tagID: String, story: UUID?, active: Bool, note: String, token: String) async throws -> OiNFCTagReceipt {
        guard AppClipLink.isValidPostcardTag(tagID) else { throw OiNFCTagError.invalidTag }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= OiNFCTagError.noteLimit else { throw OiServiceError.invalidInput }
        let body = try JSONSerialization.data(withJSONObject: [
            "p_tag": tagID,
            "p_story": story.map { $0.uuidString.lowercased() as Any } ?? NSNull(),
            "p_active": active,
            "p_note": trimmed
        ])
        let data = try await request("rest/v1/rpc/oi_operator_set_nfc_tag", method: "POST", token: token, body: body)
        let receipt = try Self.nfcDecoder.decode(OiNFCTagReceipt.self, from: data)
        guard receipt.tagId == tagID, receipt.storyId == story, receipt.active == active else {
            throw OiNFCTagError.mismatchedReceipt
        }
        return receipt
    }
}
