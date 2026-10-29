import Observation
import SwiftUI

/// 촬영 흐름과 앱 생명주기를 연결하며, AR과 녹화 상태는 각각의 담당 객체가 관리합니다.
@MainActor @Observable
final class ARCameraViewModel {
    let controller: ARSessionController
    let video: ARVideoRecorder
    var videoMode = false
    var countdown: Int?
    private(set) var closing = false
    private var timerTask: Task<Void, Never>?
    private var startupTask: Task<Void, Never>?
    private var startupID: UUID?
    private var recordingStartTask: Task<Void, Never>?
    private var recordingStopTask: Task<Void, Never>?
    private var visible = false
    private var active = false
    private var retryRequested = false

    convenience init() {
        self.init(controller: ARSessionController(), video: ARVideoRecorder())
    }

    init(controller: ARSessionController, video: ARVideoRecorder) {
        self.controller = controller
        self.video = video
    }

    func appear(in phase: ScenePhase) {
        visible = true
        active = phase == .active
        resumeCamera()
    }

    func close() async {
        disappear()
        closing = true
        let pendingRecordingStart = recordingStartTask
        if let recordingStopTask {
            await recordingStopTask.value
        } else {
            await video.stop()
        }
        if let pendingRecordingStart { await pendingRecordingStart.value }
        closing = false
    }

    func disappear() {
        visible = false
        active = false
        retryRequested = false
        cancelStartup()
        cancelTimer()
        recordingStartTask?.cancel()
        controller.stop()
        stopRecording()
    }

    func capture() {
        guard visible, active, !closing else { return }
        if timerTask != nil { cancelTimer(); return }
        if video.state == .recording {
            stopRecording()
        } else if videoMode {
            guard controller.canCapture, !video.busy, recordingStartTask == nil else { return }
            recordingStartTask = Task { [weak self] in
                guard let self else { return }
                defer { recordingStartTask = nil }
                guard visible, active, !Task.isCancelled else { return }
                await video.start(view: controller.view)
            }
        } else {
            guard controller.canCapture, !video.busy else { return }
            let seconds = controller.settings.photoTimer
            guard seconds > 0 else { controller.capture(); return }
            countdown = seconds
            timerTask = Task { [weak self] in
                guard let self, !Task.isCancelled else { return }
                for remaining in stride(from: seconds, through: 1, by: -1) {
                    guard visible, active, !Task.isCancelled else { return }
                    countdown = remaining
                    do { try await Task.sleep(for: .seconds(1)) }
                    catch { return }
                    guard !Task.isCancelled else { return }
                }
                countdown = nil
                controller.capture()
                timerTask = nil
            }
        }
    }

    func cancelTimer() { timerTask?.cancel(); timerTask = nil; countdown = nil }

    func viewportChanged() {
        cancelTimer()
        if video.busy { stopRecording() }
    }

    func sessionReadinessChanged(_ ready: Bool) {
        if !ready { viewportChanged() }
    }

    func sceneChanged(to phase: ScenePhase) {
        active = phase == .active
        guard visible else { return }
        if active {
            resumeCamera()
        } else {
            cancelStartup()
            cancelTimer()
            controller.pause()
            stopRecording()
        }
    }

    func recordingStateChanged(_ busy: Bool) {
        controller.videoRecording = busy
        if !busy { resumeCamera() }
    }

    func retryRecovery() {
        guard visible, active, !closing, !retryRequested, startupTask == nil else { return }
        retryRequested = true
        cancelTimer()
        if video.busy { stopRecording() }
        resumeCamera()
    }

    private func resumeCamera() {
        guard visible, active, !closing, !video.busy, startupTask == nil else { return }
        let id = UUID()
        startupID = id
        let retry = retryRequested
        retryRequested = false
        startupTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if startupID == id {
                    startupTask = nil
                    startupID = nil
                }
            }
            guard visible, active, !Task.isCancelled else { return }
            if retry { await controller.retryRecovery() }
            else { await controller.start() }
        }
    }

    private func cancelStartup() {
        startupTask?.cancel()
        startupTask = nil
        startupID = nil
    }

    private func stopRecording() {
        guard video.busy, recordingStopTask == nil else { return }
        recordingStopTask = Task { [weak self] in
            guard let self else { return }
            await video.stop()
            recordingStopTask = nil
            if !video.busy { resumeCamera() }
        }
    }
}
