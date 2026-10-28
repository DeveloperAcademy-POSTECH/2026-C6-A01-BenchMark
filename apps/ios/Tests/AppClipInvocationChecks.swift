// Created by 이돈혁

import Foundation

private enum CheckError: Error { case failed }

private actor ControlledStoryRepository: StoryRepository {
    private var pending: [String: CheckedContinuation<Story?, Error>] = [:]
    private var waiting: [String: CheckedContinuation<Void, Never>] = [:]
    private(set) var requestCount = 0

    func fetchPublicStory(plaqueID: String) async throws -> Story? {
        requestCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            pending[plaqueID] = continuation
            waiting.removeValue(forKey: plaqueID)?.resume()
        }
    }

    func waitForRequest(_ id: String) async {
        if pending[id] != nil { return }
        await withCheckedContinuation { waiting[id] = $0 }
    }

    func finish(_ id: String, result: Result<Story?, Error>) {
        guard let continuation = pending.removeValue(forKey: id) else {
            preconditionFailure("Missing request: \(id)")
        }
        continuation.resume(with: result)
    }
}

@main
struct AppClipInvocationChecks {
    @MainActor
    static func main() async {
        let valid = [
            AppClipLink.defaultURLString,
            "https://APPCLIP.APPLE.COM/id?p=com.Spero.OiDonation.Clip",
            "https://appclip.apple.com:443/id?p=com.Spero.OiDonation.Clip",
            "https://appclip.apple.com/id?campaign=nfc&p=com.Spero.OiDonation.Clip",
            "https://appclip.apple.com/id?p=com.Spero.OiDonation.Clip&source=bench"
        ]
        let invalid = [
            "http://appclip.apple.com/id?p=com.Spero.OiDonation.Clip",
            "https://appclip.apple.com.evil.org/id?p=com.Spero.OiDonation.Clip",
            "https://evil.org/id?p=com.Spero.OiDonation.Clip",
            "https://appclip.apple.com:444/id?p=com.Spero.OiDonation.Clip",
            "https://user@appclip.apple.com/id?p=com.Spero.OiDonation.Clip",
            "https://user:password@appclip.apple.com/id?p=com.Spero.OiDonation.Clip",
            "https://appclip.apple.com/id/extra?p=com.Spero.OiDonation.Clip",
            "https://appclip.apple.com/id/?p=com.Spero.OiDonation.Clip",
            "https://appclip.apple.com/%69d?p=com.Spero.OiDonation.Clip",
            "https://appclip.apple.com/id?p=com.Spero.OiDonation.Clip#fragment",
            "https://appclip.apple.com/id?p=com.Spero.OiDonation.Clip#",
            "https://appclip.apple.com/id?p=com.other.Clip",
            "https://appclip.apple.com/id?p=com.spero.oidonation.clip",
            "https://appclip.apple.com/id?p=com.Spero.OiDonation",
            "https://appclip.apple.com/id",
            "https://appclip.apple.com/id?p=",
            "https://appclip.apple.com/id?p",
            "https://appclip.apple.com/id?P=com.Spero.OiDonation.Clip",
            "https://appclip.apple.com/id?p=com.Spero.OiDonation.Clip&p=com.other.Clip",
            "https://appclip.apple.com/id?p=com.Spero.OiDonation.Clip&%70=com.Spero.OiDonation.Clip"
        ]
        for value in valid { require(AppClipLink.matches(url(value)), "valid default link: \(value)") }
        for value in invalid { require(!AppClipLink.matches(url(value)), "reject link: \(value)") }

        let repository = ControlledStoryRepository()
        let model = AppClipViewModel(storyRepository: repository)
        require(model.state == .welcome, "direct launch must not wait for a missing activity")
        for value in valid {
            await model.handleInvocationURL(invocationURL: url(value))
            require(model.state == .welcome && model.story == nil && model.plaqueID == nil, "default launch")
        }
        let count = await repository.requestCount
        require(count == 0, "generic NFC link must not fetch an invented plaque")
        await model.handleInvocationURL(invocationURL: url("https://example.com/stories/preview-plaque"))
        require(model.state == .invalidLink, "sample domain must not be enabled in production")
        await model.handleInvocationURL(invocationURL: nil)
        require(model.state == .invalidLink && model.invocationURL == nil, "nil activity")
        await model.handleInvocationURL(invocationURL: url(AppClipLink.defaultURLString))
        require(model.state == .welcome, "recover after invalid activity")
        let cancelledBeforeStart = Task { await model.handleInvocationURL(invocationURL: nil) }
        cancelledBeforeStart.cancel()
        await cancelledBeforeStart.value
        require(model.state == .welcome, "a previously cancelled invocation must not change current state")

        let router = AppRouter()
        router.selectedTab = .benches
        router.storyPath = [.story("old")]
        router.isARPresented = true
        router.open(url(invalid[0]))
        require(router.selectedTab == .benches && router.isARPresented, "untrusted URL must preserve navigation")
        router.open(url(AppClipLink.defaultURLString))
        require(router.selectedTab == .home && router.storyPath.isEmpty && !router.isARPresented, "installed app opens Home")

        let storyModel = AppClipViewModel(linkParser: PublicLinkParser(allowedHost: "approved.example"),
                                         storyRepository: repository)
        let story = Story(plaqueID: "first", donorID: UUID(), title: "Test", content: "Test content")
        let first = Task { await storyModel.handleInvocationURL(invocationURL: url("https://approved.example/stories/first")) }
        await repository.waitForRequest("first")
        require(storyModel.state == .loading, "story loading")
        await repository.finish("first", result: .success(story))
        await first.value
        require(storyModel.state == .ready && storyModel.story?.plaqueID == "first", "story success")

        let delayed = Task { await storyModel.handleInvocationURL(invocationURL: url("https://approved.example/stories/delayed")) }
        await repository.waitForRequest("delayed")
        await storyModel.handleInvocationURL(invocationURL: url(AppClipLink.defaultURLString))
        await repository.finish("delayed", result: .success(story))
        await delayed.value
        require(storyModel.state == .welcome && storyModel.story == nil && storyModel.plaqueID == nil, "stale success cannot replace a newer launch")

        let staleFailure = Task { await storyModel.handleInvocationURL(invocationURL: url("https://approved.example/stories/stale-failure")) }
        await repository.waitForRequest("stale-failure")
        await storyModel.handleInvocationURL(invocationURL: nil)
        await repository.finish("stale-failure", result: .failure(CheckError.failed))
        await staleFailure.value
        require(storyModel.state == .invalidLink && storyModel.story == nil, "stale error cannot replace a newer invalid activity")

        let missing = Task { await storyModel.handleInvocationURL(invocationURL: url("https://approved.example/stories/missing")) }
        await repository.waitForRequest("missing")
        await repository.finish("missing", result: .success(nil))
        await missing.value
        require(storyModel.state == .storyNotFound, "missing story")

        let failed = Task { await storyModel.handleInvocationURL(invocationURL: url("https://approved.example/stories/failed")) }
        await repository.waitForRequest("failed")
        await repository.finish("failed", result: .failure(CheckError.failed))
        await failed.value
        require(storyModel.state == .loadFailed, "fetch error")

        let cancelled = Task { await storyModel.handleInvocationURL(invocationURL: url("https://approved.example/stories/cancelled")) }
        await repository.waitForRequest("cancelled")
        cancelled.cancel()
        await storyModel.handleInvocationURL(invocationURL: url(AppClipLink.defaultURLString))
        await repository.finish("cancelled", result: .success(story))
        await cancelled.value
        require(storyModel.state == .welcome && storyModel.story == nil, "cancelled task must not publish content")
        print("PASS: \(valid.count) valid / \(invalid.count) invalid App Clip links, default launch, installed-app routing, story states, cancellation and stale responses")
    }

    private static func url(_ value: String) -> URL {
        guard let url = URL(string: value) else { preconditionFailure("Invalid test URL: \(value)") }
        return url
    }

    private static func require(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message)
    }
}
