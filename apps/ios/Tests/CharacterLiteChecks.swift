import Foundation
import RealityKit
import CryptoKit

@main struct CharacterLiteChecks {
    struct Manifest: Decodable { let models: [Model] }
    struct Model: Decodable {
        let name: String
        let file: String
        let originalBytes: Int
        let optimizedBytes: Int
        let sourceSHA256: String
        let sha256: String
        let complianceExitCode: Int
    }
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let lite = root.appendingPathComponent("RemoteAssets/CharactersLite")
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: lite.appendingPathComponent("manifest.json")))
        for model in manifest.models {
            let original = root.appendingPathComponent("OiDonation/Resources/Characters/\(model.name).usdz")
            let output = lite.appendingPathComponent(model.file)
            func hash(_ file: URL) throws -> String {
                SHA256.hash(data: try Data(contentsOf: file, options: .mappedIfSafe)).map { String(format: "%02x", $0) }.joined()
            }
            precondition(tryHash(original) == model.sourceSHA256, "Original changed")
            precondition(tryHash(output) == model.sha256, "Output checksum changed")
            precondition(model.optimizedBytes < model.originalBytes && model.optimizedBytes < 5_000_000)
            precondition(model.complianceExitCode == 0, "USD validation failed")
            let sourceEntity = try await Entity(contentsOf: original)
            let resultEntity = try await Entity(contentsOf: output)
            let a = sourceEntity.visualBounds(relativeTo: nil)
            let b = resultEntity.visualBounds(relativeTo: nil)
            for index in 0..<3 {
                precondition(b.extents[index].isFinite && abs(a.extents[index]-b.extents[index]) <= max(0.001, a.extents[index]*0.02), "Bounds changed")
            }
            func animations(_ entity: Entity) -> Int {
                entity.availableAnimations.count + entity.children.reduce(0) { $0 + animations($1) }
            }
            precondition(animations(sourceEntity) == animations(resultEntity), "Animation count changed")
            print("PASS: \(model.name) RealityKit load, bounds, animations, SHA and size (\(model.optimizedBytes) bytes)")
            func tryHash(_ url: URL) -> String { (try? hash(url)) ?? "" }
        }
    }
}
