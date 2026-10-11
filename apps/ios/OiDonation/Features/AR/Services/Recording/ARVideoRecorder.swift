import AVFoundation
import Observation
import ReplayKit
import UIKit

@MainActor @Observable
final class ARVideoRecorder: NSObject, RPScreenRecorderDelegate {
    enum State { case idle, preparing, recording, finishing }
    var state: State = .idle
    var startedAt: Date?
    var result: ARVideoResult?
    var errorMessage: String?
    var busy: Bool { state != .idle }
    private var crop = CGRect.zero
    private var screenSize = CGSize.zero
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var stopAfterStart = false
    private let exporter = ARVideoExporter()

    func start(view: UIView) async {
        guard !busy else { return }
        state = .preparing
        stopAfterStart = false
        // 패널 접기와 오버레이 숨김이 반영된 뒤 촬영 영역의 위치와 크기를 측정합니다.
        try? await Task.sleep(for: .milliseconds(250))
        guard !stopAfterStart else { state = .idle; return }
        guard await AVAudioApplication.requestRecordPermission() else {
            errorMessage = "음성을 녹음하려면 설정에서 마이크 접근을 허용해 주세요."
            state = .idle
            return
        }
        guard !stopAfterStart, let window = view.window, !view.bounds.isEmpty else {
            state = .idle
            return
        }
        let rect = view.convert(view.bounds, to: window).intersection(window.bounds)
        guard rect.width > 1, rect.height > 1 else { state = .idle; return }
        screenSize = window.bounds.size
        crop = CGRect(x: rect.minX / screenSize.width, y: rect.minY / screenSize.height,
                      width: rect.width / screenSize.width, height: rect.height / screenSize.height)
        let recorder = RPScreenRecorder.shared()
        guard recorder.isAvailable else {
            errorMessage = "현재 화면 녹화를 사용할 수 없습니다. 다른 녹화를 종료한 뒤 다시 시도해 주세요."
            state = .idle
            return
        }
        ARRecordingOrientation.lock(to: window)
        recorder.isMicrophoneEnabled = true
        recorder.delegate = self
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                recorder.startRecording { error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                }
            }
            startedAt = Date()
            state = .recording
            if stopAfterStart { await stop() }
        } catch {
            ARRecordingOrientation.unlock()
            recorder.isMicrophoneEnabled = false
            errorMessage = "녹화 시작 실패: \(error.localizedDescription)"
            state = .idle
        }
    }

    func stop() async {
        if state == .preparing { stopAfterStart = true; return }
        guard state == .recording else { return }
        state = .finishing
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Finish AR video") { [weak self] in
            Task { @MainActor in self?.exporter.cancel() }
        }
        defer {
            ARRecordingOrientation.unlock()
            RPScreenRecorder.shared().isMicrophoneEnabled = false
            state = .idle
            startedAt = nil
            if backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
                backgroundTask = .invalid
            }
        }
        let raw = FileManager.default.temporaryDirectory.appending(path: "오이기부-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: raw) }
        do {
            try await RPScreenRecorder.shared().stopRecording(withOutput: raw)
            let output = try await exporter.exportCameraArea(from: raw, crop: crop)
            result = ARVideoResult(url: output)
        } catch {
            errorMessage = "영상 저장 실패: \(error.localizedDescription)"
        }
    }

    func screenRecorder(_ screenRecorder: RPScreenRecorder,
                        didStopRecordingWith previewViewController: RPPreviewViewController?, error: Error?) {
        guard state == .recording else { return }
        state = .idle
        startedAt = nil
        ARRecordingOrientation.unlock()
        screenRecorder.isMicrophoneEnabled = false
        errorMessage = "시스템에서 녹화가 중단되어 저장하지 못했습니다. " + (error?.localizedDescription ?? "다시 촬영해 주세요.")
    }

}
