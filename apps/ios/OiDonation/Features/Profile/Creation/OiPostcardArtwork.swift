//
//  OiPostcardArtwork.swift
//  OiDonation
//
//  Created by Codex on 2026/11/12.
//

import SwiftUI
import UIKit
import CoreImage
import ImageIO

/// Figma 5400:6051. All coordinates use the 362 × 502 postcard canvas.
struct OiPostcardPaper: View {
    var body: some View {
        Image("OiPostcardPaper").renderingMode(.template).resizable()
    }
}

struct OiPostcardFront<Artwork: View>: View {
    var fill: OiDraftCustomization.Fill = .gradient
    var first: UInt32 = 0xE8EECF
    var second: UInt32 = 0xD5DBC6
    var backgroundStyle: OiPostcardBackgroundStyle? = nil
    var date = ""
    var design: OiCardDesign? = nil
    @ViewBuilder var artwork: () -> Artwork

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let backgroundStyle { OiPostcardBackground(style: backgroundStyle) }
            else { OiCardGradient(fill: fill, first: first, second: second) }
            artwork().frame(width: 296, height: 436).clipped().offset(x: 33, y: 33)
            if design?.postcardLayoutVersion == 2 {
                Rectangle().stroke(Color(white: 0.62), lineWidth: 0.6)
                    .frame(width: 296, height: 436).offset(x: 33, y: 33)
                OiPostcardDecorations(stamp: design?.postcardStamp, logo: design?.postcardLogo)
            } else {
                ForEach(0..<3) { index in
                    Image("OiPostcardWave\(index + 1)").resizable()
                        .frame(width: 121, height: index == 1 ? 17 : 16)
                        .offset(x: 23, y: CGFloat(26 + index * 13))
                        .accessibilityHidden(true)
                }
                Text(date).font(OiPostcardTypography.date)
                    .foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
                    .frame(width: 150, height: 21, alignment: .trailing).offset(x: 167, y: 42)
                    .accessibilityLabel("작성 날짜 \(date)")
                Text("OiD").font(OiPostcardTypography.mark).tracking(1.12)
                    .foregroundStyle(.white).fixedSize().rotationEffect(.degrees(-90))
                    .frame(width: 21, height: 58).offset(x: 43, y: 396)
                    .accessibilityHidden(true)
            }
            Image("OiPostcardSeal").renderingMode(.template).resizable()
                .foregroundStyle(Color(oiRGB: OiPostcardInk.color(backgroundStyle?.paperColor ?? first)))
                .frame(width: design?.postcardLayoutVersion == 2 ? 98 : 116,
                       height: design?.postcardLayoutVersion == 2 ? 98 : 116)
                .offset(x: design?.postcardLayoutVersion == 2 ? 243 : 229,
                        y: design?.postcardLayoutVersion == 2 ? 380 : 365)
                .accessibilityHidden(true)
        }.frame(width: 362, height: 502).mask(OiPostcardPaper()).dynamicTypeSize(.medium)
    }
}

struct OiPostcardBack: View {
    var fill: OiDraftCustomization.Fill = .gradient
    var first: UInt32 = 0xE8EECF
    var second: UInt32 = 0xD5DBC6
    var backgroundStyle: OiPostcardBackgroundStyle? = nil
    let message: String
    let author: String
    var scrollable = false
    var exportFontSize: CGFloat? = nil
    private var ink: Color { Color(oiRGB: OiPostcardInk.color(backgroundStyle?.paperColor ?? first)) }
    var body: some View {
        ZStack(alignment: .topLeading) {
            if let backgroundStyle { OiPostcardBackground(style: backgroundStyle) }
            else { OiCardGradient(fill: fill, first: first, second: second) }
            Group {
                if let selected = backgroundStyle?.backLogoColor {
                    OiPostcardPostechLogo(color: selected)
                } else {
                    Image("OiPostcardWatermark").renderingMode(.template).resizable()
                        .foregroundStyle(ink.opacity(0.15))
                }
            }.frame(width: 213, height: 213).offset(x: 129, y: 259).accessibilityHidden(true)
            Group {
                if scrollable {
                    ScrollView { letter.fixedSize(horizontal: false, vertical: true) }.scrollIndicators(.hidden)
                } else { letter.minimumScaleFactor(0.6) }
            }.frame(width: 292, height: 389, alignment: .topLeading).offset(x: 35, y: 30)
            Text("FROM").font(OiPostcardTypography.from).opacity(0.98)
                .frame(height: 10)
                .offset(x: 35, y: 443)
            Text(author).font(OiPostcardTypography.author).tracking(0.72).opacity(0.98)
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(width: 292, height: 15, alignment: .leading).offset(x: 35, y: 457)
        }.foregroundStyle(ink).frame(width: 362, height: 502)
            .mask(OiPostcardPaper()).dynamicTypeSize(.medium)
    }
    private var letter: some View {
        Text(message.isEmpty ? "아직 남긴 이야기가 없어요." : message)
            .font(exportFontSize.map { .custom(OiPostcardTypography.handwritingName, fixedSize: $0) } ?? OiPostcardTypography.handwriting)
            .tracking(0.17).lineSpacing(OiPostcardTypography.lineSpacing * (exportFontSize ?? 17) / 17)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// Keep ink readable even for dark or custom RGB paper colors.
enum OiPostcardInk {
    static func color(_ rgb: UInt32) -> UInt32 {
        switch rgb {
        case 0xE8EECF: return 0x323F1D
        case 0xE8D8E8, 0xEECFDF: return 0x3F1D2C
        case 0xF1D8D6, 0xEECFCF: return 0x3F1D1D
        default: break
        }
        let r = Double((rgb >> 16) & 255), g = Double((rgb >> 8) & 255), b = Double(rgb & 255)
        if r * 0.2126 + g * 0.7152 + b * 0.0722 < 105 { return 0xFFFFFF }
        return UInt32(r * 0.28) << 16 | UInt32(g * 0.28) << 8 | UInt32(b * 0.28)
    }
}

/// A deterministic companion color for the 296 × 436 portrait window.
/// No extra photo, network generation or saved draft field is needed.
enum OiPostcardCharacterBackdrop {
    static func color(for paper: UInt32) -> UInt32 {
        // Exact paper/backdrop pairing from Figma 5400:6786 and 5400:6871.
        if paper == 0xEECFDF { return 0x835C6E }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        UIColor(Color(oiRGB: paper)).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        // Preserve the chosen hue and enrich pale tones. A minimum brightness
        // keeps near-black paper usable without jumps while dragging the color picker.
        let depth = max(0.16, brightness * 0.55)
        let chroma = min(1, max(saturation, min(0.30, saturation * 2.3)))
        return Color(UIColor(hue: hue, saturation: chroma, brightness: depth, alpha: 1)).oiRGB
    }
}

/// Only a horizontal gesture flips; vertical drags remain available for reading.
enum OiPostcardFlip {
    static func accepts(_ translation: CGSize) -> Bool {
        abs(translation.width) >= 35 && abs(translation.width) > abs(translation.height) * 1.3
    }
}

struct OiFlippablePostcard<Front: View, Back: View>: View {
    @Binding var showingBack: Bool
    @ViewBuilder var front: () -> Front
    @ViewBuilder var back: () -> Back
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var angle = 0.0
    var body: some View {
        GeometryReader { proxy in
            Group {
                if showingBack { back() } else { front() }
            }.frame(width: 362, height: 502)
                .scaleEffect(proxy.size.width / 362, anchor: .topLeading)
        }.aspectRatio(362 / 502, contentMode: .fit)
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.35)
            .contentShape(Rectangle())
            .onTapGesture { flip() }
            .simultaneousGesture(DragGesture(minimumDistance: 20).onEnded { value in
                if OiPostcardFlip.accepts(value.translation) { flip() }
            })
            .accessibilityElement(children: .contain)
            .accessibilityLabel("엽서 \(showingBack ? "뒷면" : "앞면")")
            .accessibilityHint("탭하거나 옆으로 밀어서 뒤집기")
            .accessibilityAction(named: "엽서 뒤집기") { flip() }
            .accessibilityIdentifier("oi.postcard.flip")
    }
    private func flip() {
        guard angle == 0 else { return }
        if reduceMotion { showingBack.toggle(); return }
        withAnimation(.easeIn(duration: 0.16), completionCriteria: .logicallyComplete) { angle = 90 } completion: {
            showingBack.toggle()
            angle = -90
            withAnimation(.easeOut(duration: 0.16)) { angle = 0 }
        }
    }
}

enum OiPostcardDate {
    static func string(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "yy.MM.dd"
        return formatter.string(from: date)
    }
    static func string(from value: String) -> String {
        let numbers = value.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
        guard numbers.count >= 3 else { return value }
        return String(format: "%02d.%02d.%02d", (Int(numbers[0]) ?? 0) % 100, Int(numbers[1]) ?? 0, Int(numbers[2]) ?? 0)
    }
}

/// Figma presets and custom paper share a base and two softly blurred color fields.
/// Rasterize only when the chosen color changes, not while the card flips or moves.
struct OiPostcardBackground: View {
    let style: OiPostcardBackgroundStyle
    var body: some View {
        if let key = style.preset, let preset = OiPostcardPreset(rawValue: key) {
            Image(preset.asset).resizable()
        } else if let middle = style.middleColor, let end = style.endColor {
            if let image = OiPostcardBackgroundTexture.image(start: style.color, middle: middle, end: end) {
                Image(uiImage: image).resizable()
            } else { Color(oiRGB: middle) }
        } else if style.fill == .gradient, let image = OiPostcardBackgroundTexture.image(color: style.color) {
            Image(uiImage: image).resizable()
        } else { Color(oiRGB: style.color) }
    }
}

enum OiPostcardBackgroundTexture {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>(); cache.totalCostLimit = 16 * 1024 * 1024
        return cache
    }()
    private static let context = CIContext(options: [.cacheIntermediates: false, .workingColorSpace: NSNull()])
    /// Cache the Figma blur masks once; dragging a color changes only their tint.
    private static let customMasks: [CIImage] = {
        let size = CGSize(width: 362, height: 502), margin: CGFloat = 375
        let extent = CGRect(origin: .zero, size: size)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.preferredRange = .standard
        let fields = [CGRect(x: -89, y: 252, width: 243, height: 234),
                      CGRect(x: 268, y: -56, width: 243, height: 274)]
        return fields.compactMap { rect in
            let source = UIGraphicsImageRenderer(size: CGSize(width: size.width + margin * 2,
                height: size.height + margin * 2), format: format).image { renderer in
                renderer.cgContext.translateBy(x: margin, y: margin)
                renderer.cgContext.setFillColor(UIColor.white.withAlphaComponent(0.8).cgColor)
                renderer.cgContext.fillEllipse(in: rect)
            }
            guard let cg = source.cgImage else { return nil }
            let blurred = CIImage(cgImage: cg).applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 125])
                .cropped(to: CGRect(x: margin, y: margin, width: size.width, height: size.height))
                .transformed(by: CGAffineTransform(translationX: -margin, y: -margin))
            guard let mask = context.createCGImage(blurred, from: extent, format: .RGBA8,
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else { return nil }
            return CIImage(cgImage: mask)
        }
    }()

    static func image(start: UInt32, middle: UInt32, end: UInt32) -> UIImage? {
        let key = "figma-fields-v1-\(start)-\(middle)-\(end)" as NSString
        if let image = cache.object(forKey: key) { return image }
        guard customMasks.count == 2 else { return nil }
        let extent = CGRect(x: 0, y: 0, width: 362, height: 502)
        var output = CIImage(color: CIColor(color: UIColor(Color(oiRGB: middle)))).cropped(to: extent)
        for (mask, color) in zip(customMasks, [end, start]) {
            let zero = CIVector(x: 0, y: 0, z: 0, w: 0)
            let tinted = mask.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": zero, "inputGVector": zero, "inputBVector": zero,
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: CGFloat((color >> 16) & 255) / 255,
                    y: CGFloat((color >> 8) & 255) / 255, z: CGFloat(color & 255) / 255, w: 0)
            ])
            output = tinted.composited(over: output)
        }
        guard let cg = context.createCGImage(output, from: extent, format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else { return nil }
        let image = UIImage(cgImage: cg)
        cache.setObject(image, forKey: key, cost: 362 * 502 * 4)
        return image
    }

    static func image(color: UInt32) -> UIImage? {
        let key = String(color) as NSString
        if let image = cache.object(forKey: key) { return image }
        let size = CGSize(width: 362, height: 502), margin: CGFloat = 300
        let extent = CGRect(origin: .zero, size: size)
        let accents = accentColors(color)
        var output = CIImage(color: CIColor(color: UIColor(Color(oiRGB: color)))).cropped(to: extent)
        let fields: [(CGRect, UInt32)] = [
            (CGRect(x: -103, y: 226, width: 243, height: 234), accents.0),
            (CGRect(x: 268, y: -56, width: 243, height: 274), accents.1)
        ]
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        for (rect, tint) in fields {
            let image = UIGraphicsImageRenderer(size: CGSize(width: size.width + margin * 2,
                height: size.height + margin * 2), format: format).image { renderer in
                renderer.cgContext.translateBy(x: margin, y: margin)
                renderer.cgContext.setFillColor(UIColor(Color(oiRGB: tint)).withAlphaComponent(0.8).cgColor)
                renderer.cgContext.fillEllipse(in: rect)
            }
            guard let cg = image.cgImage else { return nil }
            let haze = CIImage(cgImage: cg).applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 100])
                .cropped(to: CGRect(x: margin, y: margin, width: size.width, height: size.height))
                .transformed(by: CGAffineTransform(translationX: -margin, y: -margin))
            output = haze.composited(over: output)
        }
        guard let cg = context.createCGImage(output, from: extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else { return nil }
        let image = UIImage(cgImage: cg)
        cache.setObject(image, forKey: key, cost: 362 * 502 * 4)
        return image
    }
    private static func accentColors(_ color: UInt32) -> (UInt32, UInt32) {
        switch color {
        case 0xEECFDF: return (0xC76A94, 0x8B4A69)
        case 0xE8EECF: return (0xB5C76A, 0x768B4A)
        case 0xEECFCF: return (0xC76A6A, 0x8B4A4A)
        default:
            var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
            UIColor(Color(oiRGB: color)).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
            let accentSaturation = min(1, saturation * 3.59)
            return (Color(UIColor(hue: hue, saturation: accentSaturation, brightness: brightness * 0.836, alpha: 1)).oiRGB,
                    Color(UIColor(hue: hue, saturation: accentSaturation, brightness: brightness * 0.584, alpha: 1)).oiRGB)
        }
    }
}

/// Nonpersonal style metadata travels inside the approved PNG, so the back uses
/// the same background after loading on another device. No server fields change.
@MainActor enum OiPostcardBackgroundMetadata {
    private static let prefix = "oi-postcard-background-v1:"
    private static let styles = NSMapTable<UIImage, NSData>(keyOptions: .weakMemory, valueOptions: .strongMemory)
    static func png(image: UIImage, style: OiPostcardBackgroundStyle) -> Data? {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let cg = image.cgImage, let json = try? encoder.encode(style) else { return nil }
        let data = NSMutableData()
        guard let writer = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        let properties = [kCGImagePropertyPNGDictionary: [kCGImagePropertyPNGDescription: prefix + json.base64EncodedString()]] as CFDictionary
        CGImageDestinationAddImage(writer, cg, properties)
        guard CGImageDestinationFinalize(writer) else { return nil }
        return data as Data
    }
    static func remember(png: Data, image: UIImage) {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pngProperties = properties[kCGImagePropertyPNGDictionary] as? [CFString: Any],
              let value = pngProperties[kCGImagePropertyPNGDescription] as? String,
              value.hasPrefix(prefix), value.count < 512,
              let data = Data(base64Encoded: String(value.dropFirst(prefix.count))),
              let style = try? JSONDecoder().decode(OiPostcardBackgroundStyle.self, from: data),
              [style.color, style.middleColor ?? 0, style.endColor ?? 0, style.backLogoColor ?? 0]
                .allSatisfy({ $0 <= 0xFFFFFF }) else { return }
        styles.setObject(data as NSData, forKey: image)
    }
    static func style(for image: UIImage) -> OiPostcardBackgroundStyle? {
        guard let data = styles.object(forKey: image) else { return nil }
        return try? JSONDecoder().decode(OiPostcardBackgroundStyle.self, from: data as Data)
    }
}
