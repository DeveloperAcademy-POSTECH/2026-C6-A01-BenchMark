//
//  ARGameCameraView.swift
//  OiDonationClip
//
//  Created by jiwon hong on 10/28/26.
//

import ARKit
import Foundation
import RealityKit
import SwiftUI
import UIKit

@MainActor
final class ARGameCameraController: NSObject, ARSessionDelegate {
    let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)

    private let targetCount: Int
    private let cucumberImageURL: URL?
    private let onCollect: () -> Void
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    private var didPlaceCollectibles = false
    private var cucumberTexture: TextureResource?
    private var latestCameraTransform: simd_float4x4?
    private var textureTask: Task<Void, Never>?

    init(
        targetCount: Int,
        cucumberImageURL: URL?,
        onCollect: @escaping () -> Void
    ) {
        self.targetCount = targetCount
        self.cucumberImageURL = cucumberImageURL
        self.onCollect = onCollect
        super.init()
        view.session.delegate = self
        view.session.delegateQueue = .main
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTap(_:))))
        feedbackGenerator.prepare()
    }

    func start() {
        didPlaceCollectibles = false
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        configuration.isLightEstimationEnabled = true
        configuration.environmentTexturing = .automatic
        view.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        textureTask = Task { await prepareCucumberTexture() }
    }

    func stop() {
        textureTask?.cancel()
        view.session.pause()
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard !didPlaceCollectibles else { return }
        guard case .normal = frame.camera.trackingState else { return }
        latestCameraTransform = frame.camera.transform
        placeCollectiblesIfReady()
    }

    private func prepareCucumberTexture() async {
        if let cucumberImageURL,
           let (data, _) = try? await URLSession.shared.data(from: cucumberImageURL),
           let image = UIImage(data: data),
           let cgImage = image.cgImage {
            cucumberTexture = try? await TextureResource(
                image: cgImage,
                withName: "story-cucumber",
                options: .init(semantic: .color)
            )
        }

        if cucumberTexture == nil {
            cucumberTexture = try? await TextureResource(named: "ARGameIntroCucumber")
        }
        placeCollectiblesIfReady()
    }

    private func placeCollectiblesIfReady() {
        guard !didPlaceCollectibles,
              cucumberTexture != nil,
              let latestCameraTransform else { return }
        didPlaceCollectibles = true
        placeCollectibles(relativeTo: latestCameraTransform)
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
            let root = makeCollectible(index: index)
            root.position = [sin(angle) * distance, heights[index % heights.count], -cos(angle) * distance]
            anchor.addChild(root)
        }

        view.scene.addAnchor(anchor)
    }

    private func makeCollectible(index: Int) -> Entity {
        let root = Entity()
        root.name = "collectible-\(index)"
        root.components.set(BillboardComponent())

        if let glowMaterial = material(named: "ARGamePlayingGlow") {
            let glow = ModelEntity(
                mesh: .generatePlane(width: 0.46, height: 0.62),
                materials: [glowMaterial]
            )
            glow.position.z = -0.01
            root.addChild(glow)
        }

        if let cucumberTexture,
           let cucumberMaterial = material(texture: cucumberTexture) {
            let cucumber = ModelEntity(
                mesh: .generatePlane(width: 0.36, height: 0.57),
                materials: [cucumberMaterial]
            )
            cucumber.generateCollisionShapes(recursive: true)
            root.addChild(cucumber)
        }

        return root
    }

    private func material(named name: String) -> UnlitMaterial? {
        guard let texture = try? TextureResource.load(named: name) else { return nil }
        return material(texture: texture)
    }

    private func material(texture: TextureResource) -> UnlitMaterial? {
        var material = UnlitMaterial()
        material.color = .init(tint: .white, texture: .init(texture))
        material.blending = .transparent(opacity: .init(floatLiteral: 1))
        return material
    }

    @objc
    private func didTap(_ recognizer: UITapGestureRecognizer) {
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

    func makeUIView(context: Context) -> ARView {
        controller.start()
        return controller.view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    static func dismantleUIView(_ uiView: ARView, coordinator: Void) {
        uiView.session.pause()
    }
}
