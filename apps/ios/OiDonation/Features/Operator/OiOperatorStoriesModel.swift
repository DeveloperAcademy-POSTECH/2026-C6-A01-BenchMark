import Foundation
import Observation

enum OiOperatorStoryFilter: String, CaseIterable, Identifiable {
    case pending, published, hidden, all
    var id: String { rawValue }
    var title: String {
        switch self { case .pending: "검토 대기"; case .published: "공개"; case .hidden: "비공개"; case .all: "전체" }
    }
    func contains(_ story: OiLiveStory) -> Bool {
        self == .all || story.status == rawValue
    }
}

struct OiOperatorStoryDetail {
    let story: OiLiveStory
    let media: [OiMedia]
}

struct OiOperatorStoryReviewResult {
    let story: OiLiveStory
    let warning: String?
}

enum OiOperatorStoryError: LocalizedError {
    case accessDenied, busy, unconfirmedResult, storyUnavailable
    var errorDescription: String? {
        switch self {
        case .accessDenied: "운영자 권한이 없어 이야기를 확인하거나 처리할 수 없어요."
        case .busy: "다른 작업을 처리 중이에요. 완료된 뒤 다시 확인해 주세요."
        case .unconfirmedResult: "처리 결과를 확인하지 못했어요. 중복 처리하지 말고 최신 내용을 다시 불러와 주세요."
        case .storyUnavailable: "이야기가 삭제되었거나 더 이상 검토할 수 없는 상태예요. 목록을 새로고침해 주세요."
        }
    }
}

@MainActor protocol OiOperatorStoryServing {
    func operatorStories() async throws -> [OiLiveStory]
    func operatorStory(_ id: UUID) async throws -> OiOperatorStoryDetail
    func reviewOperatorStory(_ story: OiLiveStory, publish: Bool) async throws -> OiOperatorStoryReviewResult
}

@MainActor @Observable
final class OiOperatorStoriesModel {
    var filter: OiOperatorStoryFilter = .pending
    private(set) var stories: [OiLiveStory] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var error: String?
    private var requestID = UUID()
    var filtered: [OiLiveStory] { stories.filter { filter.contains($0) } }

    func load(using service: any OiOperatorStoryServing) async {
        guard !isLoading else { return }
        let request = UUID(); requestID = request
        isLoading = true; error = nil
        defer { if requestID == request { isLoading = false } }
        do {
            let values = try await service.operatorStories()
            try Task.checkCancellation()
            guard requestID == request else { return }
            stories = values; hasLoaded = true
        } catch {
            guard requestID == request else { return }
            stories = []; hasLoaded = false
            if !OiServiceFailure.isCancellation(error) { self.error = error.localizedDescription }
        }
    }

    func apply(_ story: OiLiveStory) {
        // Reject a late read that started before this confirmed write.
        requestID = UUID(); isLoading = false
        stories.removeAll { $0.id == story.id }
        if ["pending", "published", "hidden"].contains(story.status) { stories.insert(story, at: 0) }
        stories.sort { $0.createdAt == $1.createdAt ? $0.id.uuidString > $1.id.uuidString : $0.createdAt > $1.createdAt }
    }
}

@MainActor @Observable
final class OiOperatorStoryModel {
    private(set) var detail: OiOperatorStoryDetail?
    private(set) var isLoading = false
    private(set) var isProcessing = false
    private(set) var error: String?
    private(set) var notice: String?
    private(set) var warning: String?
    private(set) var requiresReload = false
    private var requestID = UUID()
    var canReview: Bool { detail != nil && !isLoading && !isProcessing && !requiresReload }

    func load(_ id: UUID, using service: any OiOperatorStoryServing) async {
        guard !isProcessing, !isLoading else { return }
        let request = UUID(); requestID = request
        isLoading = true; detail = nil; error = nil; notice = nil; warning = nil
        requiresReload = true
        defer { if requestID == request { isLoading = false } }
        do {
            let value = try await service.operatorStory(id)
            try Task.checkCancellation()
            guard requestID == request else { return }
            detail = value; requiresReload = false
        } catch {
            guard requestID == request else { return }
            if !OiServiceFailure.isCancellation(error) { self.error = error.localizedDescription }
        }
    }

    func review(_ snapshot: OiLiveStory, publish: Bool,
                using service: any OiOperatorStoryServing) async -> OiLiveStory? {
        guard canReview else { return nil }
        guard detail?.story == snapshot else {
            requiresReload = true; error = "이야기 내용이 바뀌었어요. 최신 내용을 다시 확인해 주세요."; return nil
        }
        isProcessing = true; error = nil; notice = nil; warning = nil
        defer { isProcessing = false }
        do {
            let result = try await service.reviewOperatorStory(snapshot, publish: publish)
            // The server receipt is authoritative even if the following refresh failed.
            detail = OiOperatorStoryDetail(story: result.story, media: detail?.media ?? [])
            notice = publish ? "이야기를 공개했어요." : "이야기를 비공개로 변경했어요."
            warning = result.warning
            requiresReload = result.warning != nil
            return result.story
        } catch {
            requiresReload = true
            switch error {
            case OiServiceError.conflict:
                self.error = "다른 작업으로 이야기 상태가 바뀌었어요. 최신 내용을 다시 확인한 뒤 처리해 주세요."
            case OiServiceError.signInRequired, OiServiceError.accountChanged, OiOperatorStoryError.accessDenied:
                detail = nil; self.error = error.localizedDescription
            case OiOperatorStoryError.busy:
                self.error = error.localizedDescription
            default:
                self.error = "처리 결과를 확인하지 못했어요. 중복 처리하지 말고 최신 내용을 다시 불러와 주세요."
            }
            return nil
        }
    }
}
