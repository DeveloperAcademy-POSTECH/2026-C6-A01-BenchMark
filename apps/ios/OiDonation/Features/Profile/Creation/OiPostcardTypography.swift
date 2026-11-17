//
//  OiPostcardTypography.swift
//  OiDonation
//
//  Created by Codex on 2026/11/12.
//

import CoreText
import SwiftUI
import UIKit

/// Figma 5400:6603. Keep these fonts local to postcards, not the editor's controls.
@MainActor
enum OiPostcardTypography {
    static let handwritingName = "NanumEongGeongKwiCe"
    static let bodySize: CGFloat = 17
    static let bodyLineHeight: CGFloat = 25.5

    private static let registration: Void = {
        let name = handwritingName
        if let url = Bundle.main.url(forResource: name, withExtension: "ttf")
            ?? Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()

    static func registerFonts() { _ = registration }

    static var handwriting: Font {
        registerFonts()
        return .custom(handwritingName, fixedSize: bodySize)
    }

    static var lineSpacing: CGFloat {
        registerFonts()
        let lineHeight = UIFont(name: handwritingName, size: bodySize)?.lineHeight ?? bodySize
        return max(0, bodyLineHeight - lineHeight)
    }

    static let author = Font.custom("Paperlogy-4Regular", fixedSize: 12)
}

/// Figma 6635:10680 uses a same-ink 0.4pt outside stroke.
struct OiPostcardLetteringStroke: TextRenderer {
    private static let offsets: [CGPoint] = (0..<8).map { direction in
        let angle = Double(direction) * .pi / 4
        return CGPoint(x: 0.4 * cos(angle), y: 0.4 * sin(angle))
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for offset in Self.offsets {
                var edge = context
                edge.translateBy(x: offset.x, y: offset.y)
                edge.draw(line)
            }
            context.draw(line)
        }
    }
}
