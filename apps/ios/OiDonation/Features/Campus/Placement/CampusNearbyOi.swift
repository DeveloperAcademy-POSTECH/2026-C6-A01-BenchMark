import Foundation

/// Keep device examples and published stories distinct, even if their UUIDs happen to match.
struct CampusNearbyOi: Identifiable, Hashable {
    enum Source: String, Hashable { case device, shared }
    let placement: CampusPlacement
    let source: Source
    var id: String { source.rawValue + ":" + placement.id.uuidString }
}

/// Rendering defaults for field testing, not a collection/unlock policy.
enum CampusNearbySelection {
    static let enterRadius = CampusLocationQuality.radiusMeters
    static let exitRadius = 35.0
    static let maximumVisible = 12

    static func select(_ items: [CampusNearbyOi], latitude: Double, longitude: Double,
                       accuracy: Double, timestamp: Date, retained: Set<String>, now: Date = Date()) -> [CampusNearbyOi] {
        guard CampusLocationQuality.allowsFix(latitude: latitude, longitude: longitude,
            accuracy: accuracy, timestamp: timestamp, now: now) else { return [] }
        var seen = Set<String>()
        return items.filter {
            guard (try? $0.placement.validated()) != nil, seen.insert($0.id).inserted else { return false }
            return $0.placement.distance(latitude: latitude, longitude: longitude)
                <= (retained.contains($0.id) ? exitRadius : enterRadius)
        }.sorted {
            // Preserve existing anchors at crowded sites instead of swapping them on every noisy fix.
            if retained.contains($0.id) != retained.contains($1.id) { return retained.contains($0.id) }
            let a = $0.placement.distance(latitude: latitude, longitude: longitude)
            let b = $1.placement.distance(latitude: latitude, longitude: longitude)
            return a == b ? $0.id < $1.id : a < b
        }.prefix(maximumVisible).map { $0 }
    }
}
