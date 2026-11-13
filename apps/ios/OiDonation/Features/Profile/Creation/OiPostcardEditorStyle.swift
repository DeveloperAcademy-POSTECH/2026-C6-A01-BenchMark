//
//  OiPostcardEditorStyle.swift
//  OiDonation
//
//  Created by Codex on 2026/11/13.
//

import SwiftUI
import UIKit

/// Figma 5682:5378. Rasterized original SVGs retain blur that iOS's SVG importer omits.
enum OiPostcardPreset: String, CaseIterable, Identifiable {
    case apple, taupe, orange, butter, sand, lime, sage, sky, midnight, lavender, blush, stone
    var id: String { rawValue }
    var asset: String { "OiPostcardPreset-" + rawValue }
    var swatch: String { "OiPostcardSwatch-" + rawValue }
    var title: String {
        switch self {
        case .apple: "애플"; case .taupe: "토프"; case .orange: "오렌지"; case .butter: "버터"
        case .sand: "샌드"; case .lime: "라임"; case .sage: "세이지"; case .sky: "스카이"
        case .midnight: "미드나잇"; case .lavender: "라벤더"; case .blush: "블러시"; case .stone: "스톤"
        }
    }
    var color: UInt32 { colors.middle }
    /// Exact base and two blurred ellipse colors in Figma 5682:5378.
    var colors: OiPostcardGradientColors {
        switch self {
        case .apple: .init(start: 0xB71515, middle: 0xEECFCF, end: 0xC76A6A)
        case .taupe: .init(start: 0xA54C27, middle: 0xF3E9E5, end: 0xC28C75)
        case .orange: .init(start: 0xDD6401, middle: 0xFFEBD4, end: 0xDE843A)
        case .butter: .init(start: 0xCFAB2A, middle: 0xF9F5EA, end: 0xF9DE7F)
        case .sand: .init(start: 0x8B794A, middle: 0xEEE7CF, end: 0xC7A86A)
        case .lime: .init(start: 0x768B4A, middle: 0xE8EECF, end: 0xB5C76A)
        case .sage: .init(start: 0x478532, middle: 0xF3FDF0, end: 0x9DBF91)
        case .sky: .init(start: 0x4CA1E0, middle: 0xF2F8FC, end: 0xACCCE4)
        case .midnight: .init(start: 0x4A6E8B, middle: 0xCFE1EE, end: 0x6A9CC7)
        case .lavender: .init(start: 0x6E529C, middle: 0xF3EFFA, end: 0xA188C9)
        case .blush: .init(start: 0xB72F71, middle: 0xEFD6E2, end: 0xE29BBB)
        case .stone: .init(start: 0x445049, middle: 0xE9EFEC, end: 0x87948D)
        }
    }
}

struct OiPostcardGradientColors: Equatable {
    var start: UInt32
    var middle: UInt32
    var end: UInt32
}

extension OiPostcardBackgroundStyle {
    var customColors: OiPostcardGradientColors {
        if let preset, let selected = OiPostcardPreset(rawValue: preset) { return selected.colors }
        return .init(start: color, middle: middleColor ?? color, end: endColor ?? color)
    }

    mutating func setCustomColor(_ value: UInt32, at index: Int) {
        var colors = customColors
        switch index {
        case 0: colors.start = value
        case 1: colors.middle = value
        case 2: colors.end = value
        default: return
        }
        preset = nil; fill = .gradient
        color = colors.start; middleColor = colors.middle; endColor = colors.end
    }
}

enum OiPostcardAuthor {
    static func text(mode: String?, name: String, academic: String) -> String {
        switch mode {
        case "anonymous": "익명"
        case "academic": academic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "익명" : academic
        case nil, "name": name
        default: "익명"
        }
    }
    static func academic(department: String?, year: String?) -> String {
        [department?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
         year.map { $0.isEmpty ? "" : $0 + "학번" } ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

enum OiPostcardBackLogoStyle {
    static func color(for style: OiPostcardBackgroundStyle) -> UInt32 {
        if let selected = style.backLogoColor { return selected }
        let paper = style.paperColor, ink = OiPostcardInk.color(paper)
        func channel(_ shift: Int) -> UInt32 {
            UInt32((Double((paper >> shift) & 255) * 0.85 + Double((ink >> shift) & 255) * 0.15).rounded())
        }
        return channel(16) << 16 | channel(8) << 8 | channel(0)
    }
}

/// Original Figma 5483:20211 vector, tinted without changing its shape or adding a background.
struct OiPostcardPostechLogo: View {
    let color: UInt32
    var body: some View {
        Image("OiPostcardPostechLogo").renderingMode(.template).resizable().scaledToFit()
            .foregroundStyle(Color(oiRGB: color)).accessibilityHidden(true)
    }
}

/// Artwork is placed in the Figma 362 × 502 coordinate system, not stretched to the image window.
struct OiPostcardDecorations: View {
    let stamp: Int?
    let logo: String?
    var body: some View {
        ZStack(alignment: .topLeading) {
            if let stamp, (1...12).contains(stamp) {
                let index = (stamp - 1) % 6 + 1
                let color = stamp <= 6 ? "white" : "black"
                let size = sizes[index - 1]
                let origin = origins[index - 1]
                Image("OiPostcardStamp-\(color)\(index)").resizable().scaledToFit()
                    .frame(width: size.width, height: size.height).offset(x: origin.x, y: origin.y)
            }
            if logo == "white" || logo == "black" {
                Image("OiPostcardLogo-" + (logo ?? "white")).resizable()
                    .frame(width: 362, height: 502)
            }
        }.frame(width: 362, height: 502, alignment: .topLeading).accessibilityHidden(true)
    }
    private var sizes: [CGSize] {
        [CGSize(width: 122.25, height: 46.75), CGSize(width: 118, height: 44),
         CGSize(width: 121, height: 43.75), CGSize(width: 121, height: 50.75),
         CGSize(width: 103.27, height: 102.58), CGSize(width: 120.15, height: 78.15)]
    }
    private var origins: [CGPoint] {
        [CGPoint(x: 22.5, y: 24.5), CGPoint(x: 26, y: 28), CGPoint(x: 24, y: 24),
         CGPoint(x: 24, y: 24), CGPoint(x: 14.36, y: 34.86), CGPoint(x: 21.85, y: 17.06)]
    }
}

/// A selected story attachment is decoded once and only copied to the card after an explicit tap.
struct OiCardAttachmentOption: View {
    let number: Int
    let load: () async throws -> Data?
    let select: (Data) -> Void
    @State private var data: Data?
    @State private var failed = false
    @State private var attempt = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                if let data { select(data) }
            } label: {
                HStack(spacing: 16) {
                    if let data, let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFill().frame(width: 80, height: 80).clipped()
                    } else if failed { Image(systemName: "photo").frame(width: 80, height: 80) }
                    else { ProgressView().frame(width: 80, height: 80) }
                    Text("이야기 사진 \(number)")
                }
            }.disabled(data == nil)
            if failed { Button("사진 다시 불러오기") { attempt += 1 }.font(.caption) }
        }.task(id: attempt) {
            failed = false
            do {
                guard let bytes = try await load(), UIImage(data: bytes) != nil else { throw OiPhotoDataError.unreadable }
                try Task.checkCancellation()
                data = bytes
            } catch is CancellationError { }
            catch { failed = true }
        }
    }
}
