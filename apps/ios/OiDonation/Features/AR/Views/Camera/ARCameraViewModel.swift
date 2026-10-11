import Observation
import SwiftUI

/// 촬영 흐름과 앱 생명주기를 연결하며, AR과 녹화 상태는 각각의 담당 객체가 관리합니다.
@MainActor @Observable
final class ARCameraViewModel {
    let controller: ARSessionController
    let video: ARVideoRecorder
    var videoMode = false
    var countdown: Int?
    private var timerTask: Task<Void, Never>?

    convenience init() {
        self.init(controller: ARSessionController(), video: ARVideoRecorder())
    }

    init(controller: ARSessionController, video: ARVideoRecorder) {
        self.controller = controller
        self.video = video
    }

    func close() async {
        cancelTimer()
        controller.stop()
        await video.stop()
    }

    func capture() {
        if video.state == .recording {
            Task { await video.stop() }
        } else if videoMode {
            Task { await video.start(view: controller.view) }
        } else {
            if countdown != nil { cancelTimer(); return }
            let seconds = controller.settings.photoTimer
            guard seconds > 0 else { controller.capture(); return }
            timerTask = Task { [weak self] in
                guard let self else { return }
                for remaining in stride(from: seconds, through: 1, by: -1) {
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
        if video.state == .recording { Task { await video.stop() } }
    }

    func sessionReadinessChanged(_ ready: Bool) {
        if !ready { viewportChanged() }
    }

    func sceneChanged(to phase: ScenePhase) {
        if phase == .active && !video.busy {
            Task { await controller.start() }
        } else if phase != .active {
            cancelTimer()
            controller.pause()
            Task { await video.stop() }
        }
    }
}
