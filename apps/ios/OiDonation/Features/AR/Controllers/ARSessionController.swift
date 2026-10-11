import ARKit
import AVFoundation
import Observation
import RealityKit
import SwiftUI

@MainActor @Observable
final class ARSessionController: NSObject, ARSessionDelegate {
    let view = RealityKit.ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
    let animation = ARAnimationController()
    private let characters = ARCharacterController()
    private let lighting = ARLightingController()
    var motions: [ARAnimationController.Motion] { animation.motions }
    var selectedMotion: Int? { animation.selectedMotion }
    var motionPlaying: Bool { animation.motionPlaying }
    var settings = ARCaptureSettings()
    var message = "바닥이 보이도록 카메라를 천천히 움직여 주세요."
    var tracking = "준비 중"
    var loading = false
    var placed = false
    var locked = false
    var ready = false
    var capturing = false
    var videoRecording = false
    var errorMessage: String?
    let peopleSupported = ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth)
    let meshSupported = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    private var anchor: AnchorEntity?
    private var characterRoot: Entity?
    private var loadedCharacter: ARCharacter?
    var canCapture: Bool { placed && ready && !loading && !capturing && !videoRecording && loadedCharacter == settings.character }
    private var loadTask: Task<Void, Never>?
    private var wantsRunning = false

    override init() {
        super.init()
        view.session.delegate = self
        view.session.delegateQueue = .main
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
        lighting.install(in: view)
        applySettings()
    }

    func start() async {
        wantsRunning = true
        guard ARWorldTrackingConfiguration.isSupported else {
            message = "AR 촬영은 지원되는 실제 iPhone에서 실행해 주세요. 시뮬레이터에서는 카메라 AR을 사용할 수 없습니다."
            return
        }
        let allowed = await AVCaptureDevice.requestAccess(for: .video)
        guard wantsRunning else { return }
        guard allowed else {
            message = "카메라 권한이 필요합니다. 설정 앱에서 OiDonation의 카메라 접근을 허용해 주세요."
            return
        }
        ready = true
        configureSession()
        if characterRoot == nil { loadCharacter() }
    }

    func stop() {
        pause()
        loadTask?.cancel()
        loading = false
        animation.stop()
    }

    func pause() {
        wantsRunning = false
        view.session.pause()
        ready = false
    }

    func configureSession() {
        guard ready else { return }
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        config.isLightEstimationEnabled = true
        config.environmentTexturing = .automatic
        if settings.peopleOcclusion && peopleSupported {
            config.frameSemantics.insert(.personSegmentationWithDepth)
        }
        if meshSupported { config.sceneReconstruction = .mesh }
        view.session.run(config)
    }

    func update(from previous: ARCaptureSettings) {
        if previous.character != settings.character { loadCharacter() }
        if previous.peopleOcclusion != settings.peopleOcclusion { configureSession() }
        applySettings()
    }

    func applySettings() {
        lighting.apply(settings, to: view, meshSupported: meshSupported)
        characterRoot?.scale = SIMD3(repeating: settings.height)
        characterRoot?.orientation = simd_quatf(angle: settings.rotation * .pi / 180, axis: [0, 1, 0])
        characterRoot?.position.y = settings.floorOffset
    }

    func loadCharacter() {
        loadTask?.cancel()
        loading = true
        let selection = settings.character
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let (root, model) = try await self.characters.load(selection)
                try Task.checkCancellation()
                self.animation.load(from: model)
                self.characterRoot?.removeFromParent()
                self.characterRoot = root
                self.loadedCharacter = selection
                self.anchor?.addChild(root)
                self.loading = false
                self.applySettings()
                self.message = self.placed ? "캐릭터를 바꿨습니다." : "캐릭터 준비 완료 · 인식된 바닥을 터치하세요."
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.loading = false
                self.errorMessage = "캐릭터 로딩 실패: \(error.localizedDescription)"
            }
        }
    }

    func playMotion(_ id: Int) {
        guard !loading, !capturing, !videoRecording else { return }
        animation.playMotion(id)
    }

    func toggleMotion() {
        guard !loading, !capturing, !videoRecording else { return }
        animation.toggleMotion()
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        guard ready, !loading, !locked, !capturing, !videoRecording, let root = characterRoot else { return }
        guard let hit = view.raycast(from: gesture.location(in: view), allowing: .existingPlaneGeometry, alignment: .horizontal).first else {
            message = "아직 바닥을 찾지 못했습니다. 바닥을 여러 각도에서 비춰 주세요."
            return
        }
        anchor?.removeFromParent()
        let newAnchor = AnchorEntity(world: hit.worldTransform)
        newAnchor.addChild(root)
        view.scene.addAnchor(newAnchor)
        anchor = newAnchor
        placed = true
        message = "배치 완료 · 바닥을 다시 터치하면 이동합니다."
        applySettings()
    }

    func resetPlacement() {
        anchor?.removeFromParent()
        anchor = nil
        placed = false
        locked = false
        message = "새 위치의 바닥을 터치하세요."
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        switch camera.trackingState {
        case .normal: tracking = "추적 정상"
        case .notAvailable: tracking = "추적 불가"
        case .limited(let reason):
            switch reason {
            case .initializing: tracking = "공간 인식 중"
            case .excessiveMotion: tracking = "천천히 움직여 주세요"
            case .insufficientFeatures: tracking = "무늬 있는 바닥을 비춰 주세요"
            case .relocalizing: tracking = "기존 공간을 다시 인식 중"
            @unknown default: tracking = "추적 제한"
            }
        }
    }

    func sessionWasInterrupted(_ session: ARSession) { tracking = "카메라 일시 중단"; ready = false }
    func sessionInterruptionEnded(_ session: ARSession) { ready = wantsRunning; configureSession() }
    func session(_ session: ARSession, didFailWithError error: Error) {
        ready = false
        errorMessage = "AR 세션 오류: \(error.localizedDescription). 앱을 다시 활성화하거나 재시도해 주세요."
    }

}
