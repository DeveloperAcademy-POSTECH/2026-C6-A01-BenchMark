import Foundation

nonisolated struct ClipAsset: Codable, Equatable, Sendable {
    let url: URL
    let sha256: String?
}

nonisolated struct ClipCharacter: Codable, Equatable, Identifiable, Sendable {
    var id: String { asset.url.absoluteString + (asset.sha256 ?? "") }
    let name: String
    let heightMeters: Float
    let asset: ClipAsset
}

nonisolated struct ClipStory: Codable, Sendable {
    let id: String
    let benchID: String
    let published: Bool
    let title: String
    let body: String
    let donorDisplayName: String
    let images: [ClipAsset]
    let character: ClipCharacter?

    func validate(route: ClipRoute, configuration: ClipConfiguration) throws {
        guard published else { throw ClipError.unavailable }
        guard ClipRoute.validID(id), ClipRoute.validID(benchID),
              !title.isEmpty, title.count <= 200, body.count <= 20000,
              donorDisplayName.count <= 100, images.count <= 12 else { throw ClipError.invalidResponse }
        switch route {
        case .bench(let expected): guard benchID == expected else { throw ClipError.invalidResponse }
        case .story(let expected): guard id == expected else { throw ClipError.invalidResponse }
        }
        for image in images {
            guard configuration.permits(image.url, hosts: configuration.assetHosts) else { throw ClipError.assetURL }
        }
        if let character {
            guard configuration.permits(character.asset.url, hosts: configuration.assetHosts),
                  character.asset.url.pathExtension.lowercased() == "usdz",
                  character.heightMeters.isFinite, (0.1...3).contains(character.heightMeters),
                  let hash = character.asset.sha256, hash.count == 64,
                  hash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
                throw ClipError.invalidResponse
            }
        }
    }
}
