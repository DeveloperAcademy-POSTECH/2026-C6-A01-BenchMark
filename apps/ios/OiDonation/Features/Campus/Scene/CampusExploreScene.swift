import SwiftUI
import RealityKit
import Observation

/// Reuses the OiCampus mesh/height-field format. All camera work stays in RealityKit.
@MainActor @Observable
final class CampusExploreScene: NSObject, UIGestureRecognizerDelegate {
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var ready = false
    var onRegion: ((CampusRegion) -> Void)?
    var onPlacement: ((UUID) -> Void)?
    private var sharedMap = false
    var onStory: ((String) -> Void)?
    private(set) var data: CampusMapData?
    private(set) var placementReady = false
    private(set) var placementLoading = false
    private(set) var placementError: String?
    private(set) var editingPlacement = false
    private(set) var draftPoint: SIMD3<Float>?
    var placementMessage = "지도에서 건물 밖의 바닥을 눌러 주세요."
    @ObservationIgnored private var oiTemplate: Entity?
    @ObservationIgnored private let placementLayer = Entity()
    @ObservationIgnored private var draftEntity: Entity?
    @ObservationIgnored private var savedPlacements: [CampusPlacement] = []
    @ObservationIgnored private var canvas: CampusMapCanvas?
    @ObservationIgnored private let root = AnchorEntity(world: .zero)
    @ObservationIgnored private let camera = PerspectiveCamera()
    @ObservationIgnored private var pins: [(UIButton, SIMD3<Float>)] = []
    @ObservationIgnored private var positions: [String: SIMD3<Float>] = [:]
    private var target = SIMD3<Float>(25, 0, 25)
    private var radius: Float = 180
    private var yaw: Float = 0
    private var pitch: Float = 0.98
    private var panTouchCount = 0
    @ObservationIgnored private var navigationGestures: [UIGestureRecognizer] = []
    private var region: CampusRegion?
    private var stories: [CampusStory] = []
    private var visible = true
    private static var cachedMesh: Entity?

    func makeView() -> CampusMapCanvas {
        if let canvas { return canvas }
        let canvas = CampusMapCanvas()
        self.canvas = canvas
        canvas.isHidden = !visible
        root.addChild(camera)
        camera.camera.fieldOfViewInDegrees = 42
        camera.camera.near = 0.1; camera.camera.far = 1800
        let sun = DirectionalLight(); sun.light.intensity = 2200
        sun.look(at: .zero, from: SIMD3(30, 60, 40), relativeTo: nil); root.addChild(sun)
        let fill = DirectionalLight(); fill.light.intensity = 900
        fill.look(at: .zero, from: SIMD3(-30, 40, -50), relativeTo: nil); root.addChild(fill)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 2
        navigationGestures = [
            pan,
            UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:))),
            UIRotationGestureRecognizer(target: self, action: #selector(rotate(_:)))
        ]
        for gesture in navigationGestures {
            gesture.delegate = self
            // Include marker touches, cancelling the button's tap once a map gesture begins.
            gesture.cancelsTouchesInView = true
            canvas.addGestureRecognizer(gesture)
        }
        let tap = UITapGestureRecognizer(target: self, action: #selector(selectPlacement(_:)))
        tap.delegate = self
        for gesture in navigationGestures { tap.require(toFail: gesture) }
        canvas.addGestureRecognizer(tap)
        canvas.didLayout = { [weak self] in self?.updateCamera() }
        if visible { attachRenderer(to: canvas) }
        updateCamera()
        return canvas
    }

    func load() async {
        guard !ready, !isLoading else { return }
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            let data = try CampusMapData.load()
            guard let url = Bundle.main.url(forResource: "campus-mobile", withExtension: "oimesh") else { throw CocoaError(.fileNoSuchFile) }
            let map: Entity
            if let cached = Self.cachedMesh { map = cached.clone(recursive: true) }
            else {
                let loaded = try await CampusMeshLoader.load(url: url)
                try Task.checkCancellation()
                Self.cachedMesh = loaded
                map = loaded.clone(recursive: true)
            }
            root.addChild(map); self.data = data; ready = true
            if let region { focus(region, stories: stories) } else { showOverview() }
        } catch is CancellationError { }
        catch { self.error = "캠퍼스 지도를 불러오지 못했어요. 다시 시도해 주세요." }
    }

    func setVisible(_ active: Bool) {
        visible = active
        canvas?.isHidden = !active
        guard let canvas else { return }
        if active {
            attachRenderer(to: canvas)
            updateCamera()
        }
    }

    func suspendForARCamera() {
        setVisible(false)
        // Keep this renderer across story navigation. Only the AR camera needs it released.
        canvas?.map?.scene.removeAnchor(root)
        canvas?.removeRenderer()
    }

    private func attachRenderer(to canvas: CampusMapCanvas) {
        guard canvas.map == nil else { return }
        let view = canvas.installRenderer()
        view.environment.background = .color(UIColor(red: 0.78, green: 0.86, blue: 0.70, alpha: 1))
        view.renderOptions = [.disableMotionBlur, .disableDepthOfField, .disableCameraGrain]
        view.scene.addAnchor(root)
    }

    func showOverview() {
        region = nil; clearPins()
        // Fit both the northern science buildings and the eastern library into a portrait viewport.
        target = SIMD3(32, 2, 1); radius = 305; yaw = 0; pitch = 1.02
        guard let data else { updateCamera(); return }
        guard !sharedMap else { updateCamera(); return }
        for region in CampusRegion.examples {
            guard let place = data.pois.first(where: { $0.id == region.placeID }) else { continue }
            let button = UIButton(type: .custom)
            button.setBackgroundImage(UIImage(named: "OiCluster"), for: .normal)
            button.setTitle("\(region.sampleCount)", for: .normal)
            button.titleLabel?.font = UIFont(name: "Paperlogy-9Black", size: 30) ?? .systemFont(ofSize: 30, weight: .black)
            button.setTitleColor(UIColor(red: 0.95, green: 0.97, blue: 0.91, alpha: 1), for: .normal)
            button.bounds.size = CGSize(width: region.sampleCount > 20 ? 120 : 86, height: region.sampleCount > 20 ? 145 : 106)
            button.accessibilityLabel = "\(region.title), 오이 \(region.sampleCount)개"
            button.accessibilityIdentifier = "campus.region.\(region.id)"
            button.addAction(UIAction { [weak self] _ in self?.onRegion?(region) }, for: .touchUpInside)
            attach(button, at: data.world(place.p) + SIMD3(0, 5, 0))
        }
        updateCamera()
    }

    func focus(_ region: CampusRegion, stories: [CampusStory]) {
        self.region = region; self.stories = stories; clearPins()
        guard let data, let place = data.pois.first(where: { $0.id == region.placeID }) else { return }
        target = data.world(place.p); radius = 63; yaw = 0.1; pitch = 0.88
        let center = target
        // Spread fixtures across nearby walking paths instead of stacking them on adjacent nodes.
        let candidates = data.graph.sorted { $0.key < $1.key }.map { data.world($0.value.p) }
            .filter { simd_distance_squared($0, target) < 15 * 15 }
        var remaining = candidates
        var selected: [SIMD3<Float>] = []
        while !remaining.isEmpty, selected.count < stories.count {
            let next = remaining.indices.max { a, b in
                func score(_ point: SIMD3<Float>) -> Float {
                    selected.isEmpty ? -simd_distance_squared(point, center) : selected.map { simd_distance_squared(point, $0) }.min()!
                }
                return score(remaining[a]) < score(remaining[b])
            }!
            selected.append(remaining.remove(at: next))
        }
        for (index, story) in stories.enumerated() {
            guard index < selected.count else { break }
            let point = selected[index]
            positions[story.id] = point
            let button = UIButton(type: .custom)
            button.setImage(UIImage(named: story.image), for: .normal)
            button.imageView?.contentMode = .scaleAspectFit
            button.bounds.size = CGSize(width: 62, height: 76)
            button.accessibilityLabel = "\(story.title) 이야기 보기"
            button.accessibilityIdentifier = "campus.pin.\(story.id)"
            button.addAction(UIAction { [weak self] _ in self?.onStory?(story.id) }, for: .touchUpInside)
            attach(button, at: point + SIMD3(0, 2.5, 0))
        }
        updateCamera()
    }

    func focusBackdrop(_ region: CampusRegion) {
        focus(region, stories: []); radius = 38; pitch = 0.9; updateCamera()
    }

    func preparePlacements() async {
        guard !placementReady, !placementLoading else { return }
        placementLoading = true; placementError = nil
        defer { placementLoading = false }
        do {
            oiTemplate = try await CampusOiAsset.load()
            try Task.checkCancellation()
            root.addChild(placementLayer)
            placementReady = true
            syncPlacements(records: savedPlacements)
        } catch is CancellationError { }
        catch { placementError = "오이 모델을 불러오지 못했어요. 다시 시도해 주세요." }
    }

    func syncPlacements(records: [CampusPlacement]) {
        savedPlacements = records
        placementLayer.children.removeAll()
        guard let data, let oiTemplate else { return }
        for record in records {
            let entity = oiTemplate.clone(recursive: true)
            entity.name = "placement:" + record.id.uuidString
            entity.position = data.world(latitude: record.latitude, longitude: record.longitude)
            // Map symbols are enlarged for legibility; AR uses the saved size in metres.
            entity.scale = SIMD3(repeating: Float(record.heightMeters * data.unitsPerMeter * 20))
            entity.orientation = CampusOiAsset.heading(record.headingDegrees)
            placementLayer.addChild(entity)
        }
    }

    func setSharedMap(_ enabled: Bool) {
        guard sharedMap != enabled else { return }
        sharedMap = enabled
        showOverview()
    }

    func setDraft(_ placement: CampusPlacement) {
        guard let data else { return }
        let point = data.world(latitude: placement.latitude, longitude: placement.longitude)
        guard data.placementError(at: point) == nil else { return }
        draftPoint = point
        placementMessage = String(format: "위도 %.6f · 경도 %.6f", placement.latitude, placement.longitude)
        updateDraft(height: placement.heightMeters, heading: placement.headingDegrees)
    }

    func beginPlacement() {
        guard placementReady else { return }
        editingPlacement = true; draftPoint = nil
        placementMessage = "지도에서 건물 밖의 바닥을 눌러 주세요."
        projectPins()
    }

    func endPlacement() {
        editingPlacement = false; draftPoint = nil
        draftEntity?.removeFromParent(); draftEntity = nil
        projectPins()
    }

    func updateDraft(height: Double, heading: Double) {
        guard let point = draftPoint, let data, let oiTemplate else { return }
        if draftEntity == nil {
            let entity = oiTemplate.clone(recursive: true)
            root.addChild(entity); draftEntity = entity
        }
        draftEntity?.position = point
        draftEntity?.scale = SIMD3(repeating: Float(height * data.unitsPerMeter * 20))
        draftEntity?.orientation = CampusOiAsset.heading(heading)
    }

    @objc private func selectPlacement(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended, let view = canvas?.map, let data else { return }
        let point = gesture.location(in: view)
        if editingPlacement {
            guard let ray = view.ray(through: point),
                  let hit = data.surface?.intersect(origin: ray.origin, direction: ray.direction) else {
                draftPoint = nil; draftEntity?.isEnabled = false
                placementMessage = "선택할 수 있는 캠퍼스 바닥을 다시 눌러 주세요."
                return
            }
            if let error = data.placementError(at: hit) {
                draftPoint = nil; draftEntity?.isEnabled = false; placementMessage = error
            } else {
                draftPoint = hit; draftEntity?.isEnabled = true
                let coordinate = data.coordinate(hit)
                placementMessage = String(format: "위도 %.6f · 경도 %.6f", coordinate.latitude, coordinate.longitude)
            }
        } else {
            var entity = view.entity(at: point)
            while let current = entity {
                if let record = savedPlacements.first(where: { current.name == "placement:" + $0.id.uuidString }) {
                    if let onPlacement { onPlacement(record.id) } else { onStory?(record.storyID) }; return
                }
                entity = current.parent
            }
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer is UITapGestureRecognizer else { return true }
        var view = touch.view
        while let current = view {
            if current is UIControl { return false }
            view = current.superview
        }
        return true
    }

    func distances() -> [String: Float] { positions.mapValues { simd_distance($0, target) } }
    func visibleStoryIDs() -> Set<String> {
        guard let view = canvas?.map else { return [] }
        return Set(positions.compactMap { id, point in
            guard camera.convert(position: point, from: nil).z < 0,
                  let screen = view.project(point), view.bounds.contains(screen) else { return nil }
            return id
        })
    }
    func recenter() { if let region { focus(region, stories: stories) } else { showOverview() } }
    private func clearPins() { pins.forEach { $0.0.removeFromSuperview() }; pins.removeAll(); positions.removeAll() }
    private func attach(_ button: UIButton, at position: SIMD3<Float>) { canvas?.addSubview(button); pins.append((button, position)) }
    private func updateCamera() {
        let position = target + SIMD3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * radius
        camera.look(at: target, from: position, relativeTo: nil)
        projectPins()
        // RealityKit updates its projection on the next frame after the camera moves.
        DispatchQueue.main.async { [weak self] in self?.projectPins() }
    }
    private func projectPins() {
        guard visible, let view = canvas?.map else { return }
        for (button, world) in pins {
            let local = camera.convert(position: world, from: nil)
            guard local.z < 0, let screen = view.project(world), screen.x.isFinite, screen.y.isFinite else { button.isHidden = true; continue }
            button.isHidden = editingPlacement || !view.bounds.insetBy(dx: -100, dy: -100).contains(screen)
            button.center = CGPoint(x: screen.x, y: screen.y - button.bounds.height * 0.35)
        }
        if region == nil {
            // Nearby campus regions must remain separately tappable at the overview scale.
            let buttons = pins.map(\.0).filter { !$0.isHidden }
            for _ in 0..<4 {
                for i in buttons.indices {
                    for j in buttons.indices where j > i {
                        let a = buttons[i], b = buttons[j]
                        guard a.frame.insetBy(dx: -3, dy: -3).intersects(b.frame) else { continue }
                        let dx = b.center.x - a.center.x, dy = b.center.y - a.center.y
                        let gap = (a.bounds.height + b.bounds.height) / 2 + 6 - abs(dy)
                        if abs(dx) < (a.bounds.width + b.bounds.width) / 2, gap > 0 {
                            let shift = gap / 2 * (dy >= 0 ? 1 : -1)
                            a.center.y -= shift; b.center.y += shift
                        }
                    }
                }
            }
        }
    }
    @objc private func pan(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .began || gesture.state == .changed else {
            panTouchCount = 0
            return
        }
        let touches = gesture.numberOfTouches
        let delta = gesture.translation(in: canvas)
        gesture.setTranslation(.zero, in: canvas)
        // Adding/lifting a finger changes the touch centroid. Rebase without moving the camera.
        guard gesture.state == .changed, touches == panTouchCount else {
            panTouchCount = touches
            return
        }
        if touches == 2 {
            yaw -= Float(delta.x) * 0.006
            pitch = min(1.4, max(0.35, pitch + Float(delta.y) * 0.004))
        } else if touches == 1 {
            let right = SIMD3<Float>(cos(yaw), 0, -sin(yaw))
            let forward = SIMD3<Float>(sin(yaw), 0, cos(yaw))
            target -= right * Float(delta.x) * radius * 0.0012 + forward * Float(delta.y) * radius * 0.0012
            target.x = min(110, max(-120, target.x))
            target.z = min(150, max(-180, target.z))
        }
        updateCamera()
    }
    @objc private func pinch(_ gesture: UIPinchGestureRecognizer) {
        guard gesture.state == .began || gesture.state == .changed else { return }
        radius = min(600, max(20, radius / Float(gesture.scale)))
        gesture.scale = 1
        updateCamera()
    }
    @objc private func rotate(_ gesture: UIRotationGestureRecognizer) {
        guard gesture.state == .began || gesture.state == .changed else { return }
        // Incremental changes compose with two-finger dragging instead of overwriting its yaw.
        yaw -= Float(gesture.rotation)
        gesture.rotation = 0
        updateCamera()
    }
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        navigationGestures.contains { $0 === gestureRecognizer }
            && navigationGestures.contains { $0 === otherGestureRecognizer }
    }
}

final class CampusMapCanvas: UIView {
    private(set) var map: RealityKit.ARView?
    var didLayout: (() -> Void)?
    override init(frame: CGRect) { super.init(frame: frame) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func installRenderer() -> RealityKit.ARView {
        if let map { return map }
        let view = RealityKit.ARView(frame: bounds, cameraMode: .nonAR, automaticallyConfigureSession: false)
        map = view
        insertSubview(view, at: 0)
        return view
    }
    func removeRenderer() {
        map?.removeFromSuperview()
        map = nil
    }
    override func layoutSubviews() { super.layoutSubviews(); map?.frame = bounds; didLayout?() }
}

struct CampusMapSurface: UIViewRepresentable {
    let scene: CampusExploreScene
    func makeUIView(context: Context) -> CampusMapCanvas { scene.makeView() }
    func updateUIView(_ view: CampusMapCanvas, context: Context) { }
}
