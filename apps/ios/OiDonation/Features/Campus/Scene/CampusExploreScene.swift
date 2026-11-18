import SwiftUI
import RealityKit
import ARKit
import Observation
import CoreText

extension OiLiveStory {
    var campusPlacement: CampusPlacement? {
        CampusPlacement.story(id: id, latitude: latitude, longitude: longitude,
                              heightMeters: heightMeters, headingDegrees: headingDegrees)
    }
}

struct CampusAuthoredPlacement: Identifiable, Equatable {
    enum Visibility: Equatable {
        case personal, pending, published

        var title: String {
            switch self {
            case .personal: "나만 보기"
            case .pending: "검토 중 · 나만 보기"
            case .published: "공개 중 · 내 오이"
            }
        }

        init(story: OiLiveStory?) {
            switch story?.status {
            case "pending": self = .pending
            case "published": self = .published
            default: self = .personal
            }
        }
    }

    let placement: CampusPlacement
    let regionID: String
    let title: String
    let visibility: Visibility
    let wardrobe: OiWardrobeLook?
    let submittedArtwork: OiCucumberArtworkReference?
    var id: String { placement.storyID }

    init?(story: OiLiveStory, owner: UUID, localDraft: OiLocalDraft?) {
        guard story.userId == owner, story.isRegisteredOnCampus,
              let placement = story.campusPlacement else { return nil }

        // The private look belongs to the story ID, even if server normalization changes a field.
        let wardrobe = localDraft?.id == story.id ? localDraft?.customization?.wardrobe : nil
        let visibility = Visibility(story: story)
        let artwork = visibility == .published || wardrobe == nil ? story.cucumberArtwork : nil
        guard visibility == .pending || wardrobe != nil || artwork != nil else { return nil }
        self.placement = placement
        self.regionID = story.regionId
        self.title = story.cucumberName
        self.visibility = visibility
        self.wardrobe = artwork == nil ? wardrobe : nil
        self.submittedArtwork = artwork
    }

    /// Records read from the signed-in account's vault are private to the home map.
    init?(personal record: OiLocalDraft, story: OiLiveStory?) {
        guard story?.status != "published" || story?.cucumberArtwork == nil,
              let saved = record.personalPlacement,
              let placement = CampusPlacement.story(id: record.id, latitude: saved.latitude, longitude: saved.longitude,
                  heightMeters: saved.heightMeters, headingDegrees: saved.headingDegrees) else { return nil }
        self.placement = placement
        self.regionID = saved.regionID
        self.title = saved.name
        self.visibility = Visibility(story: story)
        self.wardrobe = record.customization?.wardrobe
        self.submittedArtwork = self.wardrobe == nil ? story?.cucumberArtwork : nil
    }
}

/// Reuses the OiCampus mesh/height-field format. All camera work stays in RealityKit.
@MainActor @Observable
final class CampusExploreScene: NSObject, UIGestureRecognizerDelegate {
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var ready = false
    private(set) var hasMovedFromOverview = false
    // Released maps always use apricot cream, including devices with an old palette preference.
    private(set) var appearance: CampusMapAppearance = .apricotCream
    var onEducationDistrict: (() -> Void)?
    @ObservationIgnored private var educationEntity: ModelEntity?
    @ObservationIgnored private var educationButton: UIButton?
    private var educationNear = false
    @ObservationIgnored private var educationDetailTask: Task<Void, Never>?
    private var educationCamera: (target: SIMD3<Float>, radius: Float, yaw: Float, pitch: Float)?
    var onStoryCluster: ((CampusRegion, Set<String>) -> Void)?
    var onBuilding: ((CampusBuildingTarget) -> Void)? {
        didSet {
            mapLabels.onSelectBuilding = onBuilding == nil ? nil : { [weak self] id in
                guard let self, let item = self.buildingTargets.first(where: { $0.id == id }) else { return }
                self.selectBuilding(item)
            }
            if let data, let canvas { mapLabels.configure(data: data, in: canvas) }
        }
    }
    private(set) var selectedBuilding: CampusBuildingTarget?
    @ObservationIgnored private var buildingTargets: [CampusBuildingTarget] = []
    private var buildingCamera: (target: SIMD3<Float>, radius: Float, yaw: Float, pitch: Float, moved: Bool)?
    private var buildingViewport: CGSize?
    var onPlacement: ((UUID) -> Void)?
    private var sharedMap = false
    var onStory: ((String) -> Void)?
    var onAuthoredPlacement: ((UUID) -> Void)?
    /// A tap that hits no cucumber, placement or landmark; map drags never count (#395).
    var onEmptyMapTap: (() -> Void)?
    @ObservationIgnored var loadCucumberPortrait: ((String) async throws -> UIImage)?
    @ObservationIgnored var loadCucumberModel: ((OiCucumberArtworkReference) async throws -> Entity)?
    @ObservationIgnored var loadPublicCucumberModel: ((CampusStory) async throws -> Entity)?
    @ObservationIgnored private var portraitTasks: [Task<Void, Never>] = []
    @ObservationIgnored private let portraitCache = NSCache<NSString, UIImage>()
    @ObservationIgnored private var storyModelTask: Task<Void, Never>?
    @ObservationIgnored private let storyModelCache: NSCache<NSString, Entity> = {
        let cache = NSCache<NSString, Entity>()
        cache.countLimit = 8
        return cache
    }()
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
    @ObservationIgnored private var previewTouchState = CampusPlacementGestureState()
    @ObservationIgnored private var previewRecognizer: OiTouchSequenceRecognizer?
    @ObservationIgnored private var placementLayer = Entity()
    @ObservationIgnored private var authoredLayer = Entity()
    @ObservationIgnored private var storyLayer = Entity()
    @ObservationIgnored private var authoredPlacements: [String: CampusAuthoredPlacement] = [:]
    @ObservationIgnored private var authoredModelTask: Task<Void, Never>?
    @ObservationIgnored private let authoredModels: NSCache<NSString, AuthoredModel> = {
        let cache = NSCache<NSString, AuthoredModel>(); cache.countLimit = 8
        return cache
    }()
    @ObservationIgnored private var authoredPins: [String: AuthoredPin] = [:]
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
    @ObservationIgnored private var mapSun: DirectionalLight?
    @ObservationIgnored private var shadowDistance: Float = 0
    @ObservationIgnored private var pins: [StoryPin] = []
    @ObservationIgnored private var regionClustering: CampusRegionClustering?
    @ObservationIgnored private var clusterStories: [String: CampusStory] = [:]
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
    @ObservationIgnored private var overviewStories: [CampusStory] = []
    private var visible = true
    private let stillFrameDelay: Duration?
    private static var cachedMesh: Entity?
    private static var loadingMesh: Task<Entity, Error>?
    @ObservationIgnored private var displayedMap: Entity?

    private final class AuthoredModel {
        let template: Entity
        let bounds: BoundingBox
        init(template: Entity, bounds: BoundingBox) { self.template = template; self.bounds = bounds }
    }

    private struct AuthoredPin {
        let button: CampusAuthoredPinButton
        let ground: SIMD3<Float>
        var modelCorners: [SIMD3<Float>] = []
        var entity: Entity?
    }

    private struct StoryPin {
        let story: CampusStory
        let button: CampusStoryPinButton
        let ground: SIMD3<Float>
        let mapHeight: Float
        var requestedPortrait = false
        var requestedModel = false
        var model: StoryModel?
    }

    private struct StoryModel {
        let entity: Entity
        let templateHeight: Float
        let unitCorners: [SIMD3<Float>]
    }

    init(stillFrameDelay: Duration? = nil) {
        self.stillFrameDelay = stillFrameDelay
        super.init()
    }

    func makeView() -> CampusMapCanvas {
        if let canvas { return canvas }
        let canvas = CampusMapCanvas()
        self.canvas = canvas
        regionButtons.values.forEach { canvas.addSubview($0) }
        pins.forEach { canvas.addSubview($0.button) }
        authoredPins.values.forEach { canvas.addSubview($0.button) }
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
        if placementPreview != nil { installPreviewGestures(on: canvas) }
        canvas.didLayout = { [weak self] in
            if let self, self.selectedBuilding != nil, self.buildingViewport != self.canvas?.bounds.size {
                self.fitSelectedBuilding(animated: true)
            }
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
        #if DEBUG
        let began = CACurrentMediaTime()
        #endif
        defer {
            isLoading = false
            #if DEBUG
            if ready { print("CAMPUS_READY seconds=\(CACurrentMediaTime() - began) thermal=\(ProcessInfo.processInfo.thermalState.rawValue)") }
            #endif
        }
        do {
            let data = try CampusMapData.load()
            guard let url = Bundle.main.url(forResource: "campus-mobile", withExtension: "oimesh") else { throw CocoaError(.fileNoSuchFile) }
            async let mesh = Self.sharedMesh(url: url, data: data)
            async let education = CampusEducationDistrict.prepare(.far)
            _ = try await (mesh, education)
            try Task.checkCancellation()
            // Loading may finish while AR has suspended the map. Keep the template
            // detached until a renderer is available instead of reviving the old scene.
            if canvas?.map != nil { try installMap() }
            self.data = data; ready = true
            buildingTargets = CampusBuildingTarget.catalog(data)
            try installEducationDistrict(data: data)
            if let canvas { mapLabels.configure(data: data, in: canvas) }
            if let region { focus(region, stories: stories) } else { showOverview() }
            rebuildAuthoredPlacements()
            updateCamera()
        } catch is CancellationError { }
        catch { self.error = "캠퍼스 지도를 불러오지 못했어요. 다시 시도해 주세요." }
    }

    private static func sharedMesh(url: URL, data: CampusMapData) async throws -> Entity {
        if let cachedMesh { return cachedMesh }
        if let loadingMesh { return try await loadingMesh.value }
        // Home and summary maps can overlap during navigation. Share one preparation/upload.
        let task = Task { try await CampusMeshLoader.load(url: url, mapData: data) }
        loadingMesh = task
        do {
            let mesh = try await task.value
            cachedMesh = mesh; loadingMesh = nil
            return mesh
        } catch {
            loadingMesh = nil
            throw error
        }
    }

    func setAppearance(_ appearance: CampusMapAppearance) {
        guard appearance != self.appearance else { return }
        let previous = self.appearance
        self.appearance = appearance
        do {
            if let view = canvas?.map { mapSun = try appearance.configureLighting(in: view, root: root) }
            shadowDistance = 0
            updateMapShadows()
            if canvas?.map != nil, Self.cachedMesh != nil { try installMap() }
            canvas?.setAppearance(appearance)
            updateCamera()
        } catch {
            self.appearance = previous
            if let view = canvas?.map { mapSun = try? previous.configureLighting(in: view, root: root) }
            shadowDistance = 0
            updateMapShadows()
            self.error = "지도 색상을 불러오지 못했어요. 다시 시도해 주세요."
        }
    }

    private func installMap() throws {
        guard let template = Self.cachedMesh else { return }
        let replacement = try appearance.makeMap(from: template)
        displayedMap?.removeFromParent()
        root.addChild(replacement)
        displayedMap = replacement
    }

    private func installEducationDistrict(data: CampusMapData) throws {
        educationDetailTask?.cancel()
        educationDetailTask = nil
        educationEntity?.removeFromParent()
        let entity = try CampusEducationDistrict.makeEntity(data: data)
        root.addChild(entity)
        educationEntity = entity
        educationNear = false
        if educationButton == nil {
            let button = UIButton(type: .system)
            button.accessibilityIdentifier = "campus.education-district"
            button.accessibilityLabel = "교육지구 2.0 건립 예정 부지, 사업 안내 보기"
            button.addAction(UIAction { [weak self] _ in self?.selectEducationDistrict() }, for: .touchUpInside)
            educationButton = button
        }
        if let button = educationButton {
            configureEducationButton(button)
            canvas?.addSubview(button)
        }
    }

    private func configureEducationButton(_ button: UIButton) {
        var config = UIButton.Configuration.plain()
        config.title = "교육지구 2.0"
        config.subtitle = "건립 예정"
        config.titleAlignment = .center
        config.titlePadding = 1
        config.titleLineBreakMode = .byClipping
        config.subtitleLineBreakMode = .byClipping
        config.baseForegroundColor = UIColor(red: 0.22, green: 0.34, blue: 0.40, alpha: 1)
        config.background = .clear()
        config.contentInsets = NSDirectionalEdgeInsets(top: 2, leading: 3, bottom: 2, trailing: 3)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { input in
            var output = input
            output.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
            return output
        }
        config.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { input in
            var output = input
            output.font = UIFont.systemFont(ofSize: 9.5, weight: .medium)
            return output
        }
        button.configuration = config
        // A text-only halo preserves contrast without a plate covering the campus.
        button.layer.shadowColor = UIColor.white.cgColor
        button.layer.shadowOpacity = 0.95
        button.layer.shadowRadius = 1.5
        button.layer.shadowOffset = .zero
    }

    func selectEducationDistrict() {
        guard selectedBuilding == nil, !editingPlacement, !selectingCenterLocation, let data else { return }
        if educationCamera == nil { educationCamera = (target, radius, yaw, pitch) }
        stopNavigation()
        yaw = CampusEducationDistrict.heading
        pitch = 0.65
        animateCamera(to: data.grounded(CampusEducationDistrict.center) + SIMD3(0, -2, 0), radius: 60)
        onEducationDistrict?()
    }

    func finishEducationDistrict() {
        guard let previous = educationCamera else { return }
        educationCamera = nil
        stopNavigation()
        yaw = previous.yaw; pitch = previous.pitch
        animateCamera(to: previous.target, radius: previous.radius)
    }

    func selectBuilding(_ building: CampusBuildingTarget) {
        guard onBuilding != nil, !sharedMap, !editingPlacement, !selectingCenterLocation,
              placementPreview == nil, educationCamera == nil else { return }
        if buildingCamera == nil { buildingCamera = (target, radius, yaw, pitch, hasMovedFromOverview) }
        stopNavigation()
        selectedBuilding = building
        pitch = 0.78
        onBuilding?(building)
        fitSelectedBuilding(animated: true)
    }

    private func fitSelectedBuilding(animated: Bool) {
        guard let building = selectedBuilding, let canvas else { return }
        let distance = building.cameraRadius(viewport: canvas.bounds.size, yaw: yaw, pitch: pitch)
        buildingViewport = canvas.bounds.size
        if animated { animateCamera(to: building.center, radius: distance) }
        else { stopNavigation(); target = building.center; radius = distance }
    }

    func finishBuilding() {
        guard let previous = buildingCamera else { return }
        selectedBuilding = nil; buildingCamera = nil; buildingViewport = nil
        stopNavigation()
        yaw = previous.yaw; pitch = previous.pitch; hasMovedFromOverview = previous.moved
        animateCamera(to: previous.target, radius: previous.radius)
    }

    func setVisible(_ active: Bool) {
        visible = active
        if !active {
            canvas?.cancelStillFrameCapture()
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

    func suspendRendering() {
        setVisible(false)
        educationDetailTask?.cancel()
        educationDetailTask = nil
        authoredModelTask?.cancel(); authoredModelTask = nil
        // Release the renderer and its scene while keeping navigation values and asset templates.
        guard let canvas, canvas.map != nil else { return }
        clearStoryPins()
        for id in authoredPins.keys {
            authoredPins[id]?.entity?.removeFromParent()
            authoredPins[id]?.entity = nil; authoredPins[id]?.modelCorners = []
        }
        canvas.removeRenderer()
        root = AnchorEntity(world: .zero)
        displayedMap = nil
        mapSun = nil
        educationEntity = nil
        placementLayer = Entity()
        authoredLayer = Entity()
        storyLayer = Entity()
        draftEntity = nil
        placementReticle = nil
    }

    private func attachRenderer(to canvas: CampusMapCanvas) {
        guard canvas.map == nil else { return }
        let view = canvas.installRenderer()
        canvas.setAppearance(appearance)
        view.renderOptions = [.disableMotionBlur, .disableDepthOfField, .disableCameraGrain]
        // Do not move a previously rendered camera/anchor graph into another ARView.
        // Its engine state can retain the old camera while UIKit pins keep moving.
        // Rebuild scene entities; retain only navigation values and asset templates.
        root = AnchorEntity(world: .zero)
        camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 42
        camera.camera.near = editingPlacement ? 0.01 : 0.1; camera.camera.far = 1800
        root.addChild(camera)
        shadowDistance = 0
        do { mapSun = try appearance.configureLighting(in: view, root: root) }
        catch { self.error = "지도 조명을 불러오지 못했어요. 다시 시도해 주세요." }
        if ready {
            do { try installMap() }
            catch { self.error = "지도 색상을 불러오지 못했어요. 다시 시도해 주세요." }
        }
        if let data { try? installEducationDistrict(data: data) }
        placementLayer = Entity()
        root.addChild(placementLayer)
        syncPlacements(records: savedPlacements)
        storyLayer = Entity()
        root.addChild(storyLayer)
        makeStoryPins(region == nil ? overviewStories : stories)
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

    /// `keepingCamera` returns to the overview markers without moving the map (closing a region list, #395).
    func showOverview(keepingCamera: Bool = false) {
        stopNavigation()
        region = nil; hasMovedFromOverview = keepingCamera
        clearRegionButtons()
        if !keepingCamera { target = SIMD3(32, 2, 1); radius = 305; yaw = 0; pitch = 1.02 }
        rebuildStoryClusters()
        makeStoryPins(overviewStories)
        rebuildAuthoredPlacements()
        // Keep the exact zoom when the list closes; only keep it inside the map's limits.
        radius = keepingCamera ? min(zoomLimits.upperBound, max(zoomLimits.lowerBound, radius)) : settledRadius()
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
        if self.region == nil { stopNavigation() }
        self.region = region; self.stories = stories
        clearRegionButtons()
        makeStoryPins(stories)
        rebuildAuthoredPlacements()
        updateCamera()
    }

    func setOverviewStories(_ stories: [CampusStory]) {
        guard overviewStories != stories else { return }
        overviewStories = stories
        guard region == nil else { return }
        rebuildStoryClusters()
        makeStoryPins(stories)
        updateCamera()
    }

    private func rebuildStoryClusters() {
        clearRegionButtons()
        guard !sharedMap, region == nil, let data else { return }
        let sites = overviewStories.compactMap { story -> CampusRegionClustering.Site? in
            if let latitude = story.latitude, let longitude = story.longitude,
               latitude.isFinite, longitude.isFinite, (-90...90).contains(latitude), (-180...180).contains(longitude) {
                return .init(id: story.id, anchor: data.world(latitude: latitude, longitude: longitude))
            }
            // Only coordinate-less legacy stories use their own historic region anchor.
            guard story.latitude == nil, story.longitude == nil,
                  let region = CampusRegion.campus.first(where: { $0.id == story.regionID }),
                  let place = data.pois.first(where: { $0.id == region.placeID }) else { return nil }
            return .init(id: story.id, anchor: data.world(place.p))
        }
        regionClustering = CampusRegionClustering(sites: sites)
        clusterStories = Dictionary(overviewStories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func storyClusterButton(_ node: CampusRegionClustering.Node) -> CampusRegionButton? {
        if let button = regionButtons[node.id] { return button }
        guard let data else { return nil }
        let ids = Set(node.siteIDs)
        let names = Set(ids.compactMap { clusterStories[$0]?.location })
        let title = names.count == 1 ? (names.first ?? "주변 이야기") : "주변 이야기"
        let coordinate = data.coordinate(node.anchor)
        let selection = CampusRegion(id: node.id, title: title, placeID: "",
            latitude: coordinate.latitude, longitude: coordinate.longitude)
        let button = CampusRegionButton()
        button.accessibilityIdentifier = "campus.cluster." + node.id
        button.setCount(ids.count)
        button.accessibilityLabel = "\(title), 오이 \(ids.count)개"
        button.accessibilityHint = "이 버블에 포함된 이야기 목록 보기"
        button.addAction(UIAction { [weak self] _ in self?.onStoryCluster?(selection, ids) }, for: .touchUpInside)
        button.isHidden = true
        canvas?.addSubview(button)
        regionButtons[node.id] = button
        return button
    }

    func focus(_ region: CampusRegion, stories: [CampusStory], placement: CampusPlacement? = nil, animated: Bool = false) {
        stopNavigation()
        self.region = region; self.stories = stories
        guard let data else { return }
        let destination: SIMD3<Float>
        let destinationRadius: Float
        if let placement {
            destination = data.world(latitude: placement.latitude, longitude: placement.longitude)
            destinationRadius = 23
            if !animated { yaw = 0; pitch = 0.75 }
        } else if let latitude = region.latitude, let longitude = region.longitude {
            destination = data.world(latitude: latitude, longitude: longitude)
            let span = stories.compactMap { story -> Float? in
                guard let lat = story.latitude, let lon = story.longitude else { return nil }
                let point = data.world(latitude: lat, longitude: lon)
                return simd_distance(SIMD2(point.x, point.z), SIMD2(destination.x, destination.z))
            }.max() ?? 0
            destinationRadius = min(600, max(63, span * 3))
        } else {
            guard let place = data.pois.first(where: { $0.id == region.placeID }) else { return }
            destination = data.world(place.p); destinationRadius = 63
            if !animated { yaw = 0.1; pitch = 0.88 }
        }
        if !animated { target = destination; radius = destinationRadius }
        clearRegionButtons()
        makeStoryPins(stories)
        rebuildAuthoredPlacements()
        if animated { animateCamera(to: destination, radius: destinationRadius) }
        else { updateCamera() }
    }

    private var showsStoryCharacters: Bool { region != nil || sharedMap }

    private func makeStoryPins(_ stories: [CampusStory]) {
        clearStoryPins()
        guard let data else { return }
        let mapScale = CampusPlacementGeometry.mapScale(unitsPerMeter: data.unitsPerMeter, editing: false)
        // Re-search can span multiple regions. Legacy records without coordinates
        // must still use their own region's paths, never the nearest region's center.
        for story in stories {
            if let latitude = story.latitude, let longitude = story.longitude {
                attachStory(story, at: data.world(latitude: latitude, longitude: longitude), mapScale: mapScale)
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
            for (story, point) in zip(records, selected) { attachStory(story, at: point, mapScale: mapScale) }
        }
    }

    private func attachStory(_ story: CampusStory, at point: SIMD3<Float>, mapScale: Float) {
        positions[story.id] = point
        // Overview keeps only positions and counts, without images, models or download tasks.
        guard showsStoryCharacters, authoredPlacements[story.id] == nil else { return }
        let button = CampusStoryPinButton(type: .custom)
        let placeholder = UIImage(systemName: "leaf")
        if let path = story.cucumberPortraitPath {
            button.tintColor = .systemGreen
            button.setImage(portraitCache.object(forKey: path as NSString) ?? placeholder, for: .normal)
        } else {
            let key = "asset:\(story.portraitImage)" as NSString
            let artwork = portraitCache.object(forKey: key) ?? UIImage(named: story.portraitImage)
                .flatMap { cacheStoryPortrait($0, key: key) }
            button.setImage(artwork ?? placeholder, for: .normal)
        }
        button.imageView?.contentMode = .scaleAspectFit
        button.contentHorizontalAlignment = .fill
        button.contentVerticalAlignment = .fill
        button.accessibilityLabel = "\(story.title) 이야기 보기"
        button.accessibilityIdentifier = "campus.pin.\(story.id)"
        button.addAction(UIAction { [weak self] _ in self?.onStory?(story.id) }, for: .touchUpInside)
        canvas?.addSubview(button)
        pins.append(StoryPin(story: story, button: button, ground: point, mapHeight: Float(story.heightMeters) * mapScale))
    }

    private func cacheStoryPortrait(_ source: UIImage, key: NSString) -> UIImage? {
        // Map pins are small. Trim the padding once at display resolution.
        let thumbnailSize = CGSize(width: 256, height: 256)
        let image: UIImage
        if let raster = source.cgImage, max(raster.width, raster.height) > 256 {
            image = source.preparingThumbnail(of: thumbnailSize) ?? source
        } else {
            image = source
        }
        guard let artwork = CucumberArtwork.normalized(image), let raster = artwork.cgImage else { return nil }
        portraitCache.totalCostLimit = 12 * 1024 * 1024
        portraitCache.setObject(artwork, forKey: key, cost: raster.bytesPerRow * raster.height)
        return artwork
    }

    private func loadVisiblePortrait(at index: Int) {
        let pin = pins[index]
        guard !pin.requestedPortrait, let path = pin.story.cucumberPortraitPath else { return }
        if let image = portraitCache.object(forKey: path as NSString) {
            pins[index].requestedPortrait = true
            pin.button.setImage(image, for: .normal)
        } else if let loadCucumberPortrait {
            pins[index].requestedPortrait = true
            portraitTasks.append(Task { [weak self, weak button = pin.button] in
                guard let image = try? await loadCucumberPortrait(path), !Task.isCancelled,
                      let self, let button, let artwork = self.cacheStoryPortrait(image, key: path as NSString) else { return }
                button.setImage(artwork, for: .normal)
                self.canvas?.invalidateProjection()
            })
        }
    }

    private func loadVisibleStoryModel(at index: Int) {
        let pin = pins[index]
        let story = pin.story
        let load = loadPublicCucumberModel
        guard !story.isExample, !pin.requestedModel, story.cucumberPortraitPath == nil || load != nil else { return }
        let key = (story.cucumberPortraitPath ?? "bundled-default") as NSString
        if let template = storyModelCache.object(forKey: key) {
            pins[index].requestedModel = true
            attachStoryModel(template, at: index)
            return
        }
        // Build one visible model at a time so a refreshed map doesn't decode all textures at once.
        guard storyModelTask == nil else { return }
        pins[index].requestedModel = true
        storyModelTask = Task { [weak self, weak button = pin.button] in
            let template: Entity?
            if story.cucumberPortraitPath == nil { template = try? await CampusOiAsset.load() }
            else { template = try? await load?(story) }
            guard !Task.isCancelled, let self, let button,
                  let index = self.pins.firstIndex(where: { $0.button === button }) else { return }
            self.storyModelTask = nil
            if let template {
                self.storyModelCache.setObject(template, forKey: key)
                self.attachStoryModel(template, at: index)
            }
            self.updateCamera()
        }
    }

    private func attachStoryModel(_ template: Entity, at index: Int) {
        let pin = pins[index]
        let bounds = template.visualBounds(relativeTo: template)
        let height = bounds.extents.y
        guard height.isFinite, height > 0.001 else { return }
        let entity = template.clone(recursive: true)
        entity.name = "public:" + pin.story.id
        entity.position = pin.ground
        entity.orientation = CampusOiAsset.heading(pin.story.headingDegrees)
        let corners = [bounds.min.x, bounds.max.x].flatMap { x in
            [bounds.min.y, bounds.max.y].flatMap { y in
                [bounds.min.z, bounds.max.z].map { z in
                    entity.orientation.act(SIMD3(x, y, z) / height)
                }
            }
        }
        storyLayer.addChild(entity)
        pins[index].model = StoryModel(entity: entity, templateHeight: height, unitCorners: corners)
    }

    func focusBackdrop(_ region: CampusRegion) {
        focus(region, stories: []); radius = 38; pitch = 0.9; updateCamera()
    }

    func authoredPlacement(id: UUID) -> CampusAuthoredPlacement? {
        authoredPlacements[id.uuidString]
    }

    func setAuthoredPlacements(_ placements: [CampusAuthoredPlacement]) {
        let updated = placements.reduce(into: [String: CampusAuthoredPlacement]()) { $0[$1.id] = $1 }
        guard authoredPlacements != updated else { return }
        authoredModelTask?.cancel(); authoredModelTask = nil
        for (id, previous) in authoredPlacements where updated[id] == nil || updated[id]?.wardrobe != previous.wardrobe || updated[id]?.submittedArtwork != previous.submittedArtwork {
            authoredModels.removeObject(forKey: id as NSString)
        }
        if updated.isEmpty { authoredModels.removeAllObjects() }
        authoredPlacements = updated
        makeStoryPins(region == nil ? overviewStories : stories)
        rebuildAuthoredPlacements()
        updateCamera()
    }

    private func authoredItemIsVisible(_ item: CampusAuthoredPlacement) -> Bool {
        guard showsStoryCharacters, visible, !editingPlacement, educationCamera == nil,
              let data, let canvas else { return false }
        let point = data.world(latitude: item.placement.latitude, longitude: item.placement.longitude)
        guard let screen = mapProjection(in: canvas.bounds).point(point) else { return false }
        return canvas.bounds.insetBy(dx: -100, dy: -100).contains(screen)
    }

    private func requestAuthoredModels() {
        guard showsStoryCharacters, visible, authoredModelTask == nil,
              authoredPlacements.values.contains(where: { authoredModels.object(forKey: $0.id as NSString) == nil && authoredPins[$0.id]?.entity == nil && authoredItemIsVisible($0) }) else { return }
        authoredModelTask = Task { [weak self] in
            guard let self else { return }
            await loadAuthoredModelsNow()
            if !Task.isCancelled { authoredModelTask = nil }
        }
    }

    func loadAuthoredModels() async {
        requestAuthoredModels()
        await authoredModelTask?.value
    }

    private func loadAuthoredModelsNow() async {
        var attempted: Set<String> = []
        while !Task.isCancelled, showsStoryCharacters, visible {
            // Camera gestures can reveal an earlier ID while another model is awaiting I/O.
            // Recheck visibility after each await, but do not repeatedly retry failed assets.
            guard let item = authoredPlacements.values.filter({
                !attempted.contains($0.id) && authoredModels.object(forKey: $0.id as NSString) == nil
                    && authoredPins[$0.id]?.entity == nil && authoredItemIsVisible($0)
            }).min(by: { $0.id < $1.id }) else { return }
            attempted.insert(item.id)
            do {
                let model: Entity
                if let artwork = item.submittedArtwork {
                    guard let loadCucumberModel else { continue }
                    model = try await loadCucumberModel(artwork)
                } else if let wardrobe = item.wardrobe { model = try await OiWardrobeAsset.loadForPlacement(wardrobe) }
                else { model = try await CampusOiAsset.load() }
                try Task.checkCancellation()
                guard authoredPlacements[item.id] == item, authoredItemIsVisible(item) else { continue }
                let bounds = model.visualBounds(relativeTo: model)
                let size = simd_max(bounds.extents, SIMD3(repeating: 0.05))
                model.components.set(CollisionComponent(shapes: [
                    .generateBox(size: size).offsetBy(translation: bounds.center)
                ]))
                let authoredModel = AuthoredModel(template: model, bounds: bounds)
                authoredModels.setObject(authoredModel, forKey: item.id as NSString)
                if let data {
                    attachAuthoredModel(item, model: authoredModel, data: data)
                    updateCamera()
                }
            } catch is CancellationError {
                return
            } catch {
                // The location label is usable even when a local wardrobe asset cannot load.
                continue
            }
        }
    }

    private func rebuildAuthoredPlacements() {
        authoredModelTask?.cancel(); authoredModelTask = nil
        authoredLayer.children.removeAll()
        authoredPins.values.forEach { $0.button.removeFromSuperview() }
        authoredPins.removeAll()
        guard showsStoryCharacters, let data else { return }
        for item in authoredPlacements.values.sorted(by: { $0.id < $1.id }) {
            let placement = item.placement
            let point = data.world(latitude: placement.latitude, longitude: placement.longitude)
            let button = CampusAuthoredPinButton(title: item.title, status: item.visibility.title)
            button.accessibilityIdentifier = "campus.authored.\(item.id)"
            button.addAction(UIAction { [weak self] _ in self?.onAuthoredPlacement?(placement.id) }, for: .touchUpInside)
            canvas?.addSubview(button)
            authoredPins[item.id] = AuthoredPin(button: button, ground: point)
            if authoredItemIsVisible(item), let model = authoredModels.object(forKey: item.id as NSString) {
                attachAuthoredModel(item, model: model, data: data)
            }
        }
    }

    private func attachAuthoredModel(_ item: CampusAuthoredPlacement, model: AuthoredModel, data: CampusMapData) {
        authoredPins[item.id]?.entity?.removeFromParent()
        let placement = item.placement
        let entity = model.template.clone(recursive: true)
        entity.name = "authored:" + item.id
        entity.position = data.world(latitude: placement.latitude, longitude: placement.longitude)
        let templateHeight: Float = item.wardrobe == nil && item.submittedArtwork == nil ? 1 : OiWardrobeAsset.placementHeight
        entity.scale = SIMD3(repeating: CampusPlacementGeometry.mapScale(unitsPerMeter: data.unitsPerMeter, editing: false)
                            * Float(placement.heightMeters) / templateHeight)
        entity.orientation = CampusOiAsset.heading(placement.headingDegrees)
        authoredLayer.addChild(entity)
        authoredPins[item.id]?.entity = entity

        // Cache the rotated bounds so camera gestures only reproject points.
        let bounds = model.bounds
        let transform = entity.transformMatrix(relativeTo: nil)
        authoredPins[item.id]?.modelCorners = [bounds.min.x, bounds.max.x].flatMap { x in
            [bounds.min.y, bounds.max.y].flatMap { y in
                [bounds.min.z, bounds.max.z].map { z in
                    let corner = transform * SIMD4<Float>(x, y, z, 1)
                    return SIMD3(corner.x, corner.y, corner.z)
                }
            }
        }
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
        if let canvas { installPreviewGestures(on: canvas) }
        let point = data.world(latitude: placement.latitude, longitude: placement.longitude)
        if let region = nearestRegion(to: point) { focus(region, stories: [], placement: placement) }
        syncPlacements(records: [placement])
    }

    func commitPlacementPreview() {
        guard let placement = placementPreview, let data else { return }
        let point = data.world(latitude: placement.latitude, longitude: placement.longitude)
        onPreviewChange?(placement, nearestRegion(to: point))
    }

    private func installPreviewGestures(on canvas: CampusMapCanvas) {
        guard previewRecognizer == nil else { return }
        navigationGestures.forEach { $0.isEnabled = false }
        canvas.isMultipleTouchEnabled = true
        let recognizer = OiTouchSequenceRecognizer(target: self, action: #selector(handlePreviewTouches(_:)))
        canvas.addGestureRecognizer(recognizer)
        previewRecognizer = recognizer
    }

    @objc private func handlePreviewTouches(_ recognizer: OiTouchSequenceRecognizer) {
        updatePlacementPreviewTouches(recognizer.points)
    }

    func updatePlacementPreviewTouches(_ points: [Int: CGPoint]) {
        let change = previewTouchState.update(points)
        if points.isEmpty {
            previewDragPoint = nil
            commitPlacementPreview()
            return
        }
        guard let change, let placement = placementPreview, let data, let view = canvas?.map else { return }
        switch change {
        case .move(let delta):
            movePlacementPreview(placement, by: delta, data: data, viewport: view.bounds)
        case .transform(let horizontal, let scale, let rotation):
            guard view.bounds.width > 0 else { return }
            let range = CampusPlacement.heightRange
            let height = min(range.upperBound, max(range.lowerBound, placement.heightMeters * Double(scale)))
            let degrees = -360 * Double(horizontal / view.bounds.width) - rotation * 180 / .pi
            let heading = CampusPlacement.wrappedHeading(placement.headingDegrees + degrees)
            guard height != placement.heightMeters || heading != placement.headingDegrees else { return }
            updatePlacementPreview(placement, latitude: placement.latitude, longitude: placement.longitude,
                                   height: height, heading: heading)
        }
    }

    private func movePlacementPreview(_ placement: CampusPlacement, by delta: CGPoint,
                                      data: CampusMapData, viewport: CGRect) {
        let projection = mapProjection(in: viewport)
        let foot = data.world(latitude: placement.latitude, longitude: placement.longitude)
        guard let previous = previewDragPoint ?? projection.point(foot) else { return }
        let next = CGPoint(x: previous.x + delta.x, y: previous.y + delta.y)
        previewDragPoint = next
        guard viewport.contains(next), let ray = projection.ray(through: next),
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
        guard !selectingCenterLocation, placementPreview == nil else { return }
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
            guard selectedBuilding == nil else { return }
            if hitsEducationBuilding(at: point, viewport: view.bounds) {
                selectEducationDistrict(); return
            }
            if onBuilding != nil, let id = mapLabels.building(at: point), let building = buildingTargets.first(where: { $0.id == id }) {
                selectBuilding(building); return
            }
            var entity = view.entity(at: point)
            while let current = entity {
                if current === educationEntity { selectEducationDistrict(); return }
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
            if onBuilding != nil, !sharedMap, let ray = mapProjection(in: view.bounds).ray(through: point),
               let building = CampusBuildingTarget.hit(in: buildingTargets, origin: ray.origin, direction: ray.direction) {
                selectBuilding(building); return
            }
            onEmptyMapTap?()
        }
    }

    /// Use the saved camera pose so the first tap also works while the renderer is parked.
    /// One local bounding box avoids collision meshes for hundreds of thousands of pearl triangles.
    private func hitsEducationBuilding(at point: CGPoint, viewport: CGRect) -> Bool {
        guard let building = educationEntity,
              let ray = mapProjection(in: viewport).ray(through: point) else { return false }
        let inverse = building.transformMatrix(relativeTo: nil).inverse
        let localOrigin = inverse * SIMD4<Float>(ray.origin, 1)
        let localDirection = inverse * SIMD4<Float>(ray.direction, 0)
        let bounds = building.visualBounds(recursive: false, relativeTo: building)
        var entry: Float = 0, exit = Float.greatestFiniteMagnitude
        for axis in 0..<3 {
            let origin = localOrigin[axis], direction = localDirection[axis]
            guard origin.isFinite, direction.isFinite else { return false }
            if abs(direction) < 0.000001 {
                guard origin >= bounds.min[axis], origin <= bounds.max[axis] else { return false }
            } else {
                let a = (bounds.min[axis] - origin) / direction
                let b = (bounds.max[axis] - origin) / direction
                entry = max(entry, min(a, b)); exit = min(exit, max(a, b))
                if exit < entry { return false }
            }
        }
        return exit >= entry
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if visible { canvas?.showLiveMap() }
        scheduleStillFrame()
        guard gestureRecognizer is UITapGestureRecognizer else { return true }
        var view = touch.view
        while let current = view {
            if current is UIControl { return false }
            view = current.superview
        }
        return true
    }

    func distances() -> [String: Float] { positions.mapValues { simd_distance($0, target) } }
    func visibleStoryIDs(bottomInset: CGFloat = 0) -> Set<String> {
        guard let view = canvas?.map else { return [] }
        let bounds = view.bounds
        let visible = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width,
                             height: max(0, bounds.height - bottomInset))
        let projection = mapProjection(in: bounds)
        return Set(positions.compactMap { id, point in
            guard let screen = projection.point(point), visible.contains(screen) else { return nil }
            return id
        })
    }

    func recenter() { if let region { focus(region, stories: stories) } else { showOverview() } }

    private func clearStoryPins() {
        storyModelTask?.cancel()
        storyModelTask = nil
        storyLayer.children.removeAll()
        portraitTasks.forEach { $0.cancel() }
        portraitTasks.removeAll()
        pins.forEach { $0.button.removeFromSuperview() }
        pins.removeAll()
        positions.removeAll()
    }

    private func clearRegionButtons() {
        regionButtons.values.forEach { $0.removeFromSuperview() }
        regionButtons.removeAll()
        regionClustering = nil
        clusterStories.removeAll()
    }

    private var eye: SIMD3<Float> {
        target + SIMD3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * radius
    }

    private func mapProjection(in bounds: CGRect) -> CampusMapProjection {
        CampusMapProjection(eye: eye, yaw: yaw, pitch: pitch,
                            verticalFOV: camera.camera.fieldOfViewInDegrees, viewport: bounds)
    }

    private func updateMapShadows() {
        guard appearance == .apricotCream, let mapSun else { return }
        // Keep the shadow map focused when zoomed in, without rebuilding it for
        // every tiny pinch delta. The overview still covers the whole campus.
        let distance = min(650, max(60, ceil(radius * 2.2 / 20) * 20))
        guard distance != shadowDistance else { return }
        mapSun.shadow = .init(shadowProjection: .automatic(maximumDistance: distance), depthBias: 1)
        shadowDistance = distance
    }

    private func updateCamera() {
        updateMapShadows()
        storyLayer.isEnabled = selectedBuilding == nil
        authoredLayer.isEnabled = selectedBuilding == nil
        camera.look(at: target, from: eye, relativeTo: nil)
        updateCenterLocation()
        guard visible, let canvas, let view = canvas.map else { return }
        canvas.showLiveMap()
        defer { scheduleStillFrame() }
        let projection = mapProjection(in: view.bounds)
        // Scale by the map zoom so rotating or tilting alone cannot swell the artwork.
        let pointsPerMapUnit = projection.focalLength / CGFloat(radius)
        let visibleBounds = view.bounds.insetBy(dx: -100, dy: -100)
        var storyFrames: [CGRect] = []
        for index in pins.indices {
            let pin = pins[index]
            let button = pin.button
            guard selectedBuilding == nil, !editingPlacement, educationCamera == nil, let foot = projection.point(pin.ground), visibleBounds.contains(foot) else {
                if let model = pin.model {
                    model.entity.removeFromParent()
                    pins[index].model = nil
                    pins[index].requestedModel = false
                }
                button.isHidden = true
                continue
            }
            loadVisibleStoryModel(at: index)
            let height = min(76, max(28, CGFloat(pin.mapHeight) * pointsPerMapUnit))
            if let model = pins[index].model {
                let worldHeight = Float(height / pointsPerMapUnit)
                let scale = worldHeight / model.templateHeight
                if model.entity.scale.x != scale { model.entity.scale = SIMD3(repeating: scale) }
                let frame = model.unitCorners.reduce(CGRect(origin: foot, size: .zero)) { frame, corner in
                    guard let point = projection.point(pin.ground + worldHeight * corner) else { return frame }
                    return frame.union(CGRect(origin: point, size: .zero))
                }
                button.place(modelFrame: frame)
                storyFrames.append(button.frame.insetBy(dx: -12, dy: -12))
            } else {
                loadVisiblePortrait(at: index)
                button.place(foot: foot, height: height)
            }
            button.isHidden = false
        }

        var visibleButtons: [UIView] = pins.map(\.button)
        for (id, pin) in authoredPins {
            guard selectedBuilding == nil, !editingPlacement, educationCamera == nil, let screen = projection.point(pin.ground), visibleBounds.contains(screen) else {
                pin.button.isHidden = true
                pin.entity?.removeFromParent(); authoredPins[id]?.entity = nil
                authoredPins[id]?.modelCorners = []
                continue
            }
            if pin.entity == nil, let item = authoredPlacements[id], let data,
               let model = authoredModels.object(forKey: id as NSString) {
                attachAuthoredModel(item, model: model, data: data)
            }
            let top = pin.modelCorners.lazy.compactMap(projection.point).map(\.y).min() ?? screen.y
            pin.button.center = CGPoint(x: screen.x, y: top - pin.button.bounds.height / 2 - 4)
            pin.button.isHidden = false
            visibleButtons.append(pin.button)
        }

        requestAuthoredModels()
        let panelOpacity = CampusMapProjection.panelOpacity(pitch: pitch)
        let markers = regionClustering?.markers(radius: radius, focalLength: projection.focalLength,
                                                reduceMotion: UIAccessibility.isReduceMotionEnabled,
                                                separation: projection.planeSeparation) ?? []
        storyFrames.sort { $0.minY < $1.minY }
        var shownRegionIDs: Set<String> = []
        if selectedBuilding == nil && !editingPlacement && educationCamera == nil {
            for marker in markers {
                guard let screen = projection.point(marker.anchor), visibleBounds.contains(screen),
                      let button = storyClusterButton(marker.node) else { continue }
                button.place(at: screen, opacity: marker.opacity, panelOpacity: panelOpacity)
                button.avoidStoryFrames(storyFrames, in: view.bounds)
                button.isUserInteractionEnabled = marker.isInteractive
                button.isAccessibilityElement = marker.isInteractive
                button.accessibilityElementsHidden = !marker.isInteractive
                button.isHidden = false
                visibleButtons.append(button)
                shownRegionIDs.insert(marker.node.id)
            }
        }
        for (id, button) in regionButtons where !shownRegionIDs.contains(id) {
            button.removeFromSuperview()
            regionButtons.removeValue(forKey: id)
        }
        if let entity = educationEntity, let button = educationButton {
            let screen = projection.point(entity.position + SIMD3(0, 6.8, 0))
            let near = radius < (educationNear ? 105 : 85) && screen.map(visibleBounds.contains) == true
            if near != educationNear {
                educationNear = near
                updateEducationDetail(entity, near: near)
            }
            if selectedBuilding == nil, !editingPlacement, !selectingCenterLocation, let screen, visibleBounds.contains(screen) {
                // Measure against the viewport, never the previous narrow button frame.
                button.bounds.size = button.sizeThatFits(CGSize(width: max(44, view.bounds.width - 24), height: 44))
                // Keep the invisible hit area usable even when the overview caption is small.
                button.bounds.size.width = max(44, button.bounds.width)
                button.bounds.size.height = max(44, button.bounds.height)
                button.center = CGPoint(x: min(max(screen.x, button.bounds.width / 2 + 12), view.bounds.width - button.bounds.width / 2 - 12),
                                        y: max(110, min(view.bounds.height - 100, screen.y)))
                button.isHidden = false
                canvas.bringSubviewToFront(button)
                visibleButtons.append(button)
            } else { button.isHidden = true }
        }
        mapLabels.update(projection: projection, viewport: view.bounds, radius: radius, pins: visibleButtons)
    }

    private func updateEducationDetail(_ entity: ModelEntity, near: Bool) {
        educationDetailTask?.cancel()
        let detail: CampusEducationDistrict.Detail = near ? .near : .far
        if let mesh = CampusEducationDistrict.preparedMesh(detail) {
            educationDetailTask = nil
            entity.model?.mesh = mesh
            return
        }
        educationDetailTask = Task { [weak self, weak entity] in
            let mesh = try? await CampusEducationDistrict.prepare(detail)
            guard !Task.isCancelled, let self, let entity, self.educationEntity === entity else { return }
            self.educationDetailTask = nil
            guard let mesh else { return }
            entity.model?.mesh = mesh
            self.updateCamera()
        }
    }

    private func scheduleStillFrame() {
        guard let stillFrameDelay, visible, ready, activeNavigation.isEmpty, cameraMotion == nil else { return }
        canvas?.scheduleStillFrame(after: stillFrameDelay)
    }

    private var zoomLimits: ClosedRange<Float> {
        let minimum = editingPlacement ? Float(3 * (data?.unitsPerMeter ?? 0.12)) : 20
        return minimum...600
    }

    private func settledRadius(from radius: Float? = nil) -> Float {
        let current = radius ?? self.radius
        let clamped = min(zoomLimits.upperBound, max(zoomLimits.lowerBound, current))
        guard selectedBuilding == nil, !editingPlacement, let view = canvas?.map, let clustering = regionClustering else { return clamped }
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
        if visible { canvas?.showLiveMap() }
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
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
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
            scheduleStillFrame()
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
        previewTouchState = CampusPlacementGestureState()
    }

    private func updateNavigation(_ gesture: UIGestureRecognizer) -> Bool {
        let id = ObjectIdentifier(gesture)
        switch gesture.state {
        case .began, .changed:
            canvas?.showLiveMap()
            if activeNavigation.isEmpty {
                pinchReleaseVelocity = 0
                panReleaseVelocity = .zero
            }
            if activeNavigation.insert(id).inserted { stopCameraMotion() }
            return true
        case .ended, .cancelled, .failed:
            if activeNavigation.remove(id) != nil { settleCamera() }
            scheduleStillFrame()
            return false
        default:
            return false
        }
    }

    @objc private func pan(_ gesture: UIPanGestureRecognizer) {
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

    @objc private func pinch(_ gesture: UIPinchGestureRecognizer) {
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
        guard updateNavigation(gesture) else { return }
        // Positive UIKit rotation is clockwise. Increasing the orbit yaw turns
        // the visible map clockwise too, so it follows the fingers on screen.
        yaw += Float(gesture.rotation)
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

@MainActor private final class CampusStoryPinButton: UIButton {
    private var artworkSize = CGSize.zero

    func place(foot: CGPoint, height: CGFloat) {
        imageView?.isHidden = false
        let imageSize = currentImage?.size ?? CGSize(width: 46, height: 56)
        let aspect = imageSize.width / imageSize.height
        let width = height * min(aspect, 46.0 / 56.0)
        let size = CGSize(width: width, height: width / aspect)
        if artworkSize != size {
            artworkSize = size
            setNeedsLayout()
        }
        bounds.size = CGSize(width: max(44, size.width), height: max(44, size.height))
        center = CGPoint(x: foot.x, y: foot.y - artworkSize.height / 2)
    }

    func place(modelFrame: CGRect) {
        if artworkSize != .zero {
            artworkSize = .zero
            setNeedsLayout()
        }
        imageView?.isHidden = true
        bounds.size = CGSize(width: max(44, modelFrame.width), height: max(44, modelFrame.height))
        center = CGPoint(x: modelFrame.midX, y: modelFrame.midY)
    }

    override func imageRect(forContentRect contentRect: CGRect) -> CGRect {
        CGRect(x: bounds.midX - artworkSize.width / 2, y: bounds.midY - artworkSize.height / 2,
               width: artworkSize.width, height: artworkSize.height)
    }
}

@MainActor private final class CampusAuthoredPinButton: UIButton {
    init(title: String, status: String) {
        super.init(frame: .zero)
        var style = UIButton.Configuration.plain()
        style.attributedTitle = Self.mapText(title, font: .systemFont(ofSize: 12, weight: .semibold))
        style.attributedSubtitle = Self.mapText(status, font: .systemFont(ofSize: 10, weight: .medium))
        style.titleAlignment = .center
        style.titleLineBreakMode = .byTruncatingTail
        style.subtitleLineBreakMode = .byTruncatingTail
        style.titlePadding = 0
        style.contentInsets = .init(top: 2, leading: 4, bottom: 2, trailing: 4)
        configuration = style

        let maximumWidth: CGFloat = 112
        let fitted = sizeThatFits(CGSize(width: maximumWidth, height: .greatestFiniteMagnitude))
        bounds.size = CGSize(width: min(maximumWidth, max(44, ceil(fitted.width))), height: ceil(fitted.height))
        accessibilityLabel = "\(title), \(status)"
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let verticalPadding = max(0, (44 - bounds.height) / 2)
        return bounds.insetBy(dx: 0, dy: -verticalPadding).contains(point)
    }

    private static func mapText(_ title: String, font: UIFont) -> AttributedString {
        let halo = NSShadow()
        halo.shadowColor = UIColor.white
        halo.shadowBlurRadius = 1.5
        halo.shadowOffset = .zero
        return AttributedString(NSAttributedString(string: title, attributes: [
            .font: font,
            .foregroundColor: UIColor(red: 0.19, green: 0.25, blue: 0.15, alpha: 1),
            .shadow: halo
        ]))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

@MainActor final class CampusRegionButton: UIButton {
    private let diameter: CGFloat = 90
    private let minimumContentHeight: CGFloat = 57
    private let surfaceOpacity: CGFloat = 0.6
    private let panel = UIImageView(image: UIImage(named: "CampusRegionPanel"))
    private let circle = UIView()
    private let content = UIStackView()
    private let icon = UIImageView(image: UIImage(named: "OiMapCucumber"))
    private let number = UIImageView()
    private let numberFont = UIFont(name: "YANGJIN", size: 26) ?? .systemFont(ofSize: 26, weight: .bold)
    private let numberColor = UIColor(red: 84 / 255, green: 105 / 255, blue: 48 / 255, alpha: 1)
    private var displayedCount: Int?

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: diameter, height: diameter))
        circle.isUserInteractionEnabled = false
        circle.frame = bounds
        circle.backgroundColor = UIColor(red: 241/255, green: 244/255, blue: 236/255, alpha: surfaceOpacity)
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
        number.contentMode = .center
        content.addArrangedSubview(icon); content.addArrangedSubview(number)
        content.axis = .vertical; content.alignment = .center; content.spacing = 4
        content.isUserInteractionEnabled = false
        addSubview(content)
        content.frame = CGRect(x: 0, y: 0, width: diameter, height: minimumContentHeight)
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 19),
            icon.heightAnchor.constraint(equalToConstant: 23)
        ])
    }

    func setCount(_ count: Int) {
        guard displayedCount != count else { return }
        displayedCount = count
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: String(count), attributes: [
            .font: numberFont,
            .kern: 1.04,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): numberColor.cgColor
        ]))
        // Yangjin's digit outlines extend below its declared descent.
        let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let size = CGSize(width: ceil(ink.width) + 2, height: ceil(ink.height) + 2)
        number.image = UIGraphicsImageRenderer(size: size).image { renderer in
            let context = renderer.cgContext
            context.translateBy(x: size.width / 2 - ink.midX, y: size.height / 2 + ink.midY)
            context.scaleBy(x: 1, y: -1)
            context.textMatrix = .identity
            context.textPosition = .zero
            CTLineDraw(line, context)
        }
        let fittingHeight = content.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).height
        content.bounds.size.height = max(minimumContentHeight, ceil(fittingHeight))
    }

    func place(at anchor: CGPoint, opacity: CGFloat, panelOpacity: CGFloat) {
        alpha = opacity
        // Match the circle's translucency without fading the icon or count.
        panel.alpha = panelOpacity * surfaceOpacity
        circle.alpha = 1 - panelOpacity
        content.center = CGPoint(x: bounds.midX, y: bounds.midY - diameter * 0.08 * panelOpacity)
        // The 3D panel stands on its anchor; the near-overhead circle is centred on it.
        center = CGPoint(x: anchor.x, y: anchor.y - diameter * 0.5 * panelOpacity)
    }

    func avoidStoryFrames(_ stories: [CGRect], in viewport: CGRect) {
        var above = frame
        for story in stories.reversed() where above.intersects(story) {
            above.origin.y = story.minY - above.height
        }
        guard above != frame else { return }
        if above.minY >= viewport.minY {
            center.y = above.midY
            return
        }
        var below = frame
        for story in stories where below.intersects(story) {
            below.origin.y = story.maxY
        }
        center.y = below.maxY <= viewport.maxY ? below.midY : above.midY
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

final class CampusMapCanvas: UIView {
    private(set) var map: RealityKit.ARView?
    let backdrop = CAGradientLayer()
    var didLayout: (() -> Void)?
    private var lastLayoutBounds: CGRect?
    private let stillFrame = UIImageView()
    private var stillFrameTask: Task<Void, Never>?
    private var stillFrameRequest: UUID?
    override init(frame: CGRect) {
        super.init(frame: frame)
        backdrop.startPoint = CGPoint(x: 0.7, y: 0)
        backdrop.endPoint = CGPoint(x: 0.3, y: 1)
        backdrop.locations = [0, 0.46, 1]
        stillFrame.isUserInteractionEnabled = false
        stillFrame.accessibilityElementsHidden = true
        layer.insertSublayer(backdrop, at: 0)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func setAppearance(_ appearance: CampusMapAppearance) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdrop.colors = appearance.backdropColors.map(\.cgColor)
        CATransaction.commit()
        map?.isOpaque = false
        map?.backgroundColor = .clear
        map?.environment.background = .color(.clear)
    }
    func installRenderer() -> RealityKit.ARView {
        if let map { return map }
        let view = RealityKit.ARView(frame: bounds, cameraMode: .nonAR, automaticallyConfigureSession: false)
        map = view
        insertSubview(view, at: 0)
        // UIKit inserts the renderer before standalone layers. Keep the backdrop
        // underneath it on screen, including after returning from the AR camera.
        layer.insertSublayer(backdrop, below: view.layer)
        return view
    }
    func scheduleStillFrame(after delay: Duration) {
        guard stillFrameTask == nil, let map, map.superview === self, window != nil else { return }
        let request = UUID()
        stillFrameRequest = request
        stillFrameTask = Task { [weak self, weak map] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self, let map, !self.isHidden, self.window != nil,
                  self.stillFrameRequest == request else { return }
            map.snapshot(saveToHDR: false) { [weak self, weak map] image in
                Task { @MainActor in
                    guard let self, self.stillFrameRequest == request else { return }
                    self.cancelStillFrameCapture()
                    guard let image, let map, map.superview === self,
                          !self.isHidden, self.window != nil else { return }
                    self.stillFrame.image = image
                    self.stillFrame.frame = self.bounds
                    self.insertSubview(self.stillFrame, aboveSubview: map)
                    // Keep the scene and camera ready to resume on the same renderer.
                    map.removeFromSuperview()
                }
            }
        }
    }

    func cancelStillFrameCapture() {
        stillFrameRequest = nil
        stillFrameTask?.cancel()
        stillFrameTask = nil
    }

    func showLiveMap() {
        cancelStillFrameCapture()
        guard let map, map.superview == nil, stillFrame.superview === self else { return }
        insertSubview(map, belowSubview: stillFrame)
        layer.insertSublayer(backdrop, below: map.layer)
        stillFrame.removeFromSuperview()
        stillFrame.image = nil
    }

    func removeRenderer() {
        cancelStillFrameCapture()
        stillFrame.removeFromSuperview()
        stillFrame.image = nil
        map?.session.pause()
        map?.scene.anchors.removeAll()
        map?.removeFromSuperview()
        map = nil
    }
    func invalidateProjection() {
        lastLayoutBounds = nil
        setNeedsLayout()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { cancelStillFrameCapture() }
        else { didLayout?() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds != lastLayoutBounds else { return }
        lastLayoutBounds = bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdrop.frame = bounds
        CATransaction.commit()
        map?.frame = bounds
        didLayout?()
    }
}

struct CampusMapSurface: UIViewRepresentable {
    let scene: CampusExploreScene
    func makeUIView(context: Context) -> CampusMapCanvas { scene.makeView() }
    func updateUIView(_ view: CampusMapCanvas, context: Context) { }
}
