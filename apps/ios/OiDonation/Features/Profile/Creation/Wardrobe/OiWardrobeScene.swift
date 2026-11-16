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
    private(set) var editingSlot: OiPhotoSlot?
    init(editingSlot: OiPhotoSlot? = nil) { self.editingSlot = editingSlot }
    @ObservationIgnored private var photoNodes: [OiPhotoSlot: Entity] = [:]
    @ObservationIgnored private var previewImage: CGImage?
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
    @ObservationIgnored private var cardPitch: Float = 0
    @ObservationIgnored private var capturingPortrait = false
    @ObservationIgnored private var cardPoseRevision = 0

    func install() -> RealityKit.ARView {
        let view = RealityKit.ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.environment.background = .color(.white)
        view.renderOptions.formUnion([.disableMotionBlur, .disableDepthOfField, .disableCameraGrain])
        view.environment.lighting.intensityExponent = 0
        if let canvas {
            // SwiftUI can mount the new view before dismantling the previous one.
            canvas.scene.removeAnchor(anchor)
        } else {
            camera.camera.fieldOfViewInDegrees = 36
            anchor.addChild(camera)
            for (position, power) in [(SIMD3<Float>(-3, 5, 4), Float(1200)), (SIMD3<Float>(3, 3, 2), Float(700)), (SIMD3<Float>(0, 4, -3), Float(800))] {
                let light = DirectionalLight(); light.light.intensity = power
                light.look(at: [0, 0.8, 0], from: position, relativeTo: nil)
                anchor.addChild(light)
            }
        }
        view.scene.addAnchor(anchor)
        canvas = view
        updateCamera()
        return view
    }

    func isInstalled(_ view: RealityKit.ARView) -> Bool { canvas === view }

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
                    editingSlot: editingSlot, previewTexture: previewTexture, previewImage: previewImage)
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
                if let slot = editingSlot, slot.preservesOriginalMaterial(in: look), let image = previewImage {
                    await setPhotoPreview(image)
                }
                print("OI_WARDROBE_READY \(look.modelName) body=\(look.bodySource) height=\(height ?? 0)")
            } catch is CancellationError { }
            catch {
                guard generation == token else { return }
                self.error = "옷을 불러오지 못했어요. 다시 시도해 주세요."
                print("OI_WARDROBE_ERROR \(look.modelName)")
            }
        }
    }

    func editPhotos(in slot: OiPhotoSlot?, look: OiWardrobeLook) {
        editingSlot = slot
        previewTexture = nil; previewImage = nil; previewVersion += 1
        request = nil
        update(look)
    }

    func setPhotoPreview(_ image: CGImage) async {
        guard let editingSlot else { return }
        previewImage = image
        previewVersion += 1
        guard let look = request else { return }
        let version = previewVersion
        let token = generation
        do {
            if editingSlot.preservesOriginalMaterial(in: look) {
                // Keep the latest image while the selected model is loading; update()
                // reapplies it after publishing that model, never onto the previous set.
                guard loadedName == look.modelName, model != nil else { return }
                let prepared = try await OiCostumePhotoMaterial.prepare(image, resource: editingSlot.resource(in: look))
                try Task.checkCancellation()
                guard version == previewVersion, token == generation, let model else { return }
                try OiCostumePhotoMaterial.apply(prepared, to: model)
                photoPreviewError = nil
                return
            }
            let texture = try await TextureResource(image: image, options: .init(semantic: .color))
            try Task.checkCancellation()
            guard version == previewVersion, token == generation else { return }
            previewTexture = texture; photoPreviewError = nil
            if let node = photoNodes[editingSlot] { OiWardrobeAsset.applyPhoto(texture, to: node) }
        } catch is CancellationError { }
        catch {
            guard version == previewVersion, token == generation, !Task.isCancelled else { return }
            photoPreviewError = "사진 미리보기를 만들지 못했어요. 다시 시도해 주세요."
        }
    }

    func transparentCardBackground() {
        guard let canvas else { return }
        canvas.isOpaque = false
        canvas.backgroundColor = .clear
        canvas.environment.background = .color(.clear)
    }

    func cardPortrait() async -> UIImage? {
        // Serialize captures on this scene; a cancelled angle must restore the
        // background before its replacement can start rendering.
        while capturingPortrait {
            do { try await Task.sleep(for: .milliseconds(20)) } catch { return nil }
        }
        guard let canvas, !Task.isCancelled, !loading, error == nil, model != nil else { return nil }
        capturingPortrait = true
        let token = generation
        let pose = cardPoseRevision
        let original = canvas.environment.background
        defer {
            canvas.environment.background = original
            capturingPortrait = false
        }
        do {
            // Explicit opaque backdrops avoid ARView.snapshot's device-dependent alpha.
            canvas.environment.background = .color(.black)
            try await Task.sleep(for: .milliseconds(100))
            guard let black = await snapshot(canvas) else { return nil }
            try Task.checkCancellation()
            guard generation == token, cardPoseRevision == pose, isInstalled(canvas) else { return nil }
            canvas.environment.background = .color(.white)
            try await Task.sleep(for: .milliseconds(100))
            guard let white = await snapshot(canvas) else { return nil }
            try Task.checkCancellation()
            guard generation == token, cardPoseRevision == pose, isInstalled(canvas) else { return nil }
            let result = await Task.detached(priority: .userInitiated) {
                OiPortraitMatte.image(black: black, white: white)
            }.value
            try Task.checkCancellation()
            guard generation == token, cardPoseRevision == pose, isInstalled(canvas) else { return nil }
            return result
        } catch { return nil }
    }

    private final class SnapshotRequest {
        private var continuation: CheckedContinuation<UIImage?, Never>?
        init(_ continuation: CheckedContinuation<UIImage?, Never>) { self.continuation = continuation }
        func finish(_ image: UIImage?) {
            continuation?.resume(returning: image)
            continuation = nil
        }
    }

    private func snapshot(_ view: RealityKit.ARView) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let request = SnapshotRequest(continuation)
            let timeout = Task { @MainActor in
                do { try await Task.sleep(for: .seconds(4)) } catch { return }
                request.finish(nil)
            }
            view.snapshot(saveToHDR: false) { image in
                Task { @MainActor in timeout.cancel(); request.finish(image) }
            }
        }
    }

    func cardOrientation(_ orientation: OiCardOrientation) {
        let value = orientation.normalized
        let nextYaw = Float(value.yaw), nextPitch = Float(value.pitch)
        if yaw != nextYaw || cardPitch != nextPitch { cardPoseRevision += 1 }
        yaw = nextYaw; cardPitch = nextPitch
        updateCamera()
    }

    func orbit(_ dx: Float) { yaw -= dx * 0.01; updateCamera() }
    func angle(_ angle: Float) { yaw = angle; updateCamera() }
    func zoom(_ scale: Float) { distance = min(4, max(1.85, distance / scale)); updateCamera() }
    private func updateCamera() {
        let target = SIMD3<Float>(0, 0.75, 0)
        camera.look(at: target, from: target + SIMD3(sin(yaw) * cos(cardPitch) * distance,
                                              0.07 + sin(cardPitch) * distance,
                                              cos(yaw) * cos(cardPitch) * distance), relativeTo: nil)
    }
    func uninstall(_ view: RealityKit.ARView) {
        guard isInstalled(view) else { return }
        generation += 1; task?.cancel(); task = nil
        model = nil; loadedName = nil; request = nil
        // Keep the editor's latest image so a new view can recreate its texture.
        photoNodes.removeAll(); previewTexture = nil; previewVersion += 1
        view.scene.removeAnchor(anchor)
        canvas = nil
        for child in Array(anchor.children) { child.removeFromParent() }
    }
}

struct OiWardrobeSurface: UIViewRepresentable {
    let scene: OiWardrobeScene
    let look: OiWardrobeLook
    var backgroundColor: UIColor = .white
    func makeCoordinator() -> Coordinator { Coordinator(scene: scene) }
    func makeUIView(context: Context) -> RealityKit.ARView {
        let view = scene.install()
        view.environment.background = .color(backgroundColor)
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
    func updateUIView(_ view: RealityKit.ARView, context: Context) {
        guard scene.isInstalled(view) else { return }
        scene.update(look)
    }
    static func dismantleUIView(_ view: RealityKit.ARView, coordinator: Coordinator) {
        coordinator.scene.uninstall(view)
    }

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
    private let backgroundColor: UIColor
    @State private var scene: OiWardrobeScene
    init(look: OiWardrobeLook, controls: Bool = true, scene: OiWardrobeScene? = nil, backgroundColor: UIColor = .white) {
        self.look = look; self.controls = controls; self.backgroundColor = backgroundColor
        _scene = State(initialValue: scene ?? OiWardrobeScene())
    }
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        ZStack(alignment: .leading) {
            ZStack {
                if scenePhase != .background {
                    OiWardrobeSurface(scene: scene, look: look, backgroundColor: backgroundColor)
                }
                if scene.loading { ProgressView().accessibilityLabel("옷 입는 중") }
                if let error = scene.error {
                    VStack { Text(error).font(.caption); Button("다시 시도") { scene.update(look, retry: true) } }
                        .padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }.clipped()
            if controls {
                OiWardrobeRotationHint()
                    .frame(maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.bottom, 8)
                    .accessibilityAction(named: "오른쪽으로 돌리기") { scene.orbit(-157) }
                    .accessibilityAction(named: "왼쪽으로 돌리기") { scene.orbit(157) }
            }
        }
    }
}

/// Figma `5719:9948`/`5719:9947`: drag anywhere on the cucumber to turn it a full 360° (#377).
struct OiWardrobeRotationHint: View {
    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottom) {
                Image("Oi360Arc").resizable().frame(width: 57, height: 14).offset(y: 7)
                Text("360°").font(CampusStyle.body(16)).tracking(0.32)
                    .foregroundStyle(Color(white: 106 / 255))
            }
            Text("직접 만든 오이를\n회전시켜보세요!")
                .font(CampusStyle.body(10)).tracking(0.2).lineSpacing(3)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color(white: 162 / 255))
        }
        .padding(.top, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("오이를 드래그해 360도 돌려 볼 수 있어요")
        .accessibilityIdentifier("oi.wardrobe.rotationHint")
    }
}

extension UIColor {
    convenience init(wardrobeRGB value: UInt32) {
        self.init(red: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
    }
}
