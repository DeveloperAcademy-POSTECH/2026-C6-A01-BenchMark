//
//  CampusRegionClustering.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/4/26.
//

import Foundation
import simd

/// Builds a stable geographic hierarchy, then reveals it directly from the camera radius.
struct CampusRegionClustering {
    struct Site {
        let id: String
        let anchor: SIMD3<Float>
    }

    struct Node {
        let id: String
        let anchor: SIMD3<Float>
        fileprivate let sites: [Site]
        fileprivate let children: [Int]

        var siteIDs: [String] { sites.map(\.id) }
    }

    struct Marker {
        let node: Node
        let anchor: SIMD3<Float>
        let opacity: CGFloat
        let isInteractive: Bool
    }

    let nodes: [Node]

    private static let targetSpacing: Float = 95
    private static let splitStart: Float = 1.12
    private static let splitEnd: Float = 0.88

    init(sites: [Site]) {
        let valid = sites.filter { $0.anchor.x.isFinite && $0.anchor.y.isFinite && $0.anchor.z.isFinite }
        let unique = Dictionary(valid.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var nodes: [Node] = []
        // A balanced spatial hierarchy keeps construction bounded as the public feed grows.
        // Equal positions stay together at every zoom; their bubble still opens every story.
        @discardableResult func append(_ groups: [[Site]]) -> Int {
            let members = groups.flatMap { $0 }.sorted { $0.id < $1.id }
            let anchor = members.reduce(SIMD3<Float>.zero) { $0 + $1.anchor / Float(members.count) }
            let key = members.map { "\($0.id.utf8.count):\($0.id)" }.joined()
            var children: [Int] = []
            let xs = groups.map { $0[0].anchor.x }, zs = groups.map { $0[0].anchor.z }
            let dx = (xs.max() ?? 0) - (xs.min() ?? 0)
            let dz = (zs.max() ?? 0) - (zs.min() ?? 0)
            if groups.count > 1 {
                let axis = dx >= dz ? 0 : 2
                let ordered = groups.sorted {
                    let a = $0[0], b = $1[0]
                    return a.anchor[axis] == b.anchor[axis] ? a.id < b.id : a.anchor[axis] < b.anchor[axis]
                }
                let middle = ordered.count / 2
                children = [append(Array(ordered[..<middle])), append(Array(ordered[middle...]))]
            }
            let id = members.count == 1 ? "site:\(members[0].id)" : "group:\(key)"
            nodes.append(Node(id: id, anchor: anchor, sites: members, children: children))
            return nodes.count - 1
        }
        let positions = Dictionary(grouping: unique.values) { SIMD2($0.anchor.x, $0.anchor.z) }
        let groups = positions.values.map { $0.sorted { $0.id < $1.id } }
        if !groups.isEmpty { append(groups) }
        self.nodes = nodes
    }

    func markers(radius: Float, focalLength: CGFloat, reduceMotion: Bool,
                 separation: ((SIMD3<Float>, SIMD3<Float>) -> Float)? = nil) -> [Marker] {
        guard radius.isFinite, radius > 0, focalLength.isFinite, focalLength > 0,
              let root = nodes.indices.last else { return [] }
        let zoomScale = Float(focalLength) / Self.targetSpacing
        let spans = splitSpans(separation: separation ?? Self.distance)
        var result: [Marker] = []
        func append(_ index: Int, anchor: SIMD3<Float>, opacity: CGFloat, interactive: Bool) {
            let node = nodes[index]
            let splitRadius = spans[index] * zoomScale
            let progress = splitRadius > 0
                ? Self.smoothstep((Self.splitStart - radius / splitRadius) / (Self.splitStart - Self.splitEnd))
                : 0
            let showsChildren = progress >= 0.5
            let reveal = reduceMotion ? (showsChildren ? Float(1) : 0) : progress
            if reveal < 1 {
                result.append(Marker(node: node, anchor: anchor, opacity: opacity * CGFloat(1 - reveal),
                                     isInteractive: interactive && !showsChildren))
            }
            if reveal > 0 {
                for child in node.children {
                    let site = nodes[child].anchor
                    let position = reveal == 1 ? site : anchor + (site - anchor) * reveal
                    append(child, anchor: position, opacity: opacity * CGFloat(reveal),
                           interactive: interactive && showsChildren)
                }
            }
        }
        append(root, anchor: nodes[root].anchor, opacity: 1, interactive: true)
        return result
    }

    func expandedRadius(for node: Node, focalLength: CGFloat,
                        separation: ((SIMD3<Float>, SIMD3<Float>) -> Float)? = nil) -> Float {
        guard let index = nodes.firstIndex(where: { $0.id == node.id }) else { return 0 }
        let spans = splitSpans(separation: separation ?? Self.distance)
        return spans[index] * (Float(focalLength) / Self.targetSpacing) * Self.splitEnd
    }

    func settledRadius(for radius: Float, within limits: ClosedRange<Float>, focalLength: CGFloat,
                       separation: ((SIMD3<Float>, SIMD3<Float>) -> Float)? = nil) -> Float {
        let clamped = min(limits.upperBound, max(limits.lowerBound, radius))
        guard clamped > 0, clamped.isFinite, focalLength > 0, focalLength.isFinite else { return clamped }
        let scale = Float(focalLength) / Self.targetSpacing
        let bands = splitSpans(separation: separation ?? Self.distance).compactMap { span -> ClosedRange<Float>? in
            let threshold = span * scale
            guard threshold > 0, threshold.isFinite else { return nil }
            return (threshold * Self.splitEnd)...(threshold * Self.splitStart)
        }
        guard bands.contains(where: { clamped > $0.lowerBound && clamped < $0.upperBound }) else {
            return clamped
        }

        // A sibling may still be transitioning at another node's endpoint. Check
        // every candidate against all bands before choosing one destination.
        let safeBands = bands.map { ($0.lowerBound * 0.999)...($0.upperBound * 1.001) }
        let candidates = [limits.lowerBound, limits.upperBound] + safeBands.flatMap { [$0.lowerBound, $0.upperBound] }
        let stable = candidates.filter { candidate in
            limits.contains(candidate) && !safeBands.contains(where: {
                candidate > $0.lowerBound && candidate < $0.upperBound
            })
        }
        return stable.min { abs(log($0 / clamped)) < abs(log($1 / clamped)) } ?? clamped
    }

    private func splitSpans(separation: (SIMD3<Float>, SIMD3<Float>) -> Float) -> [Float] {
        var spans: [Float] = []
        spans.reserveCapacity(nodes.count)
        for node in nodes {
            guard let left = node.children.first, let right = node.children.last else {
                spans.append(0)
                continue
            }
            // Separate the pair before either child begins its own split.
            let childSpan = max(spans[left], spans[right]) * Self.splitStart / Self.splitEnd
            let visibleSpan = separation(nodes[left].anchor, nodes[right].anchor)
            spans.append(max(visibleSpan, childSpan))
        }
        return spans
    }

    static func smoothstep(_ value: Float) -> Float {
        let clamped = min(1, max(0, value))
        return clamped * clamped * (3 - 2 * clamped)
    }

    private nonisolated static func distance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        simd_distance(SIMD2(a.x, a.z), SIMD2(b.x, b.z))
    }
}
