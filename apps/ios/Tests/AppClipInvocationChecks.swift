//
//  AppClipInvocationChecks.swift
//  OiDonation
//
//  Created by 이돈혁 on 10/22/26.
//

import Foundation

private enum CheckError: Error { case failed }

private actor MutableNFCRepository: StoryRepository {
    let id = UUID()
    private var linked: String?
    private var visible = true
    private var fails = false
    init() { linked = id.uuidString }
    func configure(linked: String?, visible: Bool = true, fails: Bool = false) {
        self.linked = linked; self.visible = visible; self.fails = fails
    }
    func fetchNFCPostcardStoryID(tag: String) async throws -> String? {
        if fails { throw CheckError.failed }
        return visible ? linked : nil
    }
    func fetchPublicStory(storyID: String) async throws -> Story? {
        guard visible else { return nil }
        return Story(storyID: id.uuidString, donorID: id, donorDisplayName: "가상 농부", title: "가상 엽서", content: "가상 검사",
            publishedAt: Date(), location: .init(locationID: "pond", displayName: "가상 장소"), tags: [], cucumberID: id.uuidString, cucumberName: "가상 오이")
    }
    func fetchPublicStoryCard(storyID: String) async throws -> StoryCard? { nil }
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
        let nfc = MutableNFCRepository()
        let nfcID = await nfc.id.uuidString
        do {
            let allowed = try await nfc.canCollectNFCPostcard(tag: "pond-01", storyID: nfcID)
            require(allowed, "current public NFC story can be saved")
            await nfc.configure(linked: nil)
            let retired = try await nfc.canCollectNFCPostcard(tag: "pond-01", storyID: nfcID)
            require(!retired, "a retired tag cannot save a previously displayed card")
            await nfc.configure(linked: UUID().uuidString)
            let replaced = try await nfc.canCollectNFCPostcard(tag: "pond-01", storyID: nfcID)
            require(!replaced, "a replaced tag cannot save the previous story")
            await nfc.configure(linked: nfcID, visible: false)
            let hidden = try await nfc.canCollectNFCPostcard(tag: "pond-01", storyID: nfcID)
            require(!hidden, "a hidden story cannot be saved")
            await nfc.configure(linked: nfcID, fails: true)
            do {
                _ = try await nfc.canCollectNFCPostcard(tag: "pond-01", storyID: nfcID)
                fatalError("Offline validation must not authorize collection")
            } catch {}
        } catch { fatalError("NFC validation check failed: \(error)") }
        print("PASS: NFC collect revalidates public story, tag retirement/reassignment and network failure")
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

        let browseID = UUID()
        let storyURL = AppClipLink.storyURL(browseID)
        require(AppClipLink.storyID(in: storyURL) == browseID.uuidString, "story URL round trip")
        require(!AppClipLink.matches(url(AppClipLink.defaultURLString + "&story=bad")), "reject malformed story")
        require(!AppClipLink.matches(url(storyURL.absoluteString + "&story=" + browseID.uuidString)), "reject duplicated story parameter")
        let postcardURL = AppClipLink.postcardURL("pond-01")
        require(AppClipLink.postcardID(in: postcardURL) == "pond-01", "postcard URL round trip")
        require(AppClipLink.storyID(in: postcardURL) == nil, "postcard link has no story")
        require(!AppClipLink.matches(url(postcardURL.absoluteString + "&postcard=pond-01")), "reject duplicated postcard parameter")
        require(AppClipLink.postcardID(in: url(AppClipLink.defaultURLString + "&postcard=Bad%20ID")) == nil, "reject malformed postcard id")
        require(AppClipLink.postcardID(in: url("https://example.com/id?p=com.Spero.OiDonation.Clip&postcard=pond-01")) == nil, "reject postcard on other host")
        // The installed app opens the map home for every non-postcard App Clip link (#351).
        let appRouter = AppRouter()
        appRouter.selectedTab = .benches
        appRouter.open(storyURL)
        require(appRouter.selectedTab == .home && appRouter.storyPath.isEmpty, "installed app opens Home for a story link")

        let router = AppRouter()
        router.selectedTab = .benches
        router.storyPath = [.story("old")]
        router.isARPresented = true
        router.open(url(invalid[0]))
        require(router.selectedTab == .benches && router.isARPresented, "untrusted URL must preserve navigation")
        router.open(url(AppClipLink.defaultURLString))
        require(router.selectedTab == .home && router.storyPath.isEmpty && !router.isARPresented, "installed app opens Home")

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
        let storyCard = StoryCard(
                cardID: "card-first",
                storyID: "first",
                imageURL: url("https://example.com/story-cards/first.png")
            )
        let collectionStore = StoryCollectionStore(defaults: collectionDefaults)
        let sampleCard = StoryCard(cardID: OiSampleStory.id, storyID: OiSampleStory.id, imageURL: nil)
        require(UUID(uuidString: sampleCard.storyID) == nil, "sample cannot be passed as a server UUID")
        require(!collectionStore.collect(sampleCard), "sample collection cannot enter the shared App Group store")
        require(StoryCollectionStore(defaults: collectionDefaults).cards.isEmpty, "sample leaves no importable record")
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

        print("PASS: \(valid.count) valid / \(invalid.count) invalid App Clip links, installed-app routing to Home, AR game and collection store")
    }

    private static func url(_ value: String) -> URL {
        guard let url = URL(string: value) else { preconditionFailure("Invalid test URL: \(value)") }
        return url
    }

    private static func require(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message)
    }
}
