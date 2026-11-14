//
//  OiSeedCucumberAppearance.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/9/26.
//

import CoreGraphics

enum OiSeedCucumberPart: String, CaseIterable, Identifiable {
    case eyes, mouth, stem, body

    static let faceParts: [Self] = [.eyes, .mouth]

    var id: Self { self }

    var title: String {
        switch self {
        case .eyes: "눈"
        case .mouth: "입"
        case .stem: "꼭지"
        case .body: "몸체"
        }
    }
}

enum OiSeedCucumberLayer: CaseIterable {
    case leftEye, rightEye, mouth, stem

    var part: OiSeedCucumberPart {
        switch self {
        case .leftEye, .rightEye: .eyes
        case .mouth: .mouth
        case .stem: .stem
        }
    }

    var asset: String {
        switch self {
        case .leftEye: "SeedCucumberLeftEye"
        case .rightEye: "SeedCucumberRightEye"
        case .mouth: "SeedCucumberMouth"
        case .stem: "SeedCucumberStem"
        }
    }

    // Pixel coordinates of the registered crops in the original artwork.
    var sourceFrame: CGRect {
        switch self {
        case .leftEye: CGRect(x: 452, y: 414, width: 51, height: 53)
        case .rightEye: CGRect(x: 570, y: 451, width: 54, height: 54)
        case .mouth: CGRect(x: 484, y: 485, width: 98, height: 68)
        case .stem: CGRect(x: 500, y: 39, width: 187, height: 143)
        }
    }

    static let faceLayers: [Self] = [.leftEye, .rightEye, .mouth]
}

struct OiSeedCucumberAppearance: Codable, Equatable, Sendable {
    static let sourceSize = CGSize(width: 1058, height: 1658)
    // Ground line of the visible body artwork, excluding transparent padding.
    static let bodyPivot = CGPoint(x: sourceSize.width / 2, y: 1549)
    static let stemBase = CGPoint(x: 549, y: 164)
    static let stemDefaultTip = CGPoint(x: 650, y: 79)
    static let sizeRange: ClosedRange<CGFloat> = 0.5...2
    static let horizontalRange: ClosedRange<CGFloat> = -80...80
    static let eyeSpacingRange: ClosedRange<CGFloat> = 0.70...1.30
    static let minimumEyeMouthGap: CGFloat = 20
    private static let verticalRange: ClosedRange<CGFloat> = -110...140
    static let lengthRange: ClosedRange<CGFloat> = 0.5...1.65
    static let angleRange: ClosedRange<CGFloat> = -130...35
    static let heightRange: ClosedRange<CGFloat> = 0.85...1.20
    static let widthRange: ClosedRange<CGFloat> = 0.90...1.30

    struct Face: Codable, Equatable, Sendable {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var size: CGFloat = 1
    }

    private var eyes = Face()
    private var mouth = Face()
    var eyeSpacing: CGFloat = 1
    var stemLength: CGFloat = 1
    var stemAngle: CGFloat = 0
    var bodyHeight: CGFloat = 1 {
        didSet {
            eyes.y = min(eyes.y, faceVerticalRange(for: .eyes).upperBound)
        }
    }
    var bodyWidth: CGFloat = 1

    subscript(part: OiSeedCucumberPart) -> Face {
        get {
            switch part {
            case .eyes: eyes
            case .mouth: mouth
            case .stem, .body: Face()
            }
        }
        set {
            let face = Face(x: Self.clamp(newValue.x, to: Self.horizontalRange),
                            y: Self.clamp(newValue.y, to: faceVerticalRange(for: part)),
                            size: Self.clamp(newValue.size, to: Self.sizeRange))
            if part == .eyes { eyes = face }
            else if part == .mouth { mouth = face }
        }
    }

    func faceVerticalRange(for part: OiSeedCucumberPart) -> ClosedRange<CGFloat> {
        let range = Self.verticalRange
        // The eye stagger stays fixed when the body stretches, unlike the group and mouth centers.
        let eyeStagger = OiSeedCucumberLayer.rightEye.sourceFrame.midY - Self.eyePairCenter.y
        let centerSeparation = OiSeedCucumberLayer.mouth.sourceFrame.midY - Self.eyePairCenter.y
        let minimumOffset = (eyeStagger + Self.minimumEyeMouthGap) / bodyHeight - centerSeparation
        switch part {
        case .eyes: return range.lowerBound...Self.clamp(mouth.y - minimumOffset, to: range)
        case .mouth: return Self.clamp(eyes.y + minimumOffset, to: range)...range.upperBound
        case .stem, .body: return range
        }
    }

    var bodyTransform: CGAffineTransform {
        let pivot = Self.bodyPivot
        return CGAffineTransform(a: bodyWidth, b: 0, c: 0, d: bodyHeight,
                                 tx: pivot.x * (1 - bodyWidth), ty: pivot.y * (1 - bodyHeight))
    }

    var bodyFrame: CGRect { CGRect(origin: .zero, size: Self.sourceSize).applying(bodyTransform) }

    func faceFrame(_ layer: OiSeedCucumberLayer) -> CGRect {
        let crop = layer.sourceFrame
        let face = self[layer.part]
        let center = CGPoint(x: crop.midX, y: crop.midY)
        let anchor = layer.part == .eyes ? Self.eyePairCenter : center
        let moved = CGPoint(x: anchor.x + face.x, y: anchor.y + face.y).applying(bodyTransform)
        let width = crop.width * face.size
        let height = crop.height * face.size
        let spacing = layer.part == .eyes ? eyeSpacing : 1
        // Resize each eye around its own center independently of the spacing control.
        return CGRect(x: moved.x + (center.x - anchor.x) * spacing - width / 2,
                      y: moved.y + center.y - anchor.y - height / 2,
                      width: width, height: height)
    }

    private static let eyePairCenter: CGPoint = {
        let left = OiSeedCucumberLayer.leftEye.sourceFrame
        let right = OiSeedCucumberLayer.rightEye.sourceFrame
        return CGPoint(x: (left.midX + right.midX) / 2, y: (left.midY + right.midY) / 2)
    }()
    private static let stemVector = CGPoint(x: stemDefaultTip.x - stemBase.x, y: stemDefaultTip.y - stemBase.y)
    private static let stemAxis = atan2(stemVector.y, stemVector.x)

    var stemAttachment: CGPoint { Self.stemBase.applying(bodyTransform) }

    var stemWarp: OiSeedCucumberStemWarp {
        OiSeedCucumberStemWarp(attachment: stemAttachment, length: stemLength, angle: stemAngle)
    }

    func stemPoint(for source: CGPoint) -> CGPoint {
        stemWarp.point(for: source)
    }

    var stemTip: CGPoint { stemPoint(for: Self.stemDefaultTip) }

    mutating func moveStemTip(to tip: CGPoint) {
        let attachment = stemAttachment
        let x = tip.x - attachment.x
        let y = tip.y - attachment.y
        let distance = hypot(x, y)
        stemLength = Self.clamp(distance / hypot(Self.stemVector.x, Self.stemVector.y), to: Self.lengthRange)
        // Keep the last angle below the base so crossing it cannot flip the stem.
        guard distance > 0.001, y <= 0.001 else { return }
        let delta = atan2(min(y, -0.001), x) - Self.stemAxis
        stemAngle = Self.clamp(delta * 180 / .pi, to: Self.angleRange)
    }

    static func clamp(_ value: CGFloat, to range: ClosedRange<CGFloat>) -> CGFloat {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

struct OiSeedCucumberStemWarp {
    private static let root = OiSeedCucumberAppearance.stemBase
    private static let tip = OiSeedCucumberAppearance.stemDefaultTip
    private static let reach = hypot(tip.x - root.x, tip.y - root.y)
    // The root stays rigid. This radius keeps the radial mapping increasing
    // even at half length, so the compressed texture cannot fold.
    private static let fixedRootRadius: CGFloat = 18

    let attachment: CGPoint
    let length: CGFloat
    let angle: CGFloat

    private var reachChange: CGFloat { (length - 1) * Self.reach }
    private var radians: CGFloat { angle * .pi / 180 }

    private func bendWeight(at radius: CGFloat) -> CGFloat {
        let t = min(1, max(0, (radius - Self.fixedRootRadius) / (Self.reach - Self.fixedRootRadius)))
        return t * t * (3 - 2 * t)
    }

    func mappedRadius(_ radius: CGFloat) -> CGFloat {
        radius + reachChange * bendWeight(at: radius)
    }

    func point(for source: CGPoint) -> CGPoint {
        let x = source.x - Self.root.x
        let y = source.y - Self.root.y
        let radius = hypot(x, y)
        if radius <= Self.fixedRootRadius {
            return CGPoint(x: attachment.x + x, y: attachment.y + y)
        }
        let rotation = radians * bendWeight(at: radius)
        let scale = mappedRadius(radius) / radius
        return CGPoint(x: attachment.x + scale * (cos(rotation) * x - sin(rotation) * y),
                       y: attachment.y + scale * (sin(rotation) * x + cos(rotation) * y))
    }

    func inverseMultiplier(at radius: CGFloat) -> (cosine: CGFloat, sine: CGFloat) {
        guard radius > Self.fixedRootRadius else { return (1, 0) }
        let sourceRadius: CGFloat
        if radius >= Self.reach + reachChange {
            sourceRadius = radius - reachChange
        } else {
            var lower = Self.fixedRootRadius
            var upper = Self.reach
            for _ in 0..<12 {
                let middle = (lower + upper) / 2
                if mappedRadius(middle) < radius { lower = middle }
                else { upper = middle }
            }
            sourceRadius = (lower + upper) / 2
        }
        let rotation = -radians * bendWeight(at: sourceRadius)
        let scale = sourceRadius / radius
        return (cos(rotation) * scale, sin(rotation) * scale)
    }
}

struct OiSeedCucumberViewport {
    // Fit the largest supported pose once so changing height does not zoom the preview.
    private static let artBounds: CGRect = {
        let pivot = OiSeedCucumberAppearance.bodyPivot
        let crown = OiSeedCucumberAppearance.stemBase.y
        let tallestCrown = pivot.y + (crown - pivot.y) * OiSeedCucumberAppearance.heightRange.upperBound
        let top = tallestCrown - 280
        let source = OiSeedCucumberAppearance.sourceSize
        return CGRect(x: 0, y: top, width: source.width, height: source.height - top)
    }()
    let scale: CGFloat
    private let offset: CGPoint

    init(size: CGSize) {
        let art = Self.artBounds
        // Leave room for the selection marker in screen points at any preview size.
        let markerPadding: CGFloat = 12
        scale = max(0, min((size.width - markerPadding * 2) / art.width,
                           (size.height - markerPadding * 2) / art.height))
        offset = CGPoint(x: (size.width - art.width * scale) / 2,
                         y: (size.height - art.height * scale) / 2 - art.minY * scale)
    }

    var transform: CGAffineTransform {
        CGAffineTransform(translationX: offset.x, y: offset.y).scaledBy(x: scale, y: scale)
    }

    func location(of source: CGPoint) -> CGPoint { source.applying(transform) }

    func hitPart(at location: CGPoint, appearance: OiSeedCucumberAppearance,
                 selection: OiSeedCucumberPart) -> OiSeedCucumberPart? {
        return OiSeedCucumberLayer.allCases.compactMap { layer -> (part: OiSeedCucumberPart, distance: CGFloat)? in
            let frame = appearance.faceFrame(layer)
            let isStem = layer == .stem
            let center = self.location(of: isStem ? appearance.stemTip : CGPoint(x: frame.midX, y: frame.midY))
            let distance = hypot(location.x - center.x, location.y - center.y)
            let radius = isStem ? 22 : max(22, max(frame.width, frame.height) * scale / 2)
            return distance <= radius ? (layer.part, distance) : nil
        }.min {
            $0.distance == $1.distance ? $0.part == selection && $1.part != selection : $0.distance < $1.distance
        }?.part
    }
}
