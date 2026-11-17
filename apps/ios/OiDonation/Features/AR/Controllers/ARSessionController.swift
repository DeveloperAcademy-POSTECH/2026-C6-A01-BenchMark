import ARKit
import AVFoundation
import Metal
import Observation
import QuartzCore
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
    private(set) var subject: ARCameraSubject?
    let originalSubject: ARCameraSubject?
    private var originalSettings: ARCaptureSettings?
    private var mascotSettings = ARCaptureSettings()
    var isPalmMode: Bool { subject == nil && settings.placementMode == .palm }
    private(set) var palmTracking = false
    private var palmState = ARPalmPlacementState()
    private var palmOffset = SIMD3<Float>.zero
    private var lastPalmFrame: TimeInterval?
    private var palmFailed = false
    @ObservationIgnored private var palm: ARPalmTrackingService?
    var usesGeographicPlacement: Bool { subject?.placement != nil }
    private(set) var geographicReady = false
    private(set) var locationNotice = ""
    @ObservationIgnored private let locationProvider: (any ARCameraLocationProviding)?
    @ObservationIgnored private var geoPlacement: ARCameraGeoPlacement?
    @ObservationIgnored private var lastGeographicCheck = 0.0
    @ObservationIgnored private var headingAligned = false
    @ObservationIgnored private var cameraPoses = ARCameraPoseHistory()
    var message = "바닥이 보이도록 카메라를 천천히 움직여 주세요."
    var tracking = "준비 중"
    var loading = false
    var placed = false
    var locked = false {
        didSet {
            if oldValue != locked && isPalmMode {
                palm?.invalidate()
                if !locked { palmState.reset(); palmTracking = false }
            }
        }
    }
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
            && (!usesGeographicPlacement || geographicReady)
            && (!isPalmMode || locked || palmTracking)
    }
    private var loadTask: Task<Void, Never>?
    private var lifecycle = ARSessionLifecycle()
    @ObservationIgnored private var cameraAuthorizationTask: Task<Bool, Never>?
    private var pinchStartHeight: Float?
    private var dragStart: (point: SIMD3<Float>, anchor: SIMD3<Float>, offset: SIMD3<Float>, normal: SIMD3<Float>)?

    init(subject: ARCameraSubject? = nil, locationProvider: (any ARCameraLocationProviding)? = nil) {
        self.subject = subject
        self.originalSubject = subject
        if let target = subject?.placement {
            self.locationProvider = locationProvider ?? CampusGeoLocation()
            geoPlacement = ARCameraGeoPlacement(target: target)
        } else { self.locationProvider = nil }
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(featureUsageChanged),
            name: OiFeatureUsage.didChange, object: nil)
        settings = subject?.defaultSettings ?? ARCaptureSettings()
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

    @objc private func featureUsageChanged() {
        if !OiFeatureUsage.shared.isEnabled(.camera) {
            stop()
            message = OiFeatureUsageError.disabled(.camera).localizedDescription
        } else if usesGeographicPlacement && !OiFeatureUsage.shared.isEnabled(.location) {
            stop()
            message = OiFeatureUsageError.disabled(.location).localizedDescription
        }
    }

    private func start(recovering: Bool) async {
        guard OiFeatureUsage.shared.isEnabled(.camera),
              !usesGeographicPlacement || OiFeatureUsage.shared.isEnabled(.location) else {
            featureUsageChanged()
            return
        }
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
        animation.setSceneActive(true)
        if usesGeographicPlacement { locationProvider?.start() }
        configureSession(resetTracking: attempt.requiresTrackingReset || usesGeographicPlacement)
        updateBackground()
        if subject != nil || loadedCharacter != settings.character { loadCharacter() }
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
        animation.setSceneActive(false)
        invalidatePalm()
        locationProvider?.stop()
        invalidateGeographicPlacement()
        lifecycle.pause()
        loadTask?.cancel()
        loadTask = nil
        loading = false
        view.session.pause()
        background.setEnabled(false)
        backgroundReady = false
        ready = false
    }

    func makeSessionConfiguration() -> ARWorldTrackingConfiguration {
        let config = ARWorldTrackingConfiguration()
        // A first-use permission prompt must not run heading tracking before
        // Location Services is authorized. The live frame path switches once after a grant.
        let authorized = usesGeographicPlacement && locationProvider?.hasPreciseLocationPermission == true
        config.worldAlignment = authorized ? .gravityAndHeading : .gravity
        config.planeDetection = isPalmMode ? [] : [.horizontal]
        config.isLightEstimationEnabled = true
        config.environmentTexturing = isPalmMode ? .none : .automatic
        if subject == nil {
            let formats = ARWorldTrackingConfiguration.supportedVideoFormats
            if !formats.isEmpty {
                let defaultSize = config.videoFormat.imageResolution
                if let format = formats.first(where: {
                    $0.framesPerSecond == 30 && $0.imageResolution.width * $0.imageResolution.height <= defaultSize.width * defaultSize.height
                }) { config.videoFormat = format }
            }
        }
        if !isPalmMode && settings.peopleOcclusion && peopleSupported {
            config.frameSemantics.insert(.personSegmentationWithDepth)
        }
        if meshSupported && !isPalmMode && settings.sceneOcclusion { config.sceneReconstruction = .mesh }
        return config
    }

    func configureSession(resetTracking: Bool = false) {
        guard ready else { return }
        let config = makeSessionConfiguration()
        headingAligned = config.worldAlignment == .gravityAndHeading
        if resetTracking {
            cameraPoses.reset()
            resetPlacement()
            view.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        } else {
            view.session.run(config)
        }
    }

    func selectMascot(_ character: ARCharacter) {
        if subject != nil { originalSettings = settings }
        else { mascotSettings = settings }
        pause()
        subject = nil
        settings = mascotSettings
        settings.character = character
        discardCharacterPlacement()
        message = isPalmMode ? "손바닥 전체를 펼쳐 보여 주세요." : "바닥을 비춘 뒤 터치해 캐릭터를 놓으세요."
    }

    func restoreOriginalSubject() {
        guard let originalSubject else { return }
        mascotSettings = settings
        pause()
        subject = originalSubject
        settings = originalSettings ?? originalSubject.defaultSettings
        discardCharacterPlacement()
        message = "지도에 저장한 오이의 위치를 다시 확인하고 있어요."
    }

    private func discardCharacterPlacement() {
        resetPlacement()
        animation.stop()
        characterRoot?.removeFromParent()
        characterRoot = nil
        loadedCharacter = nil
    }

    func update(from previous: ARCaptureSettings) {
        if previous.placementMode != settings.placementMode, subject == nil {
            if isPalmMode { settings.background = .original }
            resetPlacement()
            configureSession()
            message = isPalmMode ? "손바닥 전체를 펼쳐 보여 주세요." : "바닥을 터치해 캐릭터를 놓으세요."
        }
        if previous.character != settings.character { loadCharacter() }
        if previous.peopleOcclusion != settings.peopleOcclusion || previous.sceneOcclusion != settings.sceneOcclusion { configureSession() }
        if previous.background != settings.background { updateBackground() }
        applySettings()
    }

    func resetSettings() {
        settings = subject?.defaultSettings ?? ARCaptureSettings()
    }

    func applySettings() {
        let optionalEffects: RealityKit.ARView.RenderOptions = [.disableMotionBlur, .disableDepthOfField, .disableCameraGrain]
        if subject == nil { view.renderOptions.formUnion(optionalEffects) }
        else { view.renderOptions.subtract(optionalEffects) }
        var lightingSettings = settings
        if isPalmMode || settings.background == .stadium {
            // Depth must identify virtual geometry, not reconstructed ground.
            lightingSettings.groundingShadow = false
            lightingSettings.sceneOcclusion = false
        }
        lighting.apply(lightingSettings, to: view, meshSupported: meshSupported)
        characterRoot?.scale = SIMD3(repeating: isPalmMode ? (settings.palmHeight ?? 0.065) : settings.height)
        characterRoot?.orientation = simd_quatf(angle: (isPalmMode ? (settings.palmRotation ?? 0) : settings.rotation) * .pi / 180, axis: [0, 1, 0])
        characterRoot?.position.y = isPalmMode ? 0 : settings.floorOffset
    }

    private func updateBackground() {
        backgroundReady = false
        selectingBench = settings.background == .stadium
        background.setEnabled(ready && !isPalmMode && settings.background == .stadium)
    }

    func selectBenchAgain() {
        guard ready, !capturing, !videoRecording else { return }
        selectingBench = true
        backgroundReady = false
        background.reselectBench()
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        if ready && isPalmMode { updatePalm(frame) }
        if ready && usesGeographicPlacement && headingAligned, case .normal = frame.camera.trackingState {
            let point = frame.camera.transform.columns.3
            cameraPoses.record(position: SIMD3(point.x, point.y, point.z), timestamp: frame.timestamp)
        }
        if ready && usesGeographicPlacement && frame.timestamp - lastGeographicCheck >= 0.5 {
            lastGeographicCheck = frame.timestamp
            updateGeographicPlacement(frame)
        }
        guard ready, settings.background == .stadium else { return }
        background.submit(frame, viewport: view.bounds.size,
                          orientation: view.window?.windowScene?.effectiveGeometry.interfaceOrientation ?? .portrait)
    }

    private func invalidatePalm() {
        palm?.invalidate()
        palmState.reset()
        palmTracking = false
        palmFailed = false
        lastPalmFrame = nil
        if isPalmMode && !locked { anchor?.isEnabled = false; placed = false }
    }

    private func updatePalm(_ frame: ARFrame) {
        guard !capturing, !loading else { return }
        if case .notAvailable = frame.camera.trackingState { invalidatePalm(); return }
        if locked { return }
        if palm == nil {
            palm = ARPalmTrackingService(onFailure: { [weak self] in
                guard let self, self.ready, self.isPalmMode, !self.locked else { return }
                self.palmFailed = true
            }) { [weak self] observation in
                guard let self, self.ready, self.isPalmMode, !self.locked, !self.loading, !self.capturing else { return }
                self.palmFailed = false
                self.palmState.observe(observation)
            }
        }
        let delta = lastPalmFrame.map { frame.timestamp - $0 } ?? 1.0 / 30
        lastPalmFrame = frame.timestamp
        let fresh = palmState.isFresh(at: frame.timestamp)
        if palmTracking != fresh { palmTracking = fresh }
        if let point = palmState.update(at: frame.timestamp, deltaTime: delta), let root = characterRoot {
            if anchor == nil {
                let newAnchor = AnchorEntity(world: SIMD3<Float>.zero)
                let towardCamera = frame.camera.transform.columns.3
                newAnchor.orientation = simd_quatf(angle: atan2(towardCamera.x - point.x, towardCamera.z - point.z), axis: [0, 1, 0])
                newAnchor.addChild(root)
                view.scene.addAnchor(newAnchor)
                anchor = newAnchor
            }
            anchor?.position = point + palmOffset + SIMD3(0, 0.004, 0)
            anchor?.isEnabled = true
            placed = true
            let notice = fresh ? "손바닥 추적 중 · 핀치로 크기, 드래그로 위치 조절" : "손을 다시 인식하고 있어요. 잠시 위치를 유지합니다."
            if message != notice { message = notice }
        } else {
            anchor?.isEnabled = false
            placed = false
            let notice = palmFailed ? "손 인식을 다시 준비하고 있어요. 계속되면 바닥 모드로 전환해 주세요." : "밝은 곳에서 손바닥 전체를 후면 카메라에 펼쳐 보여 주세요."
            if message != notice { message = notice }
        }
        let interval: TimeInterval
        if ProcessInfo.processInfo.thermalState == .critical { interval = 0.5 }
        else if ProcessInfo.processInfo.thermalState == .serious { interval = 0.25 }
        else if ProcessInfo.processInfo.isLowPowerModeEnabled { interval = 1.0 / 6 }
        else { interval = 1.0 / 12 }
        palm?.submit(frame, viewport: view.bounds.size,
            orientation: view.window?.windowScene?.effectiveGeometry.interfaceOrientation ?? .portrait, interval: interval)
    }

    func loadCharacter() {
        guard lifecycle.running, ready else { return }
        loadTask?.cancel()
        if case .characterLoadFailure = recoveryIssue { recoveryIssue = nil }
        loading = true
        let selection = settings.character
        if subject != nil {
            animation.stop()
            characterRoot?.removeFromParent()
            characterRoot = nil
            loadedCharacter = nil
        }
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let loaded: (root: Entity, model: Entity)
                if let subject = self.subject { loaded = try await self.characters.load(subject) }
                else { loaded = try await self.characters.load(selection) }
                let (root, model) = loaded
                try Task.checkCancellation()
                guard self.lifecycle.running, self.settings.character == selection else { return }
                // A single bounds shape is sufficient for capture gestures; do not
                // construct a convex collision mesh for every detailed model part.
                let hitBounds = root.visualBounds(relativeTo: root)
                let hitSize = SIMD3(max(0.01, hitBounds.extents.x), max(0.01, hitBounds.extents.y), max(0.01, hitBounds.extents.z))
                root.components.set(CollisionComponent(shapes: [ShapeResource.generateBox(size: hitSize).offsetBy(translation: hitBounds.center)]))
                self.animation.load(from: model)
                self.characterRoot?.removeFromParent()
                self.characterRoot = root
                self.loadedCharacter = selection
                self.anchor?.addChild(root)
                self.loading = false
                self.loadTask = nil
                self.applySettings()
                self.lastGeographicCheck = 0
                self.message = self.usesGeographicPlacement ? "저장 위치의 바닥을 찾으면 오이가 자동으로 나타나요." :
                    self.placed ? "캐릭터를 바꿨습니다." : "캐릭터 준비 완료 · 인식된 바닥을 터치하세요."
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
        guard !usesGeographicPlacement, !locked, ready, placed, !loading, !capturing, !videoRecording, gesture.numberOfTouches == 1 else {
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
            guard let anchor, let frame = view.session.currentFrame else { return }
            let normal = -SIMD3(frame.camera.transform.columns.2.x, frame.camera.transform.columns.2.y, frame.camera.transform.columns.2.z)
            let anchorPoint = anchor.position
            guard let point = dragPoint(at: origin, plane: anchorPoint, normal: normal) else { return }
            dragStart = (point, anchorPoint, palmOffset, normal)
        case .changed:
            guard let initial = dragStart else { return }
            guard let point = dragPoint(at: gesture.location(in: view), plane: initial.anchor, normal: initial.normal) else { return }
            let delta = point - initial.point
            if isPalmMode {
                let offset = initial.offset + delta
                let length = simd_length(offset)
                palmOffset = length > 0.15 ? offset * (0.15 / length) : offset
            } else { anchor?.position = initial.anchor + delta }
        case .ended, .cancelled, .failed:
            dragStart = nil
        default: break
        }
    }

    private func dragPoint(at point: CGPoint, plane: SIMD3<Float>, normal: SIMD3<Float>) -> SIMD3<Float>? {
        if !isPalmMode {
            guard let hit = view.raycast(from: point, allowing: .existingPlaneGeometry, alignment: .horizontal).first else { return nil }
            let p = hit.worldTransform.columns.3
            return SIMD3(p.x, p.y, p.z)
        }
        guard let ray = view.ray(through: point) else { return nil }
        let denominator = simd_dot(ray.direction, normal)
        guard abs(denominator) > 0.0001 else { return nil }
        let distance = simd_dot(plane - ray.origin, normal) / denominator
        guard distance.isFinite, distance > 0 else { return nil }
        return ray.origin + ray.direction * distance
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
            pinchStartHeight = isPalmMode ? (settings.palmHeight ?? 0.065) : settings.height
        case .changed:
            guard let initial = pinchStartHeight else { return }
            let height = initial * Float(gesture.scale)
            guard height.isFinite else { return }
            if isPalmMode { settings.palmHeight = min(0.2, max(0.025, height)) }
            else { settings.height = min(2.5, max(0.2, height)) }
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
        guard !usesGeographicPlacement, !isPalmMode, ready, !loading, !locked, !capturing, !videoRecording, let root = characterRoot else { return }
        guard let hit = view.raycast(from: gesture.location(in: view), allowing: .existingPlaneGeometry, alignment: .horizontal).first else {
            message = "아직 바닥을 찾지 못했습니다. 바닥을 여러 각도에서 비춰 주세요."
            return
        }
        anchor?.removeFromParent()
        let newAnchor = AnchorEntity(world: SIMD3<Float>.zero)
        newAnchor.transform = Transform(matrix: hit.worldTransform)
        newAnchor.addChild(root)
        view.scene.addAnchor(newAnchor)
        anchor = newAnchor
        placed = true
        message = "배치 완료 · 바닥을 다시 터치하면 이동합니다."
        applySettings()
    }

    private func invalidateGeographicPlacement() {
        guard usesGeographicPlacement else { return }
        geographicReady = false
        anchor?.isEnabled = false
    }

    private func updateGeographicPlacement(_ frame: ARFrame) {
        guard var resolution = geoPlacement, let locationProvider else { return }
        if headingAligned != locationProvider.hasPreciseLocationPermission {
            configureSession(resetTracking: true)
            return
        }
        let sample = locationProvider.hasUsableFix ? locationProvider.location : nil
        let fix = sample.map { ARCameraGeoPlacement.Fix(latitude: $0.coordinate.latitude,
            longitude: $0.coordinate.longitude, accuracy: $0.horizontalAccuracy, timestamp: $0.timestamp) }
        let normal: Bool
        if case .normal = frame.camera.trackingState { normal = true } else { normal = false }
        // Pair the GPS fix with the AR pose from its measurement time. Using
        // the current pose would add the user's intervening walk to the target.
        let cameraAtFix = sample.flatMap {
            cameraPoses.position(at: CACurrentMediaTime() + $0.timestamp.timeIntervalSinceNow)
        }
        let status = resolution.update(fix: fix, trackingNormal: normal, cameraAtFix: cameraAtFix) { [self] point in
            guard !loading, characterRoot != nil else { return nil }
            // Resolve ground at the saved point, not the floor below the phone.
            // A remote slope or staircase must not inherit this phone's floor height.
            let query = ARRaycastQuery(origin: SIMD3(point.x, point.y + 1, point.z), direction: [0, -1, 0],
                allowing: .existingPlaneGeometry, alignment: .horizontal)
            return view.session.raycast(query).first?.worldTransform.columns.3.y
        }
        geoPlacement = resolution
        applyGeographicStatus(status, locationMessage: locationProvider.message)
    }

    /// Shared with deterministic location/recording checks; never starts another AR session.
    func applyGeographicStatus(_ status: ARCameraGeoPlacement.Status, locationMessage: String?) {
        guard usesGeographicPlacement else { return }
        if case .ready = status { } else { invalidateGeographicPlacement() }
        switch status {
        case .waitingForLocation:
            locationNotice = locationMessage ?? "정확한 위치 권한과 최신 GPS 위치를 확인하고 있어요."
            message = "GPS 오차가 15m 이하인 위치를 기다리고 있어요."
        case .outsideRange(let distance):
            locationNotice = String(format: "저장 위치까지 약 %.0fm · 25m 안으로 이동해 주세요.", distance)
            message = "저장한 오이가 있는 장소에 가까워지면 자동으로 나타나요."
        case .waitingForSynchronizedLocation:
            locationNotice = "새 GPS 위치를 확인하고 있어요."
            message = "저장 지점 주변을 천천히 비추며 잠시 기다려 주세요."
        case .waitingForTracking:
            locationNotice = "카메라 추적을 확인하고 있어요."
            message = "주변을 천천히 비춰 공간을 인식해 주세요."
        case .waitingForGround:
            locationNotice = "저장 위치 주변의 바닥을 비춰 주세요."
            message = loading ? "선택한 오이를 불러오고 있어요." : "바닥을 인식하면 터치 없이 자동으로 배치돼요."
        case .ready(let point):
            guard !loading, let root = characterRoot else { invalidateGeographicPlacement(); return }
            if anchor == nil {
                let newAnchor = AnchorEntity(world: point)
                newAnchor.addChild(root)
                view.scene.addAnchor(newAnchor)
                anchor = newAnchor
                placed = true
                locked = true
                applySettings()
            }
            anchor?.isEnabled = true
            geographicReady = true
            locationNotice = "저장 위치 자동 배치 · GPS 기반 근사 위치"
            message = "저장 위치에 오이가 나타났어요. 사진이나 비디오로 남겨 보세요."
        }
    }

    func resetPlacement() {
        invalidatePalm()
        palmOffset = .zero
        geoPlacement?.reset()
        lastGeographicCheck = 0
        geographicReady = false
        anchor?.removeFromParent()
        anchor = nil
        placed = false
        locked = false
        message = usesGeographicPlacement ? "저장 위치의 바닥을 다시 확인하고 있어요." : "새 위치의 바닥을 터치하세요."
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        guard lifecycle.running else { return }
        if usesGeographicPlacement, case .limited = camera.trackingState { invalidateGeographicPlacement() }
        if usesGeographicPlacement, case .notAvailable = camera.trackingState { invalidateGeographicPlacement() }
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
        animation.setSceneActive(false)
        locationProvider?.stop()
        invalidatePalm()
        invalidateGeographicPlacement()
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
        animation.setSceneActive(true)
        if usesGeographicPlacement { locationProvider?.start() }
        configureSession(resetTracking: usesGeographicPlacement)
        updateBackground()
        if subject != nil || loadedCharacter != settings.character { loadCharacter() }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        guard lifecycle.fail() else { return }
        animation.setSceneActive(false)
        locationProvider?.stop()
        invalidatePalm()
        invalidateGeographicPlacement()
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
