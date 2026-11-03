//
//  ARGameCameraView.swift
//  OiDonationClip
//
//  Created by jiwon hong on 10/28/26.
//

import ARKit
import CoreImage
import Foundation
import Observation
import RealityKit
import SwiftUI
import UIKit

@MainActor
@Observable
final class ARGameCameraController: NSObject, ARSessionDelegate {
    let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)

    private let targetCount: Int
    private let cucumberImageURL: URL?
    private let onCollect: () -> Void
    private let onUnavailable: () -> Void
    private(set) var isReady = false
    var isCollecting = false
    private var isRunning = false
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    private var didPlaceCollectibles = false
    private var cucumberTexture: TextureResource?
    private var glowTexture: TextureResource?
    private var latestCameraTransform: simd_float4x4?
    private var textureTask: Task<Void, Never>?
    private var readinessTask: Task<Void, Never>?
    private var characterAspect: Float = 133 / 211
    private var latestProjection: simd_float4x4?

    init(
        targetCount: Int,
        cucumberImageURL: URL?,
        onUnavailable: @escaping () -> Void,
        onCollect: @escaping () -> Void
    ) {
        self.targetCount = targetCount
        self.cucumberImageURL = cucumberImageURL
        self.onCollect = onCollect
        self.onUnavailable = onUnavailable
        super.init()
        view.session.delegate = self
        view.session.delegateQueue = .main
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTap(_:))))
        feedbackGenerator.prepare()
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        view.session.delegate = self
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        configuration.isLightEstimationEnabled = true
        configuration.environmentTexturing = .automatic
        view.session.run(configuration)
        textureTask = Task { await prepareCucumberTexture() }
        readinessTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            guard let self, self.isRunning, !self.isReady else { return }
            self.onUnavailable()
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        isCollecting = false
        textureTask?.cancel()
        textureTask = nil
        readinessTask?.cancel()
        readinessTask = nil
        view.session.delegate = nil
        view.session.pause()
        view.scene.anchors.removeAll()
        didPlaceCollectibles = false
        latestCameraTransform = nil
        latestProjection = nil
        isReady = false
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard isRunning, !didPlaceCollectibles, view.bounds.width > 0, view.bounds.height > 0 else { return }
        guard case .normal = frame.camera.trackingState else { return }
        guard let viewRotationAngle = session.viewRotationAngle else { return }
        latestCameraTransform = frame.camera.transform
        latestProjection = frame.camera.projectionMatrix(
            viewRotationAngle: viewRotationAngle,
            viewportSize: view.bounds.size,
            zNear: 0.01,
            zFar: 100
        )
        placeCollectiblesIfReady()
    }

    func sessionWasInterrupted(_ session: ARSession) { onUnavailable() }

    func session(_ session: ARSession, didFailWithError error: Error) { onUnavailable() }

    private func prepareCucumberTexture() async {
        if let image = UIImage(named: "ARGamePlayingGlow"), let source = CIImage(image: image) {
            // Restore the original SVG's stdDeviation 35 in the AR texture.
            let blurred = source.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 35 * image.scale])
            if let cgImage = CIContext().createCGImage(blurred, from: source.extent) {
                glowTexture = try? await TextureResource(image: cgImage, options: .init(semantic: .color))
            }
        }
        guard isRunning, !Task.isCancelled else { return }
        if let image = await CucumberArtwork.load(imageURL: cucumberImageURL),
           let cgImage = image.cgImage {
            guard isRunning, !Task.isCancelled else { return }
            characterAspect = Float(cgImage.width) / Float(cgImage.height)
            cucumberTexture = try? await TextureResource(
                image: cgImage,
                withName: "story-cucumber",
                options: .init(semantic: .color)
            )
        }

        guard isRunning, !Task.isCancelled else { return }
        placeCollectiblesIfReady()
    }

    private func placeCollectiblesIfReady() {
        guard isRunning, !didPlaceCollectibles,
              cucumberTexture != nil,
              latestProjection != nil,
              let latestCameraTransform else { return }
        didPlaceCollectibles = true
        placeCollectibles(relativeTo: latestCameraTransform)
        isReady = true
        readinessTask?.cancel()
        readinessTask = nil
    }

    private func placeCollectibles(relativeTo cameraTransform: simd_float4x4) {
        let anchor = AnchorEntity(world: cameraTransform)
        let spread: Float = 70 * .pi / 180
        let angles: [Float] = [0, spread, -spread]
        let heights: [Float] = [-0.02, 0.03, -0.03]
        let distances: [Float] = [1.15, 1.25, 1.2]

        for index in 0..<targetCount {
            let angle = angles[index % angles.count]
            let distance = distances[index % distances.count]
            let root = makeCollectible(index: index, distance: distance)
            root.position = [sin(angle) * distance, heights[index % heights.count], -cos(angle) * distance]
            anchor.addChild(root)
        }

        view.scene.addAnchor(anchor)
    }

    private func makeCollectible(index: Int, distance: Float) -> Entity {
        let root = Entity()
        root.name = "collectible-\(index)"
        root.components.set(BillboardComponent())

        // Match the reference's 133 × 211 character using the actual camera FOV.
        // Collision size remains independent from the rendered artwork.
        let projectionY = abs(latestProjection?.columns.1.y ?? 1)
        let height = 2 * distance * Float(211.0 / 874.0) / max(projectionY, 0.01)
        let width = height * Float(133.0 / 211.0)
        let visualHeight = min(height, width / characterAspect)
        let visualWidth = visualHeight * characterAspect
        root.components.set(CollisionComponent(shapes: [
            .generateBox(size: [max(0.36, visualWidth), max(0.57, visualHeight), 0.04])
        ]))

        if let glowTexture, let glowMaterial = material(texture: glowTexture) {
            let glow = ModelEntity(
                mesh: .generatePlane(width: width * 246 / 133, height: height * 332 / 211),
                materials: [glowMaterial]
            )
            glow.position.z = -0.01
            glow.orientation = simd_quatf(angle: -16.56 * .pi / 180, axis: [0, 0, 1])
            root.addChild(glow)
        }

        if let cucumberTexture,
           let cucumberMaterial = material(texture: cucumberTexture) {
            let cucumber = ModelEntity(
                mesh: .generatePlane(width: visualWidth, height: visualHeight),
                materials: [cucumberMaterial]
            )
            root.addChild(cucumber)
        }

        return root
    }

    private func material(texture: TextureResource) -> UnlitMaterial? {
        var material = UnlitMaterial()
        material.color = .init(tint: .white, texture: .init(texture))
        material.blending = .transparent(opacity: .init(floatLiteral: 1))
        return material
    }

    @objc
    private func didTap(_ recognizer: UITapGestureRecognizer) {
        guard isRunning, isReady, isCollecting else { return }
        guard let hit = view.entity(at: recognizer.location(in: view)) else { return }
        var candidate: Entity? = hit

        while let entity = candidate {
            if entity.name.hasPrefix("collectible-") {
                entity.removeFromParent()
                feedbackGenerator.impactOccurred()
                feedbackGenerator.prepare()
                onCollect()
                return
            }
            candidate = entity.parent
        }
    }
}

struct ARGameCameraView: UIViewRepresentable {
    let controller: ARGameCameraController
    let isCollecting: Bool

    func makeCoordinator() -> ARGameCameraController { controller }

    func makeUIView(context: Context) -> ARView {
        controller.isCollecting = isCollecting
        controller.start()
        return controller.view
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        controller.isCollecting = isCollecting
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: ARGameCameraController) {
        coordinator.stop()
    }
}
