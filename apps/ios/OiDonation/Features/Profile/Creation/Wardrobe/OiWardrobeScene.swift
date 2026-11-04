import SwiftUI
import RealityKit
import Observation

/// One authored assembly per compatible combination. Body, cuffs and clothing always share an origin.
@MainActor @Observable
final class OiWardrobeScene {
    var loading = true
    var error: String?
    var height: Float?
    var photoPreviewError: String?
    let editingSlot: OiPhotoSlot?
    init(editingSlot: OiPhotoSlot? = nil) { self.editingSlot = editingSlot }
    @ObservationIgnored private var photoNodes: [OiPhotoSlot: Entity] = [:]
    @ObservationIgnored private var previewTexture: TextureResource?
    @ObservationIgnored private var previewVersion = 0
    @ObservationIgnored private var canvas: RealityKit.ARView?
    @ObservationIgnored private let anchor = AnchorEntity(world: .zero)
    @ObservationIgnored private let camera = PerspectiveCamera()
    @ObservationIgnored private var model: Entity?
    @ObservationIgnored private var loadedName: String?
    @ObservationIgnored private var request: OiWardrobeLook?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var yaw: Float = 0
    @ObservationIgnored private var distance: Float = 2.75

    func install() -> RealityKit.ARView {
        if let canvas { return canvas }
        let view = RealityKit.ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.environment.background = .color(.white)
        view.renderOptions.formUnion([.disableMotionBlur, .disableDepthOfField, .disableCameraGrain])
        view.environment.lighting.intensityExponent = 0
        camera.camera.fieldOfViewInDegrees = 36
        anchor.addChild(camera)
        for (position, power) in [(SIMD3<Float>(-3, 5, 4), Float(1200)), (SIMD3<Float>(3, 3, 2), Float(700)), (SIMD3<Float>(0, 4, -3), Float(800))] {
            let light = DirectionalLight(); light.light.intensity = power
            light.look(at: [0, 0.8, 0], from: position, relativeTo: nil)
            anchor.addChild(light)
        }
        view.scene.addAnchor(anchor)
        canvas = view
        updateCamera()
        return view
    }

    func update(_ look: OiWardrobeLook, retry: Bool = false) {
        guard retry || look != request else { return }
        request = look
        generation += 1
        let token = generation
        task?.cancel()
        loading = true; error = nil
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if generation == token { loading = false } }
            do {
                let (prepared, overlays) = try await OiWardrobeAsset.prepare(look,
                    existing: loadedName == look.modelName ? model : nil,
                    editingSlot: editingSlot, previewTexture: previewTexture)
                try Task.checkCancellation()
                guard generation == token, request == look else { return }
                // Publish only a complete assembly; pending color/photo changes cannot flash stale layers.
                for node in photoNodes.values { node.removeFromParent() }
                OiWardrobeAsset.assemble(look, root: prepared, overlays: overlays)
                if let editingSlot, let previewTexture, let node = overlays[editingSlot] {
                    OiWardrobeAsset.applyPhoto(previewTexture, to: node)
                }
                if model !== prepared { model?.removeFromParent(); anchor.addChild(prepared) }
                photoNodes = overlays
                model = prepared; loadedName = look.modelName
                height = prepared.visualBounds(relativeTo: prepared).extents.y
                print("OI_WARDROBE_READY \(look.modelName) body=\(look.bodySource) height=\(height ?? 0)")
            } catch is CancellationError { }
            catch {
                guard generation == token else { return }
                self.error = "옷을 불러오지 못했어요. 다시 시도해 주세요."
                print("OI_WARDROBE_ERROR \(look.modelName)")
            }
        }
    }

    func setPhotoPreview(_ image: CGImage) async {
        guard let editingSlot else { return }
        previewVersion += 1; let version = previewVersion
        do {
            let texture = try await TextureResource(image: image, options: .init(semantic: .color))
            try Task.checkCancellation()
            guard version == previewVersion else { return }
            previewTexture = texture; photoPreviewError = nil
            if let node = photoNodes[editingSlot] { OiWardrobeAsset.applyPhoto(texture, to: node) }
        } catch is CancellationError { }
        catch { photoPreviewError = "사진 미리보기를 만들지 못했어요. 사진을 다시 선택해 주세요." }
    }

    func orbit(_ dx: Float) { yaw -= dx * 0.01; updateCamera() }
    func angle(_ angle: Float) { yaw = angle; updateCamera() }
    func zoom(_ scale: Float) { distance = min(4, max(1.85, distance / scale)); updateCamera() }
    private func updateCamera() {
        let target = SIMD3<Float>(0, 0.75, 0)
        camera.look(at: target, from: target + SIMD3(sin(yaw) * distance, 0.07, cos(yaw) * distance), relativeTo: nil)
    }
    func release() {
        generation += 1; task?.cancel(); task = nil
        model?.removeFromParent(); model = nil; loadedName = nil; request = nil
        photoNodes.removeAll(); previewTexture = nil; previewVersion += 1
        canvas?.scene.anchors.removeAll(); canvas = nil
        for child in Array(anchor.children) { child.removeFromParent() }
    }
}

struct OiWardrobeSurface: UIViewRepresentable {
    let scene: OiWardrobeScene
    let look: OiWardrobeLook
    func makeCoordinator() -> Coordinator { Coordinator(scene: scene) }
    func makeUIView(context: Context) -> RealityKit.ARView {
        let view = scene.install()
        view.accessibilityIdentifier = "oi.wardrobe.preview"
        view.accessibilityLabel = "150센티미터 오이 의상 미리보기"
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.maximumNumberOfTouches = 1; pan.delegate = context.coordinator
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinch(_:)))
        pinch.delegate = context.coordinator
        view.addGestureRecognizer(pan); view.addGestureRecognizer(pinch)
        scene.update(look)
        return view
    }
    func updateUIView(_ view: RealityKit.ARView, context: Context) { scene.update(look) }
    static func dismantleUIView(_ view: RealityKit.ARView, coordinator: Coordinator) { view.scene.anchors.removeAll() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let scene: OiWardrobeScene
        init(scene: OiWardrobeScene) { self.scene = scene }
        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard let pan = gesture as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            // Let the surrounding scroll view handle vertical movement from the first touch.
            return abs(velocity.x) > abs(velocity.y)
        }
        func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
        @objc func pan(_ gesture: UIPanGestureRecognizer) {
            scene.orbit(Float(gesture.translation(in: gesture.view).x))
            gesture.setTranslation(.zero, in: gesture.view)
        }
        @objc func pinch(_ gesture: UIPinchGestureRecognizer) {
            scene.zoom(Float(gesture.scale)); gesture.scale = 1
        }
    }
}

struct OiWardrobePreview: View {
    let look: OiWardrobeLook
    var controls = true
    @State private var scene = OiWardrobeScene()
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                if scenePhase == .active {
                    OiWardrobeSurface(scene: scene, look: look)
                }
                if scene.loading { ProgressView().accessibilityLabel("옷 입는 중") }
                if let error = scene.error {
                    VStack { Text(error).font(.caption); Button("다시 시도") { scene.update(look, retry: true) } }
                        .padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }.clipped()
            if controls {
                HStack(spacing: 4) {
                    ForEach(Array([("정면", Float(0)), ("좌", .pi / 2), ("우", -.pi / 2), ("뒤", .pi)].enumerated()), id: \.offset) { _, item in
                        Button(item.0) { scene.angle(item.1) }.font(CampusStyle.body(12))
                            .frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("oi.wardrobe.angle.\(item.0)")
                    }
                }.tint(Color("OiDark"))
            }
        }
        .onDisappear { scene.release() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { scene.release() } }
    }
}

extension UIColor {
    convenience init(wardrobeRGB value: UInt32) {
        self.init(red: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
    }
}
