//
//  CampusStoryModels.swift
//  OiDonation
//
//  Created by Codex on 11/11/26.
//

import RealityKit
import Foundation

/// Public map characters share bundled meshes/textures, but keep their own world transform.
@MainActor final class CampusStoryModels {
    private struct Record {
        let resource: String
        let position: SIMD3<Float>
    }
    private var records: [String: Record] = [:]
    private var models: [String: Entity] = [:]
    private var templates: [String: Entity] = [:]
    private var failures: Set<String> = []
    private var visibleIDs: Set<String> = []
    private var layer = Entity()
    private var loading: Task<Void, Never>?
    private var generation = UUID()
    var onChange: (() -> Void)?

    // These are public preset IDs, not private draft wardrobe data. Presets without
    // an authored 3D equivalent use a neutral Oi, never a camera-facing portrait.
    static func resource(for asset: String) -> String {
        switch asset {
        case "OiCats", "OiCatsPortrait": return "wardrobe-costume-cat-bear"
        case "OiGardener": return "wardrobe-costume-farmer"
        default:
            if let costume = OiWardrobeLook.Costume.allCases.first(where: {
                asset == $0.modelName || asset == $0.thumbnailName
            }) { return costume.modelName }
            return "wardrobe-tshirt-long"
        }
    }

    func setStories(_ stories: [CampusStory], positions: [String: SIMD3<Float>]) {
        cancelLoading()
        var next: [String: Record] = [:]
        for story in stories {
            guard let position = positions[story.id] else { continue }
            next[story.id] = Record(resource: Self.resource(for: story.image), position: position)
        }
        for id in Array(models.keys) where next[id]?.resource != records[id]?.resource {
            models.removeValue(forKey: id)?.removeFromParent()
        }
        records = next
        let needed = Set(next.values.map(\.resource))
        templates = templates.filter { needed.contains($0.key) }
        failures.removeAll()
        visibleIDs.formIntersection(next.keys)
        for (id, model) in models { if let record = next[id] { model.position = record.position } }
    }

    func attach(to root: Entity) {
        suspend()
        layer = Entity()
        layer.name = "CampusStoryModels"
        root.addChild(layer)
    }

    func suspend() {
        cancelLoading()
        visibleIDs.removeAll()
        layer.removeFromParent()
        layer.children.removeAll()
        models.removeAll()
    }

    func update(visible ids: Set<String>, opacity: Float, height: Float) {
        visibleIDs = ids
        layer.components.set(OpacityComponent(opacity: opacity))
        for (id, model) in models { model.isEnabled = ids.contains(id) }
        guard layer.parent != nil else { return }
        for id in ids {
            guard let record = records[id] else { continue }
            if models[id] == nil, let template = templates[record.resource] {
                let model = template.clone(recursive: true)
                model.name = "campus.story.\(id)"
                model.position = record.position
                // Authored +Z front stays fixed in world space as the camera orbits.
                layer.addChild(model)
                models[id] = model
            }
            models[id]?.scale = SIMD3(repeating: height)
        }
        loadNextVisibleResource()
    }

    func isReady(_ id: String) -> Bool { models[id] != nil }
    func hasFailed(_ id: String) -> Bool { records[id].map { failures.contains($0.resource) } ?? false }
    func retry(_ id: String) {
        if let record = records[id] { failures.remove(record.resource) }
        loadNextVisibleResource()
        onChange?()
    }

    private func cancelLoading() {
        generation = UUID()
        loading?.cancel()
        loading = nil
    }

    private func loadNextVisibleResource() {
        guard loading == nil, layer.parent != nil else { return }
        let resources = Set(visibleIDs.compactMap { records[$0]?.resource })
        guard let resource = resources.sorted().first(where: {
            templates[$0] == nil && !failures.contains($0)
        }) else { return }
        let started = generation
        // Serial loading avoids decoding all high-resolution wardrobe textures at once.
        // Offscreen/overview stories stay metadata-only until they become visible.
        loading = Task { [weak self] in
            do {
                let imported = try await Entity(contentsOf: OiWardrobeAsset.url(resource, folder: "Wardrobe"))
                try Task.checkCancellation()
                let bounds = imported.visualBounds(relativeTo: nil)
                guard bounds.extents.y.isFinite, bounds.extents.y > 0.001 else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                let offset = Entity()
                offset.addChild(imported)
                offset.position = -SIMD3(bounds.center.x, bounds.min.y, bounds.center.z)
                let normalized = Entity()
                normalized.addChild(offset)
                normalized.scale = SIMD3(repeating: 1 / bounds.extents.y)
                let template = Entity()
                template.addChild(normalized)
                guard let self, self.generation == started else { return }
                self.templates[resource] = template
                self.loading = nil
                self.onChange?()
                self.loadNextVisibleResource()
            } catch {
                guard let self, self.generation == started, !Task.isCancelled else { return }
                self.failures.insert(resource)
                self.loading = nil
                self.onChange?()
                self.loadNextVisibleResource()
            }
        }
    }
}
