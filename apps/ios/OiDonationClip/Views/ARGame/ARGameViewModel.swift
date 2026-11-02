//
//  ARGameViewModel.swift
//  OiDonationClip
//
//  Created by jiwon hong on 10/28/26.
//

import Foundation
import Observation

@Observable
@MainActor
final class ARGameViewModel {
    enum State: Equatable {
        case introBackground
        case intro
        case requestingPermission
        case starting
        case playing
        case permissionDenied
        case success
        case storyCard
        case failure
        case unavailable
        case cameraUnavailable
    }

    private(set) var state: State = .introBackground
    private(set) var collectedCount = 0
    private(set) var remainingSeconds: Int
    let targetCount: Int
    let timeLimitSeconds: Int
    private let isARSupported: () -> Bool
    private let requestCameraAccess: () async -> Bool
    private let sleepOneSecond: () async throws -> Void
    private let monotonicNow: () -> TimeInterval
    private var roundDeadline: TimeInterval?
    private var roundID = UUID()
    private var timerRunID: UUID?

    init(
        targetCount: Int = 3,
        timeLimitSeconds: Int = 30,
        isARSupported: @escaping () -> Bool,
        requestCameraAccess: @escaping () async -> Bool,
        sleepOneSecond: @escaping () async throws -> Void = {
            try await Task.sleep(for: .seconds(1))
        },
        monotonicNow: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.targetCount = targetCount
        self.timeLimitSeconds = timeLimitSeconds
        self.remainingSeconds = timeLimitSeconds
        self.isARSupported = isARSupported
        self.requestCameraAccess = requestCameraAccess
        self.sleepOneSecond = sleepOneSecond
        self.monotonicNow = monotonicNow
    }

    func showIntro() {
        guard state == .introBackground else { return }
        state = .intro
    }

    func requestPermission() {
        guard state == .intro else { return }
        state = .requestingPermission
    }

    func resolvePermission() async {
        guard state == .requestingPermission else { return }
        guard isARSupported() else {
            state = .unavailable
            return
        }

        let isGranted = await requestCameraAccess()
        guard state == .requestingPermission, !Task.isCancelled else { return }
        if isGranted {
            state = .starting
        } else {
            state = .permissionDenied
        }
    }

    func retryPermission() {
        guard state == .permissionDenied else { return }
        state = .requestingPermission
    }

    func finishStartAnimation() {
        guard state == .starting else { return }
        roundDeadline = monotonicNow() + TimeInterval(timeLimitSeconds)
        state = .playing
    }

    func collectCucumber() {
        guard state == .playing else { return }
        updateRemainingTime()
        guard state == .playing else { return }
        collectedCount = min(collectedCount + 1, targetCount)
        if collectedCount == targetCount {
            state = .success
        }
    }

    func showStoryCard() {
        guard state == .success else { return }
        state = .storyCard
    }

    func runTimer() async {
        guard state == .playing, timerRunID == nil, !Task.isCancelled else { return }
        let runID = UUID()
        let currentRound = roundID
        timerRunID = runID
        defer {
            if timerRunID == runID { timerRunID = nil }
        }
        updateRemainingTime()
        while state == .playing, remainingSeconds > 0, !Task.isCancelled {
            do {
                try await sleepOneSecond()
            } catch {
                return
            }
            guard !Task.isCancelled, currentRound == roundID else { return }
            updateRemainingTime()
        }
    }

    func updateRemainingTime() {
        guard state == .playing, let roundDeadline else { return }
        let remaining = max(0, roundDeadline - monotonicNow())
        remainingSeconds = min(timeLimitSeconds, Int(ceil(remaining)))
        if remaining == 0 {
            state = .failure
        }
    }

    func reset() {
        roundID = UUID()
        roundDeadline = nil
        timerRunID = nil
        collectedCount = 0
        remainingSeconds = timeLimitSeconds
        state = .intro
    }

    func cameraBecameUnavailable() {
        guard state == .starting || state == .playing else { return }
        state = .cameraUnavailable
    }
}
