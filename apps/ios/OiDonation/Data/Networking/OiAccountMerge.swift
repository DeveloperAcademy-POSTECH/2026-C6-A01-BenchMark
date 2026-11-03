// Created by 이돈혁

import Foundation

struct OiMergeCounts: Decodable {
    let stories: Int
    let collections: Int
    let favorites: Int
    let evidence: Int
    let grants: Int
}

struct OiMergePreview: Decodable {
    let challengeId: UUID
    let targetAccountId: UUID
    let sourceAccountId: UUID
    let sourceIsNew: Bool
    let expiresAt: String
    let counts: OiMergeCounts
}

struct OiMergeReceipt: Decodable {
    let accountId: UUID
    let alreadyMerged: Bool
}

enum OiMergeFailure: LocalizedError {
    case reviewChanged, reauthenticationRequired

    var errorDescription: String? {
        switch self {
        case .reviewChanged: "계정 기록이나 확인 정보가 변경됐습니다. 추가 로그인 없이 통합할 기록을 다시 확인해 주세요."
        case .reauthenticationRequired: "추가 인증의 유효 시간이 지났습니다. 현재 로그인은 유지됩니다. 만료된 계정만 다시 확인해 주세요."
        }
    }
}

extension OiServiceAPI {
    func previewMerge(target: OiSession, source: OiSession, operationID: UUID) async throws -> OiMergePreview {
        try await mergeRequest(target: target, source: source, payload: ["action": "preview", "operation_id": operationID.uuidString], as: OiMergePreview.self)
    }

    func confirmMerge(target: OiSession, source: OiSession, preview: OiMergePreview, operationID: UUID) async throws -> OiMergeReceipt {
        try await mergeRequest(target: target, source: source, payload: ["action": "confirm", "operation_id": operationID.uuidString,
            "challenge_id": preview.challengeId.uuidString, "consent": true], as: OiMergeReceipt.self)
    }

    private func mergeRequest<Value: Decodable>(target: OiSession, source: OiSession, payload: [String: Any], as type: Value.Type) async throws -> Value {
        var body = payload
        body["source_access_token"] = source.accessToken
        do {
            let data = try await request("functions/v1/account-merge", method: "POST", token: target.accessToken,
                                         body: JSONSerialization.data(withJSONObject: body))
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(Value.self, from: data)
        } catch OiServiceError.invalidInput {
            throw OiMergeFailure.reviewChanged
        } catch OiServiceError.signInRequired {
            throw OiMergeFailure.reauthenticationRequired
        } catch OiServiceError.conflict {
            throw OiMergeFailure.reviewChanged
        } catch OiServiceError.server {
            throw OiServiceError.server("이 계정은 통합할 수 없습니다. 두 계정의 최근 인증과 운영자 계정 여부를 확인해 주세요.")
        }
    }
}
