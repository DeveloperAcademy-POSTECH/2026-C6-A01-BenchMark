//
//  OiSeedCucumberAppearance.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/9/26.
//

import CoreGraphics

enum OiSeedCucumberPart: String, CaseIterable, Identifiable {
    case leftEye, rightEye, mouth, stem

    var id: Self { self }

    var title: String {
        switch self {
        case .leftEye: "왼쪽 눈"
        case .rightEye: "오른쪽 눈"
        case .mouth: "입"
        case .stem: "꼭지"
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

    static let faceParts: [Self] = [.leftEye, .rightEye, .mouth]
}

struct OiSeedCucumberAppearance {
    static let sourceSize = CGSize(width: 1058, height: 1658)
    static let stemBase = CGPoint(x: 549, y: 164)
    static let stemDefaultTip = CGPoint(x: 650, y: 79)
    static let sizeRange: ClosedRange<CGFloat> = 0.5...2
    static let horizontalRange: ClosedRange<CGFloat> = -80...80
    static let verticalRange: ClosedRange<CGFloat> = -110...140
    static let lengthRange: ClosedRange<CGFloat> = 0.5...1.65
    static let angleRange: ClosedRange<CGFloat> = -130...35

    struct Face {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var size: CGFloat = 1
    }

    private var faces: [OiSeedCucumberPart: Face] = [:]
    var stemLength: CGFloat = 1
    var stemAngle: CGFloat = 0

    subscript(part: OiSeedCucumberPart) -> Face {
        get { faces[part, default: Face()] }
        set { faces[part] = newValue }
    }

    func faceFrame(_ part: OiSeedCucumberPart) -> CGRect {
        let crop = part.sourceFrame
        let face = self[part]
        let width = crop.width * face.size
        let height = crop.height * face.size
        return CGRect(x: crop.midX + face.x - width / 2, y: crop.midY + face.y - height / 2,
                      width: width, height: height)
    }

    private static let stemVector = CGPoint(x: stemDefaultTip.x - stemBase.x, y: stemDefaultTip.y - stemBase.y)
    private static let stemAxis = atan2(stemVector.y, stemVector.x)

    var stemTransform: CGAffineTransform {
        let base = Self.stemBase
        return CGAffineTransform(translationX: base.x, y: base.y)
            .rotated(by: Self.stemAxis + stemAngle * .pi / 180)
            .scaledBy(x: stemLength, y: 1)
            .rotated(by: -Self.stemAxis)
            .translatedBy(x: -base.x, y: -base.y)
    }

    var stemTip: CGPoint { Self.stemDefaultTip.applying(stemTransform) }

    mutating func moveStemTip(to tip: CGPoint) {
        let x = tip.x - Self.stemBase.x
        let y = tip.y - Self.stemBase.y
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

struct OiSeedCucumberViewport {
    // Extra space above the source lets a lengthened, upright stem remain visible.
    private static let stemClearance: CGFloat = 120
    let scale: CGFloat
    private let offset: CGPoint

    init(size: CGSize) {
        let source = OiSeedCucumberAppearance.sourceSize
        let art = CGRect(x: 0, y: -Self.stemClearance, width: source.width, height: source.height + Self.stemClearance)
        scale = min(size.width / art.width, size.height / art.height)
        offset = CGPoint(x: (size.width - art.width * scale) / 2,
                         y: (size.height - art.height * scale) / 2 - art.minY * scale)
    }

    var transform: CGAffineTransform {
        CGAffineTransform(translationX: offset.x, y: offset.y).scaledBy(x: scale, y: scale)
    }

    func location(of source: CGPoint) -> CGPoint { source.applying(transform) }

    func hitPart(at location: CGPoint, appearance: OiSeedCucumberAppearance,
                 selection: OiSeedCucumberPart) -> OiSeedCucumberPart? {
        let candidates = [selection] + OiSeedCucumberPart.allCases.filter { $0 != selection }
        return candidates.compactMap { part -> (part: OiSeedCucumberPart, distance: CGFloat)? in
            let frame = appearance.faceFrame(part)
            let center = self.location(of: part == .stem ? appearance.stemTip : CGPoint(x: frame.midX, y: frame.midY))
            let distance = hypot(location.x - center.x, location.y - center.y)
            let radius = part == .stem ? 22 : max(22, max(frame.width, frame.height) * scale / 2)
            return distance <= radius ? (part, distance) : nil
        }.min { $0.distance < $1.distance }?.part
    }
}
