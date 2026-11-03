import ARKit
import AVFoundation
import Observation
import RealityKit

/// One AR session follows the user; nearby anchors are diffed without restarting tracking.
@MainActor @Observable final class CampusNearbyARController: NSObject, ARSessionDelegate {
    private(set) var message = "카메라와 위치를 준비하고 있어요."
    private(set) var visibleCount = 0
    private(set) var nearestDistance: Double?
    private(set) var ready = false
    var onStory: ((CampusNearbyOi) -> Void)?
    @ObservationIgnored private var view: RealityKit.ARView?
    @ObservationIgnored private var template: Entity?
    @ObservationIgnored private var location: CampusGeoLocation?
    @ObservationIgnored private var items: [CampusNearbyOi] = []
    @ObservationIgnored private var anchors: [String: (item: CampusNearbyOi, anchor: AnchorEntity)] = [:]
    private var generation = UUID()
    private var active = false
    private var interrupted = false
    private var failed = false
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

    func start(location: CampusGeoLocation) async {
        stop()
        self.location = location
        message = "카메라와 위치를 준비하고 있어요."
        guard ARWorldTrackingConfiguration.isSupported else {
            message = "주변 오이 AR은 ARKit을 지원하는 실제 iPhone에서 사용할 수 있어요."
            return
        }
        let token = generation
        let allowed = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
            ? true : await AVCaptureDevice.requestAccess(for: .video)
        guard token == generation, !Task.isCancelled else { return }
        guard allowed else { message = "설정에서 카메라 권한을 허용해 주세요."; return }
        do {
            let loaded = try await CampusOiAsset.load()
            guard token == generation, !Task.isCancelled else { return }
            template = loaded
        } catch {
            guard token == generation, !Task.isCancelled else { return }
            message = "오이 모델을 불러오지 못했어요. 다시 시도해 주세요."
            return
        }
        _ = makeView()
        active = true
        location.start()
        restartTracking()
    }

    func setItems(_ updated: [CampusNearbyOi]) {
        items = updated
        // Withdraw deleted/hidden/edited objects immediately, including while GPS is unavailable.
        let current = Set(updated)
        for key in Array(anchors.keys) {
            if let entry = anchors[key], !current.contains(entry.item) { remove(key) }
        }
        visibleCount = anchors.values.filter { $0.anchor.isEnabled }.count
        lastFrameCheck = 0
    }

    func stop() {
        generation = UUID(); active = false; ready = false
        onStory = nil
        location?.stop(); view?.session.pause()
        clearAnchors(); template = nil; nearestDistance = nil
    }

    private func restartTracking() {
        guard active, let view else { return }
        clearAnchors(); interrupted = false; failed = false; lastFrameCheck = 0
        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravityAndHeading
        config.planeDetection = [.horizontal]
        config.environmentTexturing = .automatic
        config.isLightEstimationEnabled = true
        view.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        ready = true
        message = "현재 위치 주변의 오이를 찾고 있어요. 바닥을 천천히 비춰 주세요."
    }

    private func remove(_ id: String) { anchors.removeValue(forKey: id)?.anchor.removeFromParent() }
    private func clearAnchors() {
        for id in Array(anchors.keys) { remove(id) }
        visibleCount = 0
    }
    private func hideAnchors() {
        for entry in anchors.values { entry.anchor.isEnabled = false }
        visibleCount = 0
    }

    private func update(_ frame: ARFrame) {
        guard active, !interrupted, !failed, frame.timestamp - lastFrameCheck >= 0.5 else { return }
        lastFrameCheck = frame.timestamp
        guard let location, location.hasUsableFix, let fix = location.location else {
            hideAnchors(); nearestDistance = nil
            message = location?.location == nil ? (location?.message ?? "위치를 확인하고 있어요.")
                : "정확한 위치와 GPS 오차 15m 이하의 최신 신호를 기다리고 있어요."
            return
        }
        let lat = fix.coordinate.latitude, lon = fix.coordinate.longitude
        nearestDistance = items.map { $0.placement.distance(latitude: lat, longitude: lon) }.min()
        let nearby = CampusNearbySelection.select(items, latitude: lat, longitude: lon,
            accuracy: fix.horizontalAccuracy, timestamp: fix.timestamp, retained: Set(anchors.keys))
        let desired = Set(nearby.map(\.id))
        for id in Array(anchors.keys) where !desired.contains(id) { remove(id) }
        guard case .normal = frame.camera.trackingState else {
            hideAnchors(); message = "주변을 천천히 비춰 카메라 추적을 안정시켜 주세요."; return
        }
        guard let view, let template else { return }
        for entry in anchors.values { entry.anchor.isEnabled = true }
        let missing = nearby.filter { anchors[$0.id] == nil }
        if !missing.isEmpty {
            // No inferred model elevation or eye-level fallback: wait for an actual detected floor.
            if let ground = view.raycast(from: CGPoint(x: view.bounds.midX, y: view.bounds.height * 0.7),
                allowing: .existingPlaneGeometry, alignment: .horizontal).first {
                let camera = frame.camera.transform.columns.3
                for item in missing {
                    let offset = item.placement.offsetMeters(fromLatitude: lat, longitude: lon)
                    let anchor = AnchorEntity(world: SIMD3(camera.x + offset.x, ground.worldTransform.columns.3.y, camera.z + offset.z))
                    let entity = template.clone(recursive: true)
                    entity.name = item.id
                    entity.scale = SIMD3(repeating: Float(item.placement.heightMeters))
                    entity.orientation = CampusOiAsset.heading(item.placement.headingDegrees)
                    anchor.addChild(entity); view.scene.addAnchor(anchor)
                    anchors[item.id] = (item, anchor)
                }
            }
        }
        visibleCount = anchors.values.filter { $0.anchor.isEnabled }.count
        if items.isEmpty { message = "아직 표시할 오이가 없어요. 지도에 오이를 배치한 뒤 다시 확인해 주세요." }
        else if nearby.isEmpty { message = "주변 25m 안에 오이가 없어요. 지도에 표시된 위치로 이동해 주세요." }
        else if visibleCount < nearby.count { message = "가까운 오이를 찾았어요. 바닥을 비추면 나타나요." }
        else { message = "주변을 둘러보세요. 오이를 누르면 이야기가 열려요." }
    }

    @objc private func tap(_ recognizer: UITapGestureRecognizer) {
        guard active, !failed, !interrupted, location?.hasUsableFix == true, let view,
              case .normal = view.session.currentFrame?.camera.trackingState else { return }
        var entity = view.entity(at: recognizer.location(in: view))
        while let current = entity {
            if let entry = anchors[current.name], entry.anchor.isEnabled { onStory?(entry.item); return }
            entity = current.parent
        }
    }

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        MainActor.assumeIsolated { update(frame) }
    }
    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            guard active else { return }
            failed = true; ready = false; hideAnchors()
            message = "AR이 중단됐어요. ‘다시 확인’을 눌러 주세요."
        }
    }
    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        MainActor.assumeIsolated {
            guard active else { return }
            interrupted = true; hideAnchors(); message = "카메라가 잠시 중단됐어요."
        }
    }
    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        MainActor.assumeIsolated { restartTracking() }
    }
}
