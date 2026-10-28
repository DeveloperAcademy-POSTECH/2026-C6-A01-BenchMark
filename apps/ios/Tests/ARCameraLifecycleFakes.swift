// Created by 이돈혁

import Foundation

// Only platform services are replaced; the checks compile the production view model unchanged.
@MainActor
final class ARSessionController {
    struct Settings { var photoTimer = 0 }
    struct CameraView {}

    let view = CameraView()
    var settings = Settings()
    var ready = false
    var capturing = false
    var videoRecording = false
    var canCapture: Bool { ready && !capturing && !videoRecording }
    var holdsStarts = false
    private(set) var startRequests = 0
    private(set) var sessionStarts = 0
    private(set) var completedStarts = 0
    private(set) var cancelledCompletions = 0
    private(set) var retryRequests = 0
    private(set) var stopRequests = 0
    private(set) var pauseRequests = 0
    private(set) var captures = 0
    private var generation = 0
    private var pendingStarts: [CheckedContinuation<Void, Never>] = []

    var suspendedStarts: Int { pendingStarts.count }

    func start() async {
        startRequests += 1
        guard !ready else { return }
        let requestedGeneration = generation
        sessionStarts += 1
        if holdsStarts { await withCheckedContinuation { pendingStarts.append($0) } }
        completedStarts += 1
        if Task.isCancelled { cancelledCompletions += 1 }
        guard !Task.isCancelled, requestedGeneration == generation else { return }
        ready = true
    }

    func retryRecovery() async {
        retryRequests += 1
        pause()
        await start()
    }

    func releaseNextStart() {
        guard !pendingStarts.isEmpty else { return }
        pendingStarts.removeFirst().resume()
    }

    func stop() { stopRequests += 1; pause() }
    func pause() { pauseRequests += 1; generation += 1; ready = false }
    func capture() { guard canCapture else { return }; captures += 1; capturing = true }
}

@MainActor
final class ARVideoRecorder {
    enum State { case idle, preparing, recording, finishing }

    var state = State.idle
    var busy: Bool { state != .idle }
    var holdsStarts = false
    var holdsStops = false
    private(set) var startRequests = 0
    private(set) var completedStarts = 0
    private(set) var cancelledStarts = 0
    private(set) var stopRequests = 0
    private var stopAfterStart = false
    private var pendingStarts: [CheckedContinuation<Void, Never>] = []
    private var pendingStops: [CheckedContinuation<Void, Never>] = []

    var suspendedStarts: Int { pendingStarts.count }
    var suspendedStops: Int { pendingStops.count }

    func start(view: ARSessionController.CameraView) async {
        startRequests += 1
        guard !busy else { return }
        state = .preparing
        stopAfterStart = false
        if holdsStarts { await withCheckedContinuation { pendingStarts.append($0) } }
        completedStarts += 1
        if Task.isCancelled { cancelledStarts += 1 }
        guard !Task.isCancelled, !stopAfterStart else { state = .idle; return }
        state = .recording
    }

    func stop() async {
        stopRequests += 1
        if state == .preparing { stopAfterStart = true; return }
        guard state == .recording else { return }
        state = .finishing
        if holdsStops { await withCheckedContinuation { pendingStops.append($0) } }
        state = .idle
    }

    func releaseNextStart() {
        guard !pendingStarts.isEmpty else { return }
        pendingStarts.removeFirst().resume()
    }

    func releaseNextStop() {
        guard !pendingStops.isEmpty else { return }
        pendingStops.removeFirst().resume()
    }
}
