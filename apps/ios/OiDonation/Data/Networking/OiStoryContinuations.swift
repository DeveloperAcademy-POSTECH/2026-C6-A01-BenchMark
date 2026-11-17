//
//  OiStoryContinuations.swift
//  OiDonation
//
//  Created by Codex on 2026/11/17.
//

import Foundation

enum OiContinuationError: LocalizedError {
    case notSupported
    var errorDescription: String? { "이어진 이야기는 서버 업데이트 후 사용할 수 있어요." }
}

struct OiStoryContinuation: Decodable, Equatable, Identifiable {
    let childStoryId: UUID
    let parentStoryId: UUID
    let publishedAt: String
    let readAt: String?
    let story: OiLiveStory
    var id: UUID { childStoryId }
}

nonisolated struct OiContinuationCursor: Codable, Equatable, Sendable {
    let publishedAt: String
    let childStoryId: UUID
}

struct OiContinuationPage: Decodable, Equatable {
    let items: [OiStoryContinuation]
    let total: Int
    let nextCursor: OiContinuationCursor?
}

nonisolated struct OiContinuationCount: Decodable, Sendable {
    let storyId: UUID
    let count: Int
}

nonisolated struct OiContinuationTarget: Decodable, Sendable {
    let storyId: UUID
    let continuedFromStoryId: UUID?
}

extension OiServiceAPI {
    func continuations(parent: UUID? = nil, mine: Bool = false, cursor: OiContinuationCursor? = nil,
                       blocked: [UUID], token: String? = nil) async throws -> OiContinuationPage {
        var payload: [String: Any] = ["p_mine": mine, "p_blocked": blocked.map(\.uuidString)]
        if let parent { payload["p_parent"] = parent.uuidString }
        if let cursor { payload["p_before"] = cursor.publishedAt; payload["p_before_id"] = cursor.childStoryId.uuidString }
        return try await continuationRPC("oi_story_continuations", payload: payload, token: token)
    }

    func continuationCounts(_ stories: [UUID], blocked: [UUID]) async throws -> [OiContinuationCount] {
        try await continuationRPC("oi_story_continuation_counts", payload: ["p_stories": stories.map(\.uuidString),
            "p_blocked": blocked.map(\.uuidString)], token: nil)
    }

    func continuationTargets(token: String) async throws -> [OiContinuationTarget] {
        try await continuationRPC("oi_my_story_continuation_targets", payload: [:], token: token)
    }

    func readContinuation(_ child: UUID, blocked: [UUID], token: String) async throws -> OiStoryContinuation {
        try await continuationRPC("oi_read_story_continuation", payload: ["p_child": child.uuidString,
            "p_blocked": blocked.map(\.uuidString)], token: token)
    }

    private func continuationRPC<Value: Decodable>(_ name: String, payload: [String: Any], token: String?) async throws -> Value {
        let bytes = try await request("rest/v1/rpc/\(name)", method: "POST", token: token,
            body: JSONSerialization.data(withJSONObject: payload))
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Value.self, from: bytes)
    }
}
