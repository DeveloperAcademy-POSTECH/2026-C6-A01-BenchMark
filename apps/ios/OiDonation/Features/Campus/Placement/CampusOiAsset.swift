// Created by 이돈혁

import RealityKit
import Foundation

@MainActor enum CampusOiAsset {
    private static var cached: Entity?
    /// Normalized to one metre with the feet at the origin, shared by map and AR.
    static func load() async throws -> Entity {
        if let cached { return cached.clone(recursive: true) }
        guard let url = Bundle.main.url(forResource: "helmet-oi", withExtension: "usdz") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let imported = try await Entity(contentsOf: url)
        try Task.checkCancellation()
        let bounds = imported.visualBounds(relativeTo: nil)
        guard bounds.extents.y.isFinite, bounds.extents.y > 0.0001 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let normalized = Entity(), offset = Entity()
        offset.addChild(imported)
        offset.position = -SIMD3(bounds.center.x, bounds.min.y, bounds.center.z)
        normalized.addChild(offset)
        normalized.scale = SIMD3(repeating: 1 / bounds.extents.y)
        let root = Entity()
        root.addChild(normalized)
        let size = bounds.extents / bounds.extents.y
        root.components.set(CollisionComponent(shapes: [.generateBox(size: size)
            .offsetBy(translation: SIMD3(0, 0.5, 0))]))
        cached = root
        return root.clone(recursive: true)
    }
    static func heading(_ degrees: Double) -> simd_quatf {
        // Imported helmet-oi faces +Z; north is -Z in the ENU/AR world frame.
        simd_quatf(angle: Float(.pi - degrees * .pi / 180), axis: [0, 1, 0])
    }
}
