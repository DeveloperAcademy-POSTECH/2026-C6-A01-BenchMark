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
    var wearsWhiteTshirt = false
    var isActive = true

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        if isActive && scenePhase != .background {
            OiStep3CucumberStage(appearance: appearance, wearsWhiteTshirt: wearsWhiteTshirt)
        } else {
            OiSeedCucumberFrontArtwork(appearance: appearance)
        }
    }
}

private enum OiStep3CucumberPresentation: Equatable {
    case front, waitingForRotation, rotating, failed
    case waitingForWhiteTshirt(shows3D: Bool)
    case whiteTshirtFailed(shows3D: Bool)

    var shows3D: Bool {
        switch self {
        case .rotating: true
        case let .waitingForWhiteTshirt(shows3D), let .whiteTshirtFailed(shows3D): shows3D
        case .front, .waitingForRotation, .failed: false
        }
    }
}

private struct OiStep3CucumberStage: View {
    let appearance: OiSeedCucumberAppearance
    let wearsWhiteTshirt: Bool

    @State private var presentation: (appearance: OiSeedCucumberAppearance, value: OiStep3CucumberPresentation)?
    @State private var retry = 0

    private var currentPresentation: OiStep3CucumberPresentation {
        guard let presentation, presentation.appearance == appearance else { return .front }
        return presentation.value
    }

    var body: some View {
        ZStack {
            OiStep3CucumberSurface(appearance: appearance, wearsWhiteTshirt: wearsWhiteTshirt, retry: retry) { value in
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
            case .waitingForRotation:
                progress("3D 미리보기 준비 중")
            case .waitingForWhiteTshirt:
                progress("흰 반팔 티 준비 중")
            case .failed:
                retryButton("3D 미리보기 다시 시도")
            case .whiteTshirtFailed:
                retryButton("흰 반팔 티 다시 시도")
            case .front, .rotating:
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
    let wearsWhiteTshirt: Bool
    let retry: Int
    let onPresentationChange: (OiStep3CucumberPresentation) -> Void

    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> OiStep3CucumberRenderHost {
        let host = OiStep3CucumberRenderHost()
        context.coordinator.install(in: host)
        return host
    }

    func updateUIView(_ host: OiStep3CucumberRenderHost, context: Context) {
        let traits = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        host.renderer.environment.background = .color(UIColor.systemBackground.resolvedColor(with: traits))
        context.coordinator.update(appearance: appearance, wearsWhiteTshirt: wearsWhiteTshirt, retry: retry,
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

        private enum WhiteTshirtLoadState {
            case idle
            case loading(UUID, Task<Void, Never>)
            case ready(Entity)
            case failed
        }

        private weak var host: OiStep3CucumberRenderHost?
        private let anchor = AnchorEntity(world: .zero)
        private let camera = PerspectiveCamera()
        private lazy var pan = UIPanGestureRecognizer(target: self, action: #selector(didPan(_:)))
        private var loadTask: Task<Void, Never>?
        private var request: Request?
        private var loadState = LoadState.loading
        private var onPresentationChange: ((OiStep3CucumberPresentation) -> Void)?
        private var depthCenter: Float?
        private var orbitFrame: (center: SIMD3<Float>, distance: Float)?
        private var yaw: Float = 0
        private var wantsRotation = false
        private var shows3D = false
        private var lastRetry = 0
        private var model: Entity?
        private var wearsWhiteTshirt = false
        private var whiteTshirtLoadState = WhiteTshirtLoadState.idle
        private var mountedWhiteTshirt: Entity?
        private var frameRevision = 0
        private var lastPresentation: OiStep3CucumberPresentation?
        private var presentationTask: Task<Void, Never>?

        func install(in host: OiStep3CucumberRenderHost) {
            self.host = host
            host.didLayout = { [weak self] in self?.layoutChanged() }

            let renderer = host.renderer
            renderer.isAccessibilityElement = true
            renderer.accessibilityIdentifier = "oi.step3.cucumber.surface"
            renderer.accessibilityLabel = "오이 미리보기"
            renderer.accessibilityHint = "드래그하거나 동작 메뉴를 사용해 오이를 돌려 보세요."
            renderer.accessibilityValue = "정면 이미지"
            renderer.accessibilityCustomActions = [
                UIAccessibilityCustomAction(name: "왼쪽으로 돌리기") { [weak self] _ in
                    self?.rotate(by: -.pi / 6) ?? false
                },
                UIAccessibilityCustomAction(name: "오른쪽으로 돌리기") { [weak self] _ in
                    self?.rotate(by: .pi / 6) ?? false
                }
            ]
            renderer.scene.addAnchor(anchor)

            pan.maximumNumberOfTouches = 1
            pan.delegate = self
            renderer.addGestureRecognizer(pan)
        }

        func update(appearance: OiSeedCucumberAppearance, wearsWhiteTshirt: Bool, retry: Int,
                    onPresentationChange: @escaping (OiStep3CucumberPresentation) -> Void) {
            self.onPresentationChange = onPresentationChange
            let retryRequested = retry != lastRetry
            let selectionChanged = self.wearsWhiteTshirt != wearsWhiteTshirt
            lastRetry = retry
            self.wearsWhiteTshirt = wearsWhiteTshirt

            if request?.appearance != appearance || (retryRequested && loadState == .failed) {
                startModelLoad(appearance)
            }
            switch whiteTshirtLoadState {
            case .idle:
                startWhiteTshirtLoad()
            case .failed where retryRequested || (selectionChanged && wearsWhiteTshirt):
                startWhiteTshirtLoad()
            default:
                break
            }
            if selectionChanged { updateMountedWhiteTshirt() }
            if selectionChanged || retryRequested || lastPresentation == nil { schedulePresentation() }
        }

        private func startModelLoad(_ appearance: OiSeedCucumberAppearance) {
            let next = Request(appearance: appearance)
            request = next
            loadState = .loading
            yaw = 0
            wantsRotation = false
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

        private func startWhiteTshirtLoad() {
            let id = UUID()
            let task = Task { @MainActor [weak self] in
                do {
                    let shirt = try await OiSeedCucumberModel.loadWhiteTshirt()
                    try Task.checkCancellation()
                    self?.whiteTshirtLoaded(shirt, id: id)
                } catch is CancellationError {
                    return
                } catch {
                    self?.whiteTshirtLoaded(nil, id: id)
                }
            }
            whiteTshirtLoadState = .loading(id, task)
        }

        private func whiteTshirtLoaded(_ shirt: Entity?, id: UUID) {
            guard case let .loading(currentID, _) = whiteTshirtLoadState, currentID == id else { return }
            whiteTshirtLoadState = shirt.map { .ready($0) } ?? .failed
            updateMountedWhiteTshirt()
            publishPresentation()
        }

        private func updateMountedWhiteTshirt() {
            guard let model else { return }
            let selected: Entity?
            if wearsWhiteTshirt, case let .ready(shirt) = whiteTshirtLoadState {
                selected = shirt
            } else {
                selected = nil
            }
            guard mountedWhiteTshirt !== selected else { return }
            do {
                try OiSeedCucumberModel.setWhiteTshirt(selected, on: model)
                mountedWhiteTshirt = selected
                frameRevision += 1
                // Keep the original scene and angle. The front cover only lifts after
                // the selected garment has had a chance to render on that scene.
                if !shows3D, loadState == .ready {
                    loadState = .awaitingFrame
                    layoutChanged()
                }
            } catch {
                whiteTshirtLoadState = .failed
            }
        }

        func uninstall(from host: OiStep3CucumberRenderHost) {
            guard self.host === host else { return }
            request = nil
            loadTask?.cancel()
            loadTask = nil
            if case let .loading(_, task) = whiteTshirtLoadState { task.cancel() }
            whiteTshirtLoadState = .idle
            presentationTask?.cancel()
            presentationTask = nil
            onPresentationChange = nil
            host.didLayout = nil
            host.renderer.removeGestureRecognizer(pan)
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
            updateMountedWhiteTshirt()
            layoutChanged()
        }

        private func layoutChanged() {
            guard let host, let request, fitCamera(to: host.bounds.size) else { return }
            guard host.window != nil, loadState == .awaitingFrame else { return }
            loadState = .warming
            let revision = frameRevision
            // Confirm that the attached renderer can produce a frame before removing
            // the artwork. This warms the same model and renderer used for rotation.
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
            mountedWhiteTshirt?.removeFromParent()
            mountedWhiteTshirt = nil
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
            let distance = Float(size.height / 2) * metresPerPoint / tan(halfFOV)
            camera.camera.far = max(20, distance * 2)
            orbitFrame = (center, distance)
            updateOrbit()
            return true
        }

        private func updateOrbit() {
            guard let (center, distance) = orbitFrame else { return }
            let offset = SIMD3(sin(yaw) * distance, 0, cos(yaw) * distance)
            camera.look(at: center, from: center + offset, relativeTo: nil)
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }

        @objc private func didPan(_ gesture: UIPanGestureRecognizer) {
            guard gesture.state == .began || gesture.state == .changed else { return }
            let dx = Float(gesture.translation(in: gesture.view).x)
            gesture.setTranslation(.zero, in: gesture.view)
            guard dx != 0 else { return }
            _ = rotate(by: -dx * 0.01)
        }

        private func rotate(by angle: Float) -> Bool {
            guard host != nil, loadState != .failed else { return false }
            yaw = (yaw + angle).truncatingRemainder(dividingBy: 2 * .pi)
            updateOrbit()
            guard !wantsRotation else { return true }
            wantsRotation = true
            publishPresentation()
            return true
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
            if loadState == .ready, wantsRotation || mountedWhiteTshirt != nil { shows3D = true }
            let presentation: OiStep3CucumberPresentation
            if loadState == .failed {
                presentation = .failed
            } else if wearsWhiteTshirt, case .failed = whiteTshirtLoadState {
                presentation = .whiteTshirtFailed(shows3D: shows3D)
            } else if wearsWhiteTshirt && (mountedWhiteTshirt == nil || !shows3D) {
                presentation = .waitingForWhiteTshirt(shows3D: shows3D)
            } else if shows3D {
                presentation = .rotating
            } else {
                presentation = wantsRotation ? .waitingForRotation : .front
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
