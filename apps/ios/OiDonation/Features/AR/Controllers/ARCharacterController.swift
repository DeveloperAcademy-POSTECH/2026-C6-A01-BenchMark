import RealityKit
import Foundation

@MainActor
final class ARCharacterController {
    func load(_ character: ARCharacter) async throws -> (root: Entity, model: Entity) {
        let model = try await Entity(named: character.modelFilename)
        try Task.checkCancellation()
        let bounds = model.visualBounds(relativeTo: nil)
        guard bounds.extents.y.isFinite, bounds.extents.y > 0.0001 else {
            throw NSError(domain: "OiDonation", code: 1, userInfo: [NSLocalizedDescriptionKey: "모델의 높이를 계산할 수 없습니다."])
        }
        // 모델의 바닥이 원점에 오도록 배치하고 높이를 1미터로 정규화합니다.
        let normalized = Entity()
        normalized.addChild(model)
        // 정규화 변환을 애니메이션 대상 엔티티 바깥에 적용해 애니메이션의 변환 트랙과 분리합니다.
        let offset = Entity()
        model.removeFromParent()
        normalized.addChild(offset)
        offset.addChild(model)
        offset.position = -SIMD3(bounds.center.x, bounds.min.y, bounds.center.z)
        normalized.scale = SIMD3(repeating: 1 / bounds.extents.y)
        let root = Entity()
        root.addChild(normalized)
        Self.enableGroundingShadows(on: model)
        return (root, model)
    }

    private static func enableGroundingShadows(on entity: Entity) {
        if entity.components[ModelComponent.self] != nil {
            entity.components.set(GroundingShadowComponent(castsShadow: true))
        }
        for child in entity.children { enableGroundingShadows(on: child) }
    }

}
