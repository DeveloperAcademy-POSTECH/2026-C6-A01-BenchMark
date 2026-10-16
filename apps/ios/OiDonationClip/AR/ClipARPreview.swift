import SwiftUI
import ARKit
import RealityKit
import Observation

@MainActor @Observable
final class ClipCameraController: NSObject {
    private(set) var message = "평평한 바닥을 비춘 뒤 캐릭터를 놓을 곳을 터치해 주세요."
    private(set) var canCapture = false
    private(set) var capturing = false
    private weak var view: RealityKit.ARView?
    private var entity: Entity?
    private var anchor: AnchorEntity?
    private var loadTask: Task<Void, Never>?
    private var active = true
    private var ready = false
    private var gesturesInstalled = false

    func connect(_ view: RealityKit.ARView, file: URL, height: Float) {
        self.view = view
        view.session.delegateQueue = .main
        view.session.delegate = self
        run()
        loadTask = Task { [weak self] in
            do {
                let model = try await Entity(contentsOf: file)
                try Task.checkCancellation()
                guard let self, self.view === view else { return }
                let bounds = model.visualBounds(relativeTo: nil)
                guard bounds.extents.y.isFinite, bounds.extents.y > 0.0001,
                      bounds.center.x.isFinite, bounds.center.z.isFinite else { throw ClipError.invalidResponse }
                let container = ModelEntity()
                let offset = Entity()
                offset.addChild(model)
                offset.position = -SIMD3(bounds.center.x, bounds.min.y, bounds.center.z)
                container.addChild(offset)
                container.scale = SIMD3(repeating: height / bounds.extents.y)
                container.generateCollisionShapes(recursive: true)
                self.entity = container
                self.ready = true
                self.message = "평평한 바닥을 터치해 캐릭터를 배치해 주세요."
            } catch {
                guard !Task.isCancelled else { return }
                self?.message = "캐릭터를 불러오지 못했어요. 닫고 다시 시도해 주세요."
            }
        }
    }

    func place(at point: CGPoint) {
        guard active, ready, let view, let entity,
              let hit = view.raycast(from: point, allowing: .estimatedPlane, alignment: .horizontal).first else { return }
        if let anchor { view.scene.removeAnchor(anchor) }
        let next = AnchorEntity(world: hit.worldTransform)
        next.addChild(entity)
        view.scene.addAnchor(next)
        anchor = next
        if !gesturesInstalled, let model = entity as? ModelEntity {
            view.installGestures([.scale, .rotation], for: model)
            gesturesInstalled = true
        }
        canCapture = true
        message = "핀치로 크기, 두 손가락 회전으로 방향을 조절할 수 있어요."
    }

    func resetPlacement() {
        if let anchor { view?.scene.removeAnchor(anchor) }
        anchor = nil; canCapture = false
        message = "캐릭터를 놓을 바닥을 터치해 주세요."
    }

    func capture(completion: @escaping (UIImage) -> Void) {
        guard canCapture, !capturing, active, let view else { return }
        capturing = true
        view.snapshot(saveToHDR: false) { [weak self] image in
            Task { @MainActor in
                guard let self else { return }
                self.capturing = false
                guard self.active, self.view != nil, let image else {
                    self.message = "사진을 촬영하지 못했어요. 다시 시도해 주세요."
                    return
                }
                completion(image)
            }
        }
    }

    func setActive(_ active: Bool) {
        self.active = active
        if active { run() } else { view?.session.pause() }
    }
    private func run() {
        guard active, let view else { return }
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        config.isLightEstimationEnabled = true
        view.session.run(config)
    }
    func stop() {
        loadTask?.cancel(); loadTask = nil
        view?.session.pause()
        view?.session.delegate = nil
        if let anchor { view?.scene.removeAnchor(anchor) }
        anchor = nil; entity = nil; view = nil; ready = false; canCapture = false; gesturesInstalled = false
    }
}

extension ClipCameraController: @preconcurrency ARSessionDelegate {
    func session(_ session: ARSession, didFailWithError error: Error) {
        canCapture = false
        message = "AR 세션에 문제가 생겼어요. 닫은 뒤 다시 시도해 주세요."
    }
    func sessionWasInterrupted(_ session: ARSession) {
        canCapture = false
        message = "카메라가 잠시 중단됐어요."
    }
    func sessionInterruptionEnded(_ session: ARSession) {
        resetPlacement()
        if active { run() }
    }
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        switch camera.trackingState {
        case .normal:
            canCapture = anchor != nil && ready && active
        case .limited, .notAvailable:
            canCapture = false
            message = "주변을 천천히 비춰 주세요. 추적이 안정되면 촬영할 수 있어요."
        }
    }
}

struct ClipARPreview: UIViewRepresentable {
    let file: URL
    let height: Float
    let controller: ClipCameraController

    func makeUIView(context: Context) -> RealityKit.ARView {
        let view = RealityKit.ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        view.addGestureRecognizer(tap)
        controller.connect(view, file: file, height: height)
        return view
    }
    func updateUIView(_ uiView: RealityKit.ARView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(controller) }
    static func dismantleUIView(_ uiView: RealityKit.ARView, coordinator: Coordinator) { coordinator.controller.stop() }

    @MainActor final class Coordinator: NSObject {
        let controller: ClipCameraController
        init(_ controller: ClipCameraController) { self.controller = controller }
        @objc func tap(_ gesture: UITapGestureRecognizer) { controller.place(at: gesture.location(in: gesture.view)) }
    }
}
