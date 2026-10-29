import SwiftUI
import RealityKit
import ARKit
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
    @ObservationIgnored private var placementLayer = Entity()
    @ObservationIgnored private var draftEntity: Entity?
    @ObservationIgnored private var placementReticle: Entity?
    private var draftHeight = 1.0
    private var draftHeading = 0.0
    private var browsingCamera: (target: SIMD3<Float>, radius: Float, yaw: Float, pitch: Float)?
    @ObservationIgnored private var savedPlacements: [CampusPlacement] = []
    @ObservationIgnored private var editingPlacementID: UUID?
    @ObservationIgnored private var canvas: CampusMapCanvas?
    @ObservationIgnored private var root = AnchorEntity(world: .zero)
    @ObservationIgnored private var camera = PerspectiveCamera()
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
    private var regionCounts: [String: Int]?
    private var visible = true
    private static var cachedMesh: Entity?

    func makeView() -> CampusMapCanvas {
        if let canvas { return canvas }
        let canvas = CampusMapCanvas()
        self.canvas = canvas
        canvas.isHidden = !visible
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
            // Loading may finish while AR has suspended the map. Keep the template
            // detached until a renderer is available instead of reviving the old scene.
            if canvas?.map != nil { root.addChild(map) }
            self.data = data; ready = true
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
        panTouchCount = 0
    }

    private func attachRenderer(to canvas: CampusMapCanvas) {
        guard canvas.map == nil else { return }
        let view = canvas.installRenderer()
        view.environment.background = .color(UIColor(red: 0.78, green: 0.86, blue: 0.70, alpha: 1))
        view.renderOptions = [.disableMotionBlur, .disableDepthOfField, .disableCameraGrain]
        // Do not move a previously rendered camera/anchor graph into another ARView.
        // Its engine state can retain the old camera while UIKit pins keep moving.
        // Rebuild scene entities; retain only navigation values and asset templates.
        root = AnchorEntity(world: .zero)
        camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 42
        camera.camera.near = editingPlacement ? 0.01 : 0.1; camera.camera.far = 1800
        root.addChild(camera)
        let sun = DirectionalLight(); sun.light.intensity = 2200
        sun.look(at: .zero, from: SIMD3(30, 60, 40), relativeTo: nil); root.addChild(sun)
        let fill = DirectionalLight(); fill.light.intensity = 900
        fill.look(at: .zero, from: SIMD3(-30, 40, -50), relativeTo: nil); root.addChild(fill)
        if ready, let mesh = Self.cachedMesh { root.addChild(mesh.clone(recursive: true)) }
        placementLayer = Entity()
        root.addChild(placementLayer)
        syncPlacements(records: savedPlacements)
        draftEntity = nil
        placementReticle = nil
        if editingPlacement, draftPoint != nil {
            updateDraft(height: draftHeight, heading: draftHeading)
        }
        view.scene.addAnchor(root)
        updateCamera()
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
            let count = regionCounts?[region.id] ?? region.sampleCount
            button.setTitle("\(count)", for: .normal)
            button.titleLabel?.font = UIFont(name: "Paperlogy-9Black", size: 30) ?? .systemFont(ofSize: 30, weight: .black)
            button.setTitleColor(UIColor(red: 0.95, green: 0.97, blue: 0.91, alpha: 1), for: .normal)
            button.bounds.size = CGSize(width: count > 20 ? 120 : 86, height: count > 20 ? 145 : 106)
            button.accessibilityLabel = "\(region.title), 오이 \(count)개"
            button.accessibilityIdentifier = "campus.region.\(region.id)"
            button.addAction(UIAction { [weak self] _ in self?.onRegion?(region) }, for: .touchUpInside)
            attach(button, at: data.world(place.p) + SIMD3(0, 5, 0))
        }
        updateCamera()
    }

    func setRegionCounts(_ counts: [String: Int]) {
        regionCounts = counts
        if region == nil { showOverview() }
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
            let point: SIMD3<Float>
            if let latitude = story.latitude, let longitude = story.longitude {
                point = data.world(latitude: latitude, longitude: longitude)
            } else if index < selected.count {
                point = selected[index]
            } else { continue }
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
            entity.isEnabled = record.id != editingPlacementID
            entity.position = data.world(latitude: record.latitude, longitude: record.longitude)
            // Browse with readable symbols; edit with the same physical proportions as AR.
            entity.scale = SIMD3(repeating: CampusPlacementGeometry.mapScale(
                heightMeters: record.heightMeters, unitsPerMeter: data.unitsPerMeter, editing: editingPlacement))
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
        focusPlacementFromAbove()
    }

    func beginPlacement(editing placement: CampusPlacement? = nil) {
        guard placementReady else { return }
        endPlacement()
        if placement != nil, region != nil { showOverview() }
        browsingCamera = (target, radius, yaw, pitch)
        editingPlacement = true; draftPoint = nil
        draftHeight = placement?.heightMeters ?? 1; draftHeading = placement?.headingDegrees ?? 0
        editingPlacementID = placement?.id
        syncPlacements(records: savedPlacements)
        camera.camera.near = 0.01
        placementMessage = "건물 밖 바닥을 누르면 실제 축척으로 확대해요."
        if let placement, let data {
            target = data.world(latitude: placement.latitude, longitude: placement.longitude)
            setDraft(placement)
        }
        updateCamera()
    }

    func endPlacement() {
        editingPlacement = false; draftPoint = nil
        editingPlacementID = nil
        draftEntity?.removeFromParent(); draftEntity = nil
        placementReticle?.removeFromParent(); placementReticle = nil
        syncPlacements(records: savedPlacements)
        camera.camera.near = 0.1
        if let browsingCamera {
            target = browsingCamera.target; radius = browsingCamera.radius
            yaw = browsingCamera.yaw; pitch = browsingCamera.pitch
        }
        browsingCamera = nil
        updateCamera()
    }

    func updateDraft(height: Double, heading: Double) {
        draftHeight = height; draftHeading = heading
        guard let point = draftPoint, let data, let oiTemplate else { return }
        if draftEntity == nil {
            let entity = oiTemplate.clone(recursive: true)
            root.addChild(entity); draftEntity = entity
        }
        draftEntity?.position = point
        draftEntity?.scale = SIMD3(repeating: CampusPlacementGeometry.mapScale(
            heightMeters: height, unitsPerMeter: data.unitsPerMeter, editing: true))
        draftEntity?.orientation = CampusOiAsset.heading(heading)
        updatePlacementReticle(at: point)
    }

    func focusPlacementFromAbove() {
        guard editingPlacement, let point = draftPoint, let data else { return }
        target = point; yaw = 0; pitch = .pi / 2 - 0.01
        radius = Float(max(6, draftHeight * 6) * data.unitsPerMeter)
        updateCamera()
    }

    func showPlacementSurroundings() {
        guard editingPlacement, let point = draftPoint, let data else { return }
        target = point; pitch = 1.05
        radius = Float(50 * data.unitsPerMeter)
        updateCamera()
    }

    func nudgePlacement(right: Float, forward: Float, meters: Double) {
        guard editingPlacement, let point = draftPoint, let data else { return }
        do {
            let moved = try data.nudgedPlacement(from: point, right: right, forward: forward, meters: meters, yaw: yaw)
            draftPoint = moved
            let coordinate = data.coordinate(moved)
            placementMessage = String(format: "위도 %.6f · 경도 %.6f", coordinate.latitude, coordinate.longitude)
            updateDraft(height: draftHeight, heading: draftHeading)
        } catch {
            placementMessage = "그 방향으로 이동할 수 없어요. 이전 위치를 유지합니다."
        }
    }

    private func updatePlacementReticle(at point: SIMD3<Float>) {
        guard let data else { return }
        if placementReticle == nil {
            let reticle = Entity()
            // One metre cross, centred on the stored foot position. No collision shape:
            // selecting a new location must still hit the terrain rather than the marker.
            for (width, depth) in [(Float(1), Float(0.06)), (Float(0.06), Float(1))] {
                let outline = ModelEntity(mesh: .generateBox(size: [width + 0.04, 0.006, depth + 0.04]),
                    materials: [UnlitMaterial(color: .white)])
                let line = ModelEntity(mesh: .generateBox(size: [width, 0.006, depth]),
                    materials: [UnlitMaterial(color: UIColor(red: 0.05, green: 0.36, blue: 0.85, alpha: 1))])
                line.position.y = 0.006
                reticle.addChild(outline); reticle.addChild(line)
            }
            reticle.scale = SIMD3(repeating: Float(data.unitsPerMeter))
            root.addChild(reticle); placementReticle = reticle
        }
        placementReticle?.position = point + SIMD3(0, Float(0.02 * data.unitsPerMeter), 0)
        placementReticle?.isEnabled = true
    }

    @objc private func selectPlacement(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended, let view = canvas?.map, let data else { return }
        let point = gesture.location(in: view)
        if editingPlacement {
            guard let ray = view.ray(through: point),
                  let hit = data.surface?.intersect(origin: ray.origin, direction: ray.direction) else {
                draftPoint = nil; draftEntity?.isEnabled = false; placementReticle?.isEnabled = false
                placementMessage = "선택할 수 있는 캠퍼스 바닥을 다시 눌러 주세요."
                return
            }
            if let error = data.placementError(at: hit) {
                draftPoint = nil; draftEntity?.isEnabled = false; placementReticle?.isEnabled = false; placementMessage = error
            } else {
                let isFirstSelection = draftPoint == nil
                draftPoint = hit; draftEntity?.isEnabled = true
                let coordinate = data.coordinate(hit)
                placementMessage = String(format: "위도 %.6f · 경도 %.6f", coordinate.latitude, coordinate.longitude)
                updateDraft(height: draftHeight, heading: draftHeading)
                if isFirstSelection { focusPlacementFromAbove() }
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
            pitch = min(editingPlacement ? .pi / 2 - 0.01 : 1.4, max(0.35, pitch + Float(delta.y) * 0.004))
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
        let minimum = editingPlacement ? Float(3 * (data?.unitsPerMeter ?? 0.12)) : 20
        radius = min(600, max(minimum, radius / Float(gesture.scale)))
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
        map?.session.pause()
        map?.scene.anchors.removeAll()
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

#if DEBUG
/// Development-only check: inspect the rendered bitmap, not only the gesture's camera values.
@MainActor private final class CampusCheckPinch: UIPinchGestureRecognizer {
    override var state: UIGestureRecognizer.State { get { .changed } set {} }
}

extension CampusExploreScene {
    /// In-memory editor check; does not create or change a saved/shared placement.
    func checkPrecisePlacement() {
        guard ready, placementReady, let data,
              let point = data.graph.values.map({ data.world($0.p) })
                .filter({ data.placementError(at: $0) == nil })
                .min(by: { simd_distance($0, target) < simd_distance($1, target) }) else { return }
        let coordinate = data.coordinate(point)
        let example = CampusPlacement(storyID: "precision-check", latitude: coordinate.latitude, longitude: coordinate.longitude)
        beginPlacement(editing: example)
        var passed = true
        func check(_ condition: Bool, _ name: String) {
            passed = passed && condition
            print("[CampusPlacementCheck] \(name)=\(condition)")
        }
        guard let original = draftPoint else { return }
        updateDraft(height: 2, heading: 90)
        check(draftPoint == original, "resize-keeps-coordinate")
        if let draftEntity {
            check(abs(draftEntity.visualBounds(relativeTo: root).extents.y / Float(data.unitsPerMeter) - 2) < 0.001,
                  "rendered-height-is-two-metres")
        } else { check(false, "draft-created") }
        yaw = .pi / 2
        nudgePlacement(right: 1, forward: 0, meters: 0.1)
        if let moved = draftPoint {
            check(abs(simd_length(SIMD2(moved.x - original.x, moved.z - original.z)) / Float(data.unitsPerMeter) - 0.1) < 0.001,
                  "rotated-nudge-is-ten-centimetres")
            check(moved.z < original.z, "rotated-right-moves-north")
        }
        let preserved = draftPoint
        let oldReticle = placementReticle
        suspendForARCamera(); setVisible(true)
        check(draftPoint == preserved && placementReticle != nil && placementReticle !== oldReticle,
              "renderer-rebuild-restores-reticle")
        check(draftEntity?.position == draftPoint, "renderer-rebuild-keeps-foot-position")
        endPlacement()
        check(draftPoint == nil && placementReticle == nil && draftEntity == nil, "cancel-clears-preview")
        // Leave a fresh, unsaved preview open for visual inspection.
        beginPlacement(); setDraft(example)
        print("[CampusPlacementCheck] RESULT \(passed ? "PASS" : "FAIL")")
    }

    func checkRendererRestoration() async {
        guard ready, let canvas, let window = canvas.window else { return }
        let originalRadius = radius
        func waitForFrames() async { try? await Task.sleep(for: .milliseconds(900)) }
        func bitmap(_ view: RealityKit.ARView) async -> UIImage? {
            await withCheckedContinuation { continuation in
                view.snapshot(saveToHDR: false) { continuation.resume(returning: $0) }
            }
        }
        func pixels(_ image: UIImage) -> [UInt8] {
            var pixels = [UInt8](repeating: 0, count: 64 * 64 * 4)
            guard let cg = image.cgImage else { return [] }
            pixels.withUnsafeMutableBytes { bytes in
                if let context = CGContext(data: bytes.baseAddress, width: 64, height: 64, bitsPerComponent: 8,
                    bytesPerRow: 64 * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                    context.draw(cg, in: CGRect(x: 0, y: 0, width: 64, height: 64))
                }
            }
            return pixels
        }
        print("[CampusRendererCheck] START")
        var passed = true
        for cycle in 0...3 {
            if cycle > 0 {
                suspendForARCamera()
                // Exercise RealityKit's switch from a non-AR renderer to a camera session and back.
                let ranAR = await CampusRendererARInterlude.run(in: window)
                setVisible(true)
                guard ranAR else {
                    radius = originalRadius; updateCamera()
                    print("[CampusRendererCheck] SKIPPED: camera permission and ARKit device required")
                    return
                }
            }
            radius = originalRadius; updateCamera()
            await waitForFrames()
            guard let renderer = canvas.map, let before = await bitmap(renderer) else {
                print("[CampusRendererCheck] FAIL snapshot before cycle=\(cycle)"); return
            }
            let previousPosition = camera.position(relativeTo: nil)
            let gesture = CampusCheckPinch()
            gesture.scale = 0.65
            pinch(gesture)
            await waitForFrames()
            guard let after = await bitmap(renderer) else {
                print("[CampusRendererCheck] FAIL snapshot after cycle=\(cycle)"); return
            }
            let a = pixels(before), b = pixels(after)
            var difference = 0.0
            if a.count == b.count {
                for index in a.indices where index % 4 != 3 {
                    difference += Double(abs(Int(a[index]) - Int(b[index])))
                }
            }
            let delta = difference / Double(64 * 64 * 3 * 255)
            let movement = simd_distance(previousPosition, camera.position(relativeTo: nil))
            let cameraError = simd_distance(renderer.cameraTransform.translation, camera.position(relativeTo: nil))
            let ok = delta > 0.01 && movement > 1 && cameraError < 0.1
            passed = passed && ok
            print("[CampusRendererCheck] cycle=\(cycle) bitmapDelta=\(delta) cameraMove=\(movement) cameraError=\(cameraError) pass=\(ok)")
        }
        radius = originalRadius; updateCamera()
        print("[CampusRendererCheck] RESULT \(passed ? "PASS" : "FAIL")")
    }
}
#endif
