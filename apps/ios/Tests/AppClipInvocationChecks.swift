//
//  AppClipInvocationChecks.swift
//  OiDonation
//
//  Created by 이돈혁 on 10/22/26.
//

import Foundation

private enum CheckError: Error { case failed }

private actor ControlledStoryRepository: StoryRepository {
    private var pending: [String: CheckedContinuation<Story?, Error>] = [:]
    private var waiting: [String: CheckedContinuation<Void, Never>] = [:]
    private(set) var requestCount = 0

    func fetchPublicStory(storyID: String) async throws -> Story? {
        requestCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            pending[storyID] = continuation
            waiting.removeValue(forKey: storyID)?.resume()
        }
    }

    func fetchPublicStoryCard(storyID: String) async throws -> StoryCard? {
        guard storyID != "missing-card" else { return nil }
        let imageURL = URL(string: "https://example.com/story-cards/\(storyID).png")
            ?? URL(fileURLWithPath: "/\(storyID).png")
        return StoryCard(cardID: "card-\(storyID)", storyID: storyID, imageURL: imageURL)
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

private actor BrowseRepository: StoryRepository {
    let id = UUID(uuidString: "19900000-0000-4000-8000-000000000001")!
    var fails = false
    var removed = false
    var offsets: [Int] = []
    func setFailure(_ value: Bool) { fails = value }
    func removeStory() { removed = true }
    func fetchPublicStories(offset: Int) async throws -> [PublicStorySummary] {
        offsets.append(offset)
        if fails { throw CheckError.failed }
        if removed || offset > 0 { return [] }
        return Array(repeating: PublicStorySummary(id: id, userId: id, title: "가상 검사 이야기", cucumberName: "검사 오이"), count: 20)
    }
    func fetchPublicStory(storyID: String) async throws -> Story? {
        if removed { return nil }
        return Story(storyID: id.uuidString, donorID: id, donorDisplayName: "가상 농부", title: "가상 검사", content: "테스트 전용",
            publishedAt: Date(), location: StoryLocation(locationID: "pond", displayName: "검사 장소"), tags: [], cucumberID: id.uuidString, cucumberName: "검사 오이")
    }
    func fetchPublicStoryCard(storyID: String) async throws -> StoryCard? {
        StoryCard(cardID: id.uuidString, storyID: id.uuidString, imageURL: nil)
    }
}

@MainActor
private final class ControlledGameClock {
    private var sleepers: [CheckedContinuation<Void, Error>] = []
    private var observer: CheckedContinuation<Void, Never>?
    private(set) var sleepCount = 0
    private(set) var now: TimeInterval = 0

    func sleep() async throws {
        sleepCount += 1
        try await withCheckedThrowingContinuation { continuation in
            sleepers.append(continuation)
            observer?.resume()
            observer = nil
        }
    }

    func waitForSleep() async {
        if !sleepers.isEmpty { return }
        await withCheckedContinuation { observer = $0 }
    }

    func advanceTime(by seconds: TimeInterval) { now += seconds }

    func advance(by seconds: TimeInterval = 1) {
        advanceTime(by: seconds)
        sleepers.removeFirst().resume()
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

        let browseRepository = BrowseRepository()
        let browse = AppClipViewModel(storyRepository: browseRepository)
        await browse.loadPublicStories(reset: true)
        require(browse.publicStories.count == 1 && browse.hasMoreStories, "deduplicates a public page without losing pagination")
        await browse.loadPublicStories()
        let offsets = await browseRepository.offsets
        require(offsets == [0, 20] && !browse.hasMoreStories, "pagination uses server row count")
        await browseRepository.setFailure(true)
        await browse.loadPublicStories(reset: true)
        require(browse.listError != nil && browse.publicStories.count == 1, "refresh failure preserves previously loaded content")
        await browseRepository.setFailure(false)
        let browseID = await browseRepository.id
        let storyURL = AppClipLink.storyURL(browseID)
        require(AppClipLink.storyID(in: storyURL) == browseID.uuidString, "story URL round trip")
        require(!AppClipLink.matches(url(AppClipLink.defaultURLString + "&story=bad")), "reject malformed story")
        require(!AppClipLink.matches(url(storyURL.absoluteString + "&story=" + browseID.uuidString)), "reject duplicated story parameter")
        await browse.handleInvocationURL(invocationURL: storyURL)
        require(browse.state == .ready && browse.story?.storyID == browseID.uuidString, "production configuration reaches actual story without a custom host")
        let canCollect = await browse.canCollectCurrentStory()
        require(canCollect, "published story can be collected")
        let appRouter = AppRouter()
        appRouter.open(storyURL)
        require(appRouter.storyPath == [.story(browseID.uuidString)], "installed app opens the same story")
        await browseRepository.removeStory()
        let removedCanCollect = await browse.canCollectCurrentStory()
        require(!removedCanCollect, "withdrawn story cannot be saved after an AR round")
        browse.showWelcome()
        await browse.loadPublicStories(reset: true)
        require(browse.publicStories.isEmpty && browse.listError == nil, "real empty state has no invented stories")
        print("PASS: public browsing, pagination, retry, direct production story link and revoked collection")

        let repository = ControlledStoryRepository()
        let model = AppClipViewModel(storyRepository: repository)
        require(model.state == .welcome, "direct launch must not wait for a missing activity")
        for value in valid {
            await model.handleInvocationURL(invocationURL: url(value))
            require(model.state == .welcome && model.story == nil && model.storyID == nil, "default launch")
        }
        let count = await repository.requestCount
        require(count == 0, "generic NFC link must not fetch an invented story")
        await model.handleInvocationURL(invocationURL: url("https://example.com/stories/preview-story"))
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
        let story = Story(
            storyID: "first",
            donorID: UUID(),
            donorDisplayName: "Test donor",
            title: "Test",
            content: "Test content",
            publishedAt: Date(timeIntervalSince1970: 0),
            location: StoryLocation(locationID: "test-location", displayName: "Test location"),
            tags: ["Test"],
            cucumberID: "test-cucumber",
            cucumberName: "Test cucumber"
        )
        let first = Task { await storyModel.handleInvocationURL(invocationURL: url("https://approved.example/stories/first")) }
        await repository.waitForRequest("first")
        require(storyModel.state == .loading, "story loading")
        await repository.finish("first", result: .success(story))
        await first.value
        require(storyModel.state == .ready && storyModel.story?.storyID == "first", "story success")
        require(storyModel.experience?.storyCard.storyID == "first", "story card success")

        let delayed = Task { await storyModel.handleInvocationURL(invocationURL: url("https://approved.example/stories/delayed")) }
        await repository.waitForRequest("delayed")
        await storyModel.handleInvocationURL(invocationURL: url(AppClipLink.defaultURLString))
        await repository.finish("delayed", result: .success(story))
        await delayed.value
        require(storyModel.state == .welcome && storyModel.story == nil && storyModel.storyID == nil, "stale success cannot replace a newer launch")

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

        let missingCard = Task { await storyModel.handleInvocationURL(invocationURL: url("https://approved.example/stories/missing-card")) }
        await repository.waitForRequest("missing-card")
        await repository.finish("missing-card", result: .success(story))
        await missingCard.value
        require(storyModel.state == .loadFailed && storyModel.experience == nil, "missing story card")

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

        let gameClock = ControlledGameClock()
        let gameModel = ARGameViewModel(
            timeLimitSeconds: 2,
            isARSupported: { true },
            requestCameraAccess: { true },
            monotonicNow: { gameClock.now }
        )
        require(gameModel.state == .introBackground, "AR game starts at intro background")
        await gameModel.resolvePermission()
        require(gameModel.state == .introBackground, "AR game ignores permission resolution during intro background")
        gameModel.requestPermission()
        require(gameModel.state == .introBackground, "AR game ignores permission requests during intro background")
        gameModel.showIntro()
        require(gameModel.state == .intro, "AR game shows intro after background transition")
        gameModel.requestPermission()
        require(gameModel.state == .requestingPermission, "AR game requests permission")
        await gameModel.resolvePermission()
        require(gameModel.state == .starting, "AR game enters the shared camera container before animation")
        gameModel.collectCucumber()
        gameClock.advanceTime(by: 3)
        gameModel.updateRemainingTime()
        await gameModel.runTimer()
        require(gameModel.collectedCount == 0 && gameModel.remainingSeconds == 2, "starting blocks collection and timer")
        gameModel.finishStartAnimation()
        gameModel.finishStartAnimation()
        require(gameModel.state == .playing, "AR game enables collection after animation")
        gameModel.collectCucumber()
        gameModel.collectCucumber()
        require(gameModel.state == .playing, "AR game continues before target count")
        gameModel.collectCucumber()
        require(gameModel.state == .success, "AR game reaches success")
        gameModel.showStoryCard()
        require(gameModel.state == .storyCard, "AR game opens the story card after success")

        let collectionSuite = "AppClipInvocationChecks.\(UUID().uuidString)"
        guard let collectionDefaults = UserDefaults(suiteName: collectionSuite) else {
            preconditionFailure("Unable to create collection test defaults")
        }
        collectionDefaults.removePersistentDomain(forName: collectionSuite)
        let storyCard = storyModel.experience?.storyCard
            ?? StoryCard(
                cardID: "card-first",
                storyID: "first",
                imageURL: url("https://example.com/story-cards/first.png")
            )
        let collectionStore = StoryCollectionStore(defaults: collectionDefaults)
        require(collectionStore.collect(storyCard, at: Date(timeIntervalSince1970: 1)), "first collection is stored")
        require(!collectionStore.collect(storyCard, at: Date(timeIntervalSince1970: 2)), "duplicate collection is ignored")
        require(collectionStore.cards.count == 1, "one collection record is stored per story")
        let reopenedCollectionStore = StoryCollectionStore(defaults: collectionDefaults)
        require(reopenedCollectionStore.cards == collectionStore.cards, "full app can reopen App Clip collection records")
        let collectionKey = "collectedStoryCards.v1"
        let validPayload = collectionDefaults.data(forKey: collectionKey)
        let damagedPayload = Data("invalid local collection data".utf8)
        collectionDefaults.set(damagedPayload, forKey: collectionKey)
        let damagedStore = StoryCollectionStore(defaults: collectionDefaults)
        require(damagedStore.persistenceError != nil, "reopening reports unreadable App Clip records")
        require(!damagedStore.collect(storyCard), "collect cannot overwrite unreadable records")
        require(!reopenedCollectionStore.remove(storyID: storyCard.storyID), "delete cannot replace unreadable records")
        require(reopenedCollectionStore.contains(storyID: storyCard.storyID), "a failed deletion retains the last readable card in memory")
        require(collectionDefaults.data(forKey: collectionKey) == damagedPayload, "corrupt bytes survive failed mutations")

        collectionDefaults.set(validPayload, forKey: collectionKey)
        require(!reopenedCollectionStore.collect(storyCard, at: Date(timeIntervalSince1970: 3)),
                "after recovery the original card still deduplicates")
        require(reopenedCollectionStore.persistenceError == nil, "a readable store clears the error on retry")
        require(reopenedCollectionStore.remove(storyID: storyCard.storyID), "a selected preview collection record can be reset")
        require(reopenedCollectionStore.cards.isEmpty, "confirmed deletion clears the in-memory card")
        require(StoryCollectionStore(defaults: collectionDefaults).cards.isEmpty, "confirmed deletion persists")
        collectionDefaults.removePersistentDomain(forName: collectionSuite)

        gameModel.reset()
        gameModel.requestPermission()
        await gameModel.resolvePermission()
        gameModel.finishStartAnimation()
        gameClock.advanceTime(by: 1)
        gameModel.updateRemainingTime()
        require(gameModel.state == .playing, "AR game continues before timer expires")
        gameClock.advanceTime(by: 1)
        gameModel.updateRemainingTime()
        require(gameModel.state == .failure, "AR game reaches failure")
        gameModel.reset()
        require(gameModel.state == .intro, "AR game resets to intro")

        let clock = ControlledGameClock()
        let timedGame = ARGameViewModel(
            timeLimitSeconds: 3,
            isARSupported: { true },
            requestCameraAccess: { true },
            sleepOneSecond: { try await clock.sleep() },
            monotonicNow: { clock.now }
        )
        timedGame.showIntro()
        timedGame.requestPermission()
        await timedGame.resolvePermission()
        await timedGame.runTimer()
        require(clock.sleepCount == 0, "stable container's starting task must not tick")
        timedGame.finishStartAnimation()
        let firstTimer = Task { await timedGame.runTimer() }
        await clock.waitForSleep()
        await timedGame.runTimer()
        require(clock.sleepCount == 1, "duplicate timer invocation must not create another loop")
        clock.advance()
        await clock.waitForSleep()
        require(timedGame.remainingSeconds == 2, "playing transition starts exactly one tick")
        firstTimer.cancel()
        clock.advance(by: 0)
        await firstTimer.value
        require(timedGame.remainingSeconds == 2, "cancellation after sleep must not decrement")

        let staleTimer = Task { await timedGame.runTimer() }
        await clock.waitForSleep()
        timedGame.reset()
        require(timedGame.collectedCount == 0 && timedGame.remainingSeconds == 3, "retry resets round state")
        timedGame.requestPermission()
        await timedGame.resolvePermission()
        timedGame.finishStartAnimation()
        clock.advance(by: 0)
        await staleTimer.value
        require(timedGame.remainingSeconds == 3, "previous round's wakeup must not tick the new round")
        let retryTimer = Task { await timedGame.runTimer() }
        await clock.waitForSleep()
        clock.advance()
        await clock.waitForSleep()
        require(timedGame.remainingSeconds == 2, "retry owns one new timer")
        timedGame.cameraBecameUnavailable()
        clock.advance()
        await retryTimer.value
        require(timedGame.state == .cameraUnavailable && timedGame.remainingSeconds == 2,
                "camera interruption ends the round without further ticks")

        let delayedClock = ControlledGameClock()
        let delayedGame = ARGameViewModel(
            timeLimitSeconds: 5,
            isARSupported: { true },
            requestCameraAccess: { true },
            sleepOneSecond: { try await delayedClock.sleep() },
            monotonicNow: { delayedClock.now }
        )
        delayedGame.showIntro()
        delayedGame.requestPermission()
        await delayedGame.resolvePermission()
        delayedClock.advanceTime(by: 10)
        delayedGame.finishStartAnimation()
        let delayedTimer = Task { await delayedGame.runTimer() }
        await delayedClock.waitForSleep()
        delayedClock.advance(by: 3)
        await delayedClock.waitForSleep()
        require(delayedGame.remainingSeconds == 2, "a delayed wake must account for all elapsed seconds")
        delayedGame.finishStartAnimation()
        delayedClock.advance(by: 2)
        await delayedTimer.value
        require(delayedGame.state == .failure && delayedGame.remainingSeconds == 0,
                "duplicate completion cannot extend the original deadline")

        let tapClock = ControlledGameClock()
        let tapGame = ARGameViewModel(
            timeLimitSeconds: 2,
            isARSupported: { true },
            requestCameraAccess: { true },
            monotonicNow: { tapClock.now }
        )
        tapGame.showIntro()
        tapGame.requestPermission()
        await tapGame.resolvePermission()
        tapGame.finishStartAnimation()
        tapGame.collectCucumber()
        tapGame.collectCucumber()
        tapClock.advanceTime(by: 2)
        tapGame.collectCucumber()
        require(tapGame.state == .failure && tapGame.collectedCount == 2 && tapGame.remainingSeconds == 0,
                "an input at the deadline must fail before the next timer wake and cannot win")

        var cameraAllowed = false
        let deniedGameModel = ARGameViewModel(
            isARSupported: { true },
            requestCameraAccess: { cameraAllowed }
        )
        deniedGameModel.showIntro()
        deniedGameModel.requestPermission()
        await deniedGameModel.resolvePermission()
        require(deniedGameModel.state == .permissionDenied, "AR game handles denied camera permission")
        cameraAllowed = true
        deniedGameModel.retryPermission()
        await deniedGameModel.resolvePermission()
        require(deniedGameModel.state == .starting, "settings return rechecks permission without losing the experience")

        let unavailableGameModel = ARGameViewModel(
            isARSupported: { false },
            requestCameraAccess: { true }
        )
        unavailableGameModel.showIntro()
        unavailableGameModel.requestPermission()
        await unavailableGameModel.resolvePermission()
        require(unavailableGameModel.state == .unavailable, "AR game handles unavailable AR")

        storyModel.showWelcome()
        require(storyModel.state == .welcome, "back from AR game returns to welcome")
        require(storyModel.story == nil && storyModel.storyID == nil, "back from AR game clears loaded story")
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
