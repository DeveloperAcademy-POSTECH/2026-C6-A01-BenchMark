//
//  ARPostcardPrototypeView.swift
//  OiDonationClip
//
//  Created by Jiwon Hong on 11/9/26.
//

#if DEBUG
import ARKit
import AVFoundation
import CoreMotion
import RealityKit
import simd
import SwiftUI
import UIKit

struct ARPostcardPrototypeView: View {
    private enum Stage {
        case checkingCamera, locating, ready, denied, unsupported, interrupted, artworkUnavailable

        var showsCamera: Bool { self == .locating || self == .ready }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var stage = Stage.checkingCamera
    @State private var cameraAttempt = 0
    @State private var placedCount = 0
    @State private var isComplete = false
    private let onCompleted: () -> Void

    /// `onCompleted` is called once, shortly after the last piece locks into place.
    init(onCompleted: @escaping () -> Void = {}) {
        self.onCompleted = onCompleted
    }

    var body: some View {
        ZStack {
            if stage.showsCamera {
                PostcardCameraView {
                    if stage == .locating { stage = .ready }
                } onPlaced: { count in
                    placedCount = count
                    if count == ARPostcardPuzzleLayout.tileCount { isComplete = true }
                } onInterrupted: {
                    if stage.showsCamera, !isComplete { stage = .interrupted }
                } onArtworkUnavailable: {
                    if stage.showsCamera { stage = .artworkUnavailable }
                }
                .ignoresSafeArea()
            }

            VStack {
                Button("닫기", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderedProminent)
                    .frame(minWidth: 44, minHeight: 44)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()

                VStack(spacing: 8) {
                    switch stage {
                    case .checkingCamera:
                        ProgressView("카메라를 확인하고 있어요")
                    case .locating:
                        ProgressView("기기를 정면으로 들고 주변을 천천히 비춰 주세요")
                    case .ready:
                        Text("\(placedCount) / \(ARPostcardPuzzleLayout.tileCount)")
                            .font(.headline.monospacedDigit())
                        if isComplete {
                            Text("퍼즐을 완성했어요!")
                            Text("엽서를 펼치고 있어요").font(.footnote).foregroundStyle(.secondary)
                        } else {
                            Text("주변 조각을 보드로 옮겨 엽서를 맞춰 보세요")
                        }
                    case .denied:
                        Text("AR 보드를 보려면 카메라 접근을 허용해 주세요")
                        Button("설정 열기") {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            openURL(url)
                        }
                        .buttonStyle(.borderedProminent)
                    case .unsupported:
                        Text("AR을 지원하는 iPhone에서 실행해 주세요")
                    case .artworkUnavailable:
                        Text("엽서 이미지를 불러오지 못했어요")
                        Button("다시 시작", action: retry)
                            .buttonStyle(.borderedProminent)
                    case .interrupted:
                        Text("AR 카메라를 다시 시작해 주세요")
                        Button("다시 시작", action: retry)
                            .buttonStyle(.borderedProminent)
                    }
                }
                .multilineTextAlignment(.center)
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
            .padding()
        }
        .task(id: cameraAttempt) {
            guard ARWorldTrackingConfiguration.isSupported else {
                stage = .unsupported
                return
            }

            let authorized: Bool
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: authorized = true
            case .notDetermined: authorized = await AVCaptureDevice.requestAccess(for: .video)
            default: authorized = false
            }
            guard !Task.isCancelled else { return }
            stage = authorized ? .locating : .denied
        }
        .task(id: stage) {
            guard stage == .locating else { return }
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            guard stage == .locating, !Task.isCancelled else { return }
            stage = .interrupted
        }
        .task(id: isComplete) {
            // Keep the finished board visible briefly so the last snap registers before the AR view closes.
            guard isComplete else { return }
            do { try await Task.sleep(for: .milliseconds(800)) } catch { return }
            guard !Task.isCancelled else { return }
            onCompleted()
        }
        .onChange(of: scenePhase) { _, phase in
            guard !isComplete else { return }
            if phase == .background, stage.showsCamera {
                stage = .interrupted
            } else if phase == .active, stage == .denied,
                      AVCaptureDevice.authorizationStatus(for: .video) == .authorized {
                retry()
            }
        }
    }

    private func retry() {
        guard !isComplete else { return }
        placedCount = 0
        stage = .checkingCamera
        cameraAttempt += 1
    }
}

private struct PostcardCameraView: UIViewRepresentable {
    let onReady: () -> Void
    let onPlaced: (Int) -> Void
    let onInterrupted: () -> Void
    let onArtworkUnavailable: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onReady: onReady, onPlaced: onPlaced, onInterrupted: onInterrupted,
            onArtworkUnavailable: onArtworkUnavailable
        )
    }

    func makeUIView(context: Context) -> RealityKit.ARView {
        let view = RealityKit.ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        context.coordinator.start(in: view)
        return view
    }

    func updateUIView(_ uiView: RealityKit.ARView, context: Context) {}

    static func dismantleUIView(_ uiView: RealityKit.ARView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator: NSObject, ARSessionDelegate {
        private struct Drag {
            let index: Int
            let start: SIMD3<Float>
            let offset: SIMD3<Float>
            var screenPoint: CGPoint
        }

        private enum ArtworkError: Error { case invalidImage }

        private let onReady: () -> Void
        private let onPlaced: (Int) -> Void
        private let onInterrupted: () -> Void
        private let onArtworkUnavailable: () -> Void
        private let layout = ARPostcardPuzzleLayout()
        private let motion = CMMotionManager()
        private let impactFeedback = UIImpactFeedbackGenerator(style: .soft)
        private let tileThickness: Float = 0.008
        private var tileDepth: Float { tileThickness / 2 }
        private var tileSurface: Float { tileThickness + 0.0005 }
        private weak var view: RealityKit.ARView?
        private var board: Entity?
        private var artworkTask: Task<Void, Never>?
        private var materials: [UnlitMaterial]?
        private var tiles: [ModelEntity] = []
        private var placed: Set<Int> = []
        private var activeDrag: Drag?
        private var velocities: [SIMD2<Float>] = []
        private var lastFrameTime: TimeInterval?
        private var lastMotionSampleTime: TimeInterval?
        private var lastImpulseTime: TimeInterval?
        private var lastShakeTime: TimeInterval?

        init(
            onReady: @escaping () -> Void,
            onPlaced: @escaping (Int) -> Void,
            onInterrupted: @escaping () -> Void,
            onArtworkUnavailable: @escaping () -> Void
        ) {
            self.onReady = onReady
            self.onPlaced = onPlaced
            self.onInterrupted = onInterrupted
            self.onArtworkUnavailable = onArtworkUnavailable
        }

        func start(in view: RealityKit.ARView) {
            self.view = view
            let drag = UIPanGestureRecognizer(target: self, action: #selector(dragPiece(_:)))
            drag.maximumNumberOfTouches = 1
            view.addGestureRecognizer(drag)

            view.session.delegate = self
            view.session.delegateQueue = .main
            let configuration = ARWorldTrackingConfiguration()
            configuration.worldAlignment = .gravity
            view.session.run(configuration)
            artworkTask = Task { [weak self] in
                do {
                    let materials = try await Self.loadMaterials()
                    guard !Task.isCancelled else { return }
                    self?.materials = materials
                } catch {
                    guard !Task.isCancelled else { return }
                    self?.onArtworkUnavailable()
                }
            }
        }

        func stop() {
            guard let view else { return }
            self.view = nil
            artworkTask?.cancel()
            artworkTask = nil
            motion.stopDeviceMotionUpdates()
            view.session.delegate = nil
            view.session.pause()
            view.scene.anchors.removeAll()
            board = nil
            materials = nil
            tiles.removeAll()
            placed.removeAll()
            activeDrag = nil
            velocities.removeAll()
            lastFrameTime = nil
            lastMotionSampleTime = nil
            lastImpulseTime = nil
            lastShakeTime = nil
        }

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            guard let view, !view.bounds.isEmpty else { return }

            if let board {
                let elapsed = Float(frame.timestamp - (lastFrameTime ?? frame.timestamp))
                lastFrameTime = frame.timestamp
                updateLooseTiles(frame: frame, board: board, elapsed: elapsed)
                moveDraggedTile(in: view, relativeTo: board)
                return
            }

            guard let materials, case .normal = frame.camera.trackingState else { return }
            let orientation = view.window?.windowScene?.effectiveGeometry.interfaceOrientation ?? .portrait
            let worldToCamera: simd_float4x4
            if #available(iOS 27.0, *) {
                guard let angle = session.viewRotationAngle else { return }
                worldToCamera = frame.camera.viewMatrix(viewRotationAngle: angle)
            } else {
                worldToCamera = frame.camera.viewMatrix(for: orientation)
            }

            let distance: Float = view.bounds.width > view.bounds.height ? 1.72 : 1.18
            let transform = ARPostcardPuzzleLayout.trayAnchorTransform(
                cameraToWorld: worldToCamera.inverse, distance: distance
            )
            let anchor = AnchorEntity(world: transform)
            let board = makeTray()
            board.orientation = ARPostcardPuzzleLayout.initialTrayTilt(
                cameraBackY: frame.camera.transform.columns.2.y
            )
            lastFrameTime = frame.timestamp
            let tileSize = SIMD3(layout.tileWidth, layout.tileHeight, tileThickness)
            let tileMesh = MeshResource.generateBox(size: tileSize)
            let faceMesh = MeshResource.generatePlane(width: layout.tileWidth, height: layout.tileHeight)
            let edge = SimpleMaterial(color: UIColor(red: 0.89, green: 0.84, blue: 0.71, alpha: 1),
                                      roughness: 0.86, isMetallic: false)
            let tileCollision = ShapeResource.generateBox(size: tileSize)

            for (material, start) in zip(materials, layout.startingPositions.shuffled()) {
                let piece = ModelEntity(mesh: tileMesh, materials: [edge])
                let face = ModelEntity(mesh: faceMesh, materials: [material])
                face.position.z = tileSurface - tileDepth
                piece.addChild(face)
                piece.position = SIMD3(start, tileDepth)
                piece.collision = CollisionComponent(shapes: [tileCollision])
                board.addChild(piece)
                tiles.append(piece)
            }

            anchor.addChild(board)
            view.scene.addAnchor(anchor)
            self.board = board
            self.materials = nil
            velocities = Array(repeating: .zero, count: tiles.count)
            if motion.isDeviceMotionAvailable {
                motion.deviceMotionUpdateInterval = 1 / 60
                motion.startDeviceMotionUpdates()
            }
            onReady()
        }

        private func makeTray() -> Entity {
            let tray = Entity()
            let lipWidth = layout.lipWidth
            let lipHeight: Float = 0.016
            let baseDepth: Float = 0.012
            let outerWidth = layout.boardWidth + 2 * lipWidth
            let outerHeight = layout.boardHeight + 2 * lipWidth
            let surface = SimpleMaterial(color: UIColor(red: 0.70, green: 0.59, blue: 0.45, alpha: 1),
                                         roughness: 0.9, isMetallic: false)
            let rim = SimpleMaterial(color: UIColor(red: 0.84, green: 0.72, blue: 0.54, alpha: 1),
                                     roughness: 0.85, isMetallic: false)
            let base = ModelEntity(
                mesh: .generateBox(size: [outerWidth, outerHeight, baseDepth], cornerRadius: 0.004),
                materials: [surface]
            )
            base.position.z = -baseDepth / 2
            tray.addChild(base)

            let lipDepth = lipHeight + 0.004
            let sideMesh = MeshResource.generateBox(
                size: [lipWidth, outerHeight, lipDepth], cornerRadius: 0.003
            )
            let endMesh = MeshResource.generateBox(
                size: [layout.boardWidth, lipWidth, lipDepth], cornerRadius: 0.003
            )
            for sign: Float in [-1, 1] {
                let side = ModelEntity(mesh: sideMesh, materials: [rim])
                side.position = [sign * (layout.boardWidth + lipWidth) / 2, 0, lipHeight - lipDepth / 2]
                tray.addChild(side)

                let end = ModelEntity(mesh: endMesh, materials: [rim])
                end.position = [0, sign * (layout.boardHeight + lipWidth) / 2, lipHeight - lipDepth / 2]
                tray.addChild(end)
            }
            return tray
        }

        private func updateLooseTiles(frame: ARFrame, board: Entity, elapsed: Float) {
            guard activeDrag == nil, placed.count < tiles.count else { return }

            if let sample = motion.deviceMotion, lastMotionSampleTime != sample.timestamp {
                lastMotionSampleTime = sample.timestamp
                if frame.timestamp - (lastImpulseTime ?? -.infinity) >= 0.18 {
                    applyShake(sample.userAcceleration, frame: frame, board: board)
                }
            }

            guard velocities.contains(where: { $0 != .zero }) else { return }
            var positions = tileCenters()
            layout.slideTiles(positions: &positions, velocities: &velocities, locked: placed, elapsed: elapsed)
            for index in tiles.indices where !placed.contains(index) {
                tiles[index].position = SIMD3(positions[index], tileDepth)
            }
        }

        private func applyShake(_ acceleration: CMAcceleration, frame: ARFrame, board: Entity) {
            let deviceAcceleration = SIMD3(Float(acceleration.x), Float(acceleration.y), Float(acceleration.z))
            guard simd_length_squared(deviceAcceleration) >= 0.55 * 0.55 else { return }

            // Core Motion reports the device axes in portrait, independent of interface rotation.
            let portraitView: simd_float4x4
            if #available(iOS 27.0, *) {
                portraitView = frame.camera.viewMatrix(viewRotationAngle: 90)
            } else {
                portraitView = frame.camera.viewMatrix(for: .portrait)
            }
            let worldAcceleration = portraitView.inverse * SIMD4(deviceAcceleration, 0)
            let local = board.convert(direction: [worldAcceleration.x, worldAcceleration.y, worldAcceleration.z], from: nil)
            let planar = SIMD2(local.x, local.y)
            let strength = simd_length(planar)
            guard strength >= 0.25 else { return }

            let kick = -planar / strength * min(0.68, 0.24 + 0.40 * strength)
            let across = SIMD2(-kick.y, kick.x)
            for index in tiles.indices where !placed.contains(index) {
                velocities[index] = kick * Float.random(in: 0.82...1.07) + across * Float.random(in: -0.22...0.22)
            }
            if frame.timestamp - (lastShakeTime ?? -.infinity) >= 0.35 {
                impactFeedback.impactOccurred(intensity: 0.30)
            }
            lastShakeTime = frame.timestamp
            lastImpulseTime = frame.timestamp
        }

        private static func loadMaterials() async throws -> [UnlitMaterial] {
            guard let image = UIImage(named: "ARPostcardSample")?.cgImage else { throw ArtworkError.invalidImage }

            var materials: [UnlitMaterial] = []
            for index in 0..<ARPostcardPuzzleLayout.tileCount {
                try Task.checkCancellation()
                let crop = ARPostcardPuzzleLayout.crop(for: index, imageWidth: image.width, imageHeight: image.height)
                guard let tile = image.cropping(to: crop) else { throw ArtworkError.invalidImage }

                let texture = try await TextureResource(image: tile, options: .init(semantic: .color))
                var material = UnlitMaterial()
                material.color = .init(tint: .white, texture: .init(texture))
                material.blending = .transparent(opacity: .init(floatLiteral: 1))
                materials.append(material)
            }
            return materials
        }

        func sessionWasInterrupted(_ session: ARSession) {
            if view != nil { onInterrupted() }
        }

        func session(_ session: ARSession, didFailWithError error: Error) {
            if view != nil { onInterrupted() }
        }

        @objc
        private func dragPiece(_ gesture: UIPanGestureRecognizer) {
            guard let view, let board else { return }
            let point = gesture.location(in: view)

            switch gesture.state {
            case .began:
                let translation = gesture.translation(in: view)
                let touchDown = CGPoint(x: point.x - translation.x, y: point.y - translation.y)
                guard let hitEntity = view.entity(at: touchDown),
                      let index = tiles.firstIndex(where: { $0 === hitEntity }),
                      !placed.contains(index),
                      let hit = pointOnPiecePlane(at: touchDown, in: view, relativeTo: board)
                else { return }
                let start = tiles[index].position
                velocities = Array(repeating: .zero, count: tiles.count)
                impactFeedback.prepare()
                activeDrag = Drag(index: index, start: start, offset: start - hit, screenPoint: point)
                moveDraggedTile(in: view, relativeTo: board)
            case .changed:
                activeDrag?.screenPoint = point
                moveDraggedTile(in: view, relativeTo: board)
            case .ended:
                let drop = pointOnPiecePlane(at: point, in: view, relativeTo: board)
                finishDrag(at: drop)
            case .cancelled, .failed:
                finishDrag(at: nil)
            default:
                break
            }
        }

        private func moveDraggedTile(in view: RealityKit.ARView, relativeTo board: Entity) {
            guard let drag = activeDrag,
                  let hit = pointOnPiecePlane(at: drag.screenPoint, in: view, relativeTo: board) else { return }
            let position = hit + drag.offset
            tiles[drag.index].position = [position.x, position.y, tileDepth + 0.012]
        }

        private func finishDrag(at drop: SIMD3<Float>?) {
            guard let drag = activeDrag else { return }
            activeDrag = nil
            let tile = tiles[drag.index]
            guard let drop else {
                tile.position = drag.start
                return
            }

            let position = drop + drag.offset
            let center = SIMD2(position.x, position.y)
            let target = layout.cellCenter(for: drag.index)
            let positions = tileCenters()
            if layout.matchesCell(for: drag.index, at: center) {
                tile.position = SIMD3(target, tileDepth)
                tile.components.remove(CollisionComponent.self)
                placed.insert(drag.index)
                lastImpulseTime = lastFrameTime
                impactFeedback.impactOccurred(intensity: 0.55)
                if placed.count == tiles.count { motion.stopDeviceMotionUpdates() }
                onPlaced(placed.count)
            } else if layout.canRestOutsideBoard(drag.index, at: center, among: positions) {
                tile.position = SIMD3(center, tileDepth)
            } else {
                tile.position = drag.start
            }
        }

        private func tileCenters() -> [SIMD2<Float>] {
            tiles.map { SIMD2($0.position.x, $0.position.y) }
        }

        private func pointOnPiecePlane(
            at point: CGPoint, in view: RealityKit.ARView, relativeTo board: Entity
        ) -> SIMD3<Float>? {
            guard let frame = view.session.currentFrame, case .normal = frame.camera.trackingState,
                  let ray = view.ray(through: point) else { return nil }
            let origin = board.convert(position: ray.origin, from: nil)
            let direction = board.convert(direction: ray.direction, from: nil)
            guard abs(direction.z) > 0.001 else { return nil }
            let distance = (tileSurface - origin.z) / direction.z
            guard (0...4).contains(distance) else { return nil }
            return [origin.x + direction.x * distance, origin.y + direction.y * distance, tileSurface]
        }
    }
}
#endif
