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
        if let url = Bundle.main.url(forResource: "Griun_OMIRI-Rg", withExtension: "ttf")
            ?? Bundle.main.url(forResource: "Griun_OMIRI-Rg", withExtension: "ttf", subdirectory: "Fonts") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
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
