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
        let unique = Dictionary(sites.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var nodes = unique.values.sorted { $0.id < $1.id }.map { site in
            Node(id: "site:\(site.id)", anchor: site.anchor, sites: [site], children: [])
        }
        var candidates = Array(nodes.indices)
        while candidates.count > 1 {
            var nearest = (left: 0, right: 1, distance: Float.infinity)
            // Complete-link distance avoids joining far-apart places through a chain of neighbors.
            for i in candidates.indices {
                for j in candidates.indices.dropFirst(i + 1) {
                    let left = nodes[candidates[i]]
                    let right = nodes[candidates[j]]
                    var distance: Float = 0
                    for a in left.sites {
                        for b in right.sites {
                            distance = max(distance, Self.distance(a.anchor, b.anchor))
                        }
                    }
                    if distance < nearest.distance {
                        nearest = (i, j, distance)
                    }
                }
            }

            let leftIndex = candidates[nearest.left]
            let rightIndex = candidates[nearest.right]
            let left = nodes[leftIndex]
            let right = nodes[rightIndex]
            let members = (left.sites + right.sites).sorted { $0.id < $1.id }
            let anchor = (left.anchor * Float(left.sites.count) + right.anchor * Float(right.sites.count))
                / Float(members.count)
            let key = members.map { "\($0.id.utf8.count):\($0.id)" }.joined()
            nodes.append(Node(id: "group:\(key)", anchor: anchor, sites: members,
                              children: [leftIndex, rightIndex]))
            candidates.remove(at: nearest.right)
            candidates.remove(at: nearest.left)
            candidates.append(nodes.count - 1)
        }
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

    private static func distance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        simd_distance(SIMD2(a.x, a.z), SIMD2(b.x, b.z))
    }
}
