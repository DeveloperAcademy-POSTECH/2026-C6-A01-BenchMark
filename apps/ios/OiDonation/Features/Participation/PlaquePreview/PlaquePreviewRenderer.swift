import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreText
import ImageIO
import Foundation

nonisolated struct PlaquePreviewImages: Sendable {
    let plaque: CGImage
    let bench: CGImage
    let message: String
    let usesPlaceholder: Bool
}

nonisolated enum PlaquePreviewError: Error, LocalizedError {
    case invalidPlacement, messageTooLong, imageUnavailable
    var errorDescription: String? {
        switch self {
        case .invalidPlacement: "부착 영역이 겹치거나 너무 작아요. 네 모서리를 다시 지정해 주세요."
        case .messageTooLong: "문구를 미리보기 안에 모두 표시하기 어려워요. 문구를 줄이거나 줄바꿈을 조정해 주세요."
        case .imageUnavailable: "사진 미리보기를 만들지 못했어요. 다른 사진으로 다시 시도해 주세요."
        }
    }
}

/// Serial actor keeps Core Text / GPU work off the UI executor. Both views
/// receive one atomic result made from the exact same plaque pixels.
actor PlaquePreviewRenderer {
    private let context = CIContext(options: [.cacheIntermediates: false])

    func render(message: String, photo: CGImage, placement: PlaquePhotoPlacement) throws -> PlaquePreviewImages {
        try Task.checkCancellation()
        guard placement.isValid else { throw PlaquePreviewError.invalidPlacement }
        let cleaned = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let placeholder = cleaned.isEmpty
        let text = placeholder ? "오래 남길 이야기를\n입력해 주세요" : cleaned
        let plaque = try Self.drawPlaque(text: text, placeholder: placeholder)
        try Task.checkCancellation()
        let input = CIImage(cgImage: plaque)
        let base = CIImage(cgImage: photo)
        let perspective = CIFilter.perspectiveTransform()
        perspective.inputImage = input
        func point(_ p: PlaquePhotoPoint) -> CGPoint {
            CGPoint(x: p.x * Double(photo.width), y: (1 - p.y) * Double(photo.height))
        }
        perspective.topLeft = point(placement.topLeft)
        perspective.topRight = point(placement.topRight)
        perspective.bottomRight = point(placement.bottomRight)
        perspective.bottomLeft = point(placement.bottomLeft)
        guard let warped = perspective.outputImage else { throw PlaquePreviewError.imageUnavailable }
        // The alpha follows the rounded plaque, not a rectangle over the photo.
        let shadow = warped.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.25)
        ]).transformed(by: CGAffineTransform(translationX: 0, y: -1.5))
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 1.5])
        let composite = warped.composited(over: shadow.composited(over: base)).cropped(to: base.extent)
        guard let result = context.createCGImage(composite, from: base.extent) else { throw PlaquePreviewError.imageUnavailable }
        try Task.checkCancellation()
        return PlaquePreviewImages(plaque: plaque, bench: result, message: cleaned, usesPlaceholder: placeholder)
    }

    func loadPhoto(data: Data) throws -> CGImage {
        guard data.count <= 30 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 2048
              ] as CFDictionary) else { throw PlaquePreviewError.imageUnavailable }
        try Task.checkCancellation()
        return image
    }

    private static func drawPlaque(text: String, placeholder: Bool) throws -> CGImage {
        // 170:55 is only a design candidate. Pixels do not imply measured size.
        let width = 1020, height = 330
        guard text.count <= 2000, let cg = CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw PlaquePreviewError.messageTooLong }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        let shape = CGPath(roundedRect: rect.insetBy(dx: 2, dy: 2), cornerWidth: 18, cornerHeight: 18, transform: nil)
        cg.saveGState(); cg.addPath(shape); cg.clip()
        let colors = [CGColor(red: 0.94, green: 0.86, blue: 0.61, alpha: 1),
                      CGColor(red: 0.77, green: 0.65, blue: 0.38, alpha: 1),
                      CGColor(red: 0.9, green: 0.81, blue: 0.55, alpha: 1)] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 0.5, 1])!
        cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: height), end: .zero, options: [])
        cg.restoreGState()
        cg.addPath(shape); cg.setStrokeColor(CGColor(gray: 0.35, alpha: 0.6)); cg.setLineWidth(3); cg.strokePath()
        for x in [24, width - 24] {
            for y in [24, height - 24] {
                cg.setFillColor(CGColor(gray: 0.35, alpha: 0.7))
                cg.fillEllipse(in: CGRect(x: x - 5, y: y - 5, width: 10, height: 10))
            }
        }
        let textBounds = rect.insetBy(dx: 64, dy: 42)
        var ctAlignment = CTTextAlignment.center
        let paragraph = withUnsafePointer(to: &ctAlignment) {
            let setting = CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: $0)
            return CTParagraphStyleCreate([setting], 1)
        }
        var chosen: (CTFramesetter, CGSize)?
        for size in stride(from: 54.0, through: 24.0, by: -2.0) {
            let font = CTFontCreateWithName("AppleSDGothicNeo-SemiBold" as CFString, size, nil)
            let attributed = NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: placeholder ? 0.38 : 0.12, alpha: 1),
                NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraph
            ])
            let setter = CTFramesetterCreateWithAttributedString(attributed)
            let fit = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(location: 0, length: 0), nil,
                CGSize(width: textBounds.width, height: .greatestFiniteMagnitude), nil)
            guard fit.height <= textBounds.height else { continue }
            let path = CGPath(rect: CGRect(x: textBounds.minX,
                y: textBounds.midY - ceil(fit.height) / 2, width: textBounds.width, height: ceil(fit.height) + 2), transform: nil)
            let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), path, nil)
            let range = CTFrameGetVisibleStringRange(frame)
            if range.length == (text as NSString).length { chosen = (setter, fit); break }
        }
        guard let (setter, fit) = chosen else { throw PlaquePreviewError.messageTooLong }
        let path = CGPath(rect: CGRect(x: textBounds.minX, y: textBounds.midY - ceil(fit.height) / 2,
                                      width: textBounds.width, height: ceil(fit.height) + 2), transform: nil)
        let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), path, nil)
        cg.textMatrix = .identity
        CTFrameDraw(frame, cg)
        guard let result = cg.makeImage() else { throw PlaquePreviewError.imageUnavailable }
        return result
    }
}
