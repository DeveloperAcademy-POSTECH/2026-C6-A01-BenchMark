//
//  OiSeedCucumber3DPreview.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/12/26.
//

import RealityKit
import SwiftUI
import UIKit
import simd

struct OiSeedCucumber3DPreview: View {
    let appearance: OiSeedCucumberAppearance

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var state = LoadState.loading
    @State private var attempt = 0
    @State private var camera = OiSeedCucumber3DCamera()

    private enum LoadState {
        case loading
        case ready(Entity, center: SIMD3<Float>, radius: Float)
        case failed
    }

    var body: some View {
        NavigationStack {
            Group {
                switch state {
                case .loading:
                    ProgressView("3D 오이를 준비하고 있어요")
                        .accessibilityIdentifier("seedCucumber.3D.loading")
                case let .ready(model, center, radius):
                    if scenePhase != .background {
                        GeometryReader { geometry in
                            OiSeedCucumber3DSurface(model: model, center: center, radius: radius,
                                                   viewport: geometry.size, camera: $camera)
                        }
                        .clipped()
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            controls
                        }
                    }
                case .failed:
                    ContentUnavailableView {
                        Label("3D 오이를 만들 수 없어요", systemImage: "cube")
                    } actions: {
                        Button("다시 시도") { attempt += 1 }
                            .accessibilityIdentifier("seedCucumber.3D.retry")
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
            .navigationTitle("3D 랜더링")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                        .accessibilityIdentifier("seedCucumber.3D.close")
                }
            }
            .task(id: attempt) { await load() }
        }
    }

    private func load() async {
        state = .loading
        do {
            let model = try await OiSeedCucumberModel.make(appearance: appearance)
            try Task.checkCancellation()
            let bounds = model.visualBounds(relativeTo: nil)
            let radius = simd_length(bounds.extents) / 2
            guard radius.isFinite, radius > 0 else {
                state = .failed
                return
            }
            state = .ready(model, center: bounds.center, radius: radius)
        } catch is CancellationError {
            return
        } catch {
            state = .failed
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            control("왼쪽으로 돌리기", icon: "arrow.counterclockwise", id: "left") {
                camera.orbit(yaw: -.pi / 6, pitch: 0)
            }
            control("오른쪽으로 돌리기", icon: "arrow.clockwise", id: "right") {
                camera.orbit(yaw: .pi / 6, pitch: 0)
            }
            control("축소", icon: "minus.magnifyingglass", id: "zoomOut") {
                camera.magnify(by: 1 / 1.15)
            }
            control("확대", icon: "plus.magnifyingglass", id: "zoomIn") {
                camera.magnify(by: 1.15)
            }
            control("정면 보기", icon: "cube", id: "reset") {
                camera = OiSeedCucumber3DCamera()
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    private func control(_ title: String, icon: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .labelStyle(.iconOnly)
                .font(.system(size: 17, weight: .semibold))
                .frame(minWidth: 44, minHeight: 44)
                .foregroundStyle(Color("OiGreen"))
                .background(Color("OiGreen").opacity(0.12), in: Circle())
                .contentShape(Circle())
        }
        .accessibilityIdentifier("seedCucumber.3D.\(id)")
    }
}

struct OiSeedCucumber3DCamera {
    static let fieldOfView: Float = 36

    private var yaw: Float = 0
    private var pitch: Float = 0
    private var zoom: Float = 1

    static func fitDistance(radius: Float, viewport: CGSize) -> Float {
        let vertical = fieldOfView * .pi / 360
        let aspect = Float(viewport.width / max(1, viewport.height))
        let horizontal = atan(tan(vertical) * max(0.01, aspect))
        // A bounding sphere stays inside both fields of view at any orbit angle.
        return radius / sin(min(horizontal, vertical)) * 1.1
    }

    mutating func orbit(yaw changeInYaw: Float, pitch changeInPitch: Float) {
        yaw = (yaw + changeInYaw).truncatingRemainder(dividingBy: 2 * .pi)
        pitch = min(.pi / 3, max(-.pi / 3, pitch + changeInPitch))
    }

    mutating func magnify(by factor: Float) {
        guard factor.isFinite, factor > 0 else { return }
        zoom = min(1.45, max(0.55, zoom * factor))
    }

    func position(center: SIMD3<Float>, radius: Float, viewport: CGSize) -> SIMD3<Float> {
        let distance = Self.fitDistance(radius: radius, viewport: viewport) / zoom
        return center + SIMD3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
    }
}

private struct OiSeedCucumber3DSurface: UIViewRepresentable {
    let model: Entity
    let center: SIMD3<Float>
    let radius: Float
    let viewport: CGSize
    @Binding var camera: OiSeedCucumber3DCamera
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator(camera: $camera) }

    func makeUIView(context: Context) -> RealityKit.ARView {
        let view = OiSeedCucumberRenderSetup.makeView()
        view.isAccessibilityElement = true
        view.accessibilityLabel = "편집한 오이 3D 미리보기"
        view.accessibilityHint = "아래 버튼으로 오이를 돌리거나 확대할 수 있어요."
        view.accessibilityIdentifier = "seedCucumber.3D.canvas"
        context.coordinator.install(in: view, model: model, center: center, radius: radius)
        updateUIView(view, context: context)
        return view
    }

    func updateUIView(_ view: RealityKit.ARView, context: Context) {
        let traits = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        view.environment.background = .color(UIColor.systemBackground.resolvedColor(with: traits))
        let coordinator = context.coordinator
        coordinator.camera = $camera
        let position = camera.position(center: center, radius: radius, viewport: viewport)
        coordinator.cameraEntity.look(at: center, from: position, relativeTo: nil)
    }

    static func dismantleUIView(_ view: RealityKit.ARView, coordinator: Coordinator) {
        coordinator.uninstall(from: view)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let cameraEntity = PerspectiveCamera()
        var camera: Binding<OiSeedCucumber3DCamera>
        private let anchor = AnchorEntity(world: .zero)
        private lazy var pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        private lazy var pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))

        init(camera: Binding<OiSeedCucumber3DCamera>) { self.camera = camera }

        func install(in view: RealityKit.ARView, model: Entity, center: SIMD3<Float>, radius: Float) {
            cameraEntity.camera.fieldOfViewInDegrees = OiSeedCucumber3DCamera.fieldOfView
            cameraEntity.camera.fieldOfViewOrientation = .vertical
            cameraEntity.camera.near = max(0.001, radius * 0.01)
            cameraEntity.camera.far = max(20, radius * 400)
            anchor.addChild(cameraEntity)
            anchor.addChild(model)
            OiSeedCucumberRenderSetup.addLights(to: anchor, lookingAt: center)
            view.scene.addAnchor(anchor)
            pan.maximumNumberOfTouches = 1
            pan.delegate = self
            pinch.delegate = self
            view.addGestureRecognizer(pan)
            view.addGestureRecognizer(pinch)
        }

        func uninstall(from view: RealityKit.ARView) {
            view.removeGestureRecognizer(pan)
            view.removeGestureRecognizer(pinch)
            view.scene.removeAnchor(anchor)
            for child in Array(anchor.children) { child.removeFromParent() }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            (gestureRecognizer === pan && otherGestureRecognizer === pinch)
                || (gestureRecognizer === pinch && otherGestureRecognizer === pan)
        }

        @objc private func panned(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)
            camera.wrappedValue.orbit(yaw: -Float(translation.x) * 0.01, pitch: Float(translation.y) * 0.01)
            gesture.setTranslation(.zero, in: gesture.view)
        }

        @objc private func pinched(_ gesture: UIPinchGestureRecognizer) {
            camera.wrappedValue.magnify(by: Float(gesture.scale))
            gesture.scale = 1
        }
    }
}

@MainActor
enum OiSeedCucumberRenderSetup {
    static func makeView() -> RealityKit.ARView {
        let view = RealityKit.ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.renderOptions.formUnion([.disableMotionBlur, .disableDepthOfField, .disableCameraGrain])
        return view
    }

    static func addLights(to anchor: AnchorEntity, lookingAt center: SIMD3<Float>) {
        for (direction, intensity) in [(SIMD3<Float>(-3, 5, 4), Float(1200)), ([3, 3, 2], 700), ([0, 4, -3], 800)] {
            let light = DirectionalLight()
            light.light.intensity = intensity
            light.look(at: center, from: center + direction, relativeTo: nil)
            anchor.addChild(light)
        }
    }
}

#Preview {
    OiSeedCucumber3DPreview(appearance: .init())
}
