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
    var isActive = true

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        if isActive && scenePhase != .background {
            OiStep3CucumberStage(appearance: appearance)
        } else {
            OiSeedCucumberFrontArtwork(appearance: appearance)
        }
    }
}

private enum OiStep3CucumberPresentation: Equatable {
    case front, waitingForRotation, rotating, failed
}

private struct OiStep3CucumberStage: View {
    let appearance: OiSeedCucumberAppearance

    @State private var presentation: (appearance: OiSeedCucumberAppearance, value: OiStep3CucumberPresentation)?
    @State private var retry = 0

    private var currentPresentation: OiStep3CucumberPresentation {
        guard let presentation, presentation.appearance == appearance else { return .front }
        return presentation.value
    }

    var body: some View {
        ZStack {
            OiStep3CucumberSurface(appearance: appearance, retry: retry) { value in
                presentation = (appearance, value)
            }
            if currentPresentation != .rotating {
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
                ProgressView().accessibilityLabel("3D 미리보기 준비 중")
                    .padding(8)
                    .background(.regularMaterial, in: Capsule())
                    .allowsHitTesting(false)
            case .failed:
                Button("3D 미리보기 다시 시도") {
                    presentation = (appearance, .front)
                    retry += 1
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier("oi.step3.cucumber.retry")
            case .front, .rotating:
                EmptyView()
            }
        }
    }
}

private struct OiStep3CucumberSurface: UIViewRepresentable {
    let appearance: OiSeedCucumberAppearance
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
        context.coordinator.update(appearance: appearance, retry: retry, onPresentationChange: onPresentationChange)
    }

    static func dismantleUIView(_ host: OiStep3CucumberRenderHost, coordinator: Coordinator) {
        coordinator.uninstall(from: host)
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private struct Request: Sendable {
            let id = UUID()
            let appearance: OiSeedCucumberAppearance
            let retry: Int
        }

        private enum LoadState: Equatable {
            case loading, awaitingFrame, warming, ready, failed
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

        func update(appearance: OiSeedCucumberAppearance, retry: Int,
                    onPresentationChange: @escaping (OiStep3CucumberPresentation) -> Void) {
            self.onPresentationChange = onPresentationChange
            if let request, request.appearance == appearance, request.retry == retry { return }
            let next = Request(appearance: appearance, retry: retry)
            request = next
            loadState = .loading
            yaw = 0
            wantsRotation = false
            host?.renderer.accessibilityValue = "정면 이미지"
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

        func uninstall(from host: OiStep3CucumberRenderHost) {
            guard self.host === host else { return }
            request = nil
            loadTask?.cancel()
            loadTask = nil
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
            OiSeedCucumberRenderSetup.addLights(to: anchor, lookingAt: bounds.center)
            loadState = .awaitingFrame
            layoutChanged()
        }

        private func layoutChanged() {
            guard let host, let request, fitCamera(to: host.bounds.size) else { return }
            guard host.window != nil, loadState == .awaitingFrame else { return }
            loadState = .warming
            // Confirm that the attached renderer can produce a frame before removing
            // the artwork. This warms the same model and renderer used for rotation.
            host.renderer.snapshot(saveToHDR: false) { [weak self] image in
                let rendered = image != nil
                Task { @MainActor in self?.didWarmFrame(rendered, request: request) }
            }
        }

        private func didWarmFrame(_ rendered: Bool, request: Request) {
            guard request.id == self.request?.id, loadState == .warming else { return }
            guard rendered else {
                fail(request: request)
                return
            }
            loadState = .ready
            if wantsRotation { reveal() }
        }

        private func fail(request: Request) {
            guard request.id == self.request?.id else { return }
            loadTask = nil
            loadState = .failed
            clearScene()
            onPresentationChange?(.failed)
        }

        private func clearScene() {
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
            if loadState == .ready {
                reveal()
            } else {
                onPresentationChange?(.waitingForRotation)
            }
            return true
        }

        private func reveal() {
            host?.renderer.accessibilityValue = "3D 미리보기"
            onPresentationChange?(.rotating)
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
