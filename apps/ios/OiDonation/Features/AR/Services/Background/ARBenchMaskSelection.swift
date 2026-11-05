import CoreGraphics
import Foundation

/// Vision instance IDs are local to each frame. Track the selected silhouette
/// by overlap, never by reusing an ID from a previous request.
nonisolated enum ARBenchMaskSelection {
    static func instance(at point: CGPoint, labels: [UInt8], width: Int, height: Int) -> Int? {
        guard width > 0, height > 0, labels.count == width * height,
              point.x >= 0, point.x < 1, point.y >= 0, point.y < 1 else { return nil }
        let id = Int(labels[Int(point.y * CGFloat(height)) * width + Int(point.x * CGFloat(width))])
        return id == 0 ? nil : id
    }

    static func matchingInstance(labels: [UInt8], previous: [Bool]) -> Int? {
        guard labels.count == previous.count else { return nil }
        var area: [UInt8: Int] = [:]
        var intersection: [UInt8: Int] = [:]
        var previousArea = 0
        for (index, id) in labels.enumerated() {
            if id != 0 { area[id, default: 0] += 1 }
            if previous[index] {
                previousArea += 1
                if id != 0 { intersection[id, default: 0] += 1 }
            }
        }
        var best: (id: UInt8, score: Double)?
        for (id, overlap) in intersection {
            let score = Double(overlap) / Double(previousArea + area[id, default: 0] - overlap)
            if score >= 0.2, best == nil || score > best!.score { best = (id, score) }
        }
        return best.map { Int($0.id) }
    }
}
