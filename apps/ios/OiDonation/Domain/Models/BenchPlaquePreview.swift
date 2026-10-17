import Foundation

/// Photo coordinates are normalized, with a top-left origin. They belong to
/// one photo/version, never to every bench or every angle of the same bench.
nonisolated struct PlaquePhotoPoint: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
}

nonisolated struct PlaquePhotoPlacement: Codable, Hashable, Sendable {
    var topLeft: PlaquePhotoPoint
    var topRight: PlaquePhotoPoint
    var bottomRight: PlaquePhotoPoint
    var bottomLeft: PlaquePhotoPoint

    var corners: [PlaquePhotoPoint] { [topLeft, topRight, bottomRight, bottomLeft] }
    var isValid: Bool {
        let points = corners
        guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) }) else { return false }
        for i in 0..<4 {
            let a = points[i], b = points[(i + 1) % 4], c = points[(i + 2) % 4]
            let cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
            guard cross > 0.000001 else { return false }
        }
        let twiceArea = (0..<4).reduce(0.0) { sum, i in
            let a = points[i], b = points[(i + 1) % 4]
            return sum + a.x * b.y - b.x * a.y
        }
        return twiceArea > 0.0001
    }

    static let centered = Self(topLeft: .init(x: 0.3, y: 0.4), topRight: .init(x: 0.7, y: 0.4),
                              bottomRight: .init(x: 0.7, y: 0.53), bottomLeft: .init(x: 0.3, y: 0.53))
}

nonisolated struct BenchPlaquePreview: Codable, Equatable, Sendable {
    let assetName: String
    let photoVersion: String
    let placement: PlaquePhotoPlacement
}
