//
//  OiStep3CucumberPreview.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/12/26.
//

import RealityKit
import SwiftUI
import UIKit

struct OiStep3CucumberPreview: View {
    let appearance: OiSeedCucumberAppearance
    var garments: Set<OiSeedCucumberGarment> = []
    var isActive = true

    @Environment(\.scenePhase) private var scenePhase
    @State private var orbit = OiStep3CucumberOrbit()

    var body: some View {
        if isActive && scenePhase != .background {
            OiStep3CucumberStage(appearance: appearance, garments: garments, orbit: orbit)
        } else {
            OiSeedCucumberFrontArtwork(appearance: appearance)
        }
    }
}

@MainActor
private final class OiStep3CucumberOrbit {
    static let zoomRange: ClosedRange<Float> = 0.55...1.45

    var yaw: Float = 0
    var zoom: Float = 1
    var verticalOffset: Float = 0
    var requestsPreview = false
}

private enum OiStep3CucumberPresentation: Equatable {
    case front, waitingForPreview, preview3D, failed
    case waitingForGarment(OiSeedCucumberGarment, shows3D: Bool)
    case garmentFailed(OiSeedCucumberGarment, shows3D: Bool)

    var shows3D: Bool {
        switch self {
        case .preview3D: true
        case let .waitingForGarment(_, shows3D), let .garmentFailed(_, shows3D): shows3D
        case .front, .waitingForPreview, .failed: false
        }
    }
}

private struct OiStep3CucumberStage: View {
    let appearance: OiSeedCucumberAppearance
    let garments: Set<OiSeedCucumberGarment>
    let orbit: OiStep3CucumberOrbit

    @State private var presentation: (appearance: OiSeedCucumberAppearance, value: OiStep3CucumberPresentation)?
    @State private var retry = 0

    private var currentPresentation: OiStep3CucumberPresentation {
        guard let presentation, presentation.appearance == appearance else { return .front }
        return presentation.value
    }

    var body: some View {
        ZStack {
            OiStep3CucumberSurface(appearance: appearance, garments: garments,
                                   orbit: orbit, retry: retry) { value in
                presentation = (appearance, value)
            }
            if !currentPresentation.shows3D {
                // A mounted surface can load and draw behind the front illustration.
                // The same gesture target remains under the finger across the handoff.
                OiSeedCucumberFrontArtwork(appearance: appearance)
                    .background(Color(.systemBackground))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .clipped()
        .overlay(alignment: .top) {
            switch currentPresentation {
            case .waitingForPreview:
                progress("3D 미리보기 준비 중")
            case let .waitingForGarment(garment, _):
                progress("\(garment.title) 준비 중")
            case .failed:
                retryButton("3D 미리보기 다시 시도")
            case let .garmentFailed(garment, _):
                retryButton("\(garment.title) 다시 시도")
            case .front, .preview3D:
                EmptyView()
            }
        }
    }

    private func progress(_ label: String) -> some View {
        ProgressView().accessibilityLabel(label)
            .padding(8)
            .background(.regularMaterial, in: Capsule())
            .allowsHitTesting(false)
    }

    private func retryButton(_ title: String) -> some View {
        Button(title) { retry += 1 }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityIdentifier("oi.step3.cucumber.retry")
    }
}

private struct OiStep3CucumberSurface: UIViewRepresentable {
    let appearance: OiSeedCucumberAppearance
    let garments: Set<OiSeedCucumberGarment>
    let orbit: OiStep3CucumberOrbit
    let retry: Int
    let onPresentationChange: (OiStep3CucumberPresentation) -> Void

    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator(orbit: orbit) }

    func makeUIView(context: Context) -> OiStep3CucumberRenderHost {
        let host = OiStep3CucumberRenderHost()
        context.coordinator.install(in: host)
        return host
    }

    func updateUIView(_ host: OiStep3CucumberRenderHost, context: Context) {
        let traits = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        host.renderer.environment.background = .color(UIColor.systemBackground.resolvedColor(with: traits))
        context.coordinator.update(appearance: appearance, garments: garments, retry: retry,
                                   onPresentationChange: onPresentationChange)
    }

    static func dismantleUIView(_ host: OiStep3CucumberRenderHost, coordinator: Coordinator) {
        coordinator.uninstall(from: host)
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private struct Request: Sendable {
            let id = UUID()
            let appearance: OiSeedCucumberAppearance
        }

        private enum LoadState: Equatable {
            case loading, awaitingFrame, warming, ready, failed
        }

        private enum GarmentLoadState {
            case loading(UUID, Task<Void, Never>)
            case ready(Entity)
            case failed
        }

        private enum PanDirection {
            case rotate, vertical
        }

        private weak var host: OiStep3CucumberRenderHost?
        private let anchor = AnchorEntity(world: .zero)
        private let camera = PerspectiveCamera()
        private let orbit: OiStep3CucumberOrbit
        private lazy var pan = UIPanGestureRecognizer(target: self, action: #selector(didPan(_:)))
        private lazy var pinch = UIPinchGestureRecognizer(target: self, action: #selector(didPinch(_:)))
        private var loadTask: Task<Void, Never>?
        private var request: Request?
        private var loadState = LoadState.loading
        private var onPresentationChange: ((OiStep3CucumberPresentation) -> Void)?
        private var depthCenter: Float?
        private var orbitFrame: (center: SIMD3<Float>, distance: Float, height: Float)?
        private var panDirection: PanDirection?
        private var shows3D = false
        private var lastRetry = 0
        private var model: Entity?
        private var selectedGarments: Set<OiSeedCucumberGarment> = []
        private var garmentLoads: [OiSeedCucumberGarment: GarmentLoadState] = [:]
        private var mountedGarments: [OiSeedCucumberGarment: Entity] = [:]
        private var frameRevision = 0
        private var lastPresentation: OiStep3CucumberPresentation?
        private var presentationTask: Task<Void, Never>?

        init(orbit: OiStep3CucumberOrbit) { self.orbit = orbit }

        func install(in host: OiStep3CucumberRenderHost) {
            self.host = host
            host.didLayout = { [weak self] in self?.layoutChanged() }

            let renderer = host.renderer
            renderer.isAccessibilityElement = true
            renderer.accessibilityIdentifier = "oi.step3.cucumber.surface"
            renderer.accessibilityLabel = "오이 미리보기"
            renderer.accessibilityHint = "가로로 드래그해 돌리고 두 손가락으로 확대하거나 축소할 수 있어요. 확대하면 위아래로도 움직일 수 있어요."
            renderer.accessibilityValue = "정면 이미지"
            updateAccessibilityActions(for: renderer)
            renderer.scene.addAnchor(anchor)

            pan.maximumNumberOfTouches = 1
            pan.delegate = self
            pinch.delegate = self
            renderer.addGestureRecognizer(pan)
            renderer.addGestureRecognizer(pinch)
        }

        private func updateAccessibilityActions(for renderer: RealityKit.ARView) {
            var actions = [
                UIAccessibilityCustomAction(name: "왼쪽으로 돌리기") { [weak self] _ in
                    self?.rotate(by: -.pi / 6) ?? false
                },
                UIAccessibilityCustomAction(name: "오른쪽으로 돌리기") { [weak self] _ in
                    self?.rotate(by: .pi / 6) ?? false
                },
                UIAccessibilityCustomAction(name: "확대") { [weak self] _ in
                    self?.magnify(by: 1.15) ?? false
                },
                UIAccessibilityCustomAction(name: "축소") { [weak self] _ in
                    self?.magnify(by: 1 / 1.15) ?? false
                }
            ]
            if orbit.zoom > 1 {
                actions.append(contentsOf: [
                    UIAccessibilityCustomAction(name: "위쪽 보기") { [weak self] _ in
                        self?.panVertically(by: 0.1) ?? false
                    },
                    UIAccessibilityCustomAction(name: "아래쪽 보기") { [weak self] _ in
                        self?.panVertically(by: -0.1) ?? false
                    }
                ])
            }
            renderer.accessibilityCustomActions = actions
        }

        func update(appearance: OiSeedCucumberAppearance, garments: Set<OiSeedCucumberGarment>, retry: Int,
                    onPresentationChange: @escaping (OiStep3CucumberPresentation) -> Void) {
            self.onPresentationChange = onPresentationChange
            let retryRequested = retry != lastRetry
            let previousSelection = selectedGarments
            let selectionChanged = previousSelection != garments
            lastRetry = retry
            selectedGarments = garments

            if request?.appearance != appearance || (retryRequested && loadState == .failed) {
                startModelLoad(appearance)
            }
            for garment in previousSelection.subtracting(garments) {
                if case let .loading(_, task) = garmentLoads[garment] {
                    garmentLoads[garment] = nil
                    task.cancel()
                }
            }
            for garment in garments {
                switch garmentLoads[garment] {
                case nil:
                    startGarmentLoad(garment)
                case .failed where retryRequested || !previousSelection.contains(garment):
                    startGarmentLoad(garment)
                default:
                    break
                }
            }
            if selectionChanged { updateMountedGarments() }
            discardInactiveCostumes()
            if selectionChanged || retryRequested || lastPresentation == nil { schedulePresentation() }
        }

        private func startModelLoad(_ appearance: OiSeedCucumberAppearance) {
            let next = Request(appearance: appearance)
            request = next
            loadState = .loading
            shows3D = false
            lastPresentation = nil
            loadTask?.cancel()
            clearScene()
            loadTask = Task { @MainActor [weak self] in
                do {
                    let model = try await OiSeedCucumberModel.make(appearance: appearance)
                    try Task.checkCancellation()
                    self?.modelLoaded(model, request: next)
                } catch is CancellationError {
                    return
                } catch {
                    self?.fail(request: next)
                }
            }
        }

        private func startGarmentLoad(_ garment: OiSeedCucumberGarment) {
            let id = UUID()
            let task = Task { @MainActor [weak self] in
                do {
                    let asset = try await OiSeedCucumberModel.loadGarment(garment)
                    try Task.checkCancellation()
                    self?.garmentLoaded(garment, asset: asset, id: id)
                } catch is CancellationError {
                    return
                } catch {
                    self?.garmentLoaded(garment, asset: nil, id: id)
                }
            }
            garmentLoads[garment] = .loading(id, task)
        }

        private func garmentLoaded(_ garment: OiSeedCucumberGarment, asset: Entity?, id: UUID) {
            guard case let .loading(currentID, _) = garmentLoads[garment], currentID == id else { return }
            garmentLoads[garment] = asset.map { .ready($0) } ?? .failed
            updateMountedGarments()
            publishPresentation()
        }

        private func updateMountedGarments() {
            guard let model else { return }
            // Keep the entire current look on screen until every piece of the new look is ready.
            guard selectedGarments.allSatisfy({ garment in
                if case .ready = garmentLoads[garment] { return true }
                return false
            }) else { return }
            var changed = false
            for slot in OiSeedCucumberGarment.Slot.allCases {
                let previous = mountedGarments.keys.first { $0.slot == slot }
                let selected = selectedGarments.first { $0.slot == slot }
                guard previous != selected else { continue }
                let replacement: Entity?
                if let selected {
                    // Keep the previous piece visible while its replacement loads.
                    guard case let .ready(asset) = garmentLoads[selected] else { continue }
                    replacement = asset
                } else {
                    replacement = nil
                }
                do {
                    if let previous {
                        try OiSeedCucumberModel.setGarment(previous, asset: nil, on: model)
                        mountedGarments[previous] = nil
                        changed = true
                    }
                    if let selected, let replacement {
                        try OiSeedCucumberModel.setGarment(selected, asset: replacement, on: model)
                        mountedGarments[selected] = replacement
                        changed = true
                    }
                } catch {
                    if let selected { garmentLoads[selected] = .failed }
                }
            }
            guard changed else { return }
            discardInactiveCostumes()
            OiSeedCucumberModel.updateCoverage(for: Set(mountedGarments.keys), on: model)
            frameRevision += 1
            // Reveal the warmed frame for the latest outfit while keeping the camera in place.
            if !shows3D, loadState == .ready {
                loadState = .awaitingFrame
                layoutChanged()
            }
        }

        private func discardInactiveCostumes() {
            let inactive = garmentLoads.keys.filter {
                $0.slot == .costume && !selectedGarments.contains($0) && mountedGarments[$0] == nil
            }
            for garment in inactive { garmentLoads[garment] = nil }
        }

        func uninstall(from host: OiStep3CucumberRenderHost) {
            guard self.host === host else { return }
            request = nil
            loadTask?.cancel()
            loadTask = nil
            for case let .loading(_, task) in garmentLoads.values { task.cancel() }
            garmentLoads.removeAll()
            presentationTask?.cancel()
            presentationTask = nil
            onPresentationChange = nil
            host.didLayout = nil
            panDirection = nil
            host.renderer.removeGestureRecognizer(pan)
            host.renderer.removeGestureRecognizer(pinch)
            host.renderer.accessibilityCustomActions = nil
            host.renderer.scene.removeAnchor(anchor)
            clearScene()
            self.host = nil
        }

        private func modelLoaded(_ model: Entity, request: Request) {
            guard request.id == self.request?.id else { return }
            loadTask = nil
            let bounds = model.visualBounds(relativeTo: nil)
            guard bounds.center.z.isFinite, bounds.extents.y.isFinite, bounds.extents.y > 0 else {
                fail(request: request)
                return
            }
            depthCenter = bounds.center.z
            camera.camera.fieldOfViewInDegrees = 12
            camera.camera.fieldOfViewOrientation = .vertical
            camera.camera.near = 0.01
            anchor.addChild(camera)
            anchor.addChild(model)
            self.model = model
            OiSeedCucumberRenderSetup.addLights(to: anchor, lookingAt: bounds.center)
            loadState = .awaitingFrame
            updateMountedGarments()
            layoutChanged()
        }

        private func layoutChanged() {
            guard let host, let request, fitCamera(to: host.bounds.size) else { return }
            guard host.window != nil, loadState == .awaitingFrame else { return }
            loadState = .warming
            let revision = frameRevision
            // Confirm that the attached renderer can produce a frame before removing
            // the artwork. This warms the same model and renderer used for interaction.
            host.renderer.snapshot(saveToHDR: false) { [weak self] image in
                let rendered = image != nil
                Task { @MainActor in self?.didWarmFrame(rendered, request: request, revision: revision) }
            }
        }

        private func didWarmFrame(_ rendered: Bool, request: Request, revision: Int) {
            guard request.id == self.request?.id, loadState == .warming else { return }
            if revision != frameRevision {
                loadState = .awaitingFrame
                layoutChanged()
                return
            }
            guard rendered else {
                fail(request: request)
                return
            }
            loadState = .ready
            publishPresentation()
        }

        private func fail(request: Request) {
            guard request.id == self.request?.id else { return }
            loadTask = nil
            loadState = .failed
            clearScene()
            publishPresentation()
        }

        private func clearScene() {
            for asset in mountedGarments.values { asset.removeFromParent() }
            mountedGarments.removeAll()
            model = nil
            depthCenter = nil
            orbitFrame = nil
            for child in Array(anchor.children) { child.removeFromParent() }
        }

        private func fitCamera(to size: CGSize) -> Bool {
            guard let depthCenter, size.width > 0, size.height > 0 else { return false }
            let viewport = OiSeedCucumberViewport(size: size)
            guard viewport.scale > 0 else { return false }

            // The reference artwork and authored mesh share the same source pixels.
            // The narrow field of view keeps the visible scale close to the flat artwork.
            let metresPerPoint: Float = 0.001 / Float(viewport.scale)
            let ground = viewport.location(of: OiSeedCucumberAppearance.bodyPivot)
            let center = SIMD3(
                Float(size.width / 2 - ground.x) * metresPerPoint,
                Float(ground.y - size.height / 2) * metresPerPoint,
                depthCenter
            )
            let halfFOV = camera.camera.fieldOfViewInDegrees * .pi / 360
            let height = Float(size.height) * metresPerPoint
            let distance = height * 0.5 / tan(halfFOV)
            camera.camera.far = max(20, distance / OiStep3CucumberOrbit.zoomRange.lowerBound * 2)
            orbitFrame = (center, distance, height)
            updateOrbit()
            return true
        }

        private func updateOrbit() {
            guard let (center, fittedDistance, fittedHeight) = orbitFrame else { return }
            let distance = fittedDistance / orbit.zoom
            let offset = SIMD3(sin(orbit.yaw) * distance, 0, cos(orbit.yaw) * distance)
            let target = center + SIMD3(0, orbit.verticalOffset * fittedHeight, 0)
            camera.look(at: target, from: target + offset, relativeTo: nil)
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === pan else { return true }
            return direction(for: pan) != nil
        }

        private func direction(for gesture: UIPanGestureRecognizer) -> PanDirection? {
            let velocity = gesture.velocity(in: gesture.view)
            let motion = velocity == .zero ? gesture.translation(in: gesture.view) : velocity
            if abs(motion.x) > abs(motion.y) { return .rotate }
            return orbit.zoom > 1 && motion.y != 0 ? .vertical : nil
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            (gestureRecognizer === pan && otherGestureRecognizer === pinch)
                || (gestureRecognizer === pinch && otherGestureRecognizer === pan)
        }

        @objc private func didPan(_ gesture: UIPanGestureRecognizer) {
            switch gesture.state {
            case .began:
                panDirection = direction(for: gesture)
            case .changed:
                break
            default:
                panDirection = nil
                return
            }
            let translation = gesture.translation(in: gesture.view)
            gesture.setTranslation(.zero, in: gesture.view)
            guard pinch.state != .began && pinch.state != .changed else { return }
            switch panDirection {
            case .rotate where translation.x != 0:
                _ = rotate(by: -Float(translation.x) * 0.01)
            case .vertical:
                guard let height = host?.renderer.bounds.height, height > 0 else { return }
                _ = panVertically(by: Float(translation.y / height) / orbit.zoom)
            default:
                break
            }
        }

        @objc private func didPinch(_ gesture: UIPinchGestureRecognizer) {
            guard gesture.state == .began || gesture.state == .changed else { return }
            let factor = Float(gesture.scale)
            // Consume the delta so reversing at a zoom limit responds immediately.
            gesture.scale = 1
            _ = magnify(by: factor)
        }

        private func rotate(by angle: Float) -> Bool {
            guard host != nil, loadState != .failed else { return false }
            orbit.yaw = (orbit.yaw + angle).truncatingRemainder(dividingBy: 2 * .pi)
            updateOrbit()
            requestPreview()
            return true
        }

        private func clampedVerticalOffset(_ offset: Float) -> Float {
            // Keep the zoomed viewport within the original vertical framing.
            let limit = max(0, (1 - 1 / orbit.zoom) * 0.5)
            return min(limit, max(-limit, offset))
        }

        private func panVertically(by offset: Float) -> Bool {
            guard host != nil, loadState != .failed, orbit.zoom > 1, offset.isFinite else { return false }
            let position = clampedVerticalOffset(orbit.verticalOffset + offset)
            guard position != orbit.verticalOffset else { return false }
            orbit.verticalOffset = position
            updateOrbit()
            requestPreview()
            return true
        }

        private func magnify(by factor: Float) -> Bool {
            guard let host, loadState != .failed, factor.isFinite, factor > 0 else { return false }
            let range = OiStep3CucumberOrbit.zoomRange
            let zoom = min(range.upperBound, max(range.lowerBound, orbit.zoom * factor))
            if orbit.zoom != zoom {
                let wasZoomedIn = orbit.zoom > 1
                orbit.zoom = zoom
                orbit.verticalOffset = clampedVerticalOffset(orbit.verticalOffset)
                updateOrbit()
                if wasZoomedIn != (zoom > 1) { updateAccessibilityActions(for: host.renderer) }
            }
            requestPreview()
            return true
        }

        private func requestPreview() {
            guard !orbit.requestsPreview else { return }
            orbit.requestsPreview = true
            publishPresentation()
        }

        private func schedulePresentation() {
            guard presentationTask == nil else { return }
            // UIViewRepresentable updates cannot synchronously write SwiftUI state.
            presentationTask = Task { @MainActor [weak self] in
                guard let self, !Task.isCancelled else { return }
                presentationTask = nil
                publishPresentation()
            }
        }

        private func publishPresentation() {
            guard let host else { return }
            let selected = OiSeedCucumberGarment.allCases.filter(selectedGarments.contains)
            let missing = selected.first { mountedGarments[$0] == nil }
            let failed = selected.first {
                if case .failed = garmentLoads[$0] { return true }
                return false
            }
            if loadState == .ready, orbit.requestsPreview || (!selected.isEmpty && missing == nil) { shows3D = true }
            let presentation: OiStep3CucumberPresentation
            if loadState == .failed {
                presentation = .failed
            } else if let failed {
                presentation = .garmentFailed(failed, shows3D: shows3D)
            } else if let preparing = missing ?? (shows3D ? nil : selected.first) {
                presentation = .waitingForGarment(preparing, shows3D: shows3D)
            } else if shows3D {
                presentation = .preview3D
            } else {
                presentation = orbit.requestsPreview ? .waitingForPreview : .front
            }
            guard presentation != lastPresentation else { return }
            lastPresentation = presentation
            host.renderer.accessibilityValue = presentation.shows3D ? "3D 미리보기" : "정면 이미지"
            onPresentationChange?(presentation)
        }
    }
}

private final class OiStep3CucumberRenderHost: UIView {
    let renderer = OiSeedCucumberRenderSetup.makeView()
    var didLayout: (() -> Void)?

    init() {
        super.init(frame: .zero)
        addSubview(renderer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        renderer.frame = bounds
        didLayout?()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        didLayout?()
    }
}

#Preview("STEP 3 오이") {
    OiStep3CucumberPreview(appearance: .init())
        .frame(height: 270)
}
