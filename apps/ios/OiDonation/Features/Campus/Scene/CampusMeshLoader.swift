import Foundation
import RealityKit
import UIKit

/// Prepare immutable geometry off the main actor, then upload a bounded batch to RealityKit.
@MainActor enum CampusMeshLoader {
    enum Failure: Error { case invalidAsset }

    static func load(url: URL, mapData: CampusMapData? = nil) async throws -> Entity {
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("CampusGeometry-v1", isDirectory: true)
        let preparation = Task.detached(priority: .userInitiated) {
            try CampusMeshPreparation.load(url: url, mapData: mapData, cacheDirectory: cache)
        }
        let asset = try await withTaskCancellationHandler {
            try await preparation.value
        } onCancel: { preparation.cancel() }
        try Task.checkCancellation()
        #if DEBUG
        print("CAMPUS_PREPARATION cache=\(asset.cacheHit) seconds=\(asset.elapsed) tiles=\(asset.tiles.count)")
        #endif
        let root = Entity(); root.name = "POSTECH v09 native campus"
        var materials: [SIMD4<Float>: SimpleMaterial] = [:]
        func attach(_ result: (Int, MeshResource, SIMD4<Float>)) {
            let (i, mesh, c) = result
            let material: SimpleMaterial
            if let cached = materials[c] { material = cached }
            else {
                func srgb(_ v: Float) -> CGFloat { CGFloat(v <= 0.0031308 ? v*12.92 : 1.055*pow(v,1/2.4)-0.055) }
                material = SimpleMaterial(color: UIColor(red: srgb(c.x), green: srgb(c.y), blue: srgb(c.z), alpha: CGFloat(c.w)), roughness: 0.75, isMetallic: false)
                materials[c] = material
            }
            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.name = "campus-tile-\(i)"
            if CampusMeshPreparation.isVegetation(c) {
                entity.components.set(DynamicLightShadowComponent(castsShadow: false))
            }
            root.addChild(entity)
        }
        try await withThrowingTaskGroup(of: (Int, MeshResource, SIMD4<Float>).self) { group in
            var pending = 0
            for tile in asset.tiles {
                try Task.checkCancellation()
                var descriptor = MeshDescriptor(name: "Campus tile \(tile.index)")
                descriptor.positions = MeshBuffers.Positions(tile.positions)
                descriptor.normals = MeshBuffers.Normals(tile.normals)
                descriptor.primitives = .triangles(tile.indices)
                let frozen = descriptor
                group.addTask { (tile.index, try await MeshResource(from: [frozen]), tile.color) }
                pending += 1
                if pending >= 4, let result = try await group.next() { attach(result); pending -= 1 }
            }
            while let result = try await group.next() { attach(result) }
        }
        return root
    }
}
