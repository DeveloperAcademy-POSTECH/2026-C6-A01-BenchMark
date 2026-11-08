import SwiftUI
import RealityKit
import ARKit
import Observation

extension OiLiveStory {
    var campusPlacement: CampusPlacement? {
        CampusPlacement.story(id: id, latitude: latitude, longitude: longitude,
                              heightMeters: heightMeters, headingDegrees: headingDegrees)
    }
}

struct CampusAuthoredPlacement: Identifiable, Equatable {
    let placement: CampusPlacement
    let title: String
    let isPending: Bool
    let wardrobe: OiWardrobeLook?
    var id: String { placement.storyID }

    init?(story: OiLiveStory, owner: UUID, localDraft: OiLocalDraft?) {
        guard story.userId == owner, story.isRegisteredOnCampus,
              let placement = story.campusPlacement else { return nil }

        // Compare the server fields without the revision, which also advances on approval.
        var snapshot = OiStoryDraft(story: story)
        snapshot.revision = localDraft?.draft.revision ?? snapshot.revision
        snapshot.heightMeters = localDraft?.draft.heightMeters
        snapshot.headingDegrees = localDraft?.draft.headingDegrees
        let wardrobe = localDraft?.draft == snapshot ? localDraft?.customization?.wardrobe : nil
        let isPending = story.status == "pending"
        guard isPending || wardrobe != nil else { return nil }
        self.placement = placement
        self.title = story.cucumberName
        self.isPending = isPending
        self.wardrobe = wardrobe
    }
}

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
    var onAuthoredPlacement: ((UUID) -> Void)?
    private(set) var data: CampusMapData?
    private(set) var placementReady = false
    private(set) var placementLoading = false
    private(set) var placementError: String?
    private(set) var editingPlacement = false
    private(set) var selectingCenterLocation = false
    private(set) var draftPoint: SIMD3<Float>?
    private(set) var centerLocationError: String?
    private(set) var centerLocationName = "포항공과대학교"
    private(set) var placementPreview: CampusPlacement?
    private(set) var previewMovementError: String?
    var onPreviewChange: ((CampusPlacement, CampusRegion?) -> Void)?
    var placementMessage = "지도에서 건물 밖의 바닥을 눌러 주세요."
    @ObservationIgnored private var oiTemplate: Entity?
    @ObservationIgnored private var oiTemplateHeight: Float = 1
    @ObservationIgnored private var previewDragPoint: CGPoint?
    @ObservationIgnored private var placementLayer = Entity()
    @ObservationIgnored private var authoredLayer = Entity()
    @ObservationIgnored private var authoredPlacements: [String: CampusAuthoredPlacement] = [:]
    @ObservationIgnored private var authoredModels: [String: Entity] = [:]
    @ObservationIgnored private var authoredPins: [(UIButton, SIMD3<Float>)] = []
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
    @ObservationIgnored private var regionClustering: CampusRegionClustering?
    @ObservationIgnored private var regionButtons: [String: CampusRegionButton] = [:]
    @ObservationIgnored private var cameraMotion: (
        fromTarget: SIMD3<Float>, toTarget: SIMD3<Float>, targetVelocity: SIMD3<Float>,
        spring: CampusMapMotion.Spring, start: CFTimeInterval
    )?
    @ObservationIgnored private var motionDisplayLink: CADisplayLink?
    @ObservationIgnored private var activeNavigation: Set<ObjectIdentifier> = []
    @ObservationIgnored private var pinchLogRadius: Float?
    @ObservationIgnored private var pinchReleaseVelocity: Float = 0
    @ObservationIgnored private var panInput: (target: SIMD3<Float>, stretch: Float)?
    @ObservationIgnored private var panReleaseVelocity = SIMD3<Float>.zero
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
        pins.forEach { canvas.addSubview($0.0) }
        authoredPins.forEach { canvas.addSubview($0.0) }
        regionButtons.values.forEach { canvas.addSubview($0) }
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
        canvas.didLayout = { [weak self] in
            self?.updateCamera()
            if self?.activeNavigation.isEmpty == true, self?.cameraMotion == nil {
                self?.settleCamera()
            }
        }
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
            rebuildAuthoredPlacements()
            updateCamera()
        } catch is CancellationError { }
        catch { self.error = "캠퍼스 지도를 불러오지 못했어요. 다시 시도해 주세요." }
    }

    func setVisible(_ active: Bool) {
        visible = active
        if !active {
            target = CampusMapMotion.clampedTarget(target)
            radius = settledRadius()
            stopNavigation()
        }
        canvas?.isHidden = !active
        guard let canvas else { return }
        if active {
            attachRenderer(to: canvas)
            updateCamera()
        }
    }

    func setMapLabelPresentation(enabled: Bool, topInset: CGFloat, bottomInset: CGFloat, controls: [CGRect] = []) {
        mapLabels.setPresentation(enabled: enabled, insets: UIEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 0), controls: controls)
        updateCamera()
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
        authoredLayer = Entity()
        root.addChild(authoredLayer)
        rebuildAuthoredPlacements()
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
        if !sharedMap, let data {
            let sites = CampusRegion.campus.compactMap { region -> CampusRegionClustering.Site? in
                guard let place = data.pois.first(where: { $0.id == region.placeID }) else { return nil }
                return .init(id: region.id, anchor: data.world(place.p))
            }
            let clustering = CampusRegionClustering(sites: sites)
            regionClustering = clustering
            for node in clustering.nodes {
                let button = CampusRegionButton()
                let region = CampusRegion.campus.first { node.siteIDs == [$0.id] }
                button.accessibilityIdentifier = region.map { "campus.region." + $0.id } ?? "campus.cluster." + node.id
                button.addAction(UIAction { [weak self] _ in
                    if let region { self?.onRegion?(region) }
                    else { self?.expandCluster(node) }
                }, for: .touchUpInside)
                button.isHidden = true
                canvas?.addSubview(button)
                regionButtons[node.id] = button
            }
            updateRegionCounts()
        }
        radius = settledRadius()
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
        updateRegionCounts()
    }

    private func updateRegionCounts() {
        for node in regionClustering?.nodes ?? [] {
            let count = node.siteIDs.reduce(0) { $0 + (regionCounts?[$1] ?? 0) }
            let title = CampusRegion.campus.first { node.siteIDs == [$0.id] }?.title
                ?? "\(node.siteIDs.count)개 구역"
            let button = regionButtons[node.id]
            button?.setCount(count)
            button?.accessibilityLabel = "\(title), 오이 \(count)개"
            if node.siteIDs.count > 1 { button?.accessibilityHint = "이 구역들을 확대해서 보기" }
        }
    }

    func focus(_ region: CampusRegion, stories: [CampusStory], placement: CampusPlacement? = nil) {
        self.region = region; self.stories = stories
        guard let data else { return }
        if let placement {
            target = data.world(latitude: placement.latitude, longitude: placement.longitude)
            radius = 23; yaw = 0; pitch = 0.75
        } else {
            guard let place = data.pois.first(where: { $0.id == region.placeID }) else { return }
            target = data.world(place.p); radius = 63; yaw = 0.1; pitch = 0.88
        }
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
        guard authoredPlacements[story.id] == nil else { return }
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

    func retainAuthoredPlacements(_ ids: Set<UUID>) {
        setAuthoredPlacements(authoredPlacements.values.filter { ids.contains($0.placement.id) })
    }

    func setAuthoredPlacements(_ placements: [CampusAuthoredPlacement]) {
        let updated = placements.reduce(into: [String: CampusAuthoredPlacement]()) { $0[$1.id] = $1 }
        guard authoredPlacements != updated else { return }
        authoredModels = authoredModels.filter { id, _ in
            updated[id] != nil && updated[id]?.wardrobe == authoredPlacements[id]?.wardrobe
        }
        authoredPlacements = updated
        if region != nil { makeStoryPins(stories) }
        rebuildAuthoredPlacements()
        updateCamera()
    }

    func loadAuthoredModels() async {
        for item in authoredPlacements.values {
            guard !Task.isCancelled else { return }
            guard let wardrobe = item.wardrobe, authoredModels[item.id] == nil else { continue }
            do {
                let model = try await OiWardrobeAsset.loadForPlacement(wardrobe)
                try Task.checkCancellation()
                guard authoredPlacements[item.id] == item else { continue }
                let bounds = model.visualBounds(relativeTo: model)
                let size = simd_max(bounds.extents, SIMD3(repeating: 0.05))
                model.components.set(CollisionComponent(shapes: [
                    .generateBox(size: size).offsetBy(translation: bounds.center)
                ]))
                authoredModels[item.id] = model
                if let data { attachAuthoredModel(item, template: model, data: data) }
            } catch is CancellationError {
                return
            } catch {
                // The location label is usable even when a local wardrobe asset cannot load.
                continue
            }
        }
    }

    private func rebuildAuthoredPlacements() {
        authoredLayer.children.removeAll()
        authoredPins.forEach { $0.0.removeFromSuperview() }
        authoredPins.removeAll()
        guard let data else { return }
        for item in authoredPlacements.values.sorted(by: { $0.id < $1.id }) {
            let placement = item.placement
            let point = data.world(latitude: placement.latitude, longitude: placement.longitude)
            if let model = authoredModels[item.id] { attachAuthoredModel(item, template: model, data: data) }

            let status = item.isPending ? "검토 대기 · 나만 보기" : "내 오이"
            var configuration = UIButton.Configuration.filled()
            configuration.title = item.title
            configuration.subtitle = status
            configuration.titleLineBreakMode = .byTruncatingTail
            configuration.cornerStyle = .medium
            configuration.baseBackgroundColor = UIColor.systemBackground.withAlphaComponent(0.92)
            configuration.baseForegroundColor = .label
            let button = UIButton(configuration: configuration)
            button.bounds.size = CGSize(width: 142, height: 50)
            button.accessibilityLabel = "\(item.title), \(status)"
            button.accessibilityIdentifier = "campus.authored.\(item.id)"
            button.addAction(UIAction { [weak self] _ in self?.onAuthoredPlacement?(placement.id) }, for: .touchUpInside)
            canvas?.addSubview(button)
            authoredPins.append((button, point + SIMD3(0, 3.1, 0)))
        }
    }

    private func attachAuthoredModel(_ item: CampusAuthoredPlacement, template: Entity, data: CampusMapData) {
        let placement = item.placement
        let entity = template.clone(recursive: true)
        entity.name = "authored:" + item.id
        entity.position = data.world(latitude: placement.latitude, longitude: placement.longitude)
        // Wardrobe assets are 1.5m tall before applying the story's saved AR height.
        entity.scale = SIMD3(repeating: CampusPlacementGeometry.mapScale(unitsPerMeter: data.unitsPerMeter, editing: false)
                            * Float(placement.heightMeters) / 1.5)
        entity.orientation = CampusOiAsset.heading(placement.headingDegrees)
        authoredLayer.addChild(entity)
    }

    func preparePlacements(wardrobe: OiWardrobeLook? = nil) async {
        guard !placementReady, !placementLoading else { return }
        placementLoading = true; placementError = nil
        defer { placementLoading = false }
        do {
            if let wardrobe { oiTemplate = try await OiWardrobeAsset.loadForPlacement(wardrobe) }
            else { oiTemplate = try await CampusOiAsset.load() }
            try Task.checkCancellation()
            oiTemplateHeight = wardrobe == nil ? 1 : 1.5
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
            positionPlacement(entity, record: record, data: data)
            placementLayer.addChild(entity)
        }
    }

    private func positionPlacement(_ entity: Entity, record: CampusPlacement, data: CampusMapData) {
        entity.position = data.world(latitude: record.latitude, longitude: record.longitude)
        let mapScale = CampusPlacementGeometry.mapScale(unitsPerMeter: data.unitsPerMeter, editing: editingPlacement)
        let heightScale = placementPreview == nil ? 1 : Float(record.heightMeters) / oiTemplateHeight
        entity.scale = SIMD3(repeating: mapScale * heightScale)
        entity.orientation = CampusOiAsset.heading(record.headingDegrees)
    }

    func beginPlacementPreview(_ placement: CampusPlacement) {
        guard let data else { return }
        stopNavigation()
        placementPreview = placement
        let point = data.world(latitude: placement.latitude, longitude: placement.longitude)
        if let region = nearestRegion(to: point) { focus(region, stories: [], placement: placement) }
        syncPlacements(records: [placement])
    }

    func commitPlacementPreview() {
        guard let placement = placementPreview, let data else { return }
        let point = data.world(latitude: placement.latitude, longitude: placement.longitude)
        onPreviewChange?(placement, nearestRegion(to: point))
    }

    private func updatePlacementPreview(_ placement: CampusPlacement, latitude: Double, longitude: Double,
                                        height: Double, heading: Double) {
        guard let data else { return }
        let changed = CampusPlacement(id: placement.id, storyID: placement.storyID,
            latitude: latitude, longitude: longitude, heightMeters: height, headingDegrees: heading)
        placementPreview = changed
        savedPlacements = [changed]
        if let entity = placementLayer.children.first {
            positionPlacement(entity, record: changed, data: data)
            updateCamera()
        }
    }

    func setSharedMap(_ enabled: Bool) {
        guard sharedMap != enabled else { return }
        sharedMap = enabled
        showOverview()
    }

    func focusPlaceForPlacement(_ id: String) {
        guard editingPlacement, let data, let place = data.pois.first(where: { $0.id == id }) else { return }
        stopNavigation()
        target = data.world(place.p); radius = 32; pitch = 1.25
        placementMessage = "\(place.name) 주변의 건물 밖 바닥을 선택해 주세요."
        updateCamera()
    }

    /// Story location picking only needs the campus mesh, not an Oi model.
    func beginCenterLocation(latitude: Double?, longitude: Double?) {
        guard ready, let data, !selectingCenterLocation else { return }
        stopNavigation()
        endPlacement()
        browsingCamera = (target, radius, yaw, pitch)
        editingPlacement = true
        selectingCenterLocation = true
        camera.camera.near = 0.01
        if let latitude, let longitude {
            target = data.world(latitude: latitude, longitude: longitude)
        } else if let start = data.initialView?.walkingStart {
            target = data.world(start)
        }
        radius = 32; pitch = 1.05
        updateCamera()
    }

    func confirmCenterLocation() -> (latitude: Double, longitude: Double, region: CampusRegion?)? {
        guard selectingCenterLocation, ready, let data else { return nil }
        // Freeze any release animation and sample the displayed pose again.
        stopNavigation()
        updateCenterLocation()
        guard let point = draftPoint, data.placementError(at: point) == nil else { return nil }
        let coordinate = data.coordinate(point)
        return (coordinate.latitude, coordinate.longitude, nearestRegion(to: point))
    }

    private func updateCenterLocation() {
        guard selectingCenterLocation, let data else { return }
        // This is the optical center of the same camera used by the map. Using
        // its pose avoids the renderer's previous-frame ray during gestures.
        guard let hit = data.surface?.intersect(origin: eye, direction: simd_normalize(target - eye)) else {
            draftPoint = nil
            centerLocationError = "지도를 움직여 캠퍼스 바닥에 핀을 맞춰 주세요."
            centerLocationName = "위치를 선택해 주세요"
            return
        }
        centerLocationError = data.placementError(at: hit)
        draftPoint = centerLocationError == nil ? hit : nil
        if let place = data.pois.min(by: {
            simd_distance_squared(data.world($0.p), hit) < simd_distance_squared(data.world($1.p), hit)
        }), simd_distance(data.world(place.p), hit) < Float(120 * data.unitsPerMeter) {
            centerLocationName = "\(place.name) 주변"
        } else {
            centerLocationName = "포항공과대학교"
        }
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
        stopNavigation()
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
        selectingCenterLocation = false; centerLocationError = nil
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
        guard !selectingCenterLocation, let point = draftPoint, let data, let oiTemplate else { return }
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

    func inspectWardrobePlacement() {
        guard editingPlacement, let point = draftPoint, let data else { return }
        target = point + SIMD3(0, Float(0.75 * data.unitsPerMeter), 0)
        yaw = .pi - Float(draftHeading * .pi / 180)
        pitch = 0.2; radius = Float(4.5 * data.unitsPerMeter)
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
        guard !selectingCenterLocation else { return }
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
                if current.name.hasPrefix("authored:"),
                   let item = authoredPlacements[String(current.name.dropFirst("authored:".count))] {
                    onAuthoredPlacement?(item.placement.id)
                    return
                }
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
        let projection = mapProjection(in: view.bounds)
        return Set(positions.compactMap { id, point in
            guard let screen = projection.point(point), view.bounds.contains(screen) else { return nil }
            return id
        })
    }

    func recenter() { if let region { focus(region, stories: stories) } else { showOverview() } }

    private func clearPins() {
        stopNavigation()
        pins.forEach { $0.0.removeFromSuperview() }
        pins.removeAll()
        positions.removeAll()
        regionButtons.values.forEach { $0.removeFromSuperview() }
        regionButtons.removeAll()
        regionClustering = nil
    }

    private func attach(_ button: UIButton, at position: SIMD3<Float>) {
        canvas?.addSubview(button)
        pins.append((button, position))
    }

    private var eye: SIMD3<Float> {
        target + SIMD3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * radius
    }

    private func mapProjection(in bounds: CGRect) -> CampusMapProjection {
        CampusMapProjection(eye: eye, yaw: yaw, pitch: pitch,
                            verticalFOV: camera.camera.fieldOfViewInDegrees, viewport: bounds)
    }

    private func updateCamera() {
        camera.look(at: target, from: eye, relativeTo: nil)
        updateCenterLocation()
        guard visible, let view = canvas?.map else { return }
        let projection = mapProjection(in: view.bounds)
        let visibleBounds = view.bounds.insetBy(dx: -100, dy: -100)
        for (button, world) in pins + authoredPins {
            guard !editingPlacement, let screen = projection.point(world), visibleBounds.contains(screen) else {
                button.isHidden = true
                continue
            }
            button.center = CGPoint(x: screen.x, y: screen.y - button.bounds.height * 0.35)
            button.isHidden = false
        }

        let panelOpacity = CampusMapProjection.panelOpacity(pitch: pitch)
        let markers = regionClustering?.markers(radius: radius, focalLength: projection.focalLength,
                                                reduceMotion: UIAccessibility.isReduceMotionEnabled,
                                                separation: projection.planeSeparation) ?? []
        var visibleButtons = (pins + authoredPins).map(\.0)
        var shownRegionIDs: Set<String> = []
        if !editingPlacement {
            for marker in markers {
                guard let button = regionButtons[marker.node.id], let screen = projection.point(marker.anchor),
                      visibleBounds.contains(screen) else { continue }
                button.place(at: screen, opacity: marker.opacity, panelOpacity: panelOpacity)
                button.isUserInteractionEnabled = marker.isInteractive
                button.isAccessibilityElement = marker.isInteractive
                button.accessibilityElementsHidden = !marker.isInteractive
                button.isHidden = false
                visibleButtons.append(button)
                shownRegionIDs.insert(marker.node.id)
            }
        }
        for (id, button) in regionButtons where !shownRegionIDs.contains(id) {
            button.isHidden = true
        }
        mapLabels.update(projection: projection, viewport: view.bounds, radius: radius, pins: visibleButtons)
    }

    private func expandCluster(_ node: CampusRegionClustering.Node) {
        guard let view = canvas?.map, let clustering = regionClustering else { return }
        let projection = mapProjection(in: view.bounds)
        let expandedRadius = clustering.expandedRadius(for: node, focalLength: projection.focalLength,
                                                       separation: projection.planeSeparation)
        let destination = max(20, min(radius, expandedRadius))
        hasMovedFromOverview = true
        animateCamera(to: node.anchor, radius: settledRadius(from: destination))
    }

    private var zoomLimits: ClosedRange<Float> {
        let minimum = editingPlacement ? Float(3 * (data?.unitsPerMeter ?? 0.12)) : 20
        return minimum...600
    }

    private func settledRadius(from radius: Float? = nil) -> Float {
        let current = radius ?? self.radius
        let clamped = min(zoomLimits.upperBound, max(zoomLimits.lowerBound, current))
        guard !editingPlacement, let view = canvas?.map, let clustering = regionClustering else { return clamped }
        let projection = mapProjection(in: view.bounds)
        return clustering.settledRadius(for: clamped, within: zoomLimits, focalLength: projection.focalLength,
                                        separation: projection.planeSeparation)
    }

    private func settleCamera() {
        let velocity = pinchReleaseVelocity
        var targetVelocity = panReleaseVelocity
        pinchReleaseVelocity = 0
        panReleaseVelocity = .zero
        guard activeNavigation.isEmpty else { return }
        let destination = settledRadius()
        let destinationTarget = CampusMapMotion.clampedTarget(target)
        guard abs(log(destination / radius)) > 0.00001 ||
                destinationTarget != target else { return }
        if destinationTarget.x == target.x { targetVelocity.x = 0 }
        if destinationTarget.z == target.z { targetVelocity.z = 0 }
        animateCamera(to: destinationTarget, radius: destination, velocity: velocity, targetVelocity: targetVelocity)
    }

    private func animateCamera(to destination: SIMD3<Float>, radius destinationRadius: Float,
                               velocity: Float = 0, targetVelocity: SIMD3<Float> = .zero) {
        stopCameraMotion()
        if UIAccessibility.isReduceMotionEnabled || !visible {
            target = destination
            radius = destinationRadius
            updateCamera()
            return
        }
        cameraMotion = (target, destination, targetVelocity,
                        CampusMapMotion.Spring(from: radius, to: destinationRadius, velocity: velocity),
                        CACurrentMediaTime())
        let link = CADisplayLink(target: self, selector: #selector(advanceCameraMotion(_:)))
        motionDisplayLink = link
        link.add(to: .main, forMode: .common)
    }

    @objc private func advanceCameraMotion(_ link: CADisplayLink) {
        guard let motion = cameraMotion else { return }
        let sample = motion.spring.sample(at: link.targetTimestamp - motion.start)
        target = motion.fromTarget + (motion.toTarget - motion.fromTarget) * sample.progress
            + motion.targetVelocity * sample.velocityFactor
        radius = sample.radius
        updateCamera()
        if sample.isComplete {
            stopCameraMotion()
            settleCamera()
        }
    }

    private func stopCameraMotion() {
        motionDisplayLink?.invalidate()
        motionDisplayLink = nil
        cameraMotion = nil
    }

    private func stopNavigation() {
        stopCameraMotion()
        activeNavigation.removeAll()
        pinchLogRadius = nil
        pinchReleaseVelocity = 0
        panInput = nil
        panReleaseVelocity = .zero
        panTouchCount = 0
        previewDragPoint = nil
    }

    private func updateNavigation(_ gesture: UIGestureRecognizer) -> Bool {
        let id = ObjectIdentifier(gesture)
        switch gesture.state {
        case .began, .changed:
            if activeNavigation.isEmpty {
                pinchReleaseVelocity = 0
                panReleaseVelocity = .zero
            }
            if activeNavigation.insert(id).inserted { stopCameraMotion() }
            return true
        case .ended, .cancelled, .failed:
            if activeNavigation.remove(id) != nil { settleCamera() }
            return false
        default:
            return false
        }
    }

    @objc private func pan(_ gesture: UIPanGestureRecognizer) {
        if let placement = placementPreview {
            panPlacementPreview(gesture, placement: placement)
            return
        }
        if gesture.state == .ended, panTouchCount == 1, let panInput {
            let velocity = gesture.velocity(in: canvas)
            let right = SIMD3<Float>(cos(yaw), 0, -sin(yaw))
            let forward = SIMD3<Float>(sin(yaw), 0, cos(yaw))
            let worldVelocity = -(right * Float(velocity.x) + forward * Float(velocity.y)) * radius * 0.0012
            panReleaseVelocity = CampusMapMotion.targetVelocity(worldVelocity, input: panInput.target,
                                                               stretch: panInput.stretch)
        }
        guard updateNavigation(gesture) else {
            panTouchCount = 0
            panInput = nil
            return
        }
        let touches = gesture.numberOfTouches
        let delta = gesture.translation(in: canvas)
        gesture.setTranslation(.zero, in: canvas)
        // Adding/lifting a finger changes the touch centroid. Rebase without moving the camera.
        guard gesture.state == .changed, touches == panTouchCount else {
            panTouchCount = touches
            let stretch = CampusMapMotion.panStretch(radius: radius, target: target)
            panInput = touches == 1 ? (CampusMapMotion.inputTarget(for: target, stretch: stretch), stretch) : nil
            panReleaseVelocity = .zero
            return
        }
        if touches == 2 {
            yaw -= Float(delta.x) * 0.006
            pitch = min(editingPlacement ? .pi / 2 - 0.01 : 1.4, max(0.35, pitch + Float(delta.y) * 0.004))
        } else if touches == 1 {
            let right = SIMD3<Float>(cos(yaw), 0, -sin(yaw))
            let forward = SIMD3<Float>(sin(yaw), 0, cos(yaw))
            guard var input = panInput else { return }
            input.target -= right * Float(delta.x) * radius * 0.0012 + forward * Float(delta.y) * radius * 0.0012
            panInput = input
            target = CampusMapMotion.resistedTarget(input.target, stretch: input.stretch)
        }
        hasMovedFromOverview = true
        updateCamera()
    }

    private func panPlacementPreview(_ gesture: UIPanGestureRecognizer, placement: CampusPlacement) {
        defer { gesture.setTranslation(.zero, in: canvas) }
        if gesture.state == .ended || gesture.state == .cancelled {
            panTouchCount = 0
            previewDragPoint = nil
            commitPlacementPreview()
            return
        }
        let touches = gesture.numberOfTouches
        guard gesture.state == .changed, touches == panTouchCount else {
            panTouchCount = touches
            previewDragPoint = nil
            return
        }
        guard let data, let view = canvas?.map else { return }
        let delta = gesture.translation(in: canvas)
        if touches == 2, view.bounds.width > 0 {
            rotatePlacementPreview(placement, by: -360 * Double(delta.x / view.bounds.width))
        } else if touches == 1 {
            let projection = mapProjection(in: view.bounds)
            let foot = data.world(latitude: placement.latitude, longitude: placement.longitude)
            guard let previous = previewDragPoint ?? projection.point(foot) else { return }
            let next = CGPoint(x: previous.x + delta.x, y: previous.y + delta.y)
            previewDragPoint = next
            guard view.bounds.contains(next), let ray = projection.ray(through: next),
                  let hit = data.surface?.intersect(origin: ray.origin, direction: ray.direction) else {
                previewMovementError = "지도에 보이는 캠퍼스 바닥으로 옮겨 주세요."
                return
            }
            previewMovementError = data.placementError(at: hit)
            guard previewMovementError == nil else { return }
            let coordinate = data.coordinate(hit)
            updatePlacementPreview(placement, latitude: coordinate.latitude, longitude: coordinate.longitude,
                                   height: placement.heightMeters, heading: placement.headingDegrees)
        }
    }

    @objc private func pinch(_ gesture: UIPinchGestureRecognizer) {
        if let placement = placementPreview {
            defer { gesture.scale = 1 }
            if gesture.state == .ended || gesture.state == .cancelled { commitPlacementPreview() }
            guard gesture.state == .changed, gesture.scale.isFinite, gesture.scale > 0 else { return }
            let range = CampusPlacement.heightRange
            let height = min(range.upperBound, max(range.lowerBound, placement.heightMeters * Double(gesture.scale)))
            updatePlacementPreview(placement, latitude: placement.latitude, longitude: placement.longitude,
                                   height: height, heading: placement.headingDegrees)
            return
        }
        guard updateNavigation(gesture) else {
            pinchLogRadius = nil
            return
        }
        let scale = Float(gesture.scale)
        guard scale.isFinite, scale > 0 else { return }
        let input = pinchLogRadius ?? CampusMapMotion.inputLogRadius(for: radius, within: zoomLimits)
        let newInput = min(log(zoomLimits.upperBound) + 12,
                           max(log(zoomLimits.lowerBound) - 12, input - log(scale)))
        pinchLogRadius = newInput
        radius = CampusMapMotion.resistedRadius(logRadius: newInput, within: zoomLimits)
        pinchReleaseVelocity = CampusMapMotion.releaseVelocity(-Float(gesture.velocity) / scale,
                                                               logRadius: newInput, within: zoomLimits)
        gesture.scale = 1
        hasMovedFromOverview = true
        updateCamera()
    }
    @objc private func rotate(_ gesture: UIRotationGestureRecognizer) {
        if let placement = placementPreview {
            defer { gesture.rotation = 0 }
            if gesture.state == .ended || gesture.state == .cancelled { commitPlacementPreview() }
            if gesture.state == .changed { rotatePlacementPreview(placement, by: -Double(gesture.rotation) * 180 / .pi) }
            return
        }
        guard updateNavigation(gesture) else { return }
        // Positive UIKit rotation is clockwise. Increasing the orbit yaw turns
        // the visible map clockwise too, so it follows the fingers on screen.
        yaw += Float(gesture.rotation)
        gesture.rotation = 0
        hasMovedFromOverview = true
        updateCamera()
    }

    private func rotatePlacementPreview(_ placement: CampusPlacement, by degrees: Double) {
        guard degrees.isFinite, degrees != 0 else { return }
        updatePlacementPreview(placement, latitude: placement.latitude, longitude: placement.longitude,
            height: placement.heightMeters, heading: CampusPlacement.wrappedHeading(placement.headingDegrees + degrees))
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
    private let diameter: CGFloat = 90
    private let panel = UIImageView(image: UIImage(named: "CampusRegionPanel"))
    private let circle = UIView()
    private let content = UIStackView()
    private let icon = UIImageView(image: UIImage(named: "OiMapCucumber"))
    private let number = UILabel()

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: diameter, height: diameter))
        circle.isUserInteractionEnabled = false
        circle.frame = bounds
        circle.backgroundColor = UIColor(red: 241/255, green: 244/255, blue: 236/255, alpha: 0.6)
        circle.layer.cornerRadius = diameter / 2
        circle.layer.shadowColor = UIColor(red: 0.28, green: 0.39, blue: 0.15, alpha: 1).cgColor
        circle.layer.shadowOpacity = 0.42
        circle.layer.shadowRadius = 7; circle.layer.shadowOffset = CGSize(width: 0, height: 3)
        circle.layer.shadowPath = UIBezierPath(ovalIn: bounds).cgPath
        addSubview(circle)

        panel.isUserInteractionEnabled = false
        panel.contentMode = .scaleToFill
        // The export includes 12 points of shadow outside the 81×90 silhouette.
        panel.frame = bounds.insetBy(dx: diameter * 0.05, dy: 0).insetBy(dx: -12, dy: -12)
        addSubview(panel)

        icon.contentMode = .scaleAspectFit
        number.font = UIFont(name: "Paperlogy-7Bold", size: 26) ?? .systemFont(ofSize: 26, weight: .bold)
        number.textColor = UIColor(red: 84 / 255, green: 105 / 255, blue: 48 / 255, alpha: 1)
        number.textAlignment = .center
        content.addArrangedSubview(icon); content.addArrangedSubview(number)
        content.axis = .vertical; content.alignment = .center; content.spacing = 4
        content.isUserInteractionEnabled = false
        addSubview(content)
        content.frame = CGRect(x: 0, y: 0, width: diameter, height: 57)
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 19),
            icon.heightAnchor.constraint(equalToConstant: 23)
        ])
    }

    func setCount(_ count: Int) {
        number.attributedText = NSAttributedString(string: String(count), attributes: [.kern: 1.04])
    }

    func place(at anchor: CGPoint, opacity: CGFloat, panelOpacity: CGFloat) {
        alpha = opacity
        panel.alpha = panelOpacity
        circle.alpha = 1 - panelOpacity
        content.center = CGPoint(x: bounds.midX, y: bounds.midY - diameter * 0.08 * panelOpacity)
        // The 3D panel stands on its anchor; the near-overhead circle is centred on it.
        center = CGPoint(x: anchor.x, y: anchor.y - diameter * 0.5 * panelOpacity)
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
