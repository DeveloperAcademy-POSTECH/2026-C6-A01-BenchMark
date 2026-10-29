// Created by 이돈혁

import Foundation
import SwiftUI
import Darwin

@main
struct ARCameraLifecycleChecks {
    struct Failure: Error, CustomStringConvertible { let description: String }

    @MainActor
    static func main() async {
        do {
            try await delayedStartupCannotOutliveClose()
            try await hiddenCameraIgnoresLateCallbacks()
            try await sceneTransitionsCancelStaleStartup()
            try await retryWaitsForFinishingVideo()
            try await activeCameraRestartsAfterVideoDrains()
            try await countdownCancellationAndRepeatedCapture()
            try await recordingCommandsAreDeduplicated()
            try await closeWaitsForPreparingVideo()
            try await disappearanceCancelsPreparingVideo()
            print("PASS: AR camera lifecycle, delayed startup cancellation, scene races, deferred retry, recorder drain, countdown cancellation, duplicate capture prevention, pending video startup drain")
        } catch {
            print("FAIL: \(error)")
            exit(EXIT_FAILURE)
        }
    }

    @MainActor
    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw Failure(description: message) }
    }

    @MainActor
    private static func eventually(_ message: String, _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !condition() {
            guard ContinuousClock.now < deadline else { throw Failure(description: "Timed out: \(message)") }
            await Task.yield()
        }
    }

    @MainActor
    private static func settle() async {
        for _ in 0..<30 { await Task.yield() }
    }

    @MainActor
    private static func delayedStartupCannotOutliveClose() async throws {
        let controller = ARSessionController()
        let video = ARVideoRecorder()
        let model = ARCameraViewModel(controller: controller, video: video)
        controller.holdsStarts = true
        model.appear(in: .active)
        try await eventually("camera startup suspended") { controller.suspendedStarts == 1 }
        await model.close()
        controller.releaseNextStart()
        try await eventually("cancelled startup returned") { controller.completedStarts == 1 }
        try expect(controller.cancelledCompletions == 1, "Closing must cancel the owned startup task")
        try expect(!controller.ready && controller.stopRequests == 1, "Late startup must not reactivate the closed camera")
        let requests = controller.startRequests
        model.sceneChanged(to: .active)
        model.recordingStateChanged(false)
        model.retryRecovery()
        model.capture()
        await settle()
        try expect(controller.startRequests == requests && controller.captures == 0, "Closed cameras must ignore later callbacks")
    }

    @MainActor
    private static func sceneTransitionsCancelStaleStartup() async throws {
        let controller = ARSessionController()
        let model = ARCameraViewModel(controller: controller, video: ARVideoRecorder())
        model.appear(in: .active)
        model.sceneChanged(to: .inactive)
        await settle()
        try expect(controller.startRequests == 0 && !controller.ready, "Inactive transition must cancel startup before its task runs")

        controller.holdsStarts = true
        model.sceneChanged(to: .active)
        try await eventually("first active startup") { controller.suspendedStarts == 1 }
        model.sceneChanged(to: .inactive)
        model.sceneChanged(to: .active)
        try await eventually("replacement active startup") { controller.suspendedStarts == 2 }
        controller.releaseNextStart()
        try await eventually("stale startup returned") { controller.completedStarts == 1 }
        try expect(!controller.ready && controller.cancelledCompletions == 1, "Old active request must not win after inactive/active")
        controller.releaseNextStart()
        try await eventually("latest startup ready") { controller.ready }
        await model.close()
    }

    @MainActor
    private static func hiddenCameraIgnoresLateCallbacks() async throws {
        let controller = ARSessionController()
        let video = ARVideoRecorder()
        let model = ARCameraViewModel(controller: controller, video: video)
        controller.holdsStarts = true
        model.appear(in: .active)
        try await eventually("startup before disappearance") { controller.suspendedStarts == 1 }
        model.disappear()
        controller.releaseNextStart()
        try await eventually("hidden startup returned") { controller.completedStarts == 1 }
        try expect(controller.cancelledCompletions == 1 && !controller.ready, "Disappearance must cancel a suspended startup")

        controller.holdsStarts = false
        model.appear(in: .active)
        try await eventually("camera visible again") { controller.ready }
        await settle()
        video.state = .recording
        video.holdsStops = true
        model.disappear()
        try await eventually("hidden video finalization") { video.suspendedStops == 1 }
        let starts = controller.sessionStarts
        model.sceneChanged(to: .active)
        model.retryRecovery()
        model.capture()
        video.releaseNextStop()
        try await eventually("hidden video stopped") { !video.busy }
        model.recordingStateChanged(false)
        await settle()
        try expect(controller.sessionStarts == starts && !controller.ready && controller.captures == 0,
                   "Late active/drain callbacks must not restart or capture while hidden")
        await model.close()
    }

    @MainActor
    private static func retryWaitsForFinishingVideo() async throws {
        let controller = ARSessionController()
        let video = ARVideoRecorder()
        let model = ARCameraViewModel(controller: controller, video: video)
        model.appear(in: .active)
        try await eventually("initial camera ready") { controller.ready }
        await settle()
        video.state = .finishing
        model.recordingStateChanged(true)
        model.retryRecovery()
        model.retryRecovery()
        await settle()
        try expect(controller.retryRequests == 0, "Retry must not restart a camera while video export is finishing")
        video.state = .idle
        model.recordingStateChanged(false)
        try await eventually("queued recovery starts") { controller.retryRequests == 1 && controller.ready }
        await settle()
        try expect(controller.retryRequests == 1, "Repeated retry taps must produce exactly one deferred recovery")
        await model.close()
    }

    @MainActor
    private static func activeCameraRestartsAfterVideoDrains() async throws {
        let controller = ARSessionController()
        let video = ARVideoRecorder()
        let model = ARCameraViewModel(controller: controller, video: video)
        model.appear(in: .active)
        try await eventually("initial camera ready") { controller.ready }
        await settle()
        video.state = .recording
        video.holdsStops = true
        model.recordingStateChanged(true)
        model.sceneChanged(to: .inactive)
        try await eventually("video finalization suspended") { video.suspendedStops == 1 }
        model.sceneChanged(to: .active)
        await settle()
        try expect(!controller.ready && controller.sessionStarts == 1, "Foreground return must wait for the existing video to finish")
        video.releaseNextStop()
        try await eventually("camera restarted after owned stop completed") { controller.ready && controller.sessionStarts == 2 }
        model.recordingStateChanged(false)
        await settle()
        try expect(controller.sessionStarts == 2 && video.stopRequests == 1, "Recorder drain must not duplicate session or stop work")
        await model.close()
    }

    @MainActor
    private static func countdownCancellationAndRepeatedCapture() async throws {
        let controller = ARSessionController()
        let model = ARCameraViewModel(controller: controller, video: ARVideoRecorder())
        model.appear(in: .active)
        try await eventually("photo camera ready") { controller.ready }
        await settle()
        controller.settings.photoTimer = 1
        model.capture()
        model.capture()
        await settle()
        try expect(model.countdown == nil, "A second capture in the same actor turn must cancel the first countdown")
        model.capture()
        try await eventually("photo countdown visible") { model.countdown == 1 }
        model.sceneChanged(to: .inactive)
        try expect(model.countdown == nil, "Leaving the active scene must clear countdown immediately")
        try await Task.sleep(for: .milliseconds(1_100))
        try expect(controller.captures == 0, "Cancelled countdowns must never capture later")
        model.sceneChanged(to: .active)
        try await eventually("photo camera resumed") { controller.ready }
        controller.settings.photoTimer = 0
        model.capture()
        model.capture()
        try expect(controller.captures == 1, "Rapid photo capture taps must respect the controller's in-flight capture")
        await model.close()
    }

    @MainActor
    private static func recordingCommandsAreDeduplicated() async throws {
        let controller = ARSessionController()
        let video = ARVideoRecorder()
        let model = ARCameraViewModel(controller: controller, video: video)
        model.appear(in: .active)
        try await eventually("recording camera ready") { controller.ready }
        await settle()
        model.videoMode = true
        model.capture()
        model.capture()
        try await eventually("recording started") { video.state == .recording }
        try expect(video.startRequests == 1, "Repeated capture taps must not enqueue duplicate video starts")
        video.holdsStops = true
        model.capture()
        model.capture()
        try await eventually("recording stop suspended") { video.suspendedStops == 1 }
        try expect(video.stopRequests == 1, "Repeated stop taps must reuse the existing stop task")
        video.releaseNextStop()
        try await eventually("recording stopped") { !video.busy }
        await settle()
        await model.close()

        let closedController = ARSessionController()
        let closedVideo = ARVideoRecorder()
        let closedModel = ARCameraViewModel(controller: closedController, video: closedVideo)
        closedModel.appear(in: .active)
        try await eventually("second recording camera ready") { closedController.ready }
        await settle()
        closedModel.videoMode = true
        closedModel.capture()
        await closedModel.close()
        await settle()
        try expect(closedVideo.startRequests == 0, "Closing must cancel a queued video start before it runs")
    }

    @MainActor
    private static func closeWaitsForPreparingVideo() async throws {
        let controller = ARSessionController()
        let video = ARVideoRecorder()
        let model = ARCameraViewModel(controller: controller, video: video)
        model.appear(in: .active)
        try await eventually("camera before preparing video") { controller.ready }
        await settle()
        model.videoMode = true
        video.holdsStarts = true
        model.capture()
        try await eventually("video startup suspended") { video.suspendedStarts == 1 && video.state == .preparing }

        var closeEntered = false
        var closeCompleted = false
        let closeTask = Task { @MainActor in
            closeEntered = true
            await model.close()
            closeCompleted = true
        }
        try await eventually("close entered while video prepares") { closeEntered }
        await settle()
        let dismissedBeforeStartupDrained = closeCompleted
        let heldPreparingState = video.state == .preparing
        video.releaseNextStart()
        try await eventually("close completed after startup returned") { closeCompleted }
        await closeTask.value
        try expect(!dismissedBeforeStartupDrained && heldPreparingState,
                   "Close must await the pending recorder startup before dismissal")
        try expect(video.cancelledStarts == 1 && !video.busy && video.suspendedStarts == 0,
                   "Closing must drain cancelled recorder startup without leaving a live recorder")
        try expect(!controller.ready && !model.closing, "Close must finish with camera and closing state cleared")
    }

    @MainActor
    private static func disappearanceCancelsPreparingVideo() async throws {
        let controller = ARSessionController()
        let video = ARVideoRecorder()
        let model = ARCameraViewModel(controller: controller, video: video)
        model.appear(in: .active)
        try await eventually("camera before hidden video") { controller.ready }
        await settle()
        model.videoMode = true
        video.holdsStarts = true
        model.capture()
        try await eventually("video preparing before disappearance") { video.suspendedStarts == 1 }
        model.disappear()
        video.releaseNextStart()
        try await eventually("hidden recorder startup drained") { video.completedStarts == 1 && !video.busy }
        model.recordingStateChanged(false)
        model.sceneChanged(to: .active)
        model.capture()
        await settle()
        try expect(video.cancelledStarts == 1 && video.startRequests == 1 && !controller.ready,
                   "Disappearance must cancel preparing video and reject late restart/capture callbacks")
        await model.close()
    }
}
