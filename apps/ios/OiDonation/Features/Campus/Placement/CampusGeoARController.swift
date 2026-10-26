import ARKit
import RealityKit
import AVFoundation
import Observation

/// A separate on-site placement experiment; the existing photo/palm camera stays unchanged.
@MainActor @Observable final class CampusGeoARController: NSObject, ARSessionDelegate {
    enum Mode: String { case preparing = "AR 준비 중", geographic = "지리 추적", gps = "GPS 근사 배치", manual = "직접 바닥 보정" }
    private(set) var mode = Mode.preparing
    private(set) var message = "카메라 권한과 모델을 확인하고 있어요."
    private(set) var canChangeMode = false
    private(set) var placed = false
    var onStory: (() -> Void)?
    @ObservationIgnored private var view: RealityKit.ARView?
    @ObservationIgnored private var character: Entity?
    @ObservationIgnored private var anchor: AnchorEntity?
    @ObservationIgnored private var geoAnchor: ARGeoAnchor?
    @ObservationIgnored private var location: CampusGeoLocation?
    private var placement: CampusPlacement?
    private var active = false
    private var localized = false
    private var interrupted = false
    private var failed = false
    private var generation = UUID()
    private var lastFrameCheck = 0.0

    func makeView() -> RealityKit.ARView {
        if let view { return view }
        let result = RealityKit.ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        result.session.delegate = self
        result.session.delegateQueue = .main
        result.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tap(_:))))
        view = result
        return result
    }

    func start(_ placement: CampusPlacement, location: CampusGeoLocation) async {
        stop()
        self.placement = placement; self.location = location
        mode = .preparing; message = "카메라 권한과 모델을 확인하고 있어요."
        guard ARWorldTrackingConfiguration.isSupported else {
            message = "현장 AR은 ARKit을 지원하는 실제 iPhone에서 사용할 수 있어요."; return
        }
        let token = generation
        let allowed = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
            ? true : await AVCaptureDevice.requestAccess(for: .video)
        guard token == generation, !Task.isCancelled else { return }
        guard allowed else { message = "설정에서 카메라 권한을 허용한 뒤 다시 시도해 주세요."; return }
        do {
            let entity = try await CampusOiAsset.load()
            guard token == generation, !Task.isCancelled else { return }
            entity.name = "campus-geo-oi"
            entity.scale = SIMD3(repeating: Float(placement.heightMeters))
            entity.orientation = CampusOiAsset.heading(placement.headingDegrees)
            character = entity
        } catch {
            guard token == generation else { return }
            message = "오이 모델을 불러오지 못했어요. 다시 시도해 주세요."; return
        }
        _ = makeView()
        active = true; canChangeMode = true
        location.start()
        guard ARGeoTrackingConfiguration.isSupported else { startApproximate(); return }
        message = "이 위치의 지리 추적 지원을 확인하고 있어요. 오래 걸리면 GPS 근사 배치를 선택해 주세요."
        ARGeoTrackingConfiguration.checkAvailability(at: .init(latitude: placement.latitude, longitude: placement.longitude)) { [weak self] available, _ in
            Task { @MainActor in
                guard let self, self.active, self.generation == token else { return }
                if available { self.startGeographic() }
                else {
                    self.startApproximate()
                    self.message = "지리 추적을 사용할 수 없어 GPS 근사 배치를 시작했어요. 네트워크나 지역 지원에 따라 달라질 수 있습니다. 바닥을 비춰 주세요."
                }
            }
        }
    }

    private func clearAnchor() {
        if let geoAnchor { view?.session.remove(anchor: geoAnchor) }
        geoAnchor = nil
        anchor?.removeFromParent(); anchor = nil; placed = false
        character?.removeFromParent()
    }
    private func prepare(_ mode: Mode) -> RealityKit.ARView? {
        guard active, let view, character != nil else { return nil }
        generation = UUID() // Invalidate an outstanding availability callback.
        clearAnchor(); self.mode = mode
        localized = false; interrupted = false; failed = false; lastFrameCheck = 0
        return view
    }
    private func startGeographic() {
        guard let view = prepare(.geographic) else { return }
        let config = ARGeoTrackingConfiguration()
        config.planeDetection = [.horizontal]
        config.isLightEstimationEnabled = true
        view.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        message = "건물과 주변 풍경을 천천히 비춰 위치를 보정해 주세요. 지리 추적이 계속 준비 중이면 GPS 근사 배치를 사용할 수 있어요."
    }
    func startApproximate(manual: Bool = false) {
        guard let view = prepare(manual ? .manual : .gps) else { return }
        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravityAndHeading
        config.planeDetection = [.horizontal]
        config.environmentTexturing = .automatic
        config.isLightEstimationEnabled = true
        view.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        message = manual
            ? "지도에서 선택한 실제 지점을 찾고 그곳의 바닥을 눌러 주세요. 보정은 이번 AR 세션에만 적용돼요."
            : "GPS와 나침반을 이용한 근사 위치입니다. 목표 주변에서 바닥을 비춰 주세요. 실제 위치와 수 m 이상 차이 날 수 있어요."
    }
    func reset() {
        if mode == .geographic { startGeographic() }
        else { startApproximate(manual: mode == .manual) }
    }
    func stop() {
        active = false; canChangeMode = false; generation = UUID()
        location?.stop(); view?.session.pause(); clearAnchor()
        character = nil
    }

    private var positionReady: Bool {
        guard let placement, let location else { return false }
        return location.isReady(for: placement)
    }
    private func addContent(to anchor: AnchorEntity) {
        guard let character, let view else { return }
        character.removeFromParent(); anchor.addChild(character)
        view.scene.addAnchor(anchor); self.anchor = anchor; placed = true
        message = "오이를 누르면 연결된 예시 이야기가 열려요. 실제 발 위치와 주변을 확인해 주세요."
    }
    private func update(_ frame: ARFrame) {
        guard active, !interrupted, !failed, frame.timestamp - lastFrameCheck > 0.5 else { return }
        lastFrameCheck = frame.timestamp
        let normal: Bool
        if case .normal = frame.camera.trackingState { normal = true } else { normal = false }
        let valid = positionReady && normal && (mode != .geographic || localized)
        anchor?.isEnabled = valid
        guard valid else {
            message = !positionReady ? "목표 25m 안에서 GPS 오차가 15m 이하인 최신 위치를 기다리고 있어요." : "주변을 천천히 비춰 카메라 추적과 위치 보정을 안정시켜 주세요."
            return
        }
        if placed { message = "오이를 눌러 예시 이야기 보기 · \(mode.rawValue)"; return }
        guard let view, let placement else { return }
        if mode == .geographic {
            // No altitude: let ARKit resolve ground level, never use the approximate mesh elevation.
            let geo = ARGeoAnchor(coordinate: .init(latitude: placement.latitude, longitude: placement.longitude))
            geoAnchor = geo
            view.session.add(anchor: geo)
            addContent(to: AnchorEntity(anchor: geo))
        } else if mode == .gps {
            guard let current = location?.location,
                  let ground = view.raycast(from: CGPoint(x: view.bounds.midX, y: view.bounds.height * 0.7),
                    allowing: .existingPlaneGeometry, alignment: .horizontal).first else {
                message = "목표 주변의 바닥을 천천히 비춰 주세요. 바닥 높이를 찾으면 GPS 근사 위치에 나타나요."; return
            }
            let camera = frame.camera.transform.columns.3
            let offset = placement.offsetMeters(fromLatitude: current.coordinate.latitude, longitude: current.coordinate.longitude)
            // Freeze the initial GPS solution. Reapplying noisy fixes every frame would make the character drift.
            let point = SIMD3(camera.x + offset.x, ground.worldTransform.columns.3.y, camera.z + offset.z)
            addContent(to: AnchorEntity(world: point))
        } else if mode == .manual {
            message = "지도에서 선택한 실제 지점의 바닥을 눌러 주세요. 이번 세션에만 보정됩니다."
        }
    }
    @objc private func tap(_ recognizer: UITapGestureRecognizer) {
        guard active, !failed, !interrupted, let view, positionReady,
              case .normal = view.session.currentFrame?.camera.trackingState else { return }
        let point = recognizer.location(in: view)
        if placed, anchor?.isEnabled == true {
            var entity = view.entity(at: point)
            while let item = entity {
                if item.name == "campus-geo-oi" { onStory?(); return }
                entity = item.parent
            }
        }
        guard mode == .manual, !placed else { return }
        guard let hit = view.raycast(from: point, allowing: .existingPlaneGeometry, alignment: .horizontal).first else {
            message = "바닥이 아직 인식되지 않았어요. 바닥을 천천히 비춰 다시 눌러 주세요."; return
        }
        let t = hit.worldTransform.columns.3
        addContent(to: AnchorEntity(world: SIMD3(t.x, t.y, t.z)))
    }

    // ARSession delivers these callbacks on delegateQueue == .main, avoiding per-frame tasks/queues.
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        MainActor.assumeIsolated { update(frame) }
    }
    nonisolated func session(_ session: ARSession, didChange status: ARGeoTrackingStatus) {
        MainActor.assumeIsolated {
            guard active, mode == .geographic else { return }
            localized = status.state == .localized && (status.accuracy == .medium || status.accuracy == .high)
            if !localized { anchor?.isEnabled = false }
        }
    }
    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            guard active else { return }
            failed = true; anchor?.isEnabled = false
            message = "AR을 계속할 수 없어요. 다시 배치하거나 GPS·바닥 보정으로 전환해 주세요."
        }
    }
    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        MainActor.assumeIsolated {
            guard active else { return }
            interrupted = true; anchor?.isEnabled = false
            message = "카메라가 잠시 중단됐어요. 복귀하면 다시 위치를 확인합니다."
        }
    }
    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        MainActor.assumeIsolated { guard active else { return }; reset() }
    }
}
