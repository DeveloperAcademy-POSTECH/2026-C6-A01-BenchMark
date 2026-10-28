//
//  OiDonationApp.swift
//  OiDonation
//
//  Created by jiwon hong on 10/8/26.
//

import SwiftUI
import CoreText

@main
struct OiDonationApp: App {
    @UIApplicationDelegateAdaptor(ARRecordingOrientation.self) private var appDelegate
    init() {
        for name in ["Griun_OMIRI-Rg", "Paperlogy-4Regular", "Paperlogy-5Medium", "Paperlogy-6SemiBold", "Paperlogy-8ExtraBold", "Paperlogy-9Black", "Mona12TextKR", "Pretendard-Regular", "Pretendard-Bold", "PearToucan-Regular", "PearToucan-Light", "KIM-WILDgag-Bold"] {
            let ext = name.hasPrefix("Pretendard") ? "otf" : "ttf"
            if let url = Bundle.main.url(forResource: name, withExtension: ext)
                ?? Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Fonts") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-splash-preview-start") {
                OiSplashView(previewLogoPhase: false)
            } else if ProcessInfo.processInfo.arguments.contains("-splash-preview-logo") {
                OiSplashView(previewLogoPhase: true)
            } else {
                OiLaunchView(container: .pilot)
            }
            #else
            OiLaunchView(container: .pilot)
            #endif
        }
    }
}
