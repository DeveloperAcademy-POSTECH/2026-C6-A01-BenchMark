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
    private(set) var hasMovedFromOverview = false
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
    @ObservationIgnored private let mapLabels = CampusMapLabels()
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
        if let data { mapLabels.configure(data: data, in: canvas) }
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
            if let canvas { mapLabels.configure(data: data, in: canvas) }
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

    func setMapLabelPresentation(enabled: Bool, topInset: CGFloat, bottomInset: CGFloat, controls: [CGRect] = []) {
        mapLabels.setPresentation(enabled: enabled, insets: UIEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 0), controls: controls)
        projectPins()
    }

    func suspendForARCamera() {
        setVisible(false)
        // Release before presenting another RealityKit renderer; navigation values stay here.
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
        region = nil; hasMovedFromOverview = false; clearPins()
        target = SIMD3(32, 2, 1); radius = 305; yaw = 0; pitch = 1.02
        guard let data else { updateCamera(); return }
        guard !sharedMap else { updateCamera(); return }
        for region in CampusRegion.campus {
            guard let place = data.pois.first(where: { $0.id == region.placeID }) else { continue }
            let count = regionCounts?[region.id] ?? 0
            let button = CampusRegionButton(count: count, diameter: count > 20 ? 146 : count >= 10 ? 118 : 90)
            button.accessibilityLabel = "\(region.title), 오이 \(count)개"
            button.accessibilityIdentifier = "campus.region.\(region.id)"
            button.addAction(UIAction { [weak self] _ in self?.onRegion?(region) }, for: .touchUpInside)
            attach(button, at: data.world(place.p) + SIMD3(0, 5, 0))
        }
        updateCamera()
    }

    func nearestRegion() -> CampusRegion? { nearestRegion(to: target) }
    private func nearestRegion(to point: SIMD3<Float>) -> CampusRegion? {
        guard let data else { return nil }
        return CampusRegion.campus.compactMap { region -> (CampusRegion, Float)? in
            guard let place = data.pois.first(where: { $0.id == region.placeID }) else { return nil }
            return (region, simd_distance_squared(data.world(place.p), point))
        }.min { $0.1 < $1.1 }?.0
    }

    func showStoriesInCurrentArea(_ region: CampusRegion, stories: [CampusStory]) {
        self.region = region; self.stories = stories
        makeStoryPins(stories)
        updateCamera()
    }

    func setRegionCounts(_ counts: [String: Int]) {
        guard regionCounts != counts else { return }
        regionCounts = counts
        if region == nil {
            let saved = (target, radius, yaw, pitch, hasMovedFromOverview)
            showOverview()
            (target, radius, yaw, pitch, hasMovedFromOverview) = saved
            updateCamera()
        }
    }

    func focus(_ region: CampusRegion, stories: [CampusStory]) {
        self.region = region; self.stories = stories
        guard let data, let place = data.pois.first(where: { $0.id == region.placeID }) else { return }
        target = data.world(place.p); radius = 63; yaw = 0.1; pitch = 0.88
        makeStoryPins(stories)
        updateCamera()
    }

    private func makeStoryPins(_ stories: [CampusStory]) {
        clearPins()
        guard let data else { return }
        // Re-search can span multiple regions. Legacy records without coordinates
        // must still use their own region's paths, never the nearest region's center.
        for story in stories {
            if let latitude = story.latitude, let longitude = story.longitude {
                attachStory(story, at: data.world(latitude: latitude, longitude: longitude))
            }
        }
        for region in CampusRegion.campus {
            let records = stories.filter { $0.regionID == region.id && ($0.latitude == nil || $0.longitude == nil) }
            guard !records.isEmpty, let place = data.pois.first(where: { $0.id == region.placeID }) else { continue }
            let center = data.world(place.p)
            var remaining = data.graph.sorted { $0.key < $1.key }.map { data.world($0.value.p) }
                .filter { simd_distance_squared($0, center) < 15 * 15 }
            var selected: [SIMD3<Float>] = []
            while !remaining.isEmpty, selected.count < records.count {
                let next = remaining.indices.max { a, b in
                    func score(_ point: SIMD3<Float>) -> Float {
                        selected.isEmpty ? -simd_distance_squared(point, center) : selected.map { simd_distance_squared(point, $0) }.min()!
                    }
                    return score(remaining[a]) < score(remaining[b])
                }!
                selected.append(remaining.remove(at: next))
            }
            for (story, point) in zip(records, selected) { attachStory(story, at: point) }
        }
    }

    private func attachStory(_ story: CampusStory, at point: SIMD3<Float>) {
        positions[story.id] = point
        let button = UIButton(type: .custom)
        button.setImage(UIImage(named: story.portraitImage), for: .normal)
        button.imageView?.contentMode = .scaleAspectFit
        button.bounds.size = CGSize(width: 62, height: 76)
        button.accessibilityLabel = "\(story.title) 이야기 보기"
        button.accessibilityIdentifier = "campus.pin.\(story.id)"
        button.addAction(UIAction { [weak self] _ in self?.onStory?(story.id) }, for: .touchUpInside)
        attach(button, at: point + SIMD3(0, 2.5, 0))
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
            // Map icons use a constant 1m reference; AR keeps the saved physical height.
            entity.scale = SIMD3(repeating: CampusPlacementGeometry.mapScale(
                unitsPerMeter: data.unitsPerMeter, editing: editingPlacement))
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
        placementMessage = "건물 밖 바닥을 누르면 배치 위치를 확대해요."
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
            unitsPerMeter: data.unitsPerMeter, editing: true))
        draftEntity?.orientation = CampusOiAsset.heading(heading)
        updatePlacementReticle(at: point)
    }

    func focusPlacementFromAbove() {
        guard editingPlacement, let point = draftPoint, let data else { return }
        target = point; yaw = 0; pitch = .pi / 2 - 0.01
        radius = Float(6 * data.unitsPerMeter)
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
            (button as? CampusRegionButton)?.setPanel(pitch < 0.95)
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
        mapLabels.update(map: view, camera: camera, radius: radius, pins: pins.map(\.0))
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
        hasMovedFromOverview = true
        updateCamera()
    }
    @objc private func pinch(_ gesture: UIPinchGestureRecognizer) {
        guard gesture.state == .began || gesture.state == .changed else { return }
        let minimum = editingPlacement ? Float(3 * (data?.unitsPerMeter ?? 0.12)) : 20
        radius = min(600, max(minimum, radius / Float(gesture.scale)))
        gesture.scale = 1
        hasMovedFromOverview = true
        updateCamera()
    }
    @objc private func rotate(_ gesture: UIRotationGestureRecognizer) {
        guard gesture.state == .began || gesture.state == .changed else { return }
        // Incremental changes compose with two-finger dragging instead of overwriting its yaw.
        yaw -= Float(gesture.rotation)
        gesture.rotation = 0
        hasMovedFromOverview = true
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

@MainActor private final class CampusRegionButton: UIButton {
    private let diameter: CGFloat
    private let panel = UIImageView(image: UIImage(named: "CampusRegionPanel"))
    private let content = UIStackView()
    private let icon = UIImageView(image: UIImage(named: "OiMapCucumber"))
    private let number = UILabel()
    private lazy var iconWidth = icon.widthAnchor.constraint(equalToConstant: 19)
    private lazy var iconHeight = icon.heightAnchor.constraint(equalToConstant: 23)
    private var panelMode: Bool?
    init(count: Int, diameter: CGFloat) {
        self.diameter = diameter
        super.init(frame: CGRect(x: 0, y: 0, width: diameter, height: diameter))
        panel.isUserInteractionEnabled = false
        panel.contentMode = .scaleToFill
        addSubview(panel)
        icon.contentMode = .scaleAspectFit
        number.text = String(count)
        number.font = UIFont(name: "PearToucan-Bold", size: 26) ?? .systemFont(ofSize: 26, weight: .bold)
        number.attributedText = NSAttributedString(string: String(count), attributes: [.kern: 1.04])
        number.textColor = UIColor(red: 101 / 255, green: 126 / 255, blue: 58 / 255, alpha: 1)
        number.textAlignment = .center
        content.addArrangedSubview(icon); content.addArrangedSubview(number)
        content.axis = .vertical; content.alignment = .center; content.spacing = 4
        content.isUserInteractionEnabled = false
        addSubview(content)
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([iconWidth, iconHeight])
        isAccessibilityElement = true
        setPanel(false)
    }
    func setPanel(_ enabled: Bool) {
        guard panelMode != enabled else { return }
        panelMode = enabled
        // Figma changes the silhouette at a lower pitch, not the count's type size.
        let height = diameter
        bounds.size = CGSize(width: enabled ? height * 0.9 : diameter, height: height)
        panel.isHidden = !enabled
        // Export includes 12 points of shadow around its 81×90 silhouette.
        panel.frame = bounds.insetBy(dx: -height * 12/90, dy: -height * 12/90)
        backgroundColor = enabled ? .clear : UIColor(red: 241/255, green: 244/255, blue: 236/255, alpha: 1)
        layer.cornerRadius = enabled ? 0 : diameter / 2
        layer.shadowColor = UIColor(red: 0.28, green: 0.39, blue: 0.15, alpha: 1).cgColor
        layer.shadowOpacity = enabled ? 0 : 0.42
        layer.shadowRadius = 7; layer.shadowOffset = CGSize(width: 0, height: 3)
        layer.shadowPath = enabled ? nil : UIBezierPath(ovalIn: bounds).cgPath
        iconWidth.constant = 19
        iconHeight.constant = 23
        content.spacing = 4
        content.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 57)
        content.center = CGPoint(x: bounds.midX, y: bounds.midY - (enabled ? height * 0.08 : 0))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
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
    /// Exercise the real projection, pinch and renderer-rebuild paths without writing any data.
    func checkMapLabels() async {
        guard ready else { return }
        var passed = true
        func settle() async {
            try? await Task.sleep(for: .milliseconds(500))
            projectPins()
        }
        func check(_ condition: Bool, _ name: String) {
            passed = passed && condition
            print("[CampusMapLabelCheck] \(name)=\(condition) areas=\(mapLabels.visibleAreaCount) buildings=\(mapLabels.visibleBuildingCount)")
        }
        showOverview(); await settle()
        check(mapLabels.visibleAreaCount > 0 && mapLabels.visibleBuildingCount == 0, "overview")
        check(mapLabels.isVisible("area.rist-labs"), "rist-overview")
        let zoomIn = CampusCheckPinch(); zoomIn.scale = 4; pinch(zoomIn); await settle()
        check(mapLabels.visibleAreaCount == 0 && mapLabels.visibleBuildingCount > 0, "pinch-in")
        yaw += 0.4; pitch = 0.85; updateCamera(); await settle()
        check(mapLabels.visibleBuildingCount > 0, "rotated-roofs")
        let savedCamera = (target, radius, yaw, pitch)
        suspendForARCamera(); setVisible(true); await settle()
        check(target == savedCamera.0 && radius == savedCamera.1 && yaw == savedCamera.2 && pitch == savedCamera.3
              && mapLabels.visibleBuildingCount > 0, "renderer-return")
        let zoomOut = CampusCheckPinch(); zoomOut.scale = 0.25; pinch(zoomOut); await settle()
        check(mapLabels.visibleAreaCount > 0 && mapLabels.visibleBuildingCount == 0, "pinch-out")
        if let data, let rist = CampusBuildingLabel.groups(data).first(where: { $0.id == "rist-labs" }) {
            target = rist.anchor; radius = 85; yaw = 0; pitch = 1.1
            updateCamera(); await settle()
            let ids = data.buildingLabelGroups?.first(where: { $0.id == "rist-labs" })?.buildingIDs ?? []
            check(ids.contains { mapLabels.isVisible("building.\($0)") }, "rist-building-roofs")
        } else { check(false, "rist-group-data") }
        showOverview(); await settle()
        print("[CampusMapLabelCheck] RESULT \(passed ? "PASS" : "FAIL")")
    }

    /// Regressions: a count refresh and area search must not reset the user's camera.
    func checkMapBrowsing() {
        guard ready else { return }
        showOverview()
        let gesture = CampusCheckPinch(); gesture.scale = 1.1; pinch(gesture)
        pitch = 0.7; updateCamera()
        let saved = (target, radius, yaw, pitch)
        let counts = regionCounts ?? [:]
        var changed = counts; changed["pond", default: 0] += 1
        setRegionCounts(changed)
        var passed = target == saved.0 && radius == saved.1 && yaw == saved.2 && pitch == saved.3 && hasMovedFromOverview
        setRegionCounts(counts)
        if let nearest = nearestRegion() {
            showStoriesInCurrentArea(nearest, stories: [])
            passed = passed && target == saved.0 && radius == saved.1 && yaw == saved.2 && pitch == saved.3
        } else { passed = false }
        showOverview()
        (target, radius, yaw, pitch) = saved
        hasMovedFromOverview = true; updateCamera()
        print("[CampusMapBrowsingCheck] RESULT \(passed ? "PASS" : "FAIL")")
    }

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
            check(abs(draftEntity.visualBounds(relativeTo: root).extents.y / Float(data.unitsPerMeter) - 1) < 0.001,
                  "map-height-stays-at-one-metre")
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
