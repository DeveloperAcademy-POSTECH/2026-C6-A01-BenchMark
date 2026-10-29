import ARKit
import AVFoundation
import Metal
import Observation
import RealityKit
import SwiftUI

@MainActor @Observable
final class ARSessionController: NSObject, ARSessionDelegate, UIGestureRecognizerDelegate {
    var backgroundMessage = ""
    var backgroundReady = false
    var selectingBench = false
    @ObservationIgnored private lazy var background = ARStadiumBackgroundService(
        background: UIImage(named: "StadiumBackground")?.cgImage) { [weak self] message, ready in
            self?.backgroundMessage = message
            self?.backgroundReady = ready
            if ready { self?.selectingBench = false }
        }
    var photoViewport = CGRect.zero
    let view = RealityKit.ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
    let animation = ARAnimationController()
    private let characters = ARCharacterController()
    private let lighting = ARLightingController()
    private let photoCapture = ARPhotoCaptureService()
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
    var recoveryIssue: ARRecoveryIssue?
    var starting: Bool { lifecycle.starting }
    var result: ARCaptureResult?
    let peopleSupported = ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth)
    let meshSupported = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    private var anchor: AnchorEntity?
    private var characterRoot: Entity?
    private var loadedCharacter: ARCharacter?
    var canCapture: Bool {
        (placed || settings.background == .stadium)
            && (settings.background == .original || backgroundReady)
            && ready && !loading && !capturing && !videoRecording
            && loadedCharacter == settings.character
    }
    private var loadTask: Task<Void, Never>?
    private var lifecycle = ARSessionLifecycle()
    @ObservationIgnored private var cameraAuthorizationTask: Task<Bool, Never>?
    private var pinchStartHeight: Float?
    private var dragStart: (rotation: Float, floorOffset: Float)?

    override init() {
        super.init()
        view.session.delegate = self
        view.session.delegateQueue = .main
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        let pan = UIPanGestureRecognizer(target: self, action: #selector(dragged(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        pinch.delegate = self
        tap.require(toFail: pinch)
        tap.require(toFail: pan)
        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(pinch)
        view.addGestureRecognizer(tap)
        let compositor = background
        view.renderCallbacks.prepareWithDevice = { compositor.prepare(device: $0) }
        view.renderCallbacks.postProcess = { compositor.render($0) }
        if let device = MTLCreateSystemDefaultDevice() { compositor.prepare(device: device) }
        lighting.install(in: view)
        applySettings()
    }

    func start() async {
        await start(recovering: false)
    }

    private func start(recovering: Bool) async {
        guard let attempt = lifecycle.beginStart(recovering: recovering) else { return }
        guard ARWorldTrackingConfiguration.isSupported else {
            if lifecycle.rejectStart(attempt) { showRecovery(.unsupported) }
            return
        }
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            // Reuse the system prompt if the app resumed before its older request completed.
            let authorization = cameraAuthorizationTask ?? Task { await AVCaptureDevice.requestAccess(for: .video) }
            cameraAuthorizationTask = authorization
            _ = await authorization.value
            cameraAuthorizationTask = nil
        }
        // A newer start may already own the session after a pause during the prompt.
        guard lifecycle.isCurrent(attempt) else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .restricted:
            if lifecycle.rejectStart(attempt) { showRecovery(.cameraRestricted) }
            return
        case .denied, .notDetermined:
            if lifecycle.rejectStart(attempt) { showRecovery(.cameraDenied) }
            return
        @unknown default:
            if lifecycle.rejectStart(attempt) { showRecovery(.cameraRestricted) }
            return
        }
        guard lifecycle.completeStart(attempt) else { return }
        recoveryIssue = nil
        ready = true
        configureSession(resetTracking: attempt.requiresTrackingReset)
        updateBackground()
        if loadedCharacter != settings.character { loadCharacter() }
    }

    func retryRecovery() async {
        guard let recoveryIssue, recoveryIssue.canRetry, !capturing, !videoRecording else { return }
        switch recoveryIssue {
        case .characterLoadFailure:
            if lifecycle.running && ready { loadCharacter() }
            else { await start() }
        case .interrupted, .sessionFailure:
            await start(recovering: true)
        case .unsupported, .cameraDenied, .cameraRestricted:
            break
        }
    }

    private func showRecovery(_ issue: ARRecoveryIssue) {
        recoveryIssue = issue
        message = issue.message
    }

    func stop() {
        pause()
        animation.stop()
    }

    func pause() {
        lifecycle.pause()
        loadTask?.cancel()
        loadTask = nil
        loading = false
        view.session.pause()
        background.setEnabled(false)
        backgroundReady = false
        ready = false
    }

    func configureSession(resetTracking: Bool = false) {
        guard ready else { return }
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        config.isLightEstimationEnabled = true
        config.environmentTexturing = .automatic
        if settings.peopleOcclusion && peopleSupported {
            config.frameSemantics.insert(.personSegmentationWithDepth)
        }
        if meshSupported { config.sceneReconstruction = .mesh }
        if resetTracking {
            resetPlacement()
            view.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        } else {
            view.session.run(config)
        }
    }

    func update(from previous: ARCaptureSettings) {
        if previous.character != settings.character { loadCharacter() }
        if previous.peopleOcclusion != settings.peopleOcclusion { configureSession() }
        if previous.background != settings.background { updateBackground() }
        applySettings()
    }

    func applySettings() {
        var lightingSettings = settings
        if settings.background == .stadium {
            // Depth must identify virtual geometry, not reconstructed ground.
            lightingSettings.groundingShadow = false
            lightingSettings.sceneOcclusion = false
        }
        lighting.apply(lightingSettings, to: view, meshSupported: meshSupported)
        characterRoot?.scale = SIMD3(repeating: settings.height)
        characterRoot?.orientation = simd_quatf(angle: settings.rotation * .pi / 180, axis: [0, 1, 0])
        characterRoot?.position.y = settings.floorOffset
    }

    private func updateBackground() {
        backgroundReady = false
        selectingBench = settings.background == .stadium
        background.setEnabled(ready && settings.background == .stadium)
    }

    func selectBenchAgain() {
        guard ready, !capturing, !videoRecording else { return }
        selectingBench = true
        backgroundReady = false
        background.reselectBench()
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard ready, settings.background == .stadium else { return }
        background.submit(frame, viewport: view.bounds.size,
                          orientation: view.window?.windowScene?.effectiveGeometry.interfaceOrientation ?? .portrait)
    }

    func loadCharacter() {
        guard lifecycle.running, ready else { return }
        loadTask?.cancel()
        if case .characterLoadFailure = recoveryIssue { recoveryIssue = nil }
        loading = true
        let selection = settings.character
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let (root, model) = try await self.characters.load(selection)
                try Task.checkCancellation()
                guard self.lifecycle.running, self.settings.character == selection else { return }
                model.generateCollisionShapes(recursive: true)
                self.animation.load(from: model)
                self.characterRoot?.removeFromParent()
                self.characterRoot = root
                self.loadedCharacter = selection
                self.anchor?.addChild(root)
                self.loading = false
                self.loadTask = nil
                self.applySettings()
                self.message = self.placed ? "캐릭터를 바꿨습니다." : "캐릭터 준비 완료 · 인식된 바닥을 터치하세요."
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, self.lifecycle.running, self.settings.character == selection else { return }
                self.loading = false
                self.loadTask = nil
                self.showRecovery(.characterLoadFailure(error.localizedDescription))
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

    @objc private func dragged(_ gesture: UIPanGestureRecognizer) {
        guard ready, placed, !loading, !capturing, !videoRecording, gesture.numberOfTouches == 1 else {
            dragStart = nil
            return
        }
        switch gesture.state {
        case .began:
            // Require the drag to start on the character rather than anywhere on the floor.
            let translation = gesture.translation(in: view)
            let location = gesture.location(in: view)
            let origin = CGPoint(x: location.x - translation.x, y: location.y - translation.y)
            guard touchesCharacter(at: origin) else {
                dragStart = nil
                return
            }
            dragStart = (settings.rotation, settings.floorOffset)
        case .changed:
            guard let initial = dragStart else { return }
            let translation = gesture.translation(in: view)
            settings.rotation = (initial.rotation + Float(translation.x) * 0.5 + 180)
                .truncatingRemainder(dividingBy: 360)
            if settings.rotation < 0 { settings.rotation += 360 }
            settings.rotation -= 180
            // Moving upward on screen lifts the character above the detected floor.
            settings.floorOffset = min(0.3, max(-0.3, initial.floorOffset - Float(translation.y) * 0.002))
            applySettings()
        case .ended, .cancelled, .failed:
            dragStart = nil
        default: break
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        (gestureRecognizer is UIPanGestureRecognizer && other is UIPinchGestureRecognizer)
            || (gestureRecognizer is UIPinchGestureRecognizer && other is UIPanGestureRecognizer)
    }

    private func touchesCharacter(at point: CGPoint) -> Bool {
        guard let root = characterRoot else { return false }
        if let hit = view.entity(at: point), belongsToCharacter(hit, root: root) { return true }
        // Animated/thin meshes can miss collision ray tests; accept their visible screen bounds.
        let bounds = root.visualBounds(relativeTo: nil)
        var projected: [CGPoint] = []
        for x in [bounds.min.x, bounds.max.x] {
            for y in [bounds.min.y, bounds.max.y] {
                for z in [bounds.min.z, bounds.max.z] {
                    if let p = view.project(SIMD3(x, y, z)), p.x.isFinite, p.y.isFinite {
                        projected.append(p)
                    }
                }
            }
        }
        guard let first = projected.first else { return false }
        var rect = CGRect(origin: first, size: .zero)
        for p in projected {
            rect = CGRect(x: min(rect.minX, p.x), y: min(rect.minY, p.y),
                          width: max(rect.maxX, p.x) - min(rect.minX, p.x),
                          height: max(rect.maxY, p.y) - min(rect.minY, p.y))
        }
        return rect.insetBy(dx: -16, dy: -16).contains(point)
    }

    private func belongsToCharacter(_ entity: Entity, root: Entity) -> Bool {
        var candidate: Entity? = entity
        while let current = candidate {
            if current === root { return true }
            candidate = current.parent
        }
        return false
    }

    @objc private func pinched(_ gesture: UIPinchGestureRecognizer) {
        guard ready, placed, !loading, !capturing, !videoRecording else {
            pinchStartHeight = nil
            return
        }
        switch gesture.state {
        case .began:
            pinchStartHeight = settings.height
        case .changed:
            guard let initial = pinchStartHeight else { return }
            let height = initial * Float(gesture.scale)
            guard height.isFinite else { return }
            settings.height = min(2.5, max(0.2, height))
            applySettings()
        case .ended, .cancelled, .failed:
            pinchStartHeight = nil
        default: break
        }
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        if settings.background == .stadium && selectingBench {
            guard ready, !capturing, !videoRecording, view.bounds.width > 0, view.bounds.height > 0 else { return }
            let point = gesture.location(in: view)
            background.selectBench(at: CGPoint(x: point.x / view.bounds.width, y: point.y / view.bounds.height))
            return
        }
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
        guard lifecycle.running else { return }
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

    func sessionWasInterrupted(_ session: ARSession) {
        guard lifecycle.interrupt() else { return }
        tracking = "카메라 일시 중단"
        loadTask?.cancel()
        loadTask = nil
        loading = false
        background.setEnabled(false)
        backgroundReady = false
        ready = false
        showRecovery(.interrupted)
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        guard lifecycle.endInterruption() else { return }
        if case .interrupted = recoveryIssue { recoveryIssue = nil }
        ready = true
        configureSession()
        updateBackground()
        if loadedCharacter != settings.character { loadCharacter() }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        guard lifecycle.fail() else { return }
        ready = false
        loadTask?.cancel()
        loadTask = nil
        loading = false
        view.session.pause()
        background.setEnabled(false)
        backgroundReady = false
        showRecovery(.sessionFailure(error.localizedDescription))
    }

    func capture() {
        guard canCapture, let frame = view.session.currentFrame else { return }
        if settings.background == .stadium && !background.hasFreshMask {
            errorMessage = "벤치를 다시 인식한 후 촬영해 주세요."
            return
        }
        capturing = true
        photoCapture.capture(view: view, viewport: photoViewport, frame: frame, anchor: anchor, settings: settings,
                             peopleSupported: peopleSupported, meshSupported: meshSupported,
                             snapshot: settings.background == .stadium ? { [background] completion in
                                 background.captureNextFrame { image in
                                     Task { @MainActor in completion(image.map { UIImage(cgImage: $0) }) }
                                 }
                             } : nil) { [weak self] outcome in
            guard let self else { return }
            self.capturing = false
            switch outcome {
            case .success(let result): self.result = result
            case .failure(let error): self.errorMessage = "사진 저장 실패: \(error.localizedDescription)"
            }
        }
    }
}
