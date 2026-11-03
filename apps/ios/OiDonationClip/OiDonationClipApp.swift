//
//  OiDonationClipApp.swift
//  OiDonationClip
//
//  Created by jiwon hong on 10/12/26.
//

import SwiftUI
import CoreText
import StoreKit

@main
struct OiDonationClipApp: App {
    @State private var isOverlayPresented = false

    init() {
        for name in ["PearToucan-Regular", "KIM-WILDgag-Bold", "Griun_OMIRI-Rg", "Mona12TextKR", "Paperlogy-6SemiBold"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf")
                ?? Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            rootView
                .appStoreOverlay(isPresented: $isOverlayPresented) {
                    SKOverlay.AppClipConfiguration(position: .bottom)
                }
        }
    }

    private var rootView: some View {
        ContentView(storyRepository: RealStoryRepository(), onRequestFullApp: { isOverlayPresented = true })
    }
}
