import UIKit

/// A noninteractive screen-space layer. Labels follow roof coordinates as the camera moves.
@MainActor final class CampusMapLabels {
    private struct Entry {
        let id: String
        let anchor: SIMD3<Float>
        let roof: [SIMD3<Float>]
        let label: CampusMapNameLabel
    }
    private var areas: [Entry] = []
    private var buildings: [Entry] = []
    private var level = CampusMapLabelLayout.Level.areas
    private var enabled = false
    private var insets = UIEdgeInsets.zero
    private var controls: [CGRect] = []
    private weak var host: UIView?

    func configure(data: CampusMapData, in host: UIView) {
        self.host = host
        (areas + buildings).forEach { $0.label.removeFromSuperview() }
        areas = CampusRegion.campus.compactMap { region in
            guard let place = data.pois.first(where: { $0.id == region.placeID }) else { return nil }
            return entry(id: "area.\(region.id)", title: region.title,
                         point: data.world(place.p), roof: [], size: 13)
        }
        areas += CampusBuildingLabel.groups(data).map {
            entry(id: "area.\($0.id)", title: $0.title, point: $0.anchor, roof: $0.roof, size: 13)
        }
        let landmarks = Set(data.pois.filter { ["53", "72", "83", "88", "7", "58"].contains($0.id) }.compactMap(\.buildingId))
        buildings = CampusBuildingLabel.catalog(data).filter { $0.id != CampusEducationDistrict.retiredBuildingID }.sorted {
            if landmarks.contains($0.id) != landmarks.contains($1.id) { return landmarks.contains($0.id) }
            return $0.id < $1.id
        }.map { entry(id: "building.\($0.id)", title: $0.title, point: $0.anchor, roof: $0.roof, size: 11) }
    }

    func setPresentation(enabled: Bool, insets: UIEdgeInsets, controls: [CGRect]) {
        self.enabled = enabled; self.insets = insets; self.controls = controls
        if !enabled { (areas + buildings).forEach { $0.label.isHidden = true } }
    }

    private func entry(id: String, title: String, point: SIMD3<Float>, roof: [SIMD3<Float>], size: CGFloat) -> Entry {
        let label = CampusMapNameLabel()
        label.text = title; label.font = .systemFont(ofSize: size, weight: .semibold)
        label.accessibilityIdentifier = "campus.label.\(id)"
        label.sizeToFit(); label.bounds.size.width += 6; label.bounds.size.height += 6
        label.isHidden = true; host?.addSubview(label)
        return Entry(id: id, anchor: point, roof: roof, label: label)
    }

    func update(projection: CampusMapProjection, viewport bounds: CGRect, radius: Float, pins: [UIView]) {
        guard enabled, radius > 0 else { return }
        let density = projection.focalLength / CGFloat(radius)
        level = CampusMapLabelLayout.level(pixelsPerUnit: density, previous: level)
        let active = level == .areas ? areas : buildings
        let inactive = level == .areas ? buildings : areas
        inactive.forEach { $0.label.isHidden = true }
        let viewport = bounds.inset(by: insets).insetBy(dx: 8, dy: 5)
        let visiblePins = pins.filter { !$0.isHidden && $0.alpha > 0.25 }
        var candidates: [CampusMapLabelLayout.Candidate] = []
        for item in active {
            item.label.isHidden = true
            guard let point = projection.point(item.anchor) else { continue }
            if level == .buildings {
                let points = item.roof.compactMap(projection.point)
                guard points.count == item.roof.count, let first = points.first else { continue }
                var footprint = CGRect(origin: first, size: .zero)
                for point in points { footprint = footprint.union(CGRect(origin: point, size: .zero)) }
                guard CampusMapLabelLayout.canNameBuilding(footprint: footprint) else { continue }
            }
            var frame = CGRect(x: point.x - item.label.bounds.width / 2,
                               y: point.y - item.label.bounds.height - 4, width: item.label.bounds.width, height: item.label.bounds.height)
            var alternatives: [CGRect] = []
            if level == .areas,
               let pin = visiblePins.first(where: { $0.accessibilityIdentifier == item.id.replacingOccurrences(of: "area.", with: "campus.region.") }) {
                // Keep the caption below its individual region badge when space allows.
                frame.origin = CGPoint(x: pin.frame.midX - frame.width / 2, y: pin.frame.maxY + 9)
                alternatives = [
                    CGRect(x: frame.minX, y: pin.frame.minY - frame.height - 9, width: frame.width, height: frame.height),
                    CGRect(x: pin.frame.minX - frame.width - 9, y: pin.frame.midY - frame.height / 2, width: frame.width, height: frame.height),
                    CGRect(x: pin.frame.maxX + 9, y: pin.frame.midY - frame.height / 2, width: frame.width, height: frame.height),
                    frame.offsetBy(dx: -pin.frame.width / 2, dy: 0),
                    frame.offsetBy(dx: pin.frame.width / 2, dy: 0)
                ]
            } else if level == .areas {
                // A compound has no story-count marker. If its center is clipped,
                // anchor its caption to a visible member roof rather than hide the whole area.
                let memberPoints = item.roof.compactMap(projection.point).sorted { hypot($0.x - point.x, $0.y - point.y) < hypot($1.x - point.x, $1.y - point.y) }
                let options = ([point] + memberPoints).filter { viewport.contains($0) }.flatMap { anchor -> [CGRect] in
                    let x = min(max(anchor.x - frame.width / 2, viewport.minX + 4), viewport.maxX - frame.width - 4)
                    return [CGRect(x: x, y: anchor.y - frame.height - 4, width: frame.width, height: frame.height),
                            CGRect(x: x, y: anchor.y + 8, width: frame.width, height: frame.height)]
                }
                guard let first = options.first else { continue }
                frame = first; alternatives = Array(options.dropFirst())
            }
            candidates.append(.init(id: item.id, frame: frame, alternatives: alternatives))
        }
        let accepted = CampusMapLabelLayout.placements(candidates, viewport: viewport, obstacles: visiblePins.map(\.frame) + controls)
        for item in active {
            if let frame = accepted[item.id] { item.label.frame = frame; item.label.isHidden = false }
        }
    }

}

@MainActor private final class CampusMapNameLabel: UILabel {
    override init(frame: CGRect) {
        super.init(frame: frame)
        textColor = UIColor(red: 0.19, green: 0.25, blue: 0.15, alpha: 1)
        textAlignment = .center
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        backgroundColor = .clear
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func drawText(in rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let textRect = rect.insetBy(dx: 3, dy: 3)
        let foreground = textColor
        context.saveGState()
        context.setLineWidth(3); context.setLineJoin(.round); context.setTextDrawingMode(.stroke)
        textColor = UIColor.white.withAlphaComponent(0.9)
        super.drawText(in: textRect)
        context.setTextDrawingMode(.fill); textColor = foreground
        super.drawText(in: textRect)
        context.restoreGState()
    }
}
