import Foundation
import CoreGraphics
import simd

@main struct CampusMapLabelChecks {
    static func main() throws {
        let url = URL(fileURLWithPath: CommandLine.arguments[1]).appending(path: "campus-data.json")
        let data = try JSONDecoder().decode(CampusMapData.self, from: Data(contentsOf: url))
        let labels = CampusBuildingLabel.catalog(data)
        precondition(!labels.isEmpty && Set(labels.map(\.id)).count == labels.count)
        for label in labels {
            let building = data.buildings.first { $0.id == label.id }!
            precondition(data.contains(label.anchor, polygon: building.p), "Names must anchor on their own roof, including concave buildings")
            precondition(label.anchor.y > Float(building.modelRoofZ!), "Names use model roof height, not terrain height")
            precondition(!label.title.isEmpty && Double(label.title) == nil)
            precondition(label.roof.count == building.p.count)
        }
        for title in ["C5", "생명공학연구센터", "박태준학술정보관", "지곡회관", "학생회관"] {
            precondition(labels.contains { $0.title == title }, "Missing actual campus building: \(title)")
        }
        let rist = data.buildingLabelGroups!.first { $0.id == "rist-labs" }!
        precondition(rist.name == "RIST 실험동" && Set(rist.buildingIDs).count == 8)
        precondition(CampusBuildingLabel.groups(data).contains { $0.id == rist.id && $0.title == rist.name })
        for id in rist.buildingIDs {
            let original = data.buildings.first { $0.id == id }!
            precondition(original.name?.isEmpty == true, "Shared label must not fabricate an official wing name")
            precondition(labels.first { $0.id == id }?.title == "RIST 실험동")
        }
        precondition(labels.filter { $0.title == "RIST 실험동" }.count == 8)
        precondition(labels.first { $0.id == "294906154" }?.title == "포항산업과학연구원 연구1동",
                     "Southern RIST research buildings must keep their own names")

        // A single C/L-shaped building with multiple POIs must not produce overlapping room names.
        let concave = CampusMapData.Building(id: "concave", p: [[0, 0], [8, 0], [8, 1], [1, 1], [1, 8], [0, 8]],
            name: "테스트관 (Test Hall)", levels: nil, kind: nil, modelRoofZ: 12)
        let unnamed = CampusMapData.Building(id: "unnamed", p: concave.p, name: nil, levels: nil, kind: nil, modelRoofZ: 12)
        let numeric = CampusMapData.Building(id: "number", p: concave.p, name: "101", levels: nil, kind: nil, modelRoofZ: 12)
        let malformed = CampusMapData.Building(id: "malformed", p: [[0], [1, 1], [2, 3]], name: "invalid", levels: nil, kind: nil, modelRoofZ: 12)
        let sample = CampusMapData(coordinateSystem: nil, initialView: nil, origin: [0, 0], unitsPerMeter: 1,
            bounds: [], buildings: [concave, unnamed, numeric, malformed], pois: [], graph: [:])
        let sampleLabels = CampusBuildingLabel.catalog(sample)
        precondition(sampleLabels.count == 1 && sampleLabels[0].title == "테스트관")
        precondition(sample.contains(sampleLabels[0].anchor, polygon: concave.p))
        precondition(CampusBuildingLabel.groups(sample).isEmpty, "Older map data without label groups remains supported")

        typealias Layout = CampusMapLabelLayout
        precondition(Layout.level(pixelsPerUnit: 4, previous: .areas) == .areas)
        precondition(Layout.level(pixelsPerUnit: 7, previous: .areas) == .buildings)
        precondition(Layout.level(pixelsPerUnit: 6, previous: .buildings) == .buildings)
        precondition(Layout.level(pixelsPerUnit: 6, previous: .areas) == .areas, "Small pinch reversals must not flicker")
        precondition(Layout.level(pixelsPerUnit: 5, previous: .buildings) == .areas)
        precondition(Layout.canNameBuilding(footprint: CGRect(x: 0, y: 0, width: 100, height: 40)))
        precondition(!Layout.canNameBuilding(footprint: CGRect(x: 0, y: 0, width: 30, height: 20)))
        precondition(!Layout.canNameBuilding(footprint: CGRect(x: 0, y: 0, width: 100, height: 8)), "A nearly edge-on roof must not get a name")
        precondition(!Layout.canNameBuilding(footprint: .null))

        let viewport = CGRect(x: 0, y: 100, width: 400, height: 500)
        let first = CGRect(x: 100, y: 200, width: 80, height: 20)
        let alternate = CGRect(x: 100, y: 260, width: 80, height: 20)
        let items: [Layout.Candidate] = [
            .init(id: "landmark", frame: first),
            .init(id: "overlap", frame: first.offsetBy(dx: 20, dy: 0)),
            .init(id: "header", frame: CGRect(x: 20, y: 80, width: 80, height: 20)),
            .init(id: "area", frame: first, alternatives: [alternate]),
            .init(id: "button", frame: CGRect(x: 300, y: 500, width: 70, height: 20))
        ]
        let placements = Layout.placements(items, viewport: viewport,
            obstacles: [CGRect(x: 300, y: 480, width: 80, height: 80)])
        precondition(placements == ["landmark": first, "area": alternate], "Names avoid markers, controls, other names and clipped edges")
        precondition(Layout.placements(items, viewport: .zero, obstacles: []).isEmpty)
        print("Campus map labels: PASS (\(labels.count) named roofs, concave anchors, zoom hysteresis, footprint visibility, collision layout)")

        let groundedMap = try CampusMapData.load(from: url)
        // Exercise the six shipped overview POIs using the bundled map and height field.
        let sites = ["97", "72", "88", "75", "7", "53"].map { id in
            let place = groundedMap.pois.first { $0.id == id }!
            return CampusRegionClustering.Site(id: id, anchor: groundedMap.world(place.p))
        }
        checkProjection(sites)
        checkClustering(sites)
        checkTiltClustering()
        checkSettling(sites)
        checkZoomMotion()
        checkPanMotion()
    }

    private static func checkProjection(_ sites: [CampusRegionClustering.Site]) {
        let viewport = CGRect(x: 10, y: 20, width: 400, height: 800)
        let center = CGPoint(x: viewport.midX, y: viewport.midY)
        let map = CampusMapProjection(eye: .zero, yaw: 0, pitch: 0, verticalFOV: 90, viewport: viewport)
        precondition(abs(map.focalLength - 400) < 0.01)
        precondition(close(map.point(SIMD3(0, 0, -10)), to: center), "The view axis must land at the viewport center")
        precondition(close(map.point(SIMD3(2, 1, -10)), to: CGPoint(x: 290, y: 380)), "Projection must preserve perspective and UIKit's downward y axis")
        precondition(map.point(SIMD3(0, 0, 10)) == nil, "An anchor behind the camera must not be mirrored")
        precondition(map.point(.zero) == nil, "An anchor in the camera plane must not be projected")
        precondition(map.point(SIMD3(.nan, 0, -10)) == nil)
        let rotated = CampusMapProjection(eye: .zero, yaw: .pi / 2, pitch: 0, verticalFOV: 90, viewport: viewport)
        precondition(close(rotated.point(SIMD3(-10, 0, 0)), to: center), "The orbit yaw must rotate the projection with the map")

        for site in sites {
            let anchor = site.anchor
            let pitch: Float = 1.02
            let eye = anchor + SIMD3(0, sin(pitch), cos(pitch)) * 120
            let centered = CampusMapProjection(eye: eye, yaw: 0, pitch: pitch, verticalFOV: 42, viewport: viewport)
            precondition(close(centered.point(anchor), to: center), "POI \(site.id) must project at its own ground location")
            let offset = SIMD3<Float>(12, 0, 0)
            let panned = CampusMapProjection(eye: eye + offset, yaw: 0, pitch: pitch, verticalFOV: 42, viewport: viewport)
            let expected = CGPoint(x: center.x - 12 * centered.focalLength / 120, y: center.y)
            precondition(close(panned.point(anchor), to: expected), "The marker must move with its fixed map location during a pan")
        }

        let opacity = CampusMapProjection.panelOpacity
        precondition(opacity(0.35) == 1 && opacity(1.4) == 0)
        let tilt = (0...100).map { opacity(0.84 + Float($0) * 0.0022) }
        precondition(tilt[50] > 0 && tilt[50] < 1, "The two shapes must overlap during the tilt transition")
        precondition(zip(tilt, tilt.dropFirst()).allSatisfy { previous, next in
            previous >= next && previous - next < 0.02
        }, "The shape mix must change continuously with camera tilt")
        print("Campus map projection: PASS (\(sites.count) real POI anchors, pan, yaw, camera clipping, tilt crossfade)")
    }

    private static func close(_ point: CGPoint?, to expected: CGPoint, tolerance: CGFloat = 0.01) -> Bool {
        guard let point else { return false }
        return abs(point.x - expected.x) < tolerance && abs(point.y - expected.y) < tolerance
    }

    private static func checkClustering(_ campusSites: [CampusRegionClustering.Site]) {
        typealias Cluster = CampusRegionClustering
        let sites: [Cluster.Site] = [
            .init(id: "a", anchor: SIMD3(0, 0, 0)),
            .init(id: "b", anchor: SIMD3(10, 4, 0))
        ]
        let counts = ["a": 2, "b": 3]
        let clustering = Cluster(sites: sites)
        let focalLength: CGFloat = 950
        func markers(_ radius: Float, reduceMotion: Bool = false) -> [Cluster.Marker] {
            clustering.markers(radius: radius, focalLength: focalLength, reduceMotion: reduceMotion)
        }
        let wide = markers(200).filter(\.isInteractive)
        precondition(wide.count == 1 && wide[0].node.siteIDs == ["a", "b"])
        precondition(wide[0].node.siteIDs.map { counts[$0]! }.reduce(0, +) == 5, "The merged marker must carry both counts")
        precondition(wide[0].anchor == SIMD3(5, 2, 0), "A merged marker must have a stable world anchor")
        let closeUp = markers(20).filter(\.isInteractive)
        for site in sites {
            let marker = closeUp.first { $0.node.siteIDs == [site.id] }
            precondition(marker?.anchor == site.anchor, "Split markers must return to their exact original anchors")
        }
        let targetRadius = clustering.expandedRadius(for: wide[0].node, focalLength: focalLength)
        precondition(markers(targetRadius).filter(\.isInteractive).count == 2, "Zooming into a merged marker must expose its children")

        let radii = (40...400).map { Float($0) / 2 }
        let frames = radii.map { markers($0) }
        let reversedFrames = radii.reversed().map { markers($0) }
        var sawTransition = false
        for (forward, backward) in zip(frames, reversedFrames.reversed()) {
            let ordered = forward.sorted { $0.node.id < $1.node.id }
            let reversed = backward.sorted { $0.node.id < $1.node.id }
            precondition(ordered.count == reversed.count)
            for (a, b) in zip(ordered, reversed) {
                precondition(a.node.id == b.node.id && a.anchor == b.anchor && a.opacity == b.opacity
                    && a.isInteractive == b.isInteractive, "A pinch must retrace exactly the same marker positions and opacity when reversed")
            }
            let active = forward.filter(\.isInteractive).flatMap { $0.node.siteIDs }.sorted()
            precondition(active == ["a", "b"], "Hit testing must represent each region once throughout the transition")
            if forward.contains(where: { $0.node.siteIDs.count > 1 && $0.opacity > 0 && $0.opacity < 1 }),
               let child = forward.first(where: { $0.node.siteIDs == ["a"] && $0.opacity > 0 && $0.opacity < 1 }) {
                precondition(child.anchor.x > 0 && child.anchor.x < 5, "Children must travel from the cluster to their geographic sites")
                sawTransition = true
            }
        }
        precondition(sawTransition, "The split must have intermediate visible positions")
        for (first, next) in zip(frames, frames.dropFirst()) {
            let nextByID = Dictionary(uniqueKeysWithValues: next.map { ($0.node.id, $0) })
            for marker in first {
                guard let match = nextByID[marker.node.id], marker.opacity > 0, match.opacity > 0 else { continue }
                precondition(simd_distance(marker.anchor, match.anchor) < 0.5 && abs(marker.opacity - match.opacity) < 0.05,
                    "Small zoom changes must not snap the anchor or opacity")
            }
        }
        for radius in radii {
            let visible = markers(radius, reduceMotion: true).filter { $0.opacity > 0 }
            precondition(visible.allSatisfy { $0.anchor == $0.node.anchor && $0.opacity == 1 }, "Reduce Motion must skip marker travel and fades")
            precondition(visible.flatMap { $0.node.siteIDs }.sorted() == ["a", "b"])
        }

        let campus = Cluster(sites: campusSites)
        let reordered = Cluster(sites: Array(campusSites.reversed()))
        let campusRadii: [Float] = [20, 70, 140, 305, 600]
        for radius in campusRadii {
            let active = campus.markers(radius: radius, focalLength: focalLength, reduceMotion: false).filter(\.isInteractive)
            precondition(active.flatMap { $0.node.siteIDs }.sorted() == campusSites.map(\.id).sorted())
            precondition(Set(active.map { $0.node.id }) == Set(reordered.markers(radius: radius, focalLength: focalLength,
                reduceMotion: false).filter(\.isInteractive).map { $0.node.id }), "The campus layout must have stable identities independent of input order")
            if radius == 20 { precondition(active.count == campusSites.count) }
            if radius == 600 { precondition(active.count < campusSites.count, "Zooming out must consolidate nearby campus regions") }
        }
        precondition(Cluster(sites: []).markers(radius: 305, focalLength: focalLength, reduceMotion: false).isEmpty)
        print("Campus map clustering: PASS (sum, \(campusSites.count) real POIs, pinch reversal, continuity, Reduce Motion, hit testing)")
    }

    private static func checkTiltClustering() {
        let clustering = CampusRegionClustering(sites: [
            .init(id: "far", anchor: SIMD3(0, 0, -10)),
            .init(id: "near", anchor: SIMD3(0, 0, 10))
        ])
        let radius: Float = 120
        let viewport = CGRect(x: 0, y: 0, width: 400, height: 800)
        func projection(pitch: Float, pan: Float = 0) -> CampusMapProjection {
            let eye = SIMD3(pan, sin(pitch) * radius, cos(pitch) * radius)
            return CampusMapProjection(eye: eye, yaw: 0, pitch: pitch, verticalFOV: 42, viewport: viewport)
        }
        func active(in view: CampusMapProjection, at distance: Float) -> [CampusRegionClustering.Marker] {
            clustering.markers(radius: distance, focalLength: view.focalLength, reduceMotion: false,
                separation: view.planeSeparation).filter(\.isInteractive)
        }

        let shallow = projection(pitch: 0.35)
        let merged = active(in: shallow, at: radius)
        precondition(merged.count == 1 && merged[0].node.siteIDs == ["far", "near"],
            "Depth-aligned places must cluster when foreshortened by a shallow camera")
        let overhead = projection(pitch: 1.4)
        precondition(Set(active(in: overhead, at: radius).map { $0.node.siteIDs }) == Set([["far"], ["near"]]),
            "The same places must separate at an overhead pitch without changing zoom")

        let panned = projection(pitch: 0.35, pan: 15)
        let pannedMarkers = active(in: panned, at: radius)
        precondition(pannedMarkers.map { $0.node.id } == merged.map { $0.node.id } && pannedMarkers[0].anchor == merged[0].anchor,
            "Panning must preserve cluster membership and its geographic anchor")
        precondition(panned.point(merged[0].anchor)!.x < shallow.point(merged[0].anchor)!.x,
            "The same anchor must move across the screen with the map during a pan")
        let expanded = clustering.expandedRadius(for: merged[0].node, focalLength: shallow.focalLength,
            separation: shallow.planeSeparation)
        precondition(active(in: shallow, at: expanded).count == 2, "Cluster tap zoom must respect the same shallow projection")
        print("Campus map tilt clustering: PASS (3D foreshortening, overhead separation, pan-stable grouping, tap zoom)")
    }

    private static func checkSettling(_ campusSites: [CampusRegionClustering.Site]) {
        typealias Cluster = CampusRegionClustering
        let limits: ClosedRange<Float> = 20...600
        let focalLength: CGFloat = 950
        let pair = Cluster(sites: [.init(id: "a", anchor: .zero), .init(id: "b", anchor: SIMD3(10, 0, 0))])
        precondition(pair.settledRadius(for: 95, within: limits, focalLength: focalLength) < 88)
        precondition(pair.settledRadius(for: 105, within: limits, focalLength: focalLength) > 112)
        precondition(pair.settledRadius(for: 40, within: limits, focalLength: focalLength) == 40)
        precondition(pair.settledRadius(for: 800, within: limits, focalLength: focalLength) == 600)
        precondition(pair.settledRadius(for: 10, within: limits, focalLength: focalLength) == 20)

        let boundaryPairs = [Float(2), 60].map { distance in
            Cluster(sites: [.init(id: "a", anchor: .zero), .init(id: "b", anchor: SIMD3(distance, 0, 0))])
        }
        for (group, radius) in zip(boundaryPairs, [limits.lowerBound, limits.upperBound]) {
            let settled = group.settledRadius(for: radius, within: limits, focalLength: focalLength)
            precondition(limits.contains(settled) && settled != radius, "A transition at either zoom limit must settle inward")
            precondition(group.markers(radius: settled, focalLength: focalLength, reduceMotion: false).allSatisfy { $0.opacity == 1 })
        }
        let overlapping = Cluster(sites: [
            .init(id: "a", anchor: SIMD3(0, 0, 0)), .init(id: "b", anchor: SIMD3(10, 0, 0)),
            .init(id: "c", anchor: SIMD3(100, 0, 0)), .init(id: "d", anchor: SIMD3(111, 0, 0))
        ])
        let groups = [pair, overlapping, Cluster(sites: campusSites)] + boundaryPairs
        let viewport = CGRect(x: 0, y: 0, width: 400, height: 800)
        let pitches: [Float] = [0.35, 0.95, 1.4]
        for group in groups {
            let ids = group.nodes.last!.siteIDs
            for pitch in pitches {
                let projection = CampusMapProjection(eye: .zero, yaw: 0.61, pitch: pitch, verticalFOV: 42, viewport: viewport)
                for radius in stride(from: Float(20), through: 600, by: 5) {
                    let settled = group.settledRadius(for: radius, within: limits, focalLength: focalLength,
                        separation: projection.planeSeparation)
                    let markers = group.markers(radius: settled, focalLength: focalLength, reduceMotion: false,
                        separation: projection.planeSeparation)
                    precondition(limits.contains(settled) && settled.isFinite)
                    precondition(markers.allSatisfy { $0.opacity == 1 && $0.isInteractive && $0.anchor == $0.node.anchor },
                        "Release must finish every overlapping transition at an opaque geographic anchor")
                    precondition(markers.flatMap { $0.node.siteIDs }.sorted() == ids, "Settling must preserve all counts without duplicate hit targets")
                    precondition(group.settledRadius(for: settled, within: limits, focalLength: focalLength,
                        separation: projection.planeSeparation) == settled, "An already settled zoom must remain fixed")
                }
            }
        }
        print("Campus map settling: PASS (nearest stable zoom, overlapping bands, min/max boundaries, 3 camera pitches)")
    }

    private static func checkZoomMotion() {
        typealias Motion = CampusMapMotion
        let limits: ClosedRange<Float> = 20...600
        let lower = log(limits.lowerBound)
        let upper = log(limits.upperBound)
        let inputs = (0...400).map { lower - 2 + Float($0) * (upper - lower + 4) / 400 }
        let radii = inputs.map { Motion.resistedRadius(logRadius: $0, within: limits) }
        precondition(radii.allSatisfy { $0.isFinite && $0 > 16 && $0 < 720 }, "Overzoom must remain bounded beyond both camera limits")
        precondition(zip(radii, radii.dropFirst()).allSatisfy { first, next in first < next },
            "Pinching farther must keep moving with increasing resistance")
        for (input, radius) in zip(inputs, radii) {
            let resumed = Motion.inputLogRadius(for: radius, within: limits)
            precondition(abs(resumed - input) < 0.001, "Re-grabbing a resisted radius must preserve the original pinch input")
            let reversed = Motion.resistedRadius(logRadius: resumed - 0.04 + 0.04, within: limits)
            precondition(abs(log(reversed / radius)) < 0.00001, "A reversed pinch must return to the displayed radius")
        }
        for boundary in [lower, upper] {
            let before = Motion.resistedRadius(logRadius: boundary - 0.0001, within: limits)
            let after = Motion.resistedRadius(logRadius: boundary + 0.0001, within: limits)
            precondition(abs(log(after / before)) < 0.0002, "Crossing a zoom boundary must have no position discontinuity")
        }
        precondition(abs(Motion.resistedRadius(logRadius: log(100), within: limits) - 100) < 0.0001)
        precondition(abs(Motion.releaseVelocity(1, logRadius: lower - 1, within: limits)) < 1)
        precondition(Motion.releaseVelocity(1, logRadius: log(100), within: limits) == 1)
        precondition(Motion.releaseVelocity(.infinity, logRadius: lower, within: limits) == 0)

        for (origin, destination) in [(Float(17), Float(20)), (700, 600), (95, 87.9), (105, 112.2)] {
            let spring = Motion.Spring(from: origin, to: destination)
            let first = spring.sample(at: 0)
            precondition(abs(first.radius - origin) < 0.0001 && first.progress == 0 && !first.isComplete,
                "Release must start from the last displayed radius")
            let frames60 = (0...60).map { spring.sample(at: Double($0) / 60) }
            let frames120 = (0...120).map { spring.sample(at: Double($0) / 120) }
            for (index, sample) in frames60.enumerated() {
                precondition(sample.radius == frames120[index * 2].radius, "Spring position must be independent of display refresh rate")
                precondition(sample.radius >= min(origin, destination) - 0.001 && sample.radius <= max(origin, destination) + 0.001)
            }
            precondition(frames60.last!.radius == destination && frames60.last!.progress == 1 && frames60.last!.isComplete,
                "Spring return must finish at the exact destination")
            let interrupted = spring.sample(at: 0.08).radius
            let input = Motion.inputLogRadius(for: interrupted, within: limits)
            precondition(abs(Motion.resistedRadius(logRadius: input, within: limits) - interrupted) < 0.001,
                "Re-grabbing during spring return must preserve the displayed radius")
        }
        let outward = Motion.Spring(from: 100, to: 80, velocity: 1)
        let inward = Motion.Spring(from: 100, to: 80, velocity: -1)
        precondition(outward.sample(at: 0).radius == inward.sample(at: 0).radius)
        precondition(outward.sample(at: 0.01).radius > 100 && inward.sample(at: 0.01).radius < 100,
            "The first spring frames must preserve release direction")
        precondition(outward.sample(at: 1).radius == 80 && inward.sample(at: 1).radius == 80)
        print("Campus map zoom motion: PASS (elastic limits, inverse re-grab, reversal, release velocity, 60/120Hz spring return)")
    }

    private static func checkPanMotion() {
        typealias Motion = CampusMapMotion
        let stretch: Float = 20
        let inputs: [SIMD3<Float>] = [
            SIMD3(-320, 7, 0), SIMD3(310, 7, 0), SIMD3(0, 7, -380), SIMD3(0, 7, 350),
            SIMD3(-320, 7, -380), SIMD3(-320, 7, 350), SIMD3(310, 7, -380), SIMD3(310, 7, 350)
        ]
        for input in inputs {
            let bounded = Motion.clampedTarget(input)
            let displayed = Motion.resistedTarget(input, stretch: stretch)
            precondition(displayed.y == input.y && bounded.y == input.y, "Panning must preserve terrain height")
            precondition(abs(displayed.x - bounded.x) < stretch && abs(displayed.z - bounded.z) < stretch,
                "Every map edge and corner must have finite elastic travel")
            precondition(simd_distance(Motion.inputTarget(for: displayed, stretch: stretch), input) < 0.02,
                "The elastic map position must have a continuous inverse for re-grabbing")

            // A pinch may change the camera radius before a new one-finger segment.
            let zoomRadii: [Float] = [20, 100, 600]
            for radius in zoomRadii {
                let resumedStretch = Motion.panStretch(radius: radius, target: displayed)
                let resumed = Motion.inputTarget(for: displayed, stretch: resumedStretch)
                precondition(simd_distance(Motion.resistedTarget(resumed, stretch: resumedStretch), displayed) < 0.001,
                    "Rebasing after a simultaneous zoom must preserve the displayed map position")
            }
        }

        let interior = SIMD3<Float>(25, 7, 25)
        precondition(Motion.clampedTarget(interior) == interior && Motion.resistedTarget(interior, stretch: stretch) == interior)
        let xs = (-320...310).map { Motion.resistedTarget(SIMD3(Float($0), 7, 25), stretch: stretch).x }
        let zs = (-380...350).map { Motion.resistedTarget(SIMD3(25, 7, Float($0)), stretch: stretch).z }
        for values in [xs, zs] {
            precondition(zip(values, values.dropFirst()).allSatisfy { previous, next in next > previous },
                "Dragging farther toward an edge must move continuously in the same direction")
        }
        for boundary in [SIMD3<Float>(-120, 7, 0), SIMD3(110, 7, 0), SIMD3(0, 7, -180), SIMD3(0, 7, 150)] {
            let before = Motion.resistedTarget(boundary - SIMD3(0.001, 0, 0.001), stretch: stretch)
            let after = Motion.resistedTarget(boundary + SIMD3(0.001, 0, 0.001), stretch: stretch)
            precondition(simd_distance(before, after) < 0.003, "Crossing a map boundary must not jump")
        }
        let velocity = SIMD3<Float>(10, 9, -12)
        precondition(Motion.targetVelocity(velocity, input: interior, stretch: stretch) == SIMD3(10, 0, -12))
        let resisted = Motion.targetVelocity(velocity, input: SIMD3(310, 7, -380), stretch: stretch)
        precondition(resisted.x > 0 && resisted.x < velocity.x && resisted.z < 0 && resisted.z > velocity.z && resisted.y == 0,
            "Release speed must preserve direction and lose energy at both edges of a corner")
        let extreme = Motion.targetVelocity(SIMD3(1e9, 0, -1e9), input: interior, stretch: stretch)
        precondition(extreme.x.isFinite && extreme.z.isFinite && abs(extreme.x) <= stretch * 18 && abs(extreme.z) <= stretch * 18,
            "An extreme fling must retain a bounded release speed on both map axes")

        let origin = Motion.resistedTarget(SIMD3(310, 7, -380), stretch: stretch)
        let destination = Motion.clampedTarget(origin)
        let spring = Motion.Spring(from: 100, to: 100)
        let release = SIMD3<Float>(30, 0, -40)
        func position(at elapsed: TimeInterval, velocity: SIMD3<Float>) -> SIMD3<Float> {
            let sample = spring.sample(at: elapsed)
            return origin + (destination - origin) * sample.progress + velocity * sample.velocityFactor
        }
        precondition(position(at: 0, velocity: release) == origin && spring.sample(at: 0).velocityFactor == 0,
            "Map bounce must begin from the displayed corner")
        let early = position(at: 0.001, velocity: release)
        precondition(early.x > origin.x && early.z < origin.z, "The first return frame must carry the release velocity")
        for frame in 0...60 {
            let time60 = Double(frame) / 60
            let time120 = Double(frame * 2) / 120
            precondition(position(at: time60, velocity: release) == position(at: time120, velocity: release),
                "Map bounce must use the same world position at 60Hz and 120Hz")
        }
        precondition(position(at: 1, velocity: release) == destination && spring.sample(at: 1).velocityFactor == 0,
            "Both axes must finish exactly at their map boundaries")
        print("Campus map pan motion: PASS (4 edges, 4 corners, inverse re-grab, zoom rebasing, release velocity, 60/120Hz)")
    }
}
