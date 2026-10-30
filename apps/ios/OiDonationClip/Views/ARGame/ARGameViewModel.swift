//
//  ARGameViewModel.swift
//  OiDonationClip
//
//  Created by jiwon hong on 10/28/26.
//

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
    }

    private(set) var state: State = .introBackground
    private(set) var collectedCount = 0
    private(set) var remainingSeconds: Int
    let targetCount: Int
    let timeLimitSeconds: Int
    private let isARSupported: () -> Bool
    private let requestCameraAccess: () async -> Bool

    init(
        targetCount: Int = 3,
        timeLimitSeconds: Int = 30,
        isARSupported: @escaping () -> Bool,
        requestCameraAccess: @escaping () async -> Bool
    ) {
        self.targetCount = targetCount
        self.timeLimitSeconds = timeLimitSeconds
        self.remainingSeconds = timeLimitSeconds
        self.isARSupported = isARSupported
        self.requestCameraAccess = requestCameraAccess
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
        state = isGranted ? .starting : .permissionDenied
    }

    func beginPlaying() {
        guard state == .starting else { return }
        state = .playing
    }

    func collectCucumber() {
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
        while state == .playing, remainingSeconds > 0, !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }
            elapseSecond()
        }
    }

    func elapseSecond() {
        guard state == .playing else { return }
        remainingSeconds = max(remainingSeconds - 1, 0)
        if remainingSeconds == 0 {
            state = .failure
        }
    }

    func reset() {
        collectedCount = 0
        remainingSeconds = timeLimitSeconds
        state = .intro
    }
}
