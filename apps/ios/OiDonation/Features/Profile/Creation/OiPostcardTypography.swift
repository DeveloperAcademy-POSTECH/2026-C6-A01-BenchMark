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
    static let fromName = "EduAUVICWANTPre-Regular"
    static let bodySize: CGFloat = 17
    static let bodyLineHeight: CGFloat = 25.5

    private static let registration: Void = {
        for name in ["NanumEongGeongKwiCe", "EduAUVICWANTPre"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf")
                ?? Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
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

    static var from: Font {
        registerFonts()
        return .custom(fromName, fixedSize: 6)
    }

    // REATIC Wide Bold / Narrow are pending app-embedding permission.
    // Do not silently bundle the restricted font files from the local Ch6 folder.
    static let date = Font.system(size: 14, weight: .ultraLight, design: .rounded)
    static let mark = Font.system(size: 14, weight: .light, design: .rounded)
    static let author = CampusStyle.body(12)
}
