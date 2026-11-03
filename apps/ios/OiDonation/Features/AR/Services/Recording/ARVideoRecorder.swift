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
    private var recordingOriginal: URL?
    private let exporter = ARVideoExporter()
    private let recovery = ARVideoRecoveryStore()

    override init() {
        super.init()
        do {
            if let original = try recovery.pendingRecordings().first {
                result = ARVideoResult(url: original, kind: .recoveryOriginal)
            }
        } catch {
            errorMessage = "보관된 녹화 원본을 확인하지 못했습니다. 카메라를 다시 열어 주세요."
        }
    }

    func discardRecovery(_ original: URL) throws {
        try recovery.discard(original)
    }

    func start(view: UIView) async {
        guard !busy, !Task.isCancelled else { return }
        state = .preparing
        stopAfterStart = false
        // Wait for panels and overlays to settle before measuring the recording area.
        do { try await Task.sleep(for: .milliseconds(250)) }
        catch { state = .idle; return }
        guard !Task.isCancelled, !stopAfterStart else { state = .idle; return }
        let microphoneAllowed = await AVAudioApplication.requestRecordPermission()
        guard !Task.isCancelled, !stopAfterStart else { state = .idle; return }
        guard microphoneAllowed else {
            errorMessage = "음성을 녹음하려면 설정에서 마이크 접근을 허용해 주세요."
            state = .idle
            return
        }
        guard let window = view.window, !view.bounds.isEmpty else {
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
        guard !Task.isCancelled, !stopAfterStart else { state = .idle; return }
        do {
            recordingOriginal = try recovery.recordingURL()
        } catch {
            errorMessage = "녹화 원본을 보관할 저장 공간을 준비하지 못했습니다. 여유 공간을 확인해 주세요."
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
            if Task.isCancelled {
                // A cancelled start still owns the acquired recording; finish export without cancellation.
                await Task { await self.stop() }.value
            } else if stopAfterStart {
                await stop()
            }
        } catch {
            recordingOriginal = nil
            ARRecordingOrientation.unlock()
            recorder.isMicrophoneEnabled = false
            if !Task.isCancelled, !stopAfterStart {
                errorMessage = "녹화 시작 실패: \(error.localizedDescription)"
            }
            state = .idle
        }
    }

    func stop() async {
        if state == .preparing { stopAfterStart = true; return }
        guard state == .recording else { return }
        guard let original = recordingOriginal else {
            errorMessage = "녹화 원본의 저장 위치를 확인하지 못했습니다. 다시 종료해 주세요."
            return
        }
        state = .finishing
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Finish AR video") { [weak self] in
            Task { @MainActor in self?.exporter.cancel() }
        }
        defer {
            ARRecordingOrientation.unlock()
            RPScreenRecorder.shared().isMicrophoneEnabled = false
            state = .idle
            startedAt = nil
            recordingOriginal = nil
            if backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
                backgroundTask = .invalid
            }
        }
        do {
            try await RPScreenRecorder.shared().stopRecording(withOutput: original)
            let output = try await recovery.export(original) { original in
                try await exporter.exportCameraArea(from: original, crop: crop)
            }
            result = ARVideoResult(url: output)
        } catch {
            do {
                if try recovery.pendingRecordings().contains(original) {
                    result = ARVideoResult(url: original, kind: .recoveryOriginal)
                } else {
                    errorMessage = "영상 저장 실패: \(error.localizedDescription)"
                }
            } catch {
                errorMessage = "영상 저장과 복구 원본 확인에 실패했습니다. 카메라를 다시 열어 보관된 원본을 확인해 주세요."
            }
        }
    }

    func screenRecorder(_ screenRecorder: RPScreenRecorder,
                        didStopRecordingWith previewViewController: RPPreviewViewController?, error: Error?) {
        guard state == .recording else { return }
        state = .idle
        recordingOriginal = nil
        startedAt = nil
        ARRecordingOrientation.unlock()
        screenRecorder.isMicrophoneEnabled = false
        errorMessage = "시스템에서 녹화가 중단되어 저장하지 못했습니다. " + (error?.localizedDescription ?? "다시 촬영해 주세요.")
    }

}
