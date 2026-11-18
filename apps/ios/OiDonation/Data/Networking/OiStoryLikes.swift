//
//  OiStoryLikes.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/18/26.
//

import Foundation

enum OiStoryLikeError: LocalizedError {
    case notSupported
    var errorDescription: String? { "좋아요는 서버 업데이트 후 사용할 수 있어요." }
}

/// Public like count of one story and whether the signed-in account has liked it.
nonisolated struct OiStoryLike: Decodable, Equatable, Sendable {
    let storyId: UUID
    let count: Int
    let liked: Bool
}

extension OiServiceAPI {
    /// Anonymous callers receive counts only; a signed-in token also reveals their own `liked` state.
    func storyLikes(_ stories: [UUID], token: String?) async throws -> [OiStoryLike] {
        try await likeRPC("oi_story_likes", payload: ["p_stories": stories.map(\.uuidString)], token: token)
    }

    func setStoryLike(_ story: UUID, liked: Bool, token: String) async throws -> OiStoryLike {
        try await likeRPC("oi_set_story_like", payload: ["p_story": story.uuidString, "p_liked": liked], token: token)
    }

    private func likeRPC<Value: Decodable>(_ name: String, payload: [String: Any], token: String?) async throws -> Value {
        let bytes = try await request("rest/v1/rpc/\(name)", method: "POST", token: token,
            body: JSONSerialization.data(withJSONObject: payload))
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Value.self, from: bytes)
    }
}
